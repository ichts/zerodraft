package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func TestHTTPWaffoSignatureGrammar(t *testing.T) {
	f := setup(t)
	server := httptest.NewServer(f.s.Handler())
	defer server.Close()
	body := []byte(`{"id":"grammar","eventType":"order.completed","environment":"test","data":{"orderId":"ORD_grammar","productId":"wid-test"}}`)
	stamp := strconv.FormatInt(f.now.UnixMilli(), 10)
	canonical := signedWaffoHeaderWithStamp(t, f.signer, body, stamp)
	signature := strings.TrimPrefix(canonical, "t="+stamp+",v1=")
	for _, tc := range []struct {
		name, header string
		want         int
	}{
		{"canonical", canonical, http.StatusOK},
		{"reversed", "v1=" + signature + ",t=" + stamp, http.StatusUnauthorized},
		{"whitespace", "t=" + stamp + ", v1=" + signature, http.StatusUnauthorized},
		{"leading-zero", signedWaffoHeaderWithStamp(t, f.signer, body, "0"+stamp), http.StatusUnauthorized},
	} {
		t.Run(tc.name, func(t *testing.T) {
			request, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/webhooks/waffo", bytes.NewReader(body))
			if err != nil {
				t.Fatal(err)
			}
			request.Header.Set("X-Waffo-Signature", tc.header)
			response, err := server.Client().Do(request)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			message, err := io.ReadAll(response.Body)
			if err != nil || response.StatusCode != tc.want {
				t.Fatalf("callback status = %d, want %d, read error = %v", response.StatusCode, tc.want, err)
			}
			if tc.want == http.StatusUnauthorized && strings.TrimSpace(string(message)) != "invalid signature" {
				t.Fatal("malformed signed header did not fail at signature gate")
			}
			t.Logf("POST /api/v1/webhooks/waffo (%s): HTTP %d, response %q", tc.name, response.StatusCode, strings.TrimSpace(string(message)))
		})
	}
}

// Synthetic signed events exercise the provisional license envelope, not provider business mapping.
func TestHTTPLicenseLifecycle(t *testing.T) {
	f := setup(t)
	server := httptest.NewServer(f.s.Handler())
	defer server.Close()
	post := func(path string, body any, signed bool, want int) []byte {
		t.Helper()
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		r, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/"+path, bytes.NewReader(raw))
		if err != nil {
			t.Fatal(err)
		}
		r.Header.Set("Content-Type", "application/json")
		if signed {
			r.Header.Set("X-Waffo-Signature", signedWaffoHeader(t, f.signer, raw, f.s.now()))
		}
		response, err := server.Client().Do(r)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		data, err := io.ReadAll(response.Body)
		if err != nil || response.StatusCode != want {
			t.Fatalf("%s: status=%d want=%d read error=%v", path, response.StatusCode, want, err)
		}
		if response.Header.Get("Cache-Control") != "no-store" {
			t.Fatal("credential response can be cached")
		}
		return data
	}
	post("checkout", map[string]string{}, false, http.StatusServiceUnavailable)
	body := map[string]any{"id": "test-completion", "eventType": "order.completed", "environment": "test", "data": map[string]string{"orderId": "ORD_network_test", "productId": "wid-test"}}
	post("webhooks/waffo", body, false, http.StatusUnauthorized)
	post("webhooks/waffo", body, true, http.StatusOK)
	post("webhooks/waffo", body, true, http.StatusOK)
	activation := map[string]string{"orderId": "ORD_network_test", "installLabel": "install-one", "platform": "macos"}
	var issued struct{ Token string }
	if err := json.Unmarshal(post("licenses/activate", activation, false, http.StatusOK), &issued); err != nil || issued.Token == "" {
		t.Fatal("missing activation token", err)
	}
	claims, err := VerifyToken(f.s.publicKey, issued.Token, f.now)
	if err != nil || claims.InstallLabel != "install-one" || claims.Product != "wid-test" {
		t.Fatal("token binding mismatch", err)
	}
	activation["installLabel"] = "install-two"
	post("licenses/activate", activation, false, http.StatusOK)
	activation["installLabel"] = "install-three"
	post("licenses/activate", activation, false, http.StatusConflict)
	post("licenses/validate", map[string]string{"token": issued.Token}, false, http.StatusOK)
	body["id"], body["eventType"] = "test-refund", "refund.succeeded"
	post("webhooks/waffo", body, true, http.StatusOK)
	post("licenses/validate", map[string]string{"token": issued.Token}, false, http.StatusForbidden)
	post("licenses/activate", activation, false, http.StatusForbidden)
	body["id"], body["eventType"] = "test-late-completion", "order.completed"
	post("webhooks/waffo", body, true, http.StatusOK)
	post("licenses/activate", activation, false, http.StatusForbidden)
}
