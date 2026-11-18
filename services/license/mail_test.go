package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeMailer struct {
	mu       sync.Mutex
	keys     []string
	messages []LicenseEmail
	err      error
	entered  chan struct{}
	release  chan struct{}
}

func (m *fakeMailer) Send(_ context.Context, key string, message LicenseEmail) error {
	m.mu.Lock()
	m.keys = append(m.keys, key)
	m.messages = append(m.messages, message)
	m.mu.Unlock()
	if m.entered != nil {
		close(m.entered)
		<-m.release
	}
	return m.err
}

func mailFixture() map[string]any {
	e := stripeFixture("checkout.session.completed")
	stripeFixtureObject(e)["customer_details"] = map[string]any{"email": "buyer@example.com"}
	return e
}

func TestLicenseMailCompletedAndReplayed(t *testing.T) {
	s := stripeServer(t)
	m := &fakeMailer{}
	s.cfg.Mailer = m
	e := mailFixture()
	expect(t, stripeRequest(s, e), 200)
	expect(t, stripeRequest(s, e), 200)
	now := s.now().Add(72 * time.Hour)
	s.now = func() time.Time { return now }
	expect(t, stripeRequest(s, e), 200)
	if len(m.messages) != 1 || m.keys[0] != "license/test/evt_fixture_checkout.session.completed" {
		t.Fatal("completion or replay delivery count/key mismatch")
	}
	message := m.messages[0]
	if message.From != licenseMailFrom || message.To[0] != "buyer@example.com" || message.Subject != "Your Write It Down license key" {
		t.Fatal("wrong transactional sender, recipient or subject")
	}
	link := stripeReturnURL + "#activate=cs_test_fixture"
	if !strings.Contains(message.Text, link) || !strings.Contains(message.HTML, `href="`+link+`"`) || !strings.Contains(message.Text, "cs_test_fixture") {
		t.Fatal("buyer cannot recover key and activate link")
	}
	if strings.Contains(message.HTML, "<script") || strings.Contains(message.HTML, "<img") {
		t.Fatal("email must not execute scripts or track opens")
	}
	var sent int64
	if err := s.db.QueryRow("SELECT sent_at FROM license_mail WHERE state='sent'").Scan(&sent); err != nil || sent == 0 {
		t.Fatal("delivery receipt not durable", err)
	}
	// A second Stripe event for the same purchase cannot mail the buyer twice.
	e["id"] = "evt_second_completion"
	expect(t, stripeRequest(s, e), 200)
	if len(m.messages) != 1 {
		t.Fatal("second event mailed the same purchase again")
	}
}

func TestLicenseMailRetryAfterRestartAndUnknownOutcome(t *testing.T) {
	s := stripeServer(t)
	m := &fakeMailer{err: errors.New("private provider body must not escape")}
	s.cfg.Mailer = m
	e := mailFixture()
	response := stripeRequest(s, e)
	expect(t, response, 503)
	if strings.Contains(response.Body.String(), "private") {
		t.Fatal("provider error leaked")
	}
	if stripeRows(t, s, "licenses") != 1 {
		t.Fatal("mail outage rolled back the buyer license")
	}
	// A real reopen proves leases and retry state survive process loss.
	cfg := s.cfg
	now := s.now()
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	restarted, err := Open(cfg, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	defer restarted.Close()
	expect(t, stripeRequest(restarted, e), 503) // in-flight lease has not expired
	if len(m.messages) != 1 {
		t.Fatal("lease did not survive restart")
	}
	now = now.Add(mailLease)
	m.err = nil
	expect(t, stripeRequest(restarted, e), 200)
	if len(m.messages) != 2 || m.keys[0] != m.keys[1] {
		t.Fatal("retry changed idempotency key")
	}
	before, _ := json.Marshal(m.messages[0])
	after, _ := json.Marshal(m.messages[1])
	if string(before) != string(after) {
		t.Fatal("retry changed the provider payload")
	}
	expect(t, stripeRequest(restarted, e), 200)
	if len(m.messages) != 2 {
		t.Fatal("successful retry not persisted")
	}
}

func TestLicenseMailRetryWindowFailsClosed(t *testing.T) {
	for _, advance := range []time.Duration{-time.Second, mailRetryWindow, 25 * time.Hour} {
		t.Run(advance.String(), func(t *testing.T) {
			s := stripeServer(t)
			m := &fakeMailer{err: errors.New("unknown outcome")}
			s.cfg.Mailer = m
			e := mailFixture()
			expect(t, stripeRequest(s, e), 503)
			now := s.now().Add(advance)
			s.now = func() time.Time { return now }
			expect(t, stripeRequest(s, e), 503)
			if len(m.messages) != 1 {
				t.Fatal("unsafe resend outside idempotency window")
			}
			var state string
			if err := s.db.QueryRow("SELECT state FROM license_mail").Scan(&state); err != nil || state != "review" {
				t.Fatal("ambiguous outcome not marked for review", err)
			}
		})
	}
}

func TestLicenseMailConcurrentReplay(t *testing.T) {
	s := stripeServer(t)
	m := &fakeMailer{entered: make(chan struct{}), release: make(chan struct{})}
	s.cfg.Mailer = m
	e := mailFixture()
	done := make(chan *httptest.ResponseRecorder, 1)
	go func() { done <- stripeRequest(s, e) }()
	<-m.entered
	expect(t, stripeRequest(s, e), 503)
	close(m.release)
	expect(t, <-done, 200)
	if len(m.messages) != 1 {
		t.Fatal("concurrent delivery was not leased")
	}
}

func TestLicenseMailRejectsUnpaidInvalidAndChangedRecipient(t *testing.T) {
	for _, name := range []string{"unpaid", "wrong price", "wrong environment", "expired", "refund", "bad signature"} {
		t.Run(name, func(t *testing.T) {
			s := stripeServer(t)
			m := &fakeMailer{}
			s.cfg.Mailer = m
			e := mailFixture()
			switch name {
			case "unpaid":
				stripeFixtureObject(e)["payment_status"] = "unpaid"
			case "wrong price":
				stripeFixtureObject(e)["amount_total"] = 500
			case "wrong environment":
				e["livemode"] = true
			case "expired":
				e["type"] = "checkout.session.expired"
			case "refund":
				e = stripeFixture("charge.refunded")
			}
			if name == "bad signature" {
				raw, _ := json.Marshal(e)
				expect(t, stripeRawRequest(s, raw, "invalid"), 401)
			} else {
				stripeRequest(s, e)
			}
			if len(m.messages) != 0 {
				t.Fatal("nonpurchase event sent email")
			}
		})
	}
	s := stripeServer(t)
	m := &fakeMailer{}
	s.cfg.Mailer = m
	e := mailFixture()
	stripeFixtureObject(e)["customer_details"] = map[string]any{"email": "not-an-address"}
	expect(t, stripeRequest(s, e), 503)
	stripeFixtureObject(e)["customer_details"] = map[string]any{"email": "attacker@example.com"}
	expect(t, stripeRequest(s, e), 200)
	if len(m.messages) != 0 {
		t.Fatal("changed replay redirected buyer's key")
	}
}

func TestLicenseMailRefundSuppressesPendingDelivery(t *testing.T) {
	s := stripeServer(t)
	m := &fakeMailer{err: errors.New("outage")}
	s.cfg.Mailer = m
	e := mailFixture()
	expect(t, stripeRequest(s, e), 503)
	expect(t, stripeRequest(s, stripeFixture("charge.refunded")), 200)
	now := s.now().Add(mailLease)
	s.now = func() time.Time { return now }
	expect(t, stripeRequest(s, e), 200)
	if len(m.messages) != 1 {
		t.Fatal("refunded key was mailed")
	}
}

func TestLicenseMailDoesNotBackfillExistingReceipts(t *testing.T) {
	s := stripeServer(t)
	e := mailFixture()
	expect(t, stripeRequest(s, e), 200)
	m := &fakeMailer{}
	s.cfg.Mailer = m
	expect(t, stripeRequest(s, e), 200)
	if len(m.messages) != 0 || stripeRows(t, s, "license_mail") != 0 {
		t.Fatal("email rollout backfilled an old purchase")
	}
}

func TestLicenseEmailEscapesAndPreservesCredential(t *testing.T) {
	key := `cs_test_<"&+>`
	message := licenseEmailV1("buyer@example.com", key)
	if strings.Contains(message.HTML, key) {
		t.Fatal("key was not HTML escaped")
	}
	link := strings.Split(strings.Split(message.Text, "Activate in the app\n")[1], "\n")[0]
	u, err := url.Parse(link)
	if err != nil || u.RawQuery != "" {
		t.Fatal("key escaped fragment into request query")
	}
	values, _ := url.ParseQuery(u.EscapedFragment())
	if values.Get("activate") != key {
		t.Fatal("activation URL changed credential bytes")
	}
}

type mailTransport func(*http.Request) (*http.Response, error)

func (f mailTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestResendHTTPContract(t *testing.T) {
	for _, status := range []int{200, 302, 400, 409, 429, 500} {
		t.Run(http.StatusText(status), func(t *testing.T) {
			m, err := newResendMailer("re_local_fixture")
			if err != nil {
				t.Fatal(err)
			}
			var calls int
			m.client.Transport = mailTransport(func(r *http.Request) (*http.Response, error) {
				calls++
				if r.URL.String() != "https://api.resend.com/emails" || r.Method != "POST" || r.Header.Get("Authorization") != "Bearer re_local_fixture" || r.Header.Get("Idempotency-Key") != "fixture-event" || r.Header.Get("Content-Type") != "application/json" {
					t.Fatal("wrong provider request")
				}
				var got LicenseEmail
				if err := json.NewDecoder(r.Body).Decode(&got); err != nil || got.From != licenseMailFrom || got.To[0] != "buyer@example.com" {
					t.Fatal("wrong email payload")
				}
				return &http.Response{StatusCode: status, Header: http.Header{"Location": []string{"https://attacker.example"}}, Body: io.NopCloser(strings.NewReader(`{"id":"fixture-email"}`)), Request: r}, nil
			})
			err = m.Send(context.Background(), "fixture-event", licenseEmailV1("buyer@example.com", "cs_test_fixture"))
			if (err == nil) != (status == 200) || calls != 1 {
				t.Fatal("provider status or redirect policy incorrect")
			}
		})
	}
}

func TestResendEndpointNeverSendsTheKeyElsewhere(t *testing.T) {
	for base, ok := range map[string]bool{"": true, "https://api.resend.com": true, "http://127.0.0.1:9": true, "http://[::1]:9": true,
		"https://attacker.example": false, "http://api.resend.com": false, "http://localhost:9": false, "https://api.resend.com/x": false,
		"https://u@api.resend.com": false, "http://127.0.0.1:9?x=1": false, "http://evil.example@127.0.0.1:9": false} {
		_, err := newResendMailer("re_local_fixture", base)
		if (err == nil) != ok {
			t.Fatalf("base %q accepted=%v want %v", base, err == nil, ok)
		}
	}
}
