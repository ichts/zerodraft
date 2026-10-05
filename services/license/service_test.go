package main

import (
	"bytes"
	"crypto"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"
)

type fixture struct {
	t      *testing.T
	s      *Server
	signer *rsa.PrivateKey
	now    time.Time
}

func setup(t *testing.T) *fixture {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	_, tokenKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 5, 0, 0, 0, 0, time.UTC)
	pub := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: mustMarshal(t, &key.PublicKey)})
	s, err := Open(Config{Database: filepath.Join(t.TempDir(), "licenses.db"), ProductID: "wid-test", Environment: "test", TestPublicKey: pub, TokenKey: tokenKey}, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return &fixture{t, s, key, now}
}
func mustMarshal(t *testing.T, k *rsa.PublicKey) []byte {
	t.Helper()
	b, e := x509.MarshalPKIXPublicKey(k)
	if e != nil {
		t.Fatal(e)
	}
	return b
}
func (f *fixture) request(path string, payload any, signature string) *httptest.ResponseRecorder {
	f.t.Helper()
	b, _ := json.Marshal(payload)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if signature != "" {
		req.Header.Set("X-Waffo-Signature", signature)
	}
	w := httptest.NewRecorder()
	f.s.Handler().ServeHTTP(w, req)
	return w
}
func (f *fixture) event(id, typ string) *httptest.ResponseRecorder {
	f.t.Helper()
	body := map[string]any{"id": id, "eventType": typ, "environment": "test", "data": map[string]any{"orderId": "ORD_fixture", "paymentId": "PAY_fixture", "productId": "wid-test"}}
	raw, _ := json.Marshal(body)
	hash := sha256.Sum256(raw)
	sig, e := rsa.SignPKCS1v15(rand.Reader, f.signer, crypto.SHA256, hash[:])
	if e != nil {
		f.t.Fatal(e)
	}
	return f.request("/api/v1/webhooks/waffo", body, base64.StdEncoding.EncodeToString(sig))
}
func (f *fixture) activate(label, platform string) *httptest.ResponseRecorder {
	return f.request("/api/v1/licenses/activate", map[string]string{"orderId": "ORD_fixture", "installLabel": label, "platform": platform}, "")
}
func tokenFrom(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var v struct {
		Token string `json:"token"`
	}
	if e := json.Unmarshal(w.Body.Bytes(), &v); e != nil || v.Token == "" {
		t.Fatalf("missing token: %d %s", w.Code, w.Body)
	}
	return v.Token
}
func expect(t *testing.T, w *httptest.ResponseRecorder, code int) {
	t.Helper()
	if w.Code != code {
		t.Fatalf("want %d got %d: %s", code, w.Code, w.Body)
	}
}

func TestActivationLimitAndReuse(t *testing.T) {
	f := setup(t)
	expect(t, f.event("evt1", "order.completed"), 200)
	a := f.activate("mac-one", "macos")
	expect(t, a, 200)
	id := tokenFrom(t, a)
	expect(t, f.activate("windows-two", "windows"), 200)
	expect(t, f.activate("install-third", "macos"), http.StatusConflict)
	a = f.activate("mac-one", "macos")
	expect(t, a, 200)
	first, err := VerifyToken(f.s.publicKey, id, f.now)
	if err != nil {
		t.Fatal(err)
	}
	f.s.now = func() time.Time { return f.now.Add(6 * 24 * time.Hour) }
	a = f.activate("mac-one", "macos")
	expect(t, a, 200)
	second, err := VerifyToken(f.s.publicKey, tokenFrom(t, a), f.now.Add(6*24*time.Hour))
	if err != nil || first.ActivationID != second.ActivationID || second.IssuedAt <= first.IssuedAt {
		t.Fatal("same install should reuse activation and renew token", err)
	}
}
func TestDeactivationFreesSlot(t *testing.T) {
	f := setup(t)
	expect(t, f.event("evt1", "order.completed"), 200)
	token := tokenFrom(t, f.activate("install-one", "macos"))
	expect(t, f.activate("install-two", "windows"), 200)
	expect(t, f.request("/api/v1/licenses/deactivate", map[string]string{"token": token}, ""), 200)
	expect(t, f.activate("install-three", "macos"), 200)
	expect(t, f.request("/api/v1/licenses/validate", map[string]string{"token": token}, ""), http.StatusForbidden)
}
func TestRefundRevokesAndLateOrderCannotRestore(t *testing.T) {
	f := setup(t)
	expect(t, f.event("evt1", "order.completed"), 200)
	token := tokenFrom(t, f.activate("install-one", "macos"))
	expect(t, f.event("evt2", "refund.succeeded"), 200)
	expect(t, f.request("/api/v1/licenses/validate", map[string]string{"token": token}, ""), http.StatusForbidden)
	expect(t, f.activate("install-two", "macos"), http.StatusForbidden)
	expect(t, f.event("evt3", "order.completed"), 200)
	expect(t, f.activate("install-two", "macos"), http.StatusForbidden)
}
func TestWebhookSignatureAndReplay(t *testing.T) {
	f := setup(t)
	body := map[string]any{"id": "evt1", "eventType": "order.completed", "environment": "test", "data": map[string]any{"orderId": "ORD_fixture", "productId": "wid-test"}}
	expect(t, f.request("/api/v1/webhooks/waffo", body, ""), 401)
	expect(t, f.request("/api/v1/webhooks/waffo", body, base64.StdEncoding.EncodeToString([]byte("forged"))), 401)
	raw, _ := json.Marshal(body)
	hash := sha256.Sum256(raw)
	sig, _ := rsa.SignPKCS1v15(rand.Reader, f.signer, crypto.SHA256, hash[:])
	body["eventType"] = "refund.succeeded"
	expect(t, f.request("/api/v1/webhooks/waffo", body, base64.StdEncoding.EncodeToString(sig)), 401)
	body["environment"] = "production"
	expect(t, f.request("/api/v1/webhooks/waffo", body, ""), 401)
	expect(t, f.event("evt1", "order.completed"), 200)
	expect(t, f.event("evt1", "order.completed"), 200)
	expect(t, f.activate("install-one", "macos"), 200)
}
func TestOfflineExpiryAndRefundWindow(t *testing.T) {
	f := setup(t)
	expect(t, f.event("evt1", "order.completed"), 200)
	token := tokenFrom(t, f.activate("install-one", "macos"))
	if _, e := VerifyToken(f.s.publicKey, token, f.now.Add(7*24*time.Hour)); e == nil {
		t.Fatal("expired offline token accepted")
	}
	f.s.now = func() time.Time { return f.now.Add(7 * 24 * time.Hour) }
	expect(t, f.request("/api/v1/licenses/validate", map[string]string{"token": token}, ""), 403)
	f.s.now = func() time.Time { return f.now }
	if _, e := VerifyToken(f.s.publicKey, token, f.now.Add(6*24*time.Hour)); e != nil {
		t.Fatal(e)
	}
	w := f.request("/api/v1/licenses/validate", map[string]string{"token": token}, "")
	expect(t, w, 200)
	if !bytes.Contains(w.Body.Bytes(), []byte(`"refundEligible":true`)) {
		t.Fatal(w.Body)
	}
	token = tokenFrom(t, w)
	f.s.now = func() time.Time { return f.now.Add(6 * 24 * time.Hour) }
	w = f.request("/api/v1/licenses/validate", map[string]string{"token": token}, "")
	expect(t, w, 200)
	token = tokenFrom(t, w)
	f.s.now = func() time.Time { return f.now.Add(12 * 24 * time.Hour) }
	w = f.request("/api/v1/licenses/validate", map[string]string{"token": token}, "")
	expect(t, w, 200)
	token = tokenFrom(t, w)
	f.s.now = func() time.Time { return f.now.Add(14 * 24 * time.Hour) }
	w = f.request("/api/v1/licenses/validate", map[string]string{"token": token}, "")
	expect(t, w, 200)
	if !bytes.Contains(w.Body.Bytes(), []byte(`"refundEligible":false`)) {
		t.Fatal(w.Body)
	}
}
func TestRateLimit(t *testing.T) {
	f := setup(t)
	expect(t, f.event("order", "order.completed"), 200)
	for i := 0; i < 60; i++ {
		expect(t, f.activate("install-one", "macos"), 200)
	}
	expect(t, f.activate("install-one", "macos"), 429)
}

func TestRefundBeforeCompletionAndManualRevoke(t *testing.T) {
	f := setup(t)
	expect(t, f.event("refund-first", "refund.succeeded"), 200)
	expect(t, f.event("order-later", "order.completed"), 200)
	expect(t, f.activate("install-one", "macos"), 403)
	f2 := setup(t)
	expect(t, f2.event("order", "order.completed"), 200)
	token := tokenFrom(t, f2.activate("install-one", "macos"))
	if err := revoke(f2.cfgDB(), "ORD_fixture"); err != nil {
		t.Fatal(err)
	}
	expect(t, f2.request("/api/v1/licenses/validate", map[string]string{"token": token}, ""), 403)
}
func (f *fixture) cfgDB() string { return f.s.cfg.Database }

func TestWrongProductAndEnvironment(t *testing.T) {
	f := setup(t)
	expect(t, f.event("evt1", "order.completed"), 200)
	b := map[string]any{"id": "evt2", "eventType": "order.completed", "environment": "test", "data": map[string]any{"orderId": "ORD_other", "productId": "other"}}
	raw, _ := json.Marshal(b)
	h := sha256.Sum256(raw)
	sig, _ := rsa.SignPKCS1v15(rand.Reader, f.signer, crypto.SHA256, h[:])
	expect(t, f.request("/api/v1/webhooks/waffo", b, base64.StdEncoding.EncodeToString(sig)), 400)
	b["environment"] = "production"
	raw, _ = json.Marshal(b)
	h = sha256.Sum256(raw)
	sig, _ = rsa.SignPKCS1v15(rand.Reader, f.signer, crypto.SHA256, h[:])
	expect(t, f.request("/api/v1/webhooks/waffo", b, base64.StdEncoding.EncodeToString(sig)), 401)
	expect(t, f.activate("install-one", "macos"), 200)
}
