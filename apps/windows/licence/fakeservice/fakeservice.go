// Package fakeservice is a stand-in for the licence service in headless tests: it signs real Ed25519 tokens with the
// documented contract and returns whatever status a test forces. It is never used by the app itself.
package fakeservice

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"time"

	"github.com/ichts/zerodraft/apps/windows/licence"
)

// Service is the fake. Set Status["activate"|"validate"|"checkout"] to force a status code.
type Service struct {
	URL         string
	PublicKey   string // base64 of the raw 32 bytes, as the Info.plist carries it
	Product     string
	Now         func() time.Time
	CheckoutURL string

	mu       sync.Mutex
	priv     ed25519.PrivateKey
	Status   map[string]int
	Detail   map[string]string
	Requests []map[string]string
	srv      *httptest.Server
}

// New starts the service; Close stops it.
func New(product string, now func() time.Time) *Service {
	pub, priv, _ := ed25519.GenerateKey(rand.Reader)
	s := &Service{Product: product, Now: now, priv: priv, PublicKey: base64.StdEncoding.EncodeToString(pub),
		Status: map[string]int{}, Detail: map[string]string{}, CheckoutURL: "https://checkout.stripe.com/c/pay/cs_test_fake"}
	s.srv = httptest.NewServer(http.HandlerFunc(s.handle))
	s.URL = s.srv.URL
	return s
}

// Close stops the server.
func (s *Service) Close() { s.srv.Close() }

func (s *Service) token(label string) string {
	n := s.Now().Unix()
	c := licence.Claims{LicenseID: "lic_1", ActivationID: "act_1", InstallLabel: label, Product: s.Product, IssuedAt: n, ExpiresAt: n + licence.Lifetime}
	payload, _ := json.Marshal(c)
	enc := base64.RawURLEncoding.EncodeToString(payload)
	return enc + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(s.priv, []byte(enc)))
}

func (s *Service) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	var req map[string]string
	_ = json.Unmarshal(body, &req)
	ep := strings.TrimPrefix(r.URL.Path, "/api/v1/")
	ep = strings.TrimPrefix(ep, "licenses/")
	s.mu.Lock()
	s.Requests = append(s.Requests, req)
	st, d := s.Status[ep], s.Detail[ep]
	s.mu.Unlock()
	if st != 0 {
		http.Error(w, d, st)
		return
	}
	switch ep {
	case "activate":
		json.NewEncoder(w).Encode(map[string]string{"token": s.token(req["installLabel"])})
	case "validate":
		parts := strings.Split(req["token"], ".")
		b, _ := base64.RawURLEncoding.DecodeString(parts[0])
		var c licence.Claims
		_ = json.Unmarshal(b, &c)
		json.NewEncoder(w).Encode(map[string]string{"token": s.token(c.InstallLabel)})
	case "deactivate":
		w.Write([]byte(`{"status":"deactivated"}`))
	case "checkout":
		json.NewEncoder(w).Encode(map[string]string{"url": s.CheckoutURL})
	default:
		http.NotFound(w, r)
	}
}
