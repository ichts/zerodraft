package main

import (
	"crypto"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const grace = 7 * 24 * time.Hour

type Config struct {
	Database, ProductID, Environment string
	TestPublicKey                    []byte
	TokenKey                         ed25519.PrivateKey
}
type Server struct {
	db        *sql.DB
	cfg       Config
	now       func() time.Time
	publicKey ed25519.PublicKey
}

type event struct {
	ID          string `json:"id"`
	EventType   string `json:"eventType"`
	Environment string `json:"environment"`
	Data        struct {
		OrderID   string `json:"orderId"`
		PaymentID string `json:"paymentId"`
		ProductID string `json:"productId"`
	} `json:"data"`
}
type claim struct {
	LicenseID    string `json:"licenseId"`
	ActivationID string `json:"activationId"`
	InstallLabel string `json:"installLabel"`
	Product      string `json:"product"`
	IssuedAt     int64  `json:"issuedAt"`
	ExpiresAt    int64  `json:"expiresAt"`
}

func Open(cfg Config, now func() time.Time) (*Server, error) {
	if cfg.Database == "" || cfg.ProductID == "" || cfg.Environment != "test" || len(cfg.TokenKey) != ed25519.PrivateKeySize {
		return nil, errors.New("incomplete license configuration")
	}
	if _, err := webhookKey(cfg); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", cfg.Database)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	schema := `PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL;
 CREATE TABLE IF NOT EXISTS licenses (id TEXT PRIMARY KEY, order_id TEXT NOT NULL UNIQUE, payment_id TEXT, status TEXT NOT NULL, created_at INTEGER NOT NULL, revoked_at INTEGER);
 CREATE TABLE IF NOT EXISTS activations (id TEXT PRIMARY KEY, license_id TEXT NOT NULL REFERENCES licenses(id), install_label TEXT NOT NULL, platform TEXT NOT NULL, created_at INTEGER NOT NULL, last_seen_at INTEGER NOT NULL, deactivated_at INTEGER);
 CREATE UNIQUE INDEX IF NOT EXISTS active_install ON activations(license_id, install_label) WHERE deactivated_at IS NULL;
 CREATE TABLE IF NOT EXISTS webhook_events (event_id TEXT PRIMARY KEY, event_type TEXT NOT NULL, received_at INTEGER NOT NULL);`
	if _, err = db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	return &Server{db: db, cfg: cfg, now: now, publicKey: cfg.TokenKey.Public().(ed25519.PublicKey)}, nil
}
func (s *Server) Close() error { return s.db.Close() }
func webhookKey(c Config) (*rsa.PublicKey, error) {
	block, _ := pem.Decode(c.TestPublicKey)
	if block == nil {
		return nil, errors.New("missing webhook public key")
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	rsaKey, ok := key.(*rsa.PublicKey)
	if !ok {
		return nil, errors.New("webhook key must be RSA")
	}
	return rsaKey, nil
}
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/webhooks/waffo", s.webhook)
	mux.HandleFunc("POST /api/v1/licenses/activate", s.activate)
	mux.HandleFunc("POST /api/v1/licenses/validate", s.validate)
	mux.HandleFunc("POST /api/v1/licenses/deactivate", s.deactivate)
	return mux
}
func jsonInput(w http.ResponseWriter, r *http.Request, v any) bool {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		http.Error(w, "JSON required", 415)
		return false
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10))
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		http.Error(w, "invalid request", 400)
		return false
	}
	if d.Decode(new(any)) != io.EOF {
		http.Error(w, "invalid request", 400)
		return false
	}
	return true
}
func respond(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
func (s *Server) webhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 64<<10))
	if err != nil {
		http.Error(w, "invalid request", 400)
		return
	}
	signature, err := base64.StdEncoding.DecodeString(r.Header.Get("X-Waffo-Signature"))
	if err != nil || len(signature) == 0 {
		http.Error(w, "invalid signature", 401)
		return
	}
	key, _ := webhookKey(s.cfg)
	hash := sha256.Sum256(body)
	if rsa.VerifyPKCS1v15(key, crypto.SHA256, hash[:], signature) != nil {
		http.Error(w, "invalid signature", 401)
		return
	}
	var e event
	if json.Unmarshal(body, &e) != nil || e.Environment != s.cfg.Environment {
		http.Error(w, "invalid environment or event", 401)
		return
	}
	if e.ID == "" || e.Data.OrderID == "" || e.Data.ProductID != s.cfg.ProductID || (e.EventType != "order.completed" && e.EventType != "refund.succeeded") {
		http.Error(w, "unsupported event", 400)
		return
	}
	tx, err := s.db.Begin()
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	defer tx.Rollback()
	result, err := tx.Exec("INSERT OR IGNORE INTO webhook_events VALUES (?,?,?)", e.ID, e.EventType, s.now().Unix())
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		respond(w, 200, map[string]string{"status": "duplicate"})
		return
	}
	switch e.EventType {
	case "order.completed":
		// Revocation is terminal; a reordered completion can never restore a refunded license.
		_, err = tx.Exec(`INSERT INTO licenses(id,order_id,payment_id,status,created_at) VALUES(?,?,?,?,?) ON CONFLICT(order_id) DO NOTHING`, randomID(), e.Data.OrderID, e.Data.PaymentID, "active", s.now().Unix())
	case "refund.succeeded":
		// Store a tombstone even if the refund arrives before order.completed.
		_, err = tx.Exec(`INSERT INTO licenses(id,order_id,payment_id,status,created_at,revoked_at) VALUES(?,?,?,?,?,?) ON CONFLICT(order_id) DO UPDATE SET status='revoked',revoked_at=excluded.revoked_at`, randomID(), e.Data.OrderID, e.Data.PaymentID, "revoked", s.now().Unix(), s.now().Unix())
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	respond(w, 200, map[string]string{"status": "accepted"})
}
func randomID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b[:])
}
func (s *Server) activate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		OrderID      string `json:"orderId"`
		InstallLabel string `json:"installLabel"`
		Platform     string `json:"platform"`
	}
	if !jsonInput(w, r, &req) {
		return
	}
	if len(req.OrderID) < 8 || len(req.OrderID) > 100 || len(req.InstallLabel) < 4 || len(req.InstallLabel) > 128 || (req.Platform != "macos" && req.Platform != "windows") {
		http.Error(w, "invalid activation", 400)
		return
	}
	tx, err := s.db.Begin()
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	defer tx.Rollback()
	var license, status string
	if err = tx.QueryRow("SELECT id,status FROM licenses WHERE order_id=?", req.OrderID).Scan(&license, &status); err != nil {
		http.Error(w, "license unavailable", 403)
		return
	}
	if status != "active" {
		http.Error(w, "license unavailable", 403)
		return
	}
	var id, platform string
	var created int64
	err = tx.QueryRow("SELECT id,platform,created_at FROM activations WHERE license_id=? AND install_label=? AND deactivated_at IS NULL", license, req.InstallLabel).Scan(&id, &platform, &created)
	if err == nil && platform != req.Platform {
		http.Error(w, "installation platform mismatch", 409)
		return
	}
	if errors.Is(err, sql.ErrNoRows) {
		var count int
		if tx.QueryRow("SELECT count(*) FROM activations WHERE license_id=? AND deactivated_at IS NULL", license).Scan(&count) != nil {
			http.Error(w, "storage error", 500)
			return
		}
		if count >= 2 {
			http.Error(w, "device limit reached", 409)
			return
		}
		id = randomID()
		created = s.now().Unix()
		_, err = tx.Exec("INSERT INTO activations(id,license_id,install_label,platform,created_at,last_seen_at) VALUES(?,?,?,?,?,?)", id, license, req.InstallLabel, req.Platform, created, created)
	} else if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	issued := s.now().Unix()
	respond(w, 200, map[string]string{"token": s.sign(claim{license, id, req.InstallLabel, s.cfg.ProductID, issued, issued + int64(grace.Seconds())})})
}
func (s *Server) sign(c claim) string {
	b, _ := json.Marshal(c)
	payload := base64.RawURLEncoding.EncodeToString(b)
	signature := ed25519.Sign(s.cfg.TokenKey, []byte(payload))
	return payload + "." + base64.RawURLEncoding.EncodeToString(signature)
}
func VerifyToken(public ed25519.PublicKey, token string, now time.Time) (claim, error) {
	var c claim
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return c, errors.New("invalid token")
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || !ed25519.Verify(public, []byte(parts[0]), sig) {
		return c, errors.New("invalid signature")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil || json.Unmarshal(payload, &c) != nil || c.ExpiresAt <= now.Unix() || c.IssuedAt > now.Unix()+60 || c.ExpiresAt-c.IssuedAt != int64(grace.Seconds()) {
		return c, errors.New("expired or invalid token")
	}
	return c, nil
}
func (s *Server) checked(w http.ResponseWriter, r *http.Request) (claim, bool) {
	var req struct {
		Token string `json:"token"`
	}
	if !jsonInput(w, r, &req) {
		return claim{}, false
	}
	c, err := VerifyToken(s.publicKey, req.Token, s.now())
	if err != nil || c.Product != s.cfg.ProductID {
		http.Error(w, "invalid token", 403)
		return claim{}, false
	}
	return c, true
}
func (s *Server) validate(w http.ResponseWriter, r *http.Request) {
	c, ok := s.checked(w, r)
	if !ok {
		return
	}
	var status, label string
	err := s.db.QueryRow(`SELECT l.status,a.install_label FROM activations a JOIN licenses l ON l.id=a.license_id WHERE a.id=? AND a.license_id=? AND a.deactivated_at IS NULL`, c.ActivationID, c.LicenseID).Scan(&status, &label)
	if err != nil || status != "active" || label != c.InstallLabel {
		http.Error(w, "license unavailable", 403)
		return
	}
	_, err = s.db.Exec("UPDATE activations SET last_seen_at=? WHERE id=?", s.now().Unix(), c.ActivationID)
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	c.IssuedAt = s.now().Unix()
	c.ExpiresAt = c.IssuedAt + int64(grace.Seconds())
	respond(w, 200, map[string]string{"token": s.sign(c)})
}
func (s *Server) deactivate(w http.ResponseWriter, r *http.Request) {
	c, ok := s.checked(w, r)
	if !ok {
		return
	}
	result, err := s.db.Exec(`UPDATE activations SET deactivated_at=? WHERE id=? AND license_id=? AND install_label=? AND deactivated_at IS NULL`, s.now().Unix(), c.ActivationID, c.LicenseID, c.InstallLabel)
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		http.Error(w, "activation unavailable", 403)
		return
	}
	respond(w, 200, map[string]string{"status": "deactivated"})
}
