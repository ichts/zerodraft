// Package licence is the Windows client of the existing Write It Down licence service, a port of the Mac
// Licensing/ code and the licence half of AppState: same endpoints, request and response shapes, token
// contract, offline grace and error states. The service is never changed for it.
package licence

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// Claims are the signed token payload (Mac LicenseClaims). Timestamps are Unix seconds.
type Claims struct {
	LicenseID    string `json:"licenseId"`
	ActivationID string `json:"activationId"`
	InstallLabel string `json:"installLabel"`
	Product      string `json:"product"`
	IssuedAt     int64  `json:"issuedAt"`
	ExpiresAt    int64  `json:"expiresAt"`
}

// Lifetime is the signed token lifetime the service issues: exactly seven days.
const Lifetime = tokens.LicenseTokenLifetimeSeconds

// ErrInvalidToken is the verifier's one failure (Mac LicenseActivationError.invalidToken).
var ErrInvalidToken = errors.New("licence: invalid token")

// Verifier checks tokens against the pinned Ed25519 public key (Mac LicenseTokenVerifier).
type Verifier struct {
	key       ed25519.PublicKey
	ProductID string
}

// NewVerifier takes the raw 32-byte public key, as the Info.plist carries it in base64.
func NewVerifier(key []byte, productID string) (*Verifier, error) {
	if len(key) != ed25519.PublicKeySize {
		return nil, errors.New("licence: public key is not 32 bytes")
	}
	return &Verifier{key: ed25519.PublicKey(key), ProductID: productID}, nil
}

// Verify authenticates `base64url(payload).base64url(signature)` (unpadded; the signature covers the ENCODED
// payload text) and checks product, installation, issue time (at most 60 s ahead), exact seven-day lifetime and
// that it has not expired.
func (v *Verifier) Verify(token, installLabel string, now time.Time) (Claims, error) {
	var c Claims
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return c, ErrInvalidToken
	}
	sig, ok := decode(parts[1])
	if !ok || !ed25519.Verify(v.key, []byte(parts[0]), sig) {
		return c, ErrInvalidToken
	}
	payload, ok := decode(parts[0])
	if !ok || json.Unmarshal(payload, &c) != nil {
		return c, ErrInvalidToken
	}
	n := now.Unix()
	nowF := float64(now.UnixNano()) / 1e9
	if v.ProductID == "" || c.Product != v.ProductID || installLabel == "" || c.InstallLabel != installLabel ||
		c.LicenseID == "" || c.ActivationID == "" || c.IssuedAt < 0 ||
		float64(c.IssuedAt) > nowF+60 || float64(c.ExpiresAt) <= nowF ||
		c.ExpiresAt <= c.IssuedAt || c.ExpiresAt-c.IssuedAt != Lifetime || n < 0 {
		return Claims{}, ErrInvalidToken
	}
	return c, nil
}

// decode is the strict unpadded base64url the service writes.
func decode(s string) ([]byte, bool) {
	if s == "" {
		return nil, false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return nil, false
		}
	}
	b, err := base64.RawURLEncoding.DecodeString(s)
	return b, err == nil
}
