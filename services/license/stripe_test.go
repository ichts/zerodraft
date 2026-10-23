package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

const stripeFixtureSecret = "local-generated-fixture-secret-not-a-provider-key"

func stripeHeader(secret string, body []byte, now time.Time) string {
	ts := strconv.FormatInt(now.Unix(), 10)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(ts + "."))
	mac.Write(body)
	return "t=" + ts + ",v1=" + hex.EncodeToString(mac.Sum(nil))
}

func TestStripeSignature(t *testing.T) {
	now := time.Unix(1800000000, 0)
	body := []byte("{\"raw\": true}\n")
	header := stripeHeader(stripeFixtureSecret, body, now)
	cases := []struct {
		name, header, secret string
		body                 []byte
		want                 bool
	}{
		{"valid", header, stripeFixtureSecret, body, true},
		{"wrong secret", header, "wrong", body, false},
		{"tampered body", header, stripeFixtureSecret, append(append([]byte{}, body...), ' '), false},
		{"stale timestamp", stripeHeader(stripeFixtureSecret, body, now.Add(-301*time.Second)), stripeFixtureSecret, body, false},
		{"future timestamp", stripeHeader(stripeFixtureSecret, body, now.Add(301*time.Second)), stripeFixtureSecret, body, false},
		{"boundary", stripeHeader(stripeFixtureSecret, body, now.Add(-300*time.Second)), stripeFixtureSecret, body, true},
		{"duplicate t", header + ",t=1800000000", stripeFixtureSecret, body, false},
		{"duplicate empty t", "t=," + header, stripeFixtureSecret, body, false},
		{"multiple v1", header + ",v1=" + strings.Repeat("0", 64), stripeFixtureSecret, body, true},
		{"second v1 matches", "t=1800000000,v1=" + strings.Repeat("0", 64) + "," + strings.Split(header, ",")[1], stripeFixtureSecret, body, true},
		{"legacy scheme ignored", header + ",v0=" + strings.Repeat("0", 64), stripeFixtureSecret, body, true},
		{"missing header", "", stripeFixtureSecret, body, false},
		{"missing t", strings.Split(header, ",")[1], stripeFixtureSecret, body, false},
		{"missing v1", "t=1800000000", stripeFixtureSecret, body, false},
		{"malformed hex", header + ",v1=" + strings.Repeat("z", 64), stripeFixtureSecret, body, false},
		{"uppercase wrong hex", "t=1800000000,v1=" + strings.Repeat("A", 64), stripeFixtureSecret, body, false},
		{"uppercase valid hex", strings.Split(header, ",v1=")[0] + ",v1=" + strings.ToUpper(strings.Split(header, ",v1=")[1]), stripeFixtureSecret, body, true},
		{"non-numeric timestamp", "t=not-a-time,v1=" + strings.Repeat("0", 64), stripeFixtureSecret, body, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := verifyStripeSignature(c.secret, []string{c.header}, c.body, now); got != c.want {
				t.Fatalf("got %v want %v", got, c.want)
			}
		})
	}
	if verifyStripeSignature(stripeFixtureSecret, []string{header, header}, body, now) {
		t.Fatal("duplicate timestamps across headers accepted")
	}
	if !verifyStripeSignature(stripeFixtureSecret, []string{header, "v1=" + strings.Repeat("0", 64) + ",v0=legacy"}, body, now) {
		t.Fatal("additional signature header rejected")
	}
}

func stripeServer(t *testing.T) *Server {
	t.Helper()
	_, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "fixture API unavailable", 503) }))
	t.Cleanup(api.Close)
	s, err := Open(Config{Database: filepath.Join(t.TempDir(), "stripe.db"), ProductID: "prod_fixture", Environment: "test", TokenKey: key, Provider: "stripe", StripeWebhookSecret: stripeFixtureSecret, StripeSecretKey: "sk_test_local_fixture", StripePriceID: "price_fixture", StripeAPIBase: api.URL}, func() time.Time { return time.Unix(1800000000, 0) })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func stripeFixture(typ string) map[string]any {
	o := map[string]any{"id": "cs_test_fixture", "livemode": false, "payment_intent": "pi_fixture", "amount_total": 499, "currency": "usd", "mode": "payment", "status": "complete", "payment_status": "paid", "line_items": map[string]any{"data": []any{map[string]any{"quantity": 1, "price": map[string]any{"id": "price_fixture", "product": "prod_fixture"}}}, "has_more": false}}
	if typ == "charge.refunded" {
		o = map[string]any{"id": "ch_fixture", "livemode": false, "payment_intent": "pi_fixture", "amount": 499, "amount_refunded": 499, "refunded": true, "currency": "usd"}
	}
	return map[string]any{"id": "evt_fixture_" + typ, "type": typ, "livemode": false, "data": map[string]any{"object": o}}
}
func stripeFixtureObject(e map[string]any) map[string]any {
	return e["data"].(map[string]any)["object"].(map[string]any)
}
func stripeRequest(s *Server, e map[string]any) *httptest.ResponseRecorder {
	raw, _ := json.Marshal(e)
	return stripeRawRequest(s, raw, stripeHeader(s.cfg.StripeWebhookSecret, raw, s.now()))
}
func stripeRawRequest(s *Server, raw []byte, header string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("POST", "/api/v1/webhooks/stripe", bytes.NewReader(raw))
	r.Header.Set("Stripe-Signature", header)
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	return w
}
func stripeRows(t *testing.T, s *Server, table string) int {
	t.Helper()
	var n int
	if err := s.db.QueryRow("SELECT count(*) FROM " + table).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestStripeBusinessGates(t *testing.T) {
	cases := []struct {
		name   string
		change func(map[string]any)
	}{
		{"wrong price", func(e map[string]any) {
			stripeFixtureObject(e)["line_items"] = map[string]any{"data": []any{map[string]any{"quantity": 1, "price": map[string]string{"id": "price_wrong", "product": "prod_fixture"}}}}
		}},
		{"wrong amount", func(e map[string]any) { stripeFixtureObject(e)["amount_total"] = 500 }},
		{"missing amount", func(e map[string]any) { delete(stripeFixtureObject(e), "amount_total") }},
		{"missing billing product", func(e map[string]any) {
			stripeFixtureObject(e)["line_items"] = map[string]any{"data": []any{map[string]any{"quantity": 1, "price": map[string]string{"id": "price_fixture", "product": ""}}}}
		}},
		{"paginated items", func(e map[string]any) { stripeFixtureObject(e)["line_items"].(map[string]any)["has_more"] = true }},
		{"multiple units", func(e map[string]any) {
			stripeFixtureObject(e)["line_items"].(map[string]any)["data"].([]any)[0].(map[string]any)["quantity"] = 2
		}},
		{"multiple items", func(e map[string]any) {
			items := stripeFixtureObject(e)["line_items"].(map[string]any)
			data := items["data"].([]any)
			items["data"] = append(data, data[0])
		}},

		{"wrong currency", func(e map[string]any) { stripeFixtureObject(e)["currency"] = "eur" }},
		{"wrong mode", func(e map[string]any) { stripeFixtureObject(e)["mode"] = "subscription" }},
		{"livemode true", func(e map[string]any) { e["livemode"] = true }},
		{"missing livemode", func(e map[string]any) { delete(e, "livemode") }},
		{"object livemode true", func(e map[string]any) { stripeFixtureObject(e)["livemode"] = true }},
		{"unknown event type", func(e map[string]any) { e["type"] = "payment_intent.succeeded" }},
		{"unpaid", func(e map[string]any) { stripeFixtureObject(e)["payment_status"] = "unpaid" }},
		{"missing price without API", func(e map[string]any) { delete(stripeFixtureObject(e), "line_items") }},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := stripeServer(t)
			e := stripeFixture("checkout.session.completed")
			c.change(e)
			w := stripeRequest(s, e)
			if w.Code < 400 {
				t.Fatalf("accepted %s", c.name)
			}
			if stripeRows(t, s, "licenses") != 0 || stripeRows(t, s, "stripe_events") != 0 {
				t.Fatal("rejected event mutated storage")
			}
		})
	}
}

func TestStripeLifecycle(t *testing.T) {
	s := stripeServer(t)
	e := stripeFixture("checkout.session.completed")
	expect(t, stripeRequest(s, e), 200)
	expect(t, stripeRequest(s, e), 200)
	if stripeRows(t, s, "licenses") != 1 || stripeRows(t, s, "stripe_events") != 1 || stripeRows(t, s, "stripe_purchases") != 1 {
		t.Fatal("replay duplicated rows")
	}
	raw, _ := json.Marshal(e)
	expect(t, stripeRawRequest(s, append(raw, ' '), stripeHeader(s.cfg.StripeWebhookSecret, raw, s.now())), 401)
	r := httptest.NewRequest("POST", "/api/v1/licenses/activate", strings.NewReader(`{"orderId":"cs_test_fixture","installLabel":"fixture-install","platform":"macos"}`))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	expect(t, w, 200)
	token := tokenFrom(t, w)
	if _, err := VerifyToken(s.publicKey, token, s.now()); err != nil {
		t.Fatal(err)
	}
	expect(t, stripeRequest(s, stripeFixture("charge.refunded")), 200)
	expect(t, stripeRequest(s, stripeFixture("charge.refunded")), 200)
	e["id"] = "evt_late_completion"
	expect(t, stripeRequest(s, e), 200)
	var status string
	if err := s.db.QueryRow("SELECT status FROM licenses").Scan(&status); err != nil || status != "revoked" {
		t.Fatal("refund not terminal", err)
	}
	r = httptest.NewRequest("POST", "/api/v1/licenses/validate", strings.NewReader(`{"token":"`+token+`"}`))
	r.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	expect(t, w, 403)
}

func TestStripeRejectedRefundDoesNotRevoke(t *testing.T) {
	cases := []struct {
		name   string
		change func(map[string]any)
	}{
		{"live event", func(e map[string]any) { e["livemode"] = true }},
		{"live charge", func(e map[string]any) { stripeFixtureObject(e)["livemode"] = true }},
		{"wrong amount", func(e map[string]any) { stripeFixtureObject(e)["amount"] = 500 }},
		{"wrong currency", func(e map[string]any) { stripeFixtureObject(e)["currency"] = "eur" }},
		{"no refund", func(e map[string]any) { stripeFixtureObject(e)["amount_refunded"] = 0 }},
		{"unknown binding", func(e map[string]any) { stripeFixtureObject(e)["payment_intent"] = "pi_unknown" }},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := stripeServer(t)
			expect(t, stripeRequest(s, stripeFixture("checkout.session.completed")), 200)
			e := stripeFixture("charge.refunded")
			c.change(e)
			if w := stripeRequest(s, e); w.Code < 400 {
				t.Fatal("invalid refund accepted")
			}
			var status string
			if err := s.db.QueryRow("SELECT status FROM licenses").Scan(&status); err != nil || status != "active" {
				t.Fatal("invalid refund revoked license", err)
			}
			if stripeRows(t, s, "stripe_events") != 1 {
				t.Fatal("invalid refund recorded")
			}
		})
	}
}

func TestStripeWebhookSignatureRejections(t *testing.T) {
	for _, name := range []string{"missing", "wrong secret", "tampered", "stale", "duplicate timestamp", "missing v1"} {
		t.Run(name, func(t *testing.T) {
			s := stripeServer(t)
			body, _ := json.Marshal(stripeFixture("checkout.session.completed"))
			header := stripeHeader(s.cfg.StripeWebhookSecret, body, s.now())
			switch name {
			case "missing":
				header = ""
			case "wrong secret":
				header = stripeHeader("wrong", body, s.now())
			case "tampered":
				body = append(body, ' ')
			case "stale":
				header = stripeHeader(s.cfg.StripeWebhookSecret, body, s.now().Add(-301*time.Second))
			case "duplicate timestamp":
				header += ",t=1800000000"
			case "missing v1":
				header = strings.Split(header, ",")[0] + ",v0=unsupported"
			}
			w := stripeRawRequest(s, body, header)
			expect(t, w, 401)
			if w.Body.String() != "invalid signature\n" || w.Header().Get("Cache-Control") != "no-store" {
				t.Fatal("signature response is not generic/no-store")
			}
			if stripeRows(t, s, "licenses") != 0 || stripeRows(t, s, "stripe_events") != 0 {
				t.Fatal("signature rejection mutated storage")
			}
		})
	}
}

func TestStripeRefundUnknownBinding(t *testing.T) {
	s := stripeServer(t)
	expect(t, stripeRequest(s, stripeFixture("charge.refunded")), 400)
	if stripeRows(t, s, "licenses") != 0 || stripeRows(t, s, "stripe_events") != 0 {
		t.Fatal("unknown refund mutated storage")
	}
	// The rejected delivery may be retried after its completion arrives.
	expect(t, stripeRequest(s, stripeFixture("checkout.session.completed")), 200)
	expect(t, stripeRequest(s, stripeFixture("charge.refunded")), 200)
}
func TestStripeExpiredAndConflict(t *testing.T) {
	s := stripeServer(t)
	expect(t, stripeRequest(s, stripeFixture("checkout.session.expired")), 200)
	if stripeRows(t, s, "licenses") != 0 {
		t.Fatal("expired checkout issued license")
	}
	e := stripeFixture("checkout.session.completed")
	expect(t, stripeRequest(s, e), 200)
	stripeFixtureObject(e)["ignored_field"] = "changed"
	expect(t, stripeRequest(s, e), 409)
}

func TestStripeCheckoutAndLineItemLookup(t *testing.T) {
	s := stripeServer(t)
	s.cfg.StripeSecretKey = "sk_test_local_fixture"
	var checkoutCalls, lineCalls int
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer sk_test_local_fixture" {
			t.Error("missing API authentication")
		}
		switch r.URL.Path {
		case "/v1/checkout/sessions":
			checkoutCalls++
			if r.Method != "POST" {
				t.Error("wrong method")
			}
			r.ParseForm()
			for k, v := range map[string]string{"mode": "payment", "line_items[0][price]": "price_fixture", "line_items[0][quantity]": "1", "success_url": stripeSuccessURL, "cancel_url": stripeReturnURL, "payment_method_types[0]": "card"} {
				if r.Form.Get(k) != v {
					t.Errorf("wrong %s", k)
				}
			}
			w.Write([]byte(`{"livemode":false,"url":"https://checkout.stripe.com/c/pay/fixture"}`))
		case "/v1/checkout/sessions/cs_test_fixture/line_items":
			lineCalls++
			if r.Method != "GET" {
				t.Error("wrong method")
			}
			w.Write([]byte(`{"data":[{"quantity":1,"price":{"id":"price_fixture","product":"prod_fixture"}}],"has_more":false}`))
		default:
			t.Error("unexpected API path")
			http.NotFound(w, r)
		}
	}))
	defer api.Close()
	s.cfg.StripeAPIBase = api.URL
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, httptest.NewRequest("POST", "/api/v1/checkout", nil))
	expect(t, w, 200)
	e := stripeFixture("checkout.session.completed")
	delete(stripeFixtureObject(e), "line_items")
	expect(t, stripeRequest(s, e), 200)
	if checkoutCalls != 1 || lineCalls != 1 {
		t.Fatal("provider API not exercised")
	}
	s.cfg.StripeSecretKey = ""
	w = httptest.NewRecorder()
	s.Handler().ServeHTTP(w, httptest.NewRequest("POST", "/api/v1/checkout", nil))
	expect(t, w, 503)
}

func TestStripeCheckoutRejectsUnsafeResponses(t *testing.T) {
	cases := []struct {
		name, body string
		status     int
	}{
		{"live", `{"livemode":true,"url":"https://checkout.stripe.com/c/pay/fixture"}`, 200},
		{"missing mode", `{"url":"https://checkout.stripe.com/c/pay/fixture"}`, 200},
		{"wrong domain", `{"livemode":false,"url":"https://example.com/checkout"}`, 200},
		{"http", `{"livemode":false,"url":"http://checkout.stripe.com/c/pay/fixture"}`, 200},
		{"provider error", `{"error":"private provider response"}`, 400},
		{"malformed", `{`, 200},
		{"redirect", ``, 302},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := stripeServer(t)
			s.cfg.StripeSecretKey = "sk_test_local_fixture"
			api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Location", "https://example.invalid/must-not-follow")
				w.WriteHeader(c.status)
				w.Write([]byte(c.body))
			}))
			defer api.Close()
			s.cfg.StripeAPIBase = api.URL
			w := httptest.NewRecorder()
			s.Handler().ServeHTTP(w, httptest.NewRequest("POST", "/api/v1/checkout", nil))
			expect(t, w, 502)
			if w.Body.String() != "{\"error\":\"checkout_unavailable\"}\n" {
				t.Fatal("private provider response escaped")
			}
		})
	}
}

func TestStripeSharedWebhookLimits(t *testing.T) {
	s := stripeServer(t)
	for i := 0; i < 30; i++ {
		expect(t, stripeRawRequest(s, []byte(`{}`), ""), 401)
	}
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, httptest.NewRequest("POST", "/api/v1/webhooks/waffo", nil))
	expect(t, w, 429)
	if w.Header().Get("Retry-After") != "60" {
		t.Fatal("missing shared rate limit")
	}
	w = httptest.NewRecorder()
	s.Handler().ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/health", nil))
	expect(t, w, 200)
	s = stripeServer(t)
	for i := 0; i < cap(s.webhookLimits.slots); i++ {
		s.webhookLimits.slots <- struct{}{}
	}
	expect(t, stripeRawRequest(s, []byte(`{}`), ""), 503)
	for i := 0; i < cap(s.webhookLimits.slots); i++ {
		<-s.webhookLimits.slots
	}
	w = stripeRawRequest(s, []byte(strings.Repeat("x", callbackBodyLimit+1)), "")
	expect(t, w, 400)
	if stripeRows(t, s, "licenses") != 0 {
		t.Fatal("admission failure mutated storage")
	}
}

func TestStripeHealthDoesNotUseDatabase(t *testing.T) {
	s := stripeServer(t)
	s.db.Close()
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/health", nil))
	expect(t, w, 200)
	if w.Body.String() != "ok\n" || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("invalid health response")
	}
}
func TestStripeConfiguration(t *testing.T) {
	s := stripeServer(t)
	base := s.cfg
	for _, field := range []string{"secret", "api key", "price", "product", "live key", "environment", "base"} {
		t.Run(field, func(t *testing.T) {
			c := base
			switch field {
			case "secret":
				c.StripeWebhookSecret = ""
			case "api key":
				c.StripeSecretKey = ""
			case "price":
				c.StripePriceID = ""
			case "product":
				c.ProductID = ""
			case "live key":
				c.StripeSecretKey = "sk_live_not_a_key"
			case "environment":
				c.Environment = "production"
			case "base":
				c.StripeAPIBase = "https://user:password@example.com"
			}
			opened, err := Open(c, s.now)
			if err == nil {
				opened.Close()
				t.Fatal("unsafe configuration started")
			}
		})
	}
}
