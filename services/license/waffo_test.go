package main

import (
	"bytes"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
)

func signedWaffoHeader(t *testing.T, key *rsa.PrivateKey, body []byte, at time.Time) string {
	t.Helper()
	return signedWaffoHeaderWithStamp(t, key, body, strconv.FormatInt(at.UnixMilli(), 10))
}

func signedWaffoHeaderWithStamp(t *testing.T, key *rsa.PrivateKey, body []byte, stamp string) string {
	t.Helper()
	hash := sha256.Sum256(append([]byte(stamp+"."), body...))
	signature, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, hash[:])
	if err != nil {
		t.Fatal("synthetic callback signing failed")
	}
	return "t=" + stamp + ",v1=" + base64.StdEncoding.EncodeToString(signature)
}

func callbackResponse(s *Server, body []byte, headers []string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", bytes.NewReader(body))
	r.Header["X-Waffo-Signature"] = headers
	w := httptest.NewRecorder()
	s.Handler().ServeHTTP(w, r)
	return w
}

func expectWaffoSignatureRejection(t *testing.T, s *Server, body []byte, headers []string) {
	t.Helper()
	response := callbackResponse(s, body, headers)
	if response.Code != http.StatusUnauthorized || strings.TrimSpace(response.Body.String()) != "invalid signature" {
		t.Fatal("invalid callback did not fail at the transport authentication boundary")
	}
}

func TestWaffoTimestampedSignatureHTTP(t *testing.T) {
	f := setup(t)
	body := []byte(`{"id":"timestamp-fixture","eventType":"order.completed","environment":"test","data":{"orderId":"ORD_fixture","productId":"wid-test"}}`)
	good := signedWaffoHeader(t, f.signer, body, f.now)
	expect(t, callbackResponse(f.s, body, []string{good}), http.StatusOK)
	for _, delta := range []time.Duration{-45 * time.Minute, time.Minute} {
		header := signedWaffoHeader(t, f.signer, body, f.now.Add(delta))
		expect(t, callbackResponse(f.s, body, []string{header}), http.StatusOK)
	}
	for _, delta := range []time.Duration{-45*time.Minute - time.Millisecond, time.Minute + time.Millisecond} {
		header := signedWaffoHeader(t, f.signer, body, f.now.Add(delta))
		expect(t, callbackResponse(f.s, body, []string{header}), http.StatusUnauthorized)
	}
	changed := strings.Replace(good, "t="+strconv.FormatInt(f.now.UnixMilli(), 10), "t="+strconv.FormatInt(f.now.UnixMilli()+1, 10), 1)
	expect(t, callbackResponse(f.s, body, []string{changed}), http.StatusUnauthorized)
	expect(t, callbackResponse(f.s, append(append([]byte{}, body...), ' '), []string{good}), http.StatusUnauthorized)
	expect(t, callbackResponse(f.s, body, []string{good, good}), http.StatusUnauthorized)
	wrong, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal("synthetic wrong-key setup failed")
	}
	expect(t, callbackResponse(f.s, body, []string{signedWaffoHeader(t, wrong, body, f.now)}), http.StatusUnauthorized)
	hash := sha256.Sum256(body)
	legacy, err := rsa.SignPKCS1v15(rand.Reader, f.signer, crypto.SHA256, hash[:])
	if err != nil {
		t.Fatal("synthetic legacy signing failed")
	}
	expect(t, callbackResponse(f.s, body, []string{base64.StdEncoding.EncodeToString(legacy)}), http.StatusUnauthorized)
	var count int
	if err := f.s.db.QueryRow("SELECT count(*) FROM webhook_events").Scan(&count); err != nil || count != 1 {
		t.Fatal("invalid signatures reached the event ledger")
	}
}

func TestWaffoHeaderParserRejectsAmbiguity(t *testing.T) {
	if _, ok := parseWaffoSignature("t=1792591200000,v1=YQ=="); !ok {
		t.Fatal("canonical t/v1 header rejected")
	}
	for _, header := range []string{"", "t=1", "v1=YQ==", "t=1,t=2", "t=1,v2=YQ==", "t=1,v1=YQ==,v1=YQ==", "t=1,v1=", "t=+1,v1=YQ==", "t=-1,v1=YQ==", "t=0,v1=YQ==", "t=01,v1=YQ==", "v1=YQ==,t=1", "t=1, v1=YQ==", " t=1,v1=YQ==", "t=1,v1=YQ== ", "t=1e3,v1=YQ==", "t=9223372036854775808,v1=YQ==", "t=1,v1=YR==", "t=1,v1=YQ", "t=1,v1=YQ==\r\n", "t=1,v1=Y Q==", strings.Repeat("a", waffoHeaderLimit+1)} {
		if _, ok := parseWaffoSignature(header); ok {
			t.Fatal("ambiguous or malformed signature header accepted")
		}
	}
}

func TestWaffoSignatureBytesPaddingAndOverflow(t *testing.T) {
	f := setup(t)
	body := []byte(" \r\n{\"text\":\"雪\"}\n\xff\x00")
	stamp := strconv.FormatInt(f.now.UnixMilli(), 10)
	header := signedWaffoHeaderWithStamp(t, f.signer, body, stamp)
	if !verifyWaffoSignature(f.s.webhookKey, []string{header}, body, f.now) {
		t.Fatal("exact body bytes rejected")
	}
	if verifyWaffoSignature(f.s.webhookKey, []string{header}, append(append([]byte{}, body...), 0), f.now) {
		t.Fatal("changed binary body accepted")
	}
	hash := sha256.Sum256(append([]byte(stamp+"."), body...))
	signature, err := rsa.SignPKCS1v15(rand.Reader, f.signer, crypto.SHA256, hash[:])
	if err != nil {
		t.Fatal("synthetic callback signing failed")
	}
	pss, err := rsa.SignPSS(rand.Reader, f.signer, crypto.SHA256, hash[:], nil)
	if err != nil {
		t.Fatal("synthetic RSA-PSS signing failed")
	}
	badPadding := "t=" + stamp + ",v1=" + base64.StdEncoding.EncodeToString(pss)
	for _, rejected := range []string{badPadding, "t=9223372036854775807,v1=" + base64.StdEncoding.EncodeToString(signature), "t=" + strconv.FormatInt(f.now.Unix(), 10) + ",v1=" + base64.StdEncoding.EncodeToString(signature)} {
		if verifyWaffoSignature(f.s.webhookKey, []string{rejected}, body, f.now) {
			t.Fatal("wrong padding or timestamp accepted")
		}
	}
	if verifyWaffoSignature(nil, []string{header}, body, f.now) || verifyWaffoSignature(f.s.webhookKey, nil, body, f.now) || verifyWaffoSignature(f.s.webhookKey, []string{header, header}, body, f.now) {
		t.Fatal("missing key or ambiguous signature headers accepted")
	}
}

func TestWaffoNoncanonicalHeadersFailAtSignatureGate(t *testing.T) {
	f := setup(t)
	body := []byte(`{"id":"header-fixture","eventType":"order.completed","environment":"test","data":{"orderId":"ORD_fixture","productId":"wid-test"}}`)
	stamp := strconv.FormatInt(f.now.UnixMilli(), 10)
	canonical := signedWaffoHeaderWithStamp(t, f.signer, body, stamp)
	signature := strings.TrimPrefix(canonical, "t="+stamp+",v1=")
	for _, header := range []string{
		"v1=" + signature + ",t=" + stamp,
		"t=" + stamp + ", v1=" + signature,
		" t=" + stamp + ",v1=" + signature,
		"t=" + stamp + ",v1=" + signature + " ",
		signedWaffoHeaderWithStamp(t, f.signer, body, "0"+stamp),
	} {
		expectWaffoSignatureRejection(t, f.s, body, []string{header})
	}
	if response := callbackResponse(f.s, body, []string{canonical}); response.Code != http.StatusOK {
		t.Fatal("canonical signed callback rejected")
	}
}
