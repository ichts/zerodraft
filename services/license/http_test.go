package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"
)

func TestWebhookEventIDConflict(t *testing.T) {
	f := setup(t)
	expect(t, f.event("same-id", "order.completed"), http.StatusOK)
	expect(t, f.event("same-id", "refund.succeeded"), http.StatusConflict)
	expect(t, f.event("refund-id", "refund.succeeded"), http.StatusOK)
	expect(t, f.activate("install-one", "macos"), http.StatusForbidden)
}

func TestJSONMediaType(t *testing.T) {
	f := setup(t)
	for _, contentType := range []string{"application/json-invalid", "application/json; broken"} {
		r := httptest.NewRequest(http.MethodPost, "/api/v1/licenses/activate", bytes.NewBufferString(`{"orderId":"ORD_fixture","installLabel":"install-one","platform":"macos"}`))
		r.Header.Set("Content-Type", contentType)
		w := httptest.NewRecorder()
		f.s.Handler().ServeHTTP(w, r)
		expect(t, w, http.StatusUnsupportedMediaType)
	}
}

func TestRequestLimits(t *testing.T) {
	f := setup(t)
	handler := f.s.Handler()
	for i := 0; i < 31; i++ {
		r := httptest.NewRequest(http.MethodPost, "/api/v1/checkout", nil)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		want := http.StatusServiceUnavailable
		if i == 30 {
			want = http.StatusTooManyRequests
			if w.Header().Get("Retry-After") != "60" {
				t.Fatal("missing retry delay")
			}
		}
		expect(t, w, want)
	}
	// Exhausting the client budget must not consume the callback budget.
	expect(t, f.event("order", "order.completed"), http.StatusOK)
	f.s.now = func() time.Time { return f.now.Add(time.Minute) }
	expect(t, f.request("/api/v1/checkout", nil, ""), http.StatusServiceUnavailable)
}

func TestGlobalRequestBudget(t *testing.T) {
	limits := newRequestLimits()
	now := time.Now()
	for i := 0; i < 300; i++ {
		if !limits.allow(strconv.Itoa(i), now) {
			t.Fatal("global budget exhausted early")
		}
	}
	if limits.allow("next", now) {
		t.Fatal("global request budget exceeded")
	}
	if !limits.allow("next", now.Add(time.Minute)) {
		t.Fatal("global budget did not reset")
	}
}

func TestRateLimitMemoryBound(t *testing.T) {
	limits := newRequestLimits()
	now := time.Now()
	for i := 0; i < maxRateClients; i++ {
		limits.clients[strconv.Itoa(i)] = rateWindow{start: now, count: 1}
	}
	if limits.allow("new", now) || len(limits.clients) != maxRateClients {
		t.Fatal("full client map accepted a new address")
	}
	if !limits.allow("new", now.Add(time.Minute)) || len(limits.clients) != 1 {
		t.Fatal("expired client windows were not reclaimed")
	}
}

func TestForwardedAddressTrust(t *testing.T) {
	for _, tc := range []struct {
		remote, forwarded string
		trusted           bool
		want              string
	}{
		{"127.0.0.1:1234", "203.0.113.1", true, "203.0.113.1"},
		{"127.0.0.1:1234", "203.0.113.1", false, "127.0.0.1"},
		{"198.51.100.1:1234", "203.0.113.1", true, "198.51.100.1"},
		{"127.0.0.1:1234", "203.0.113.1, 203.0.113.2", true, "127.0.0.1"},
	} {
		r := httptest.NewRequest(http.MethodPost, "/api/v1/checkout", nil)
		r.RemoteAddr = tc.remote
		r.Header.Set("X-Real-IP", tc.forwarded)
		if got := requestIP(r, tc.trusted); got != tc.want {
			t.Errorf("address = %s, want %s", got, tc.want)
		}
	}
}

func TestConcurrencyBound(t *testing.T) {
	f := setup(t)
	for i := 0; i < cap(f.s.clientLimits.slots); i++ {
		f.s.clientLimits.slots <- struct{}{}
	}
	w := f.request("/api/v1/checkout", nil, "")
	expect(t, w, http.StatusServiceUnavailable)
	if w.Header().Get("Retry-After") != "1" {
		t.Fatal("missing busy retry delay")
	}
}

func TestCheckoutUnavailableWithoutVerifiedConfiguration(t *testing.T) {
	f := setup(t)
	w := f.request("/api/v1/checkout", map[string]string{}, "")
	expect(t, w, http.StatusServiceUnavailable)
	if w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("checkout response may be cached")
	}
}
