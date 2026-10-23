// [INPUT] Raw Stripe TEST callbacks, configured price/product, API secrets and clock.
// [OUTPUT] Authenticated event receipts, session/payment-intent bindings and licenses.
// [POS] Stripe-only adapter beside the unchanged Waffo verifier and business mapping.
// [PROTOCOL] Keep this header and AGENTS.md aligned with README.md.
package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const stripeReturnURL = "https://writeitdown.app/mac.html"

func configureStripe(c *Config) error {
	if c.Environment != "test" || c.StripeWebhookSecret == "" || c.StripePriceID == "" || c.StripeProductID == "" || c.ProductID != c.StripeProductID {
		return errors.New("Stripe TEST webhook secret, price and matching product required")
	}
	if c.StripeSecretKey != "" && !strings.HasPrefix(c.StripeSecretKey, "sk_test_") {
		return errors.New("Stripe requires a TEST secret key")
	}
	if c.StripeAPIBase == "" {
		c.StripeAPIBase = "https://api.stripe.com"
	}
	u, err := url.Parse(c.StripeAPIBase)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || u.Path != "" || (u.Scheme != "https" && !(u.Scheme == "http" && (u.Hostname() == "127.0.0.1" || u.Hostname() == "::1"))) {
		return errors.New("invalid Stripe API base URL")
	}
	return nil
}

func verifyStripeSignature(secret string, headers []string, body []byte, now time.Time) bool {
	if secret == "" || len(headers) != 1 {
		return false
	}
	var timestamp string
	var timestampSeen bool
	var signatures [][]byte
	for _, part := range strings.Split(headers[0], ",") {
		pair := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(pair) != 2 {
			return false
		}
		switch pair[0] {
		case "t":
			if timestampSeen {
				return false
			}
			timestampSeen = true
			timestamp = pair[1]
		case "v1":
			if len(pair[1]) != 64 || strings.ToLower(pair[1]) != pair[1] {
				return false
			}
			sig, err := hex.DecodeString(pair[1])
			if err != nil {
				return false
			}
			signatures = append(signatures, sig)
		default:
			return false
		}
	}
	seconds, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil || seconds <= 0 || strconv.FormatInt(seconds, 10) != timestamp || len(signatures) == 0 {
		return false
	}
	signedAt := time.Unix(seconds, 0)
	if signedAt.Before(now.Add(-300*time.Second)) || signedAt.After(now.Add(300*time.Second)) {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(timestamp + "."))
	mac.Write(body)
	expected := mac.Sum(nil)
	valid := false
	for _, sig := range signatures {
		// Evaluate every candidate, even after a match, for key-rotation deliveries.
		match := hmac.Equal(expected, sig)
		valid = match || valid
	}
	return valid
}

func migrateStripe(db *sql.DB) error {
	_, err := db.Exec(`CREATE TABLE IF NOT EXISTS stripe_events (
 event_id TEXT PRIMARY KEY, event_type TEXT NOT NULL, payload_hash TEXT NOT NULL, received_at INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS stripe_purchases (
 session_id TEXT PRIMARY KEY, payment_intent TEXT NOT NULL UNIQUE,
 license_id TEXT NOT NULL UNIQUE REFERENCES licenses(id), price_id TEXT NOT NULL, product_id TEXT NOT NULL,
 amount INTEGER NOT NULL CHECK(amount=499), currency TEXT NOT NULL CHECK(currency='usd'),
 mode TEXT NOT NULL CHECK(mode='payment'))`)
	return err
}

type stripeLines struct {
	Data []struct {
		Quantity int `json:"quantity"`
		Price    struct {
			ID      string `json:"id"`
			Product string `json:"product"`
		} `json:"price"`
	} `json:"data"`
	HasMore bool `json:"has_more"`
}

type stripeObject struct {
	ID             string       `json:"id"`
	Livemode       *bool        `json:"livemode"`
	PaymentIntent  string       `json:"payment_intent"`
	AmountTotal    *int         `json:"amount_total"`
	Amount         *int         `json:"amount"`
	AmountRefunded int          `json:"amount_refunded"`
	Currency       string       `json:"currency"`
	Mode           string       `json:"mode"`
	Status         string       `json:"status"`
	PaymentStatus  string       `json:"payment_status"`
	LineItems      *stripeLines `json:"line_items"`
}

type stripeEvent struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Livemode *bool  `json:"livemode"`
	Data     struct {
		Object stripeObject `json:"object"`
	} `json:"data"`
}

func stripeTest(mode *bool) bool { return mode != nil && !*mode }
func stripeID(id, prefix string) bool {
	return strings.HasPrefix(id, prefix) && len(id) >= 8 && len(id) <= 100
}

func (s *Server) stripeWebhook(w http.ResponseWriter, r *http.Request) {
	if s.cfg.Provider != "stripe" {
		http.Error(w, "provider unavailable", 503)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, callbackBodyLimit))
	if err != nil {
		http.Error(w, "invalid request", 400)
		return
	}
	if !verifyStripeSignature(s.cfg.StripeWebhookSecret, r.Header.Values("Stripe-Signature"), body, s.now()) {
		http.Error(w, "invalid signature", 401)
		return
	}
	var e stripeEvent
	if json.Unmarshal(body, &e) != nil || !stripeTest(e.Livemode) || !stripeTest(e.Data.Object.Livemode) {
		http.Error(w, "invalid environment or event", 401)
		return
	}
	if !stripeID(e.ID, "evt_") {
		http.Error(w, "unsupported event", 400)
		return
	}
	switch e.Type {
	case "checkout.session.completed", "checkout.session.expired":
		if !s.stripeSessionAllowed(r.Context(), e.Data.Object, e.Type == "checkout.session.completed") {
			http.Error(w, "session not verified", 400)
			return
		}
	case "charge.refunded":
		o := e.Data.Object
		if !stripeID(o.PaymentIntent, "pi_") || o.Amount == nil || *o.Amount != 499 || o.Currency != "usd" || o.AmountRefunded <= 0 || o.AmountRefunded > 499 {
			http.Error(w, "refund not verified", 400)
			return
		}
	default:
		http.Error(w, "unsupported event", 400)
		return
	}
	status := s.applyStripeEvent(e, body)
	if status != 200 {
		http.Error(w, "event not accepted", status)
		return
	}
	respond(w, 200, map[string]string{"status": "accepted"})
}

func (s *Server) stripeSessionAllowed(ctx context.Context, o stripeObject, completed bool) bool {
	if !stripeID(o.ID, "cs_") || o.AmountTotal == nil || *o.AmountTotal != 499 || o.Currency != "usd" || o.Mode != "payment" {
		return false
	}
	if completed && (!stripeID(o.PaymentIntent, "pi_") || o.PaymentStatus != "paid" || o.Status != "complete") {
		return false
	}
	lines := o.LineItems
	if lines == nil {
		lines = new(stripeLines)
		if s.stripeAPI(ctx, http.MethodGet, "/v1/checkout/sessions/"+url.PathEscape(o.ID)+"/line_items", nil, lines) != nil {
			return false
		}
	}
	return !lines.HasMore && len(lines.Data) == 1 && lines.Data[0].Quantity == 1 && lines.Data[0].Price.ID == s.cfg.StripePriceID && lines.Data[0].Price.Product == s.cfg.StripeProductID
}

func (s *Server) applyStripeEvent(e stripeEvent, body []byte) int {
	tx, err := s.db.Begin()
	if err != nil {
		return 500
	}
	defer tx.Rollback()
	hash := sha256.Sum256(body)
	payloadHash := hex.EncodeToString(hash[:])
	var previous string
	err = tx.QueryRow("SELECT payload_hash FROM stripe_events WHERE event_id=?", e.ID).Scan(&previous)
	if err == nil {
		if previous == payloadHash {
			return 200
		}
		return 409
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 500
	}
	o := e.Data.Object
	err = nil
	switch e.Type {
	case "checkout.session.completed":
		err = s.stripeIssue(tx, o)
	case "charge.refunded":
		var license string
		err = tx.QueryRow(`SELECT license_id FROM stripe_purchases WHERE payment_intent=? AND price_id=? AND product_id=? AND amount=499 AND currency='usd' AND mode='payment'`, o.PaymentIntent, s.cfg.StripePriceID, s.cfg.StripeProductID).Scan(&license)
		if errors.Is(err, sql.ErrNoRows) {
			return 400
		}
		if err == nil {
			_, err = tx.Exec("UPDATE licenses SET status='revoked',revoked_at=? WHERE id=?", s.now().Unix(), license)
		}
	}
	if err != nil {
		return 500
	}
	_, err = tx.Exec("INSERT INTO stripe_events(event_id,event_type,payload_hash,received_at) VALUES(?,?,?,?)", e.ID, e.Type, payloadHash, s.now().Unix())
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		return 500
	}
	return 200
}

func (s *Server) stripeIssue(tx *sql.Tx, o stripeObject) error {
	var intent string
	err := tx.QueryRow("SELECT payment_intent FROM stripe_purchases WHERE session_id=?", o.ID).Scan(&intent)
	if err == nil {
		if intent != o.PaymentIntent {
			return errors.New("session binding conflict")
		}
		return nil // A later completion must never restore a revoked license.
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	license := randomID()
	_, err = tx.Exec("INSERT INTO licenses(id,order_id,status,created_at) VALUES(?,?,'active',?)", license, o.ID, s.now().Unix())
	if err != nil {
		return err
	}
	_, err = tx.Exec(`INSERT INTO stripe_purchases(session_id,payment_intent,license_id,price_id,product_id,amount,currency,mode) VALUES(?,?,?,?,?,499,'usd','payment')`, o.ID, o.PaymentIntent, license, s.cfg.StripePriceID, s.cfg.StripeProductID)
	return err
}

func (s *Server) stripeAPI(ctx context.Context, method, path string, form url.Values, out any) error {
	if s.cfg.StripeSecretKey == "" {
		return errors.New("Stripe unavailable")
	}
	req, err := http.NewRequestWithContext(ctx, method, s.cfg.StripeAPIBase+path, strings.NewReader(form.Encode()))
	if err != nil {
		return errors.New("Stripe unavailable")
	}
	req.Header.Set("Authorization", "Bearer "+s.cfg.StripeSecretKey)
	req.Header.Set("Stripe-Version", "2025-02-24.acacia")
	if method == http.MethodPost {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	client := &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	res, err := client.Do(req)
	if err != nil {
		return errors.New("Stripe unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return errors.New("Stripe unavailable")
	}
	raw, err := io.ReadAll(io.LimitReader(res.Body, (64<<10)+1))
	if err != nil || len(raw) > 64<<10 || json.Unmarshal(raw, out) != nil {
		return errors.New("invalid Stripe response")
	}
	return nil
}

func (s *Server) stripeCheckout(w http.ResponseWriter, r *http.Request) {
	if s.cfg.StripeSecretKey == "" {
		respond(w, 503, map[string]string{"error": "checkout_not_configured"})
		return
	}
	form := url.Values{"mode": {"payment"}, "line_items[0][price]": {s.cfg.StripePriceID}, "line_items[0][quantity]": {"1"}, "success_url": {stripeReturnURL}, "cancel_url": {stripeReturnURL}, "payment_method_types[0]": {"card"}}
	var session struct {
		URL      string `json:"url"`
		Livemode *bool  `json:"livemode"`
	}
	if s.stripeAPI(r.Context(), http.MethodPost, "/v1/checkout/sessions", form, &session) != nil || !stripeTest(session.Livemode) {
		respond(w, 502, map[string]string{"error": "checkout_unavailable"})
		return
	}
	u, err := url.Parse(session.URL)
	if err != nil || u.Scheme != "https" || u.Host != "checkout.stripe.com" || u.User != nil {
		respond(w, 502, map[string]string{"error": "checkout_unavailable"})
		return
	}
	respond(w, 200, map[string]string{"url": session.URL})
}
