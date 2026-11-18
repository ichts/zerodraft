// [INPUT] Verified Stripe completion, persistent delivery metadata and a transactional mail provider.
// [OUTPUT] One license email per purchase, with bounded idempotent retries and no stored buyer email.
// [POS] Stripe delivery boundary; license issuance remains independent of provider availability.
// [PROTOCOL] Keep README.md and services/license/AGENTS.md aligned with delivery behavior.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"html"
	"io"
	"net/http"
	"net/mail"
	"net/url"
	"strings"
	"time"
)

const licenseMailFrom = "Write It Down <contact@trefoilstudio.com>"
const mailRetryWindow = 23 * time.Hour
const mailLease = 30 * time.Second

// Send must deduplicate identical requests with the same key for at least 24 hours.
// An error can mean an unknown outcome, so callers must not change the key or payload.
type MailProvider interface {
	Send(context.Context, string, LicenseEmail) error
}

type LicenseEmail struct {
	From    string   `json:"from"`
	To      []string `json:"to"`
	Subject string   `json:"subject"`
	Text    string   `json:"text"`
	HTML    string   `json:"html"`
}

// Version 1 is immutable: retries must produce exactly the original provider request.
func licenseEmailV1(recipient, key string) LicenseEmail {
	link := stripeReturnURL + "#activate=" + url.QueryEscape(key)
	return LicenseEmail{
		From: licenseMailFrom, To: []string{recipient}, Subject: "Your Write It Down license key",
		Text: "Your license key:\n" + key + "\n\nActivate in the app\n" + link + "\n\nOr open Write It Down and paste your key into Activate.\n",
		HTML: "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"referrer\" content=\"no-referrer\"></head><body><p>Your license key:</p><p>" + html.EscapeString(key) + "</p><p><a href=\"" + html.EscapeString(link) + "\">Activate in the app</a></p><p>Or open Write It Down and paste your key into Activate.</p></body></html>",
	}
}

func migrateMail(db *sql.DB) error {
	_, err := db.Exec(`CREATE TABLE IF NOT EXISTS license_mail (
 event_id TEXT PRIMARY KEY REFERENCES stripe_events(event_id),
 license_id TEXT NOT NULL UNIQUE REFERENCES licenses(id),
 template_version INTEGER NOT NULL CHECK(template_version=1),
 state TEXT NOT NULL CHECK(state IN ('pending','sending','sent','review','suppressed')),
 first_attempt_at INTEGER, lease_until INTEGER NOT NULL DEFAULT 0, sent_at INTEGER)`)
	return err
}

func buyerEmail(value string) bool {
	address, err := mail.ParseAddress(value)
	return err == nil && address.Address == value && !strings.ContainsAny(value, "\r\n") && len(value) <= 254
}

// Stripe retries carry the original signed body, so the recipient need not be persisted.
// Changed-body redelivery still acknowledges the original receipt but cannot change an email.
func (s *Server) deliverLicense(ctx context.Context, e stripeEvent, body []byte) int {
	if s.cfg.Mailer == nil || e.Type != "checkout.session.completed" {
		return 200
	}
	var state, key, hash, licenseStatus string
	var first sql.NullInt64
	err := s.db.QueryRowContext(ctx, `SELECT m.state,l.order_id,e.payload_hash,l.status,m.first_attempt_at
 FROM license_mail m JOIN licenses l ON l.id=m.license_id JOIN stripe_events e ON e.event_id=m.event_id
 WHERE m.event_id=?`, e.ID).Scan(&state, &key, &hash, &licenseStatus, &first)
	if errors.Is(err, sql.ErrNoRows) { // Pre-email receipts and later events for the same purchase do not backfill.
		return 200
	}
	if err != nil {
		return 500
	}
	if state == "sent" || state == "suppressed" {
		return 200
	}
	digest := sha256.Sum256(body)
	if hash != hex.EncodeToString(digest[:]) {
		return 200
	}
	if licenseStatus != "active" {
		if _, err := s.db.ExecContext(ctx, "UPDATE license_mail SET state='suppressed' WHERE event_id=? AND state!='sent'", e.ID); err != nil {
			return 500
		}
		return 200
	}
	now := s.now().Unix()
	if state == "review" || first.Valid && (now < first.Int64 || now >= first.Int64+int64(mailRetryWindow/time.Second)) {
		if _, err := s.db.ExecContext(ctx, "UPDATE license_mail SET state='review' WHERE event_id=? AND state!='sent'", e.ID); err != nil {
			return 500
		}
		return 503 // Do not send again after the provider's idempotency guarantee expires.
	}
	if !buyerEmail(e.Data.Object.CustomerDetails.Email) {
		return 503
	}
	claimed, err := s.db.ExecContext(ctx, `UPDATE license_mail SET state='sending',first_attempt_at=COALESCE(first_attempt_at,?),lease_until=?
 WHERE event_id=? AND state IN ('pending','sending') AND lease_until<=?`, now, now+int64(mailLease/time.Second), e.ID, now)
	if err != nil {
		return 500
	}
	count, err := claimed.RowsAffected()
	if err != nil {
		return 500
	}
	if count != 1 {
		return 503
	}
	idempotencyKey := "license/" + s.cfg.Environment + "/" + e.ID
	if err := s.cfg.Mailer.Send(ctx, idempotencyKey, licenseEmailV1(e.Data.Object.CustomerDetails.Email, key)); err != nil {
		// Keep the lease after unknown outcomes. No provider error/body enters a log or response.
		return 503
	}
	_, err = s.db.ExecContext(ctx, "UPDATE license_mail SET state='sent',sent_at=?,lease_until=0 WHERE event_id=?", s.now().Unix(), e.ID)
	if err != nil {
		return 500
	}
	return 200
}

const resendAPIBase = "https://api.resend.com"

type ResendMailer struct {
	APIKey   string
	endpoint string
	client   *http.Client
}

// The sending key may only go to Resend itself, or to a loopback sink for local journeys.
func resendEndpoint(base string) (string, error) {
	if base == "" {
		base = resendAPIBase
	}
	u, err := url.Parse(base)
	loopback := u != nil && u.Scheme == "http" && (u.Hostname() == "127.0.0.1" || u.Hostname() == "::1")
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || u.Path != "" || (base != resendAPIBase && !loopback) {
		return "", errors.New("RESEND_API_BASE must be unset or a loopback http URL")
	}
	return base + "/emails", nil
}

func newResendMailer(key string, base ...string) (*ResendMailer, error) {
	if !strings.HasPrefix(key, "re_") || len(key) <= 3 || strings.ContainsAny(key, " \t\r\n") {
		return nil, errors.New("valid RESEND_API_KEY required")
	}
	endpoint, err := resendEndpoint(strings.Join(base, ""))
	if err != nil {
		return nil, err
	}
	return &ResendMailer{APIKey: key, endpoint: endpoint, client: &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}

func (m *ResendMailer) Send(ctx context.Context, key string, message LicenseEmail) error {
	body, err := json.Marshal(message)
	if err != nil {
		return errors.New("email unavailable")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, m.endpoint, bytes.NewReader(body))
	if err != nil {
		return errors.New("email unavailable")
	}
	req.Header.Set("Authorization", "Bearer "+m.APIKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", key)
	response, err := m.client.Do(req)
	if err != nil {
		return errors.New("email unavailable")
	}
	defer response.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(response.Body, (16<<10)+1))
	var accepted struct {
		ID string `json:"id"`
	}
	if err != nil || len(raw) > 16<<10 || response.StatusCode != http.StatusOK || json.Unmarshal(raw, &accepted) != nil || accepted.ID == "" {
		return errors.New("email unavailable")
	}
	return nil
}
