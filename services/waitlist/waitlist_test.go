package main

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newTestWaitlist(t *testing.T, now *time.Time) (*Waitlist, string) {
	t.Helper()
	file := filepath.Join(t.TempDir(), "waitlist.tsv")
	w, err := Open(Config{File: file, ReturnURL: "https://writeitdown.app/mac.html", Origin: "https://writeitdown.app",
		PerClient: 2, Global: 3, Window: 10 * time.Minute, Now: func() time.Time { return *now }})
	if err != nil {
		t.Fatal(err)
	}
	return w, file
}

func post(w http.Handler, form url.Values, headers map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/waitlist", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.RemoteAddr = "127.0.0.1:5000"
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	rec := httptest.NewRecorder()
	w.ServeHTTP(rec, req)
	return rec
}

func signup(email string) url.Values { return url.Values{"email": {email}, "consent": {"yes"}} }

func readFile(t *testing.T, file string) string {
	t.Helper()
	data, err := os.ReadFile(file)
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	return string(data)
}

func TestFormSubmissionStoresOnlyEmailAndUTCTime(t *testing.T) {
	now := time.Date(2026, 10, 18, 23, 0, 0, 0, time.FixedZone("CEST", 2*3600))
	w, file := newTestWaitlist(t, &now)
	rec := post(w, signup("reader@example.com"), map[string]string{"Origin": "https://writeitdown.app", "X-Forwarded-For": "203.0.113.9"})
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != "https://writeitdown.app/mac.html#waitlist-joined" {
		t.Fatalf("got %d %q", rec.Code, rec.Header().Get("Location"))
	}
	if got := readFile(t, file); got != "2026-10-18T21:00:00Z\treader@example.com\n" {
		t.Fatalf("file = %q", got)
	}
	info, _ := os.Stat(file)
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %v", info.Mode().Perm())
	}
}

func TestJSONOutcomesAndNothingStoredOnRejection(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	w, file := newTestWaitlist(t, &now)
	w.cfg.Global = 4
	json := map[string]string{"Accept": "application/json"}
	cases := []struct {
		form url.Values
		code int
		body string
	}{
		{url.Values{"email": {"reader@example.com"}}, 400, `{"status":"invalid"}`},
		{signup("not-an-email"), 400, `{"status":"invalid"}`},
		{signup("a@example..com"), 400, `{"status":"invalid"}`},
	}
	for i, c := range cases {
		json["X-Forwarded-For"] = "198.51.100." + string(rune('1'+i))
		rec := post(w, c.form, json)
		if rec.Code != c.code || strings.TrimSpace(rec.Body.String()) != c.body {
			t.Fatalf("case %d: %d %s", i, rec.Code, rec.Body.String())
		}
	}
	json["X-Forwarded-For"] = "198.51.100.9"
	rec := post(w, url.Values{"email": {"bot@example.com"}, "consent": {"yes"}, "website": {"spam"}}, json)
	if rec.Code != 200 || readFile(t, file) != "" {
		t.Fatalf("honeypot stored or failed: %d %q", rec.Code, readFile(t, file))
	}
}

func TestDuplicateIsAcknowledgedOnceAcrossRestart(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	w, file := newTestWaitlist(t, &now)
	post(w, signup("Reader@Example.com"), map[string]string{"X-Forwarded-For": "203.0.113.1"})
	reopened, err := Open(Config{File: file, ReturnURL: "https://x", PerClient: 5, Global: 5, Window: time.Minute,
		Now: func() time.Time { return now }})
	if err != nil {
		t.Fatal(err)
	}
	rec := post(reopened, signup("reader@example.com"), map[string]string{"X-Forwarded-For": "203.0.113.2"})
	if !strings.HasSuffix(rec.Header().Get("Location"), "#waitlist-joined") {
		t.Fatalf("duplicate outcome %q", rec.Header().Get("Location"))
	}
	if strings.Count(readFile(t, file), "\n") != 1 {
		t.Fatalf("duplicate stored: %q", readFile(t, file))
	}
}

func TestPerClientAndGlobalRateLimits(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	w, _ := newTestWaitlist(t, &now)
	json := map[string]string{"Accept": "application/json", "X-Forwarded-For": "spoofed, 203.0.113.7"}
	for i := 0; i < 2; i++ {
		if rec := post(w, signup("a@example.com"), json); rec.Code != 200 {
			t.Fatalf("submit %d: %d", i, rec.Code)
		}
	}
	if rec := post(w, signup("a@example.com"), json); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("per-client limit: %d", rec.Code)
	}
	json["X-Forwarded-For"] = "203.0.113.8"
	post(w, signup("b@example.com"), json)
	json["X-Forwarded-For"] = "203.0.113.10"
	if rec := post(w, signup("c@example.com"), json); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("global limit: %d", rec.Code)
	}
	now = now.Add(10 * time.Minute)
	if rec := post(w, signup("c@example.com"), json); rec.Code != 200 {
		t.Fatalf("window reset: %d", rec.Code)
	}
}

func TestRejectsForeignOriginWrongMethodAndOversizedBody(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	w, file := newTestWaitlist(t, &now)
	if rec := post(w, signup("a@example.com"), map[string]string{"Origin": "https://evil.example"}); rec.Code != http.StatusForbidden {
		t.Fatalf("origin: %d", rec.Code)
	}
	get := httptest.NewRecorder()
	w.ServeHTTP(get, httptest.NewRequest(http.MethodGet, "/api/waitlist", nil))
	if get.Code != http.StatusMethodNotAllowed {
		t.Fatalf("get: %d", get.Code)
	}
	big := signup("a@example.com")
	big.Set("pad", strings.Repeat("x", 5000))
	if rec := post(w, big, map[string]string{"Accept": "application/json"}); rec.Code != 400 {
		t.Fatalf("oversized: %d", rec.Code)
	}
	if readFile(t, file) != "" {
		t.Fatal("rejected requests stored data")
	}
	health := httptest.NewRecorder()
	w.ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/api/waitlist/health", nil))
	if health.Code != 200 {
		t.Fatalf("health: %d", health.Code)
	}
}

func TestUnwritableFileReportsError(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	w, err := Open(Config{File: filepath.Join(t.TempDir(), "missing", "waitlist.tsv"), ReturnURL: "https://x",
		PerClient: 5, Global: 5, Window: time.Minute, Now: func() time.Time { return now }})
	if err != nil {
		t.Fatal(err)
	}
	if rec := post(w, signup("a@example.com"), map[string]string{"Accept": "application/json"}); rec.Code != 500 {
		t.Fatalf("got %d", rec.Code)
	}
}

func TestEmailValidationAndLoopbackBinding(t *testing.T) {
	for _, bad := range []string{"", "a", "a@b", "a@b.", "a@example..com", "a@-example.com", "a@example-.com", "a@exa_mple.com", "A <a@b.co>", "a,b@c.co", "a@b.co\nx@y.co", "a\t@b.co", strings.Repeat("a", 250) + "@b.co"} {
		if _, ok := normalizeEmail(bad); ok {
			t.Errorf("accepted %q", bad)
		}
	}
	if got, ok := normalizeEmail("  reader+mac@example.co.uk "); !ok || got != "reader+mac@example.co.uk" {
		t.Errorf("rejected valid address: %q", got)
	}
	for addr, ok := range map[string]bool{"127.0.0.1:8091": true, "[::1]:8091": true, "localhost:8091": true, "0.0.0.0:8091": false, ":8091": false} {
		if (requireLoopback(addr) == nil) != ok {
			t.Errorf("requireLoopback(%q)", addr)
		}
	}
}
