package main

import (
	"net/http/httptest"
	"testing"
)

func TestStripeBuyerCORS(t *testing.T) {
	s := stripeServer(t)
	expect(t, stripeRequest(s, stripeFixture("checkout.session.completed")), 200)
	for _, origin := range []string{buyerOrigin, "https://untrusted.invalid", "null"} {
		r := httptest.NewRequest("GET", "/api/v1/license?session_id=cs_test_fixture", nil)
		r.Header.Set("Origin", origin)
		w := httptest.NewRecorder()
		s.Handler().ServeHTTP(w, r)
		expect(t, w, 200)
		want := ""
		if origin == buyerOrigin {
			want = buyerOrigin
		}
		if w.Header().Get("Access-Control-Allow-Origin") != want || w.Header().Get("Access-Control-Allow-Credentials") != "" {
			t.Fatal("buyer origin boundary failed")
		}
		if w.Header().Get("Cache-Control") != "no-store" || w.Header().Get("Vary") != "Origin" {
			t.Fatal("buyer response caching boundary failed")
		}
	}
	for path, method := range map[string]string{"/api/v1/checkout": "POST", "/api/v1/license": "GET"} {
		r := httptest.NewRequest("OPTIONS", path, nil)
		r.Header.Set("Origin", buyerOrigin)
		r.Header.Set("Access-Control-Request-Method", method)
		r.Header.Set("Access-Control-Request-Headers", "Content-Type")
		w := httptest.NewRecorder()
		s.Handler().ServeHTTP(w, r)
		expect(t, w, 204)
		if w.Header().Get("Access-Control-Allow-Origin") != buyerOrigin || w.Header().Get("Access-Control-Allow-Methods") != method || w.Header().Get("Access-Control-Allow-Headers") != "Content-Type" {
			t.Fatal("official buyer preflight failed")
		}
		r.Header.Set("Origin", "https://untrusted.invalid")
		w = httptest.NewRecorder()
		s.Handler().ServeHTTP(w, r)
		expect(t, w, 403)
		if w.Header().Get("Access-Control-Allow-Origin") != "" {
			t.Fatal("untrusted preflight allowed")
		}
	}
}
