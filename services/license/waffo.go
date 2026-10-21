// [INPUT] Pinned TEST RSA key, bounded raw callback body, signature headers and clock.
// [OUTPUT] Documented t/v1 signature verification with bounded replay freshness.
// [POS] Callback transport authentication only; no event mapping or license writes.
// [PROTOCOL] Keep this header and AGENTS.md aligned with README.md.
package main

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"strconv"
	"strings"
	"time"
)

const (
	waffoPastTolerance   = 45 * time.Minute
	waffoFutureTolerance = time.Minute
	waffoHeaderLimit     = 4096
)

type waffoSignature struct {
	timestampText string
	timestampMS   int64
	bytes         []byte
}

func parseWaffoSignature(header string) (waffoSignature, bool) {
	var result waffoSignature
	if len(header) == 0 || len(header) > waffoHeaderLimit || strings.ContainsAny(header, "\r\n") {
		return result, false
	}
	value, ok := strings.CutPrefix(header, "t=")
	if !ok {
		return result, false
	}
	stamp, encoded, ok := strings.Cut(value, ",v1=")
	if !ok || len(stamp) == 0 || len(stamp) > 19 || stamp[0] == '0' || strings.IndexFunc(stamp, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
		return result, false
	}
	millis, err := strconv.ParseInt(stamp, 10, 64)
	if err != nil || millis <= 0 {
		return result, false
	}
	signature, err := base64.StdEncoding.Strict().DecodeString(encoded)
	if err != nil || len(signature) == 0 {
		return result, false
	}
	return waffoSignature{timestampText: stamp, timestampMS: millis, bytes: signature}, true
}

func verifyWaffoSignature(key *rsa.PublicKey, headers []string, body []byte, now time.Time) bool {
	if key == nil || len(headers) != 1 {
		return false
	}
	signature, ok := parseWaffoSignature(headers[0])
	if !ok {
		return false
	}
	// Bound the signed timestamp, not now-t: hostile integers must not overflow subtraction.
	current := now.UnixMilli()
	if signature.timestampMS < current-waffoPastTolerance.Milliseconds() || signature.timestampMS > current+waffoFutureTolerance.Milliseconds() {
		return false
	}
	hash := sha256.New()
	hash.Write([]byte(signature.timestampText + "."))
	hash.Write(body)
	return rsa.VerifyPKCS1v15(key, crypto.SHA256, hash.Sum(nil), signature.bytes) == nil
}
