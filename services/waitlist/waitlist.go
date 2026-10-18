// Package main is the writeitdown.app Mac waitlist collector.
//
// [INPUT]: POST /api/waitlist form fields email, consent=yes, website (honeypot, must be empty).
// [OUTPUT]: one appended "<UTC RFC3339>\t<email>" line per new address; 303 to the site page
//
//	(no-JS) or JSON {"status": ...} when the client asks for application/json.
//
// [POS]: the only writeitdown component that stores a visitor's personal data; email + time only.
// [PROTOCOL]: README.md owns the HTTP, privacy, and deployment contract; update it with any change here.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/mail"
	"os"
	"strings"
	"sync"
	"time"
)

// Outcome is the public result of one submission; each maps to a fragment on the site page.
type Outcome string

const (
	Joined  Outcome = "joined"
	Invalid Outcome = "invalid"
	Limited Outcome = "limited"
	Failed  Outcome = "error"
)

var outcomeCodes = map[Outcome]int{Joined: http.StatusOK, Invalid: http.StatusBadRequest,
	Limited: http.StatusTooManyRequests, Failed: http.StatusInternalServerError}

// Config holds the deployment facts; see main.go for the environment variables.
type Config struct {
	File      string        // append-only waitlist file
	ReturnURL string        // site page the no-JS form returns to, e.g. https://writeitdown.app/mac.html
	Origin    string        // allowed Origin header, e.g. https://writeitdown.app
	PerClient int           // submissions allowed per client address per window
	Global    int           // submissions allowed across all clients per window
	Window    time.Duration // rate-limit window
	Now       func() time.Time
}

// Waitlist owns the file and the in-memory rate limiter and duplicate set.
type Waitlist struct {
	cfg     Config
	mu      sync.Mutex
	seen    map[string]bool
	clients map[string]*bucket
	global  bucket
}

type bucket struct {
	start time.Time
	count int
}

// Open loads existing addresses so a repeated signup is acknowledged without a second line.
func Open(cfg Config) (*Waitlist, error) {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	w := &Waitlist{cfg: cfg, seen: map[string]bool{}, clients: map[string]*bucket{}}
	f, err := os.Open(cfg.File)
	if errors.Is(err, os.ErrNotExist) {
		return w, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if _, email, ok := strings.Cut(scanner.Text(), "\t"); ok {
			w.seen[strings.ToLower(email)] = true
		}
	}
	return w, scanner.Err()
}

// ServeHTTP handles POST /api/waitlist and GET /api/waitlist/health.
func (w *Waitlist) ServeHTTP(rw http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/api/waitlist/health" && r.Method == http.MethodGet {
		rw.Write([]byte("ok\n"))
		return
	}
	if r.URL.Path != "/api/waitlist" {
		http.NotFound(rw, r)
		return
	}
	if r.Method != http.MethodPost {
		rw.Header().Set("Allow", http.MethodPost)
		http.Error(rw, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if origin := r.Header.Get("Origin"); origin != "" && origin != w.cfg.Origin {
		http.Error(rw, "forbidden origin", http.StatusForbidden)
		return
	}
	r.Body = http.MaxBytesReader(rw, r.Body, 4096)
	w.respond(rw, r, w.submit(r))
}

func (w *Waitlist) submit(r *http.Request) Outcome {
	if err := r.ParseForm(); err != nil {
		return Invalid
	}
	if !w.allow(clientAddress(r)) {
		return Limited
	}
	if r.PostForm.Get("website") != "" {
		return Joined // honeypot: look successful to bots, store nothing
	}
	email, ok := normalizeEmail(r.PostForm.Get("email"))
	if !ok || r.PostForm.Get("consent") != "yes" {
		return Invalid
	}
	if err := w.append(email); err != nil {
		return Failed
	}
	return Joined
}

func (w *Waitlist) respond(rw http.ResponseWriter, r *http.Request, outcome Outcome) {
	if strings.Contains(r.Header.Get("Accept"), "application/json") {
		rw.Header().Set("Content-Type", "application/json")
		rw.WriteHeader(outcomeCodes[outcome])
		json.NewEncoder(rw).Encode(map[string]Outcome{"status": outcome})
		return
	}
	http.Redirect(rw, r, w.cfg.ReturnURL+"#waitlist-"+string(outcome), http.StatusSeeOther)
}

// allow applies a fixed-window limit per client and across all clients.
func (w *Waitlist) allow(client string) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	now := w.cfg.Now()
	for key, b := range w.clients {
		if now.Sub(b.start) >= w.cfg.Window {
			delete(w.clients, key)
		}
	}
	b := w.clients[client]
	if b == nil {
		b = &bucket{start: now}
		w.clients[client] = b
	}
	if now.Sub(w.global.start) >= w.cfg.Window {
		w.global = bucket{start: now}
	}
	if b.count >= w.cfg.PerClient || w.global.count >= w.cfg.Global {
		return false
	}
	b.count++
	w.global.count++
	return true
}

func (w *Waitlist) append(email string) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	key := strings.ToLower(email)
	if w.seen[key] {
		return nil
	}
	f, err := os.OpenFile(w.cfg.File, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	line := w.cfg.Now().UTC().Format(time.RFC3339) + "\t" + email + "\n"
	if _, err = f.WriteString(line); err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		w.seen[key] = true
	}
	return err
}

// normalizeEmail accepts one bare address with a dotted domain and no characters that could break the file.
func normalizeEmail(raw string) (string, bool) {
	email := strings.TrimSpace(raw)
	if len(email) == 0 || len(email) > 254 || strings.ContainsAny(email, " \t\r\n,;<>\"'\\") {
		return "", false
	}
	parsed, err := mail.ParseAddress(email)
	if err != nil || parsed.Address != email || parsed.Name != "" {
		return "", false
	}
	local, domain, _ := strings.Cut(email, "@")
	if local == "" || !strings.Contains(domain, ".") {
		return "", false
	}
	for _, label := range strings.Split(domain, ".") {
		if len(label) == 0 || len(label) > 63 || !domainEdge(label[0]) || !domainEdge(label[len(label)-1]) {
			return "", false
		}
		for i := 1; i < len(label)-1; i++ {
			if !domainEdge(label[i]) && label[i] != '-' {
				return "", false
			}
		}
	}
	return email, true
}

func domainEdge(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9'
}

// clientAddress trusts only the last X-Forwarded-For hop, which the local reverse proxy appends.
func clientAddress(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		hops := strings.Split(forwarded, ",")
		return strings.TrimSpace(hops[len(hops)-1])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
