package main

import (
	"bytes"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestCallbackCaptureJunkCannotBlockSignedEvents(t *testing.T) {
	f := setup(t)
	path := captureDirectory(t)
	var err error
	var clock atomic.Int64
	now := func() time.Time { return f.now.Add(time.Duration(clock.Add(1))) }
	f.s.capture, err = openCallbackCapture(path, now)
	if err != nil {
		t.Fatal(err)
	}
	for i := range captureCountLimit {
		r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", strings.NewReader("{}"))
		r.RemoteAddr = fmt.Sprintf("192.0.2.%d:1234", i/30+1)
		w := httptest.NewRecorder()
		f.s.Handler().ServeHTTP(w, r)
		expect(t, w, http.StatusUnauthorized)
	}
	if len(capturePaths(t, path)) != captureCountLimit {
		t.Fatal("unsigned traffic did not fill the archive")
	}
	// Reset admission only to isolate capture capacity from existing rate limits.
	f.s.webhookLimits = newRequestLimits()
	expect(t, f.event("capture-after-junk-paid", "order.completed"), http.StatusOK)
	expect(t, f.activate("first-install", "macos"), http.StatusOK)
	if err := f.s.capture.close(); err != nil {
		t.Fatal(err)
	}
	f.s.capture, err = openCallbackCapture(path, now)
	if err != nil {
		t.Fatal(err)
	}
	expect(t, f.event("capture-after-junk-refund", "refund.succeeded"), http.StatusOK)
	expect(t, f.activate("first-install", "macos"), http.StatusForbidden)
	var events int
	if err := f.s.db.QueryRow("SELECT count(*) FROM webhook_events").Scan(&events); err != nil || events != 2 {
		t.Fatal("signed completion and refund were not recorded", err)
	}
	paths := capturePaths(t, path)
	if len(paths) != captureCountLimit {
		t.Fatal("capture archive is no longer bounded")
	}
	var signedCaptures int
	for _, record := range paths {
		body, err := os.ReadFile(filepath.Join(record, "body.bin"))
		if err != nil {
			t.Fatal(err)
		}
		if bytes.Contains(body, []byte("capture-after-junk-")) {
			signedCaptures++
		}
	}
	if signedCaptures != 2 {
		t.Fatal("unsigned traffic denied capture space to signed callbacks")
	}
}

func TestCallbackCaptureFailureDoesNotAuthorizeOrLeak(t *testing.T) {
	f := setup(t)
	path := captureDirectory(t)
	var err error
	f.s.capture, err = openCallbackCapture(path, f.s.now)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0755); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	writer := log.Writer()
	log.SetOutput(&output)
	t.Cleanup(func() { log.SetOutput(writer) })
	r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo?private-query-marker", strings.NewReader("private-body-marker"))
	r.Header.Set("Authorization", "private-header-marker")
	w := httptest.NewRecorder()
	f.s.Handler().ServeHTTP(w, r)
	expect(t, w, http.StatusUnauthorized)
	expect(t, f.event("capture-io-paid", "order.completed"), http.StatusOK)
	expect(t, f.activate("first-install", "macos"), http.StatusOK)
	expect(t, f.event("capture-io-refund", "refund.succeeded"), http.StatusOK)
	expect(t, f.activate("first-install", "macos"), http.StatusForbidden)
	if len(capturePaths(t, path)) != 0 {
		t.Fatal("unsafe directory received evidence")
	}
	if !strings.Contains(output.String(), "callback capture failed") {
		t.Fatal("capture failure alert missing")
	}
	for _, secret := range []string{path, "private-query-marker", "private-body-marker", "private-header-marker", "capture-io-paid", "capture-io-refund"} {
		if strings.Contains(output.String(), secret) || strings.Contains(w.Body.String(), secret) {
			t.Fatal("capture failure exposed request content or a private path")
		}
	}
}

func TestCaptureRejectsSymlinkEntryWithoutFollowingIt(t *testing.T) {
	path := captureDirectory(t)
	c := startCapture(t, path, time.Now)
	outside := filepath.Join(t.TempDir(), "untouched")
	if err := os.WriteFile(outside, []byte("outside-marker"), 0600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(path, ".pending-"+strings.Repeat("c", 32))
	if err := os.Symlink(filepath.Dir(outside), link); err != nil {
		t.Fatal(err)
	}
	if err := c.cleanup(); err == nil {
		t.Fatal("symlink entry accepted during cleanup")
	}
	r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", nil)
	if err := c.save(r, []byte("test")); err == nil {
		t.Fatal("symlink entry accepted during capture")
	}
	data, err := os.ReadFile(outside)
	if err != nil || string(data) != "outside-marker" {
		t.Fatal("cleanup followed symlink outside the archive", err)
	}
	if info, err := os.Lstat(link); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatal("unrecognized symlink was removed", err)
	}
}
