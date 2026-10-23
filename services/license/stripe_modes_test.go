package main

import (
	"bytes"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"log"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
)

func stripeLiveFixture(typ string) map[string]any {
	e := stripeFixture(typ)
	e["id"] = "evt_live_" + typ
	e["livemode"] = true
	o := stripeFixtureObject(e)
	o["livemode"] = true
	o["payment_intent"] = "pi_live_fixture"
	if typ == "charge.refunded" {
		o["id"] = "ch_live_fixture"
		return e
	}
	o["id"] = "cs_live_fixture"
	o["line_items"] = map[string]any{"has_more": false, "data": []any{map[string]any{"quantity": 1, "price": map[string]string{"id": "price_live_fixture", "product": "prod_live_billing"}}}}
	return e
}

func stripeActivateSession(t *testing.T, s *Server, session string) string {
	t.Helper()
	raw, _ := json.Marshal(map[string]string{"orderId": session, "installLabel": "same-mac-fixture", "platform": "macos"})
	r := httptest.NewRequest("POST", "/api/v1/licenses/activate", bytes.NewReader(raw))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	expect(t, w, 200)
	return tokenFrom(t, w)
}
func stripeValidateToken(t *testing.T, s *Server, token string) {
	t.Helper()
	raw, _ := json.Marshal(map[string]string{"token": token})
	r := httptest.NewRequest("POST", "/api/v1/licenses/validate", bytes.NewReader(raw))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	expect(t, w, 200)
}
func stripeCredential(s *Server, id string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/license?session_id="+url.QueryEscape(id), nil))
	return w
}

func TestStripeEnvironmentSwitchKeepsTokenContract(t *testing.T) {
	s := stripeServer(t)
	cfg := s.cfg
	public := s.publicKey
	// All LIVE envelopes in this test are local HMAC fixtures, not Stripe traffic.
	expect(t, stripeRequest(s, stripeLiveFixture("checkout.session.completed")), 401)
	expect(t, stripeRequest(s, stripeFixture("checkout.session.completed")), 200)
	testToken := stripeActivateSession(t, s, "cs_test_fixture")
	var schemaVersion int
	if err := s.db.QueryRow("PRAGMA schema_version").Scan(&schemaVersion); err != nil {
		t.Fatal(err)
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}

	// These are the only four fields changed for the TEST -> LIVE restart.
	cfg.Environment = "live"
	cfg.StripeSecretKey = "sk_live_local_fixture"
	cfg.StripeWebhookSecret = "local-live-webhook-fixture-not-a-provider-secret"
	cfg.StripePriceID = "price_live_fixture"
	live, err := Open(cfg, s.now)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { live.Close() })
	var liveSchemaVersion int
	if err := live.db.QueryRow("PRAGMA schema_version").Scan(&liveSchemaVersion); err != nil || liveSchemaVersion != schemaVersion {
		t.Fatal("mode switch changed schema", err)
	}
	if !bytes.Equal(public, live.publicKey) || cfg.ProductID != s.cfg.ProductID {
		t.Fatal("mode switch changed app identity")
	}
	expect(t, stripeRequest(live, stripeFixture("checkout.session.completed")), 401)
	mismatch := stripeLiveFixture("checkout.session.completed")
	stripeFixtureObject(mismatch)["livemode"] = false
	expect(t, stripeRequest(live, mismatch), 401)
	expect(t, stripeRequest(live, stripeLiveFixture("checkout.session.completed")), 200)
	expect(t, stripeRequest(live, stripeLiveFixture("checkout.session.completed")), 200)
	if stripeRows(t, live, "licenses") != 2 {
		t.Fatal("LIVE completion was not issued exactly once")
	}
	liveToken := stripeActivateSession(t, live, "cs_live_fixture")
	for _, token := range []string{testToken, liveToken} {
		c, err := VerifyToken(public, token, live.now())
		if err != nil || c.Product != cfg.ProductID {
			t.Fatal("single app key/product rejected a mode", err)
		}
		stripeValidateToken(t, live, token)
	}
	// The same buyer credential remains accessible across the mode switch.
	expect(t, stripeCredential(live, "cs_test_fixture"), 200)
	expect(t, stripeRequest(live, stripeFixture("charge.refunded")), 401)
	expect(t, stripeRequest(live, stripeLiveFixture("charge.refunded")), 200)
	expect(t, stripeCredential(live, "cs_live_fixture"), 404)
	stripeValidateToken(t, live, testToken)
	if err := live.Close(); err != nil {
		t.Fatal(err)
	}

	cfg.Environment = s.cfg.Environment
	cfg.StripeSecretKey = s.cfg.StripeSecretKey
	cfg.StripeWebhookSecret = s.cfg.StripeWebhookSecret
	cfg.StripePriceID = s.cfg.StripePriceID
	restored, err := Open(cfg, s.now)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { restored.Close() })
	stripeValidateToken(t, restored, testToken)
	// Offline verification uses the same format/key even for a now-revoked LIVE token.
	if _, err := VerifyToken(restored.publicKey, liveToken, restored.now()); err != nil {
		t.Fatal(err)
	}
	expect(t, stripeRequest(restored, stripeLiveFixture("checkout.session.completed")), 401)
}

func TestStripeLiveCheckoutMode(t *testing.T) {
	for _, responseLive := range []bool{false, true} {
		t.Run(map[bool]string{false: "TEST response rejected", true: "LIVE response accepted"}[responseLive], func(t *testing.T) {
			s := stripeServer(t)
			s.cfg.Environment = "live"
			s.cfg.StripeSecretKey = "sk_live_local_fixture"
			s.cfg.StripePriceID = "price_live_fixture"
			api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer sk_live_local_fixture" {
					t.Error("wrong mode API key")
				}
				if err := r.ParseForm(); err != nil || r.Form.Get("line_items[0][price]") != "price_live_fixture" || r.Form.Get("success_url") != stripeSuccessURL {
					t.Error("wrong LIVE checkout configuration")
				}
				json.NewEncoder(w).Encode(map[string]any{"livemode": responseLive, "url": "https://checkout.stripe.com/c/pay/fixture"})
			}))
			defer api.Close()
			s.cfg.StripeAPIBase = api.URL
			w := httptest.NewRecorder()
			s.Handler().ServeHTTP(w, httptest.NewRequest("POST", "/api/v1/checkout", nil))
			status := 502
			if responseLive {
				status = 200
			}
			expect(t, w, status)
		})
	}
}

func TestStripeBuyerCredentialDelivery(t *testing.T) {
	s := stripeServer(t)
	var logs bytes.Buffer
	oldWriter := log.Writer()
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(oldWriter) })
	for _, id := range []string{"cs_test_fixture", "cs_unknown_fixture", "", "not-a-session"} {
		w := stripeCredential(s, id)
		expect(t, w, 404)
		if w.Body.String() != "license unavailable\n" || w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("non-neutral missing credential response")
		}
	}
	unpaid := stripeFixture("checkout.session.completed")
	stripeFixtureObject(unpaid)["payment_status"] = "unpaid"
	expect(t, stripeRequest(s, unpaid), 400)
	expect(t, stripeCredential(s, "cs_test_fixture"), 404)
	expect(t, stripeRequest(s, stripeFixture("checkout.session.expired")), 200)
	expect(t, stripeCredential(s, "cs_test_fixture"), 404)
	completed := stripeFixture("checkout.session.completed")
	expect(t, stripeRequest(s, completed), 200)
	expect(t, stripeRequest(s, completed), 200)
	for i := 0; i < 2; i++ {
		w := stripeCredential(s, "cs_test_fixture")
		expect(t, w, 200)
		var response struct {
			LicenseKey string `json:"licenseKey"`
		}
		if json.Unmarshal(w.Body.Bytes(), &response) != nil || response.LicenseKey != "cs_test_fixture" {
			t.Fatal("buyer did not receive exact activation credential")
		}
		if w.Header().Get("Cache-Control") != "no-store" {
			t.Fatal("credential cached")
		}
		stripeActivateSession(t, s, response.LicenseKey)
	}
	if stripeRows(t, s, "licenses") != 1 || stripeRows(t, s, "stripe_purchases") != 1 {
		t.Fatal("one session issued more than one key")
	}
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/license?session_id=cs_test_fixture&session_id=cs_unknown_fixture", nil))
	expect(t, w, 404)
	expect(t, stripeCredential(s, "cs_unknown_fixture"), 404)
	expect(t, stripeRequest(s, stripeFixture("charge.refunded")), 200)
	expect(t, stripeCredential(s, "cs_test_fixture"), 404)
	if logs.Len() != 0 {
		t.Fatal("buyer credential flow wrote logs")
	}
}

func TestStripeEnvironmentConfiguration(t *testing.T) {
	s := stripeServer(t)
	der, err := x509.MarshalPKCS8PrivateKey(s.cfg.TokenKey)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "token.pem")
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("LICENSE_CALLBACK_CAPTURE_DIR", "")
	t.Setenv("LICENSE_TRUST_LOOPBACK_PROXY", "false")
	t.Setenv("LICENSE_PROVIDER", "stripe")
	t.Setenv("LICENSE_ENVIRONMENT", "test")
	t.Setenv("LICENSE_TOKEN_PRIVATE_KEY_FILE", path)
	t.Setenv("LICENSE_PRODUCT_ID", s.cfg.ProductID)
	t.Setenv("STRIPE_PRICE_ID", s.cfg.StripePriceID)
	t.Setenv("STRIPE_SECRET_KEY", s.cfg.StripeSecretKey)
	t.Setenv("STRIPE_WEBHOOK_SECRET", s.cfg.StripeWebhookSecret)
	t.Setenv("STRIPE_API_BASE", s.cfg.StripeAPIBase)
	test, err := environmentConfig(s.cfg.Database)
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("LICENSE_ENVIRONMENT", "live")
	t.Setenv("STRIPE_SECRET_KEY", "sk_live_local_fixture")
	t.Setenv("STRIPE_WEBHOOK_SECRET", "local-live-webhook-fixture")
	t.Setenv("STRIPE_PRICE_ID", "price_live_fixture")
	live, err := environmentConfig(s.cfg.Database)
	if err != nil {
		t.Fatal(err)
	}
	if live.Environment != "live" || live.ProductID != test.ProductID || !bytes.Equal(live.TokenKey, test.TokenKey) {
		t.Fatal("environment switch changed token identity")
	}
	t.Setenv("LICENSE_PRODUCT_ID", "")
	t.Setenv("STRIPE_PRODUCT_ID", test.ProductID)
	fallback, err := environmentConfig(s.cfg.Database)
	if err != nil || fallback.ProductID != test.ProductID {
		t.Fatal("stable product fallback changed app identity", err)
	}
	t.Setenv("LICENSE_PRODUCT_ID", test.ProductID)
	for _, name := range []string{"STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET", "STRIPE_PRICE_ID"} {
		original := os.Getenv(name)
		t.Setenv(name, "")
		if _, err := environmentConfig(s.cfg.Database); err == nil {
			t.Fatalf("startup accepted missing %s", name)
		}
		t.Setenv(name, original)
	}
	t.Setenv("STRIPE_SECRET_KEY", "sk_test_local_fixture")
	if _, err := environmentConfig(s.cfg.Database); err == nil {
		t.Fatal("LIVE mode accepted TEST API key")
	}
}
