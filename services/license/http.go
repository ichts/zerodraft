// [INPUT] HTTP requests, peer addresses and the configured clock/proxy boundary.
// [OUTPUT] Bounded request admission and a fail-closed checkout response.
// [POS] HTTP safeguards shared by license routes; no checkout provider adapter yet.
// [PROTOCOL] Keep this header and AGENTS.md aligned with README.md.
package main

import (
	"net"
	"net/http"
	"sync"
	"time"
)

const maxRateClients = 4096

type rateWindow struct {
	start time.Time
	count int
}

type requestLimits struct {
	mu      sync.Mutex
	clients map[string]rateWindow
	global  rateWindow
	slots   chan struct{}
}

func newRequestLimits() *requestLimits {
	return &requestLimits{clients: make(map[string]rateWindow), slots: make(chan struct{}, 16)}
}

func incrementWindow(window rateWindow, now time.Time, limit int) (rateWindow, bool) {
	if now.Sub(window.start) >= time.Minute {
		window = rateWindow{start: now}
	}
	if window.count >= limit {
		return window, false
	}
	window.count++
	return window, true
}

func (l *requestLimits) allow(ip string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	var ok bool
	l.global, ok = incrementWindow(l.global, now, 300)
	if !ok {
		return false
	}
	window, exists := l.clients[ip]
	if !exists && len(l.clients) >= maxRateClients {
		for key, value := range l.clients {
			if now.Sub(value.start) >= time.Minute {
				delete(l.clients, key)
			}
		}
		if len(l.clients) >= maxRateClients {
			return false
		}
	}
	l.clients[ip], ok = incrementWindow(window, now, 30)
	return ok
}

func requestIP(r *http.Request, trustLoopbackProxy bool) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return "unknown"
	}
	peer := net.ParseIP(host)
	if peer == nil {
		return "unknown"
	}
	if trustLoopbackProxy && peer.IsLoopback() {
		if ip := net.ParseIP(r.Header.Get("X-Real-IP")); ip != nil {
			return ip.String()
		}
	}
	return peer.String()
}

func (s *Server) protect(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		limits := s.clientLimits
		if r.URL.Path == "/api/v1/webhooks/waffo" {
			limits = s.webhookLimits
		}
		if !limits.allow(requestIP(r, s.cfg.TrustLoopbackProxy), s.now()) {
			w.Header().Set("Retry-After", "60")
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		select {
		case limits.slots <- struct{}{}:
			defer func() { <-limits.slots }()
			next.ServeHTTP(w, r)
		default:
			w.Header().Set("Retry-After", "1")
			http.Error(w, "service busy", http.StatusServiceUnavailable)
		}
	})
}

func (s *Server) checkout(w http.ResponseWriter, r *http.Request) {
	// No provider call is safe until the checkout wire contract and product are verified.
	respond(w, http.StatusServiceUnavailable, map[string]string{"error": "checkout_not_configured"})
}
