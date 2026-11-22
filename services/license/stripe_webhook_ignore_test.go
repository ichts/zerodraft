package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func stripeHTTPDelivery(t *testing.T, receiver *httptest.Server, body []byte, signature string, want int) {
	t.Helper()
	r, err := http.NewRequest(http.MethodPost, receiver.URL+"/api/v1/webhooks/stripe", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	r.Header.Set("Content-Type", "application/json")
	if signature != "" {
		r.Header.Set("Stripe-Signature", signature)
	}
	res, err := receiver.Client().Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	message, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("POST /api/v1/webhooks/stripe: HTTP %d %q", res.StatusCode, strings.TrimSpace(string(message)))
	if res.StatusCode != want {
		t.Errorf("HTTP status = %d, want %d", res.StatusCode, want)
	}
}

func stripeJSON(t *testing.T, event map[string]any) []byte {
	t.Helper()
	body, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func assertStripeRowCounts(t *testing.T, s *Server, count int) {
	t.Helper()
	for _, table := range []string{"licenses", "stripe_purchases", "stripe_events"} {
		if got := stripeRows(t, s, table); got != count {
			t.Errorf("%s row count = %d, want %d", table, got, count)
		}
	}
}

func TestStripeHTTPIgnoresForeignCheckout(t *testing.T) {
	for _, typ := range []string{"checkout.session.completed", "checkout.session.expired"} {
		for _, reason := range []string{"other_price", "other_amount", "other_currency"} {
			t.Run(typ+"/"+reason, func(t *testing.T) {
				s := stripeServer(t)
				event := stripeFixture(typ)
				o := stripeFixtureObject(event)
				if typ == "checkout.session.expired" {
					o["status"], o["payment_status"], o["payment_intent"] = "expired", "unpaid", nil
				}
				// Stripe normally omits line_items. The fake API can supply the other price.
				delete(o, "line_items")
				switch reason {
				case "other_price":
					api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
						if r.Method != http.MethodGet || r.URL.Path != "/v1/checkout/sessions/cs_test_fixture/line_items" {
							t.Errorf("unexpected Stripe API request: %s %s", r.Method, r.URL.Path)
						}
						io.WriteString(w, `{"data":[{"quantity":1,"price":{"id":"price_other_fixture","product":"prod_other_fixture"}}],"has_more":false}`)
					}))
					t.Cleanup(api.Close)
					s.cfg.StripeAPIBase = api.URL
				case "other_amount":
					o["amount_total"] = 899
				case "other_currency":
					o["currency"] = "eur"
				}
				receiver := httptest.NewServer(s.Handler())
				defer receiver.Close()
				body := stripeJSON(t, event)
				stripeHTTPDelivery(t, receiver, body, stripeHeader(stripeFixtureSecret, body, s.now()), 200)
				assertStripeRowCounts(t, s, 0)
			})
		}
	}
}

func TestStripeHTTPIgnoresForeignRefundAndUnknownType(t *testing.T) {
	for _, name := range []string{"refund_for_other_amount", "refund_for_other_currency", "unknown_event_type"} {
		t.Run(name, func(t *testing.T) {
			s := stripeServer(t)
			event := stripeFixture("charge.refunded")
			o := stripeFixtureObject(event)
			o["payment_intent"] = "pi_other_fixture"
			switch name {
			case "refund_for_other_amount":
				o["amount"], o["amount_refunded"] = 899, 899
			case "refund_for_other_currency":
				o["currency"] = "eur"
			case "unknown_event_type":
				event["type"] = "charge.succeeded"
			}
			receiver := httptest.NewServer(s.Handler())
			defer receiver.Close()
			body := stripeJSON(t, event)
			stripeHTTPDelivery(t, receiver, body, stripeHeader(stripeFixtureSecret, body, s.now()), 200)
			assertStripeRowCounts(t, s, 0)
		})
	}
}

func TestStripeHTTPRejectsInvalidEnvelopesBeforeIgnoring(t *testing.T) {
	for _, tc := range []struct {
		name string
		want int
	}{
		{"unsigned", 401},
		{"bad_signature", 401},
		{"wrong_event_mode", 401},
		{"wrong_object_mode", 401},
		{"malformed_event_id", 400},
		{"malformed_json", 401},
		{"missing_event_type", 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := stripeServer(t)
			receiver := httptest.NewServer(s.Handler())
			defer receiver.Close()
			event := stripeFixture("charge.succeeded")
			event["data"] = stripeFixture("charge.refunded")["data"]
			switch tc.name {
			case "wrong_event_mode":
				event["livemode"] = true
			case "wrong_object_mode":
				stripeFixtureObject(event)["livemode"] = true
			case "malformed_event_id":
				event["id"] = "evt_"
			case "missing_event_type":
				delete(event, "type")
			}
			body := stripeJSON(t, event)
			if tc.name == "malformed_json" {
				body = body[:len(body)-1]
			}
			sig := stripeHeader(stripeFixtureSecret, body, s.now())
			switch tc.name {
			case "unsigned":
				sig = ""
			case "bad_signature":
				sig = stripeHeader("wrong-secret", body, s.now())
			}
			stripeHTTPDelivery(t, receiver, body, sig, tc.want)
			assertStripeRowCounts(t, s, 0)
		})
	}
}

func TestStripeHTTPIssuesOneLicenseForWIDCompletionAndReplay(t *testing.T) {
	s := stripeServer(t)
	receiver := httptest.NewServer(s.Handler())
	defer receiver.Close()
	body := stripeJSON(t, stripeFixture("checkout.session.completed"))
	signature := stripeHeader(stripeFixtureSecret, body, s.now())
	for i := 0; i < 2; i++ {
		stripeHTTPDelivery(t, receiver, body, signature, 200)
		assertStripeRowCounts(t, s, 1)
	}
}
