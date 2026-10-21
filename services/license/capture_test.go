package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func captureDirectory(t *testing.T) string {
	t.Helper()
	parent := t.TempDir()
	if err := os.Chmod(parent, 0700); err != nil {
		t.Fatal(err)
	}
	return filepath.Join(parent, "captures")
}

func startCapture(t *testing.T, path string, now func() time.Time) *callbackCapture {
	t.Helper()
	c, err := openCallbackCapture(path, now)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := c.close(); err != nil {
			t.Error(err)
		}
	})
	return c
}

func capturePaths(t *testing.T, path string) []string {
	t.Helper()
	entries, err := os.ReadDir(path)
	if err != nil {
		t.Fatal(err)
	}
	var paths []string
	for _, entry := range entries {
		if _, ok := captureTime(entry.Name()); !ok {
			t.Fatal("unexpected archive entry")
		}
		paths = append(paths, filepath.Join(path, entry.Name()))
	}
	return paths
}

func requireMode(t *testing.T, path string, want os.FileMode) {
	t.Helper()
	info, err := os.Lstat(path)
	if err != nil || info.Mode().Perm() != want || info.Mode()&os.ModeSymlink != 0 {
		t.Fatal("incorrect capture file permissions or type", err)
	}
}

func TestCallbackCaptureVerbatimHTTP(t *testing.T) {
	f := setup(t)
	path := captureDirectory(t)
	var err error
	f.s.capture, err = openCallbackCapture(path, f.s.now)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(f.s.Handler())
	defer server.Close()
	body := []byte(" \r\n{\t\"test\": \"雪\"}\n\xff\x00")
	req, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/webhooks/waffo?test=capture", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Host = "callback.test"
	req.Header.Set("Content-Type", "application/json")
	req.Header["X-Waffo-Signature"] = []string{"t=1,v1=invalid", "t=2,v1=invalid"}
	req.Header["X-Repeated"] = []string{"one", "two"}
	req.Header.Set("X-Octets", string([]byte{0xff, 0xfe}))
	req.Header.Set("Cookie", "synthetic=value")
	req.Header.Set("Authorization", "synthetic-test-only")
	req.ContentLength = -1
	req.Trailer = http.Header{"X-Final": []string{"first", "second"}}
	response, err := server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatal("capture changed provisional signature rejection")
	}
	paths := capturePaths(t, path)
	if len(paths) != 1 {
		t.Fatal("callback not archived exactly once")
	}
	raw, err := os.ReadFile(filepath.Join(paths[0], "body.bin"))
	if err != nil || !bytes.Equal(raw, body) {
		t.Fatal("callback bytes changed", err)
	}
	metadata, err := os.ReadFile(filepath.Join(paths[0], "request.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got captureMetadata
	if err := json.Unmarshal(metadata, &got); err != nil {
		t.Fatal(err)
	}
	for name, values := range req.Header {
		if len(got.Headers[name]) != len(values) {
			t.Fatalf("header value count changed for %s", name)
		}
		for i, value := range values {
			if !bytes.Equal(got.Headers[name][i], []byte(value)) {
				t.Fatalf("header bytes changed for %s", name)
			}
		}
	}
	wantTrailers := map[string][][]byte{"X-Final": {[]byte("first"), []byte("second")}}
	if !reflect.DeepEqual(got.Trailers, wantTrailers) || string(got.Host) != req.Host || string(got.RequestURI) != "/api/v1/webhooks/waffo?test=capture" || !got.ReceivedAt.Equal(f.now) {
		t.Fatal("callback request metadata changed")
	}
	if !reflect.DeepEqual(got.TransferEncoding, []string{"chunked"}) {
		t.Fatal("transfer metadata missing")
	}
	requireMode(t, path, 0700)
	requireMode(t, paths[0], 0700)
	requireMode(t, filepath.Join(paths[0], "body.bin"), 0600)
	requireMode(t, filepath.Join(paths[0], "request.json"), 0600)
	var events int
	if err := f.s.db.QueryRow("SELECT count(*) FROM webhook_events").Scan(&events); err != nil || events != 0 {
		t.Fatal("capturing unverified input changed authorization state", err)
	}
}

func TestCaptureDoesNotChangeLicenseLifecycle(t *testing.T) {
	f := setup(t)
	path := captureDirectory(t)
	var err error
	f.s.capture, err = openCallbackCapture(path, f.s.now)
	if err != nil {
		t.Fatal(err)
	}
	expect(t, f.event("capture-paid", "order.completed"), 200)
	expect(t, f.event("capture-paid", "order.completed"), 200)
	expect(t, f.activate("first-install", "windows"), 200)
	expect(t, f.activate("second-install", "macos"), 200)
	expect(t, f.activate("third-install", "macos"), 409)
	expect(t, f.event("capture-refund", "refund.succeeded"), 200)
	expect(t, f.activate("first-install", "windows"), 403)
	if len(capturePaths(t, path)) != 3 {
		t.Fatal("expected each callback including duplicate, and no client credentials")
	}
}

func TestCaptureDirectoryConfiguration(t *testing.T) {
	if c, err := openCallbackCapture("", time.Now); err != nil || c != nil {
		t.Fatal("capture should be disabled by default")
	}
	for _, kind := range []string{"relative", "public-parent", "public-directory", "symlink", "parent-symlink", "file"} {
		t.Run(kind, func(t *testing.T) {
			path := captureDirectory(t)
			switch kind {
			case "relative":
				path = "relative-captures"
			case "public-parent":
				if err := os.Chmod(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
			case "public-directory":
				if err := os.Mkdir(path, 0755); err != nil {
					t.Fatal(err)
				}
			case "symlink":
				if err := os.Symlink(t.TempDir(), path); err != nil {
					t.Fatal(err)
				}
			case "parent-symlink":
				link := filepath.Join(t.TempDir(), "private-link")
				if err := os.Symlink(filepath.Dir(path), link); err != nil {
					t.Fatal(err)
				}
				path = filepath.Join(link, "captures")
			case "file":
				if err := os.WriteFile(path, nil, 0600); err != nil {
					t.Fatal(err)
				}
			}
			c, err := openCallbackCapture(path, time.Now)
			if err == nil {
				c.close()
				t.Fatal("unsafe capture directory accepted")
			}
		})
	}
}

func TestCaptureRetentionAndRestart(t *testing.T) {
	path := captureDirectory(t)
	var clock atomic.Int64
	clock.Store(time.Now().UnixNano())
	now := func() time.Time { return time.Unix(0, clock.Load()) }
	c, err := openCallbackCapture(path, now)
	if err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", nil)
	if err := c.save(r, []byte("original")); err != nil {
		c.close()
		t.Fatal(err)
	}
	if err := c.close(); err != nil {
		t.Fatal(err)
	}
	orphan := filepath.Join(path, ".pending-"+strings.Repeat("a", 32))
	if err := os.Mkdir(orphan, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(orphan, "body.bin"), []byte("unfinished"), 0600); err != nil {
		t.Fatal(err)
	}
	clock.Add(int64(captureRetention - time.Nanosecond))
	c = startCapture(t, path, now)
	if len(capturePaths(t, path)) != 1 {
		t.Fatal("startup must remove orphan but retain unexpired capture")
	}
	clock.Add(1)
	if err := c.cleanup(); err != nil || len(capturePaths(t, path)) != 0 {
		t.Fatal("expiry cleanup failed without a new callback", err)
	}
	if err := c.save(r, []byte("new")); err != nil {
		t.Fatal(err)
	}
	clock.Add(int64(captureRetention))
	if err := c.save(r, []byte("after expiry")); err != nil || len(capturePaths(t, path)) != 1 {
		t.Fatal("write did not expire previous capture", err)
	}
}

func TestCaptureReopensFullArchiveWithOrphanStaging(t *testing.T) {
	path := captureDirectory(t)
	var clock atomic.Int64
	clock.Store(time.Now().UnixNano())
	now := func() time.Time { return time.Unix(0, clock.Add(1)) }
	c := startCapture(t, path, now)
	r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", nil)
	for range captureCountLimit {
		if err := c.save(r, []byte("published")); err != nil {
			t.Fatal(err)
		}
	}
	before := capturePaths(t, path)
	if err := c.close(); err != nil {
		t.Fatal(err)
	}
	unknown := filepath.Join(path, "unrelated")
	if err := os.Mkdir(unknown, 0700); err != nil {
		t.Fatal(err)
	}
	if reopened, err := openCallbackCapture(path, now); err == nil {
		reopened.close()
		t.Fatal("unknown entry accepted at capacity")
	}
	if err := os.Remove(unknown); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(path, ".pending-"+strings.Repeat("b", 32))
	if err := os.Symlink(filepath.Dir(path), link); err != nil {
		t.Fatal(err)
	}
	if reopened, err := openCallbackCapture(path, now); err == nil {
		reopened.close()
		t.Fatal("symlink accepted at capacity")
	}
	if err := os.Remove(link); err != nil {
		t.Fatal(err)
	}
	orphan := filepath.Join(path, ".pending-"+strings.Repeat("a", 32))
	if err := os.Mkdir(orphan, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(orphan, "body.bin"), []byte("unfinished"), 0600); err != nil {
		t.Fatal(err)
	}
	c = startCapture(t, path, now)
	if _, err := os.Lstat(orphan); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("orphan staging survived restart", err)
	}
	if len(capturePaths(t, path)) != captureCountLimit {
		t.Fatal("reopening evicted a published record")
	}
	if err := c.save(r, []byte("replacement")); err != nil {
		t.Fatal(err)
	}
	after := capturePaths(t, path)
	if len(after) != captureCountLimit {
		t.Fatal("rolling archive exceeded its capacity")
	}
	if _, err := os.Stat(before[0]); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("oldest record was not evicted", err)
	}
}

func TestCaptureBoundsAndAtomicPublication(t *testing.T) {
	path := captureDirectory(t)
	c := startCapture(t, path, time.Now)
	r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", nil)
	if err := c.save(r, make([]byte, callbackBodyLimit+1)); err == nil {
		t.Fatal("oversized body accepted")
	}
	r.Header.Set("X-Large", strings.Repeat("a", captureHeaderLimit))
	if err := c.save(r, nil); err == nil {
		t.Fatal("oversized metadata accepted")
	}
	r.Header.Del("X-Large")
	if len(capturePaths(t, path)) != 0 {
		t.Fatal("rejected request left capture files")
	}
	body := bytes.Repeat([]byte("x"), callbackBodyLimit)
	stop := make(chan struct{})
	observed := make(chan error, 1)
	firstObserved := make(chan struct{})
	var observeOnce sync.Once
	go func() {
		for {
			select {
			case <-stop:
				observed <- nil
				return
			default:
			}
			entries, err := os.ReadDir(path)
			if err != nil {
				observed <- err
				return
			}
			for _, entry := range entries {
				if _, ok := captureTime(entry.Name()); !ok {
					continue
				}
				raw, err := os.ReadFile(filepath.Join(path, entry.Name(), "body.bin"))
				meta, metaErr := os.ReadFile(filepath.Join(path, entry.Name(), "request.json"))
				if err != nil || metaErr != nil || !bytes.Equal(raw, body) || !json.Valid(meta) {
					observed <- errors.New("partially published capture observed")
					return
				}
				observeOnce.Do(func() { close(firstObserved) })
			}
		}
	}()
	var successes atomic.Int64
	var wg sync.WaitGroup
	for range captureCountLimit {
		wg.Go(func() {
			if err := c.save(r, body); err == nil {
				successes.Add(1)
			}
		})
	}
	wg.Wait()
	select {
	case <-firstObserved:
	case err := <-observed:
		close(stop)
		t.Fatal("capture observer stopped before observing a record", err)
	case <-time.After(5 * time.Second):
		close(stop)
		<-observed
		t.Fatal("capture observer did not observe a published record")
	}
	close(stop)
	if err := <-observed; err != nil {
		t.Fatal(err)
	}
	if successes.Load() != captureCountLimit || len(capturePaths(t, path)) != captureCountLimit {
		t.Fatal("concurrent writes violated capture count bound")
	}
	for range 8 {
		if err := c.save(r, body); err != nil {
			t.Fatal("full archive rejected a new capture", err)
		}
	}
	if len(capturePaths(t, path)) != captureCountLimit {
		t.Fatal("rolling archive exceeded its capacity")
	}
}

type failingCallbackBody struct{}

func (failingCallbackBody) Read(p []byte) (int, error) {
	copy(p, "partial")
	return len("partial"), io.ErrUnexpectedEOF
}

func TestCaptureHTTPFailuresKeepVerificationIndependent(t *testing.T) {
	f := setup(t)
	path := captureDirectory(t)
	var err error
	f.s.capture, err = openCallbackCapture(path, f.s.now)
	if err != nil {
		t.Fatal(err)
	}
	for _, body := range []io.Reader{strings.NewReader(strings.Repeat("x", callbackBodyLimit+1)), failingCallbackBody{}} {
		r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", body)
		w := httptest.NewRecorder()
		f.s.Handler().ServeHTTP(w, r)
		if w.Code != http.StatusBadRequest || len(capturePaths(t, path)) != 0 {
			t.Fatal("partial or oversized request should not be archived")
		}
	}
	if err := os.Chmod(path, 0755); err != nil {
		t.Fatal(err)
	}
	expect(t, f.event("capture-storage-failure", "order.completed"), 200)
	expect(t, f.activate("first-install", "macos"), 200)
	if len(capturePaths(t, path)) != 0 {
		t.Fatal("unsafe directory received sensitive data")
	}
	if err := os.Chmod(path, 0700); err != nil {
		t.Fatal(err)
	}
	expect(t, f.event("capture-storage-failure", "order.completed"), 200)
}

func TestCaptureStartupCleansExpiredAndRejectsForeignEntries(t *testing.T) {
	path := captureDirectory(t)
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	expired := "capture-" + strconv.FormatInt(now.Add(-captureRetention).UnixNano(), 10) + "-" + strings.Repeat("b", 32)
	if err := os.Mkdir(filepath.Join(path, expired), 0700); err != nil {
		t.Fatal(err)
	}
	c, err := openCallbackCapture(path, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	if len(capturePaths(t, path)) != 0 {
		c.close()
		t.Fatal("expired evidence survived startup")
	}
	c.close()
	if err := os.WriteFile(filepath.Join(path, "unrelated"), []byte("do not delete"), 0600); err != nil {
		t.Fatal(err)
	}
	if c, err := openCallbackCapture(path, time.Now); err == nil {
		c.close()
		t.Fatal("non-dedicated directory accepted")
	}
	if _, err := os.Stat(filepath.Join(path, "unrelated")); err != nil {
		t.Fatal("unrelated file was removed", err)
	}
}
