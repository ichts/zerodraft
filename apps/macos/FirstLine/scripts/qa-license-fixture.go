// [INPUT]: Ready JSON path and mode-file path, both in a disposable QA directory.
// [OUTPUT]: Loopback-only license HTTP fixture with a fresh in-memory Ed25519 key.
// [POS]: Native-window QA support, not Waffo integration or purchase evidence.
// [PROTOCOL]: Keep the wire shape aligned with services/license and LICENSE_PAYMENT_SPEC.md.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

func main() {
	if len(os.Args) != 3 {
		panic("usage: qa-license-fixture ready.json mode-file")
	}
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		panic(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	defer listener.Close()
	ready, err := json.Marshal(map[string]string{
		"WIDLicenseServiceURL": "http://" + listener.Addr().String(),
		"WIDLicenseProductID":  "window-qa-product",
		"WIDLicensePublicKey":  base64.StdEncoding.EncodeToString(public),
	})
	if err != nil {
		panic(err)
	}
	if err := os.WriteFile(os.Args[1], ready, 0600); err != nil {
		panic(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/licenses/", func(w http.ResponseWriter, r *http.Request) {
		mode, err := os.ReadFile(os.Args[2])
		if err != nil {
			http.Error(w, "fixture mode missing", 500)
			return
		}
		switch strings.TrimSpace(string(mode)) {
		case "offline":
			http.Error(w, "fixture unavailable", 503)
			return
		case "refunded":
			http.Error(w, "license unavailable", 403)
			return
		}
		var request map[string]string
		if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&request) != nil {
			http.Error(w, "invalid JSON", 400)
			return
		}
		if r.URL.Path == "/api/v1/licenses/validate" {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{"token": request["token"]})
			return
		}
		if r.URL.Path != "/api/v1/licenses/activate" || request["orderId"] != "window-qa-order" || request["platform"] != "macos" || request["installLabel"] == "" {
			http.Error(w, "license unavailable", 403)
			return
		}
		now := time.Now().Unix()
		payload, err := json.Marshal(map[string]any{
			"licenseId": "window-qa-license", "activationId": "window-qa-activation",
			"installLabel": request["installLabel"], "product": "window-qa-product",
			"issuedAt": now, "expiresAt": now + 7*24*60*60,
		})
		if err != nil {
			http.Error(w, "fixture encoding error", 500)
			return
		}
		encoded := base64.RawURLEncoding.EncodeToString(payload)
		token := encoded + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(private, []byte(encoded)))
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"token": token})
	})
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		fmt.Fprintln(os.Stderr, "fixture server failed")
		os.Exit(1)
	}
}
