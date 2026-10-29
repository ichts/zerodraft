// qaserver runs the REAL licence service (services/license, built from the zerodraft repository, never modified) in
// Stripe TEST mode on loopback, behind a fake Stripe API on loopback, with a control port the end-to-end scripts
// drive: complete a checkout, refund it, fill the two-PC limit. No network, no Stripe key, no real purchase: every
// secret here is generated for this run and dies with it. It is the same arrangement the service's own tests use
// (STRIPE_API_BASE on loopback), driven from outside as a real HTTP client would.
//
//	qaserver -service /tmp/license-service -dir /tmp/wid-qa [-service-port 18060 -control-port 18061 -api-port 18062]
package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"
)

const (
	webhookSecret = "whsec_qa_generated_for_this_run_only"
	apiKey        = "sk_test_qa_generated_for_this_run_only"
	priceID       = "price_qa"
	productID     = "prod_qa_windows_slice"
)

type qa struct {
	mu           sync.Mutex
	svc          string // service origin
	sessions     []string
	completed    map[string]string // session -> payment intent
	checkouts    int
	stripeDown   bool
	tokens       []string // activations made by /qa/fill
	client       *http.Client
	lastCheckout time.Time
}

func main() {
	bin := flag.String("service", "", "the built licence service binary")
	dir := flag.String("dir", "", "scratch directory (key, database, app config)")
	sp := flag.Int("service-port", 18060, "")
	cp := flag.Int("control-port", 18061, "")
	ap := flag.Int("api-port", 18062, "")
	noBrowser := flag.Bool("no-browser", false, "write NoBrowser into the app config")
	appLog := flag.String("app-log", `C:\wid\out\qa\app.log`, "the app's event log path on the Windows machine")
	sessionSeconds := flag.Int("session-seconds", 0, "session length the QA build uses instead of the picker (0: the picker)")
	flag.Parse()
	if *bin == "" || *dir == "" {
		log.Fatal("-service and -dir required")
	}
	must(os.MkdirAll(*dir, 0o700))
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	must(err)
	der, err := x509.MarshalPKCS8PrivateKey(priv)
	must(err)
	keyFile := filepath.Join(*dir, "token-key.pem")
	must(os.WriteFile(keyFile, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0o600))
	_ = os.Remove(filepath.Join(*dir, "license.db"))

	q := &qa{svc: fmt.Sprintf("http://127.0.0.1:%d", *sp), completed: map[string]string{}, client: &http.Client{Timeout: 10 * time.Second}}
	api := &http.Server{Addr: fmt.Sprintf("127.0.0.1:%d", *ap), Handler: http.HandlerFunc(q.fakeStripe)}
	go func() { log.Println("fake stripe:", api.ListenAndServe()) }()

	cmd := exec.Command(*bin, "serve")
	cmd.Env = append(os.Environ(),
		"LICENSE_PROVIDER=stripe", "LICENSE_ENVIRONMENT=test", "LICENSE_PRODUCT_ID="+productID,
		"LICENSE_DB="+filepath.Join(*dir, "license.db"), "LICENSE_TOKEN_PRIVATE_KEY_FILE="+keyFile,
		"LICENSE_LISTEN_ADDR="+fmt.Sprintf("127.0.0.1:%d", *sp),
		"STRIPE_WEBHOOK_SECRET="+webhookSecret, "STRIPE_SECRET_KEY="+apiKey, "STRIPE_PRICE_ID="+priceID,
		fmt.Sprintf("STRIPE_API_BASE=http://127.0.0.1:%d", *ap))
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	must(cmd.Start())
	svcPID := cmd.Process.Pid
	fmt.Printf("SERVICE_PID=%d\n", svcPID)
	done := make(chan struct{})
	go func() { cmd.Wait(); close(done) }()

	cfg := map[string]any{"ServiceURL": q.svc, "ProductID": productID, "PublicKey": base64.StdEncoding.EncodeToString(pub),
		"CredentialService": "TrefoilStudio.WriteItDown.qa", "NoBrowser": *noBrowser, "LogPath": *appLog, "SessionSeconds": *sessionSeconds}
	b, _ := json.MarshalIndent(cfg, "", "  ")
	must(os.WriteFile(filepath.Join(*dir, "config.json"), b, 0o600))

	mux := http.NewServeMux()
	mux.HandleFunc("/qa/complete", q.complete)
	mux.HandleFunc("/qa/key", q.key)
	mux.HandleFunc("/qa/refund", q.refund)
	mux.HandleFunc("/qa/fill", q.fill)
	mux.HandleFunc("/qa/free", q.free)
	mux.HandleFunc("/qa/stripe-down", func(w http.ResponseWriter, r *http.Request) {
		q.mu.Lock()
		q.stripeDown = r.URL.Query().Get("on") == "1"
		q.mu.Unlock()
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/qa/status", func(w http.ResponseWriter, r *http.Request) {
		q.mu.Lock()
		defer q.mu.Unlock()
		json.NewEncoder(w).Encode(map[string]any{"checkouts": q.checkouts, "sessions": len(q.sessions), "completed": len(q.completed), "filled": len(q.tokens), "stripeDown": q.stripeDown})
	})
	ctl := &http.Server{Addr: fmt.Sprintf("127.0.0.1:%d", *cp), Handler: mux}
	go func() { log.Println("control:", ctl.ListenAndServe()) }()
	fmt.Printf("QASERVER_PID=%d READY service=%s control=127.0.0.1:%d\n", os.Getpid(), q.svc, *cp)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	select {
	case <-sig:
	case <-done:
	}
	_ = cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		_ = cmd.Process.Kill()
	}
	_ = api.Close()
	_ = ctl.Close()
}

func must(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

// fakeStripe answers the two calls the service makes to Stripe (POST /v1/checkout/sessions, GET .../line_items).
func (q *qa) fakeStripe(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Authorization") != "Bearer "+apiKey {
		http.Error(w, "bad key", 401)
		return
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	switch {
	case r.Method == "POST" && r.URL.Path == "/v1/checkout/sessions":
		if q.stripeDown {
			http.Error(w, "stripe unavailable", 500)
			return
		}
		q.checkouts++
		id := fmt.Sprintf("cs_test_qa_%d_%d", time.Now().Unix(), q.checkouts)
		q.sessions = append(q.sessions, id)
		json.NewEncoder(w).Encode(map[string]any{"id": id, "livemode": false, "url": "https://checkout.stripe.com/c/pay/" + id})
	case r.Method == "GET" && len(r.URL.Path) > len("/v1/checkout/sessions/") && r.URL.Path[len(r.URL.Path)-len("/line_items"):] == "/line_items":
		json.NewEncoder(w).Encode(map[string]any{"data": []any{map[string]any{"quantity": 1, "price": map[string]any{"id": priceID, "product": "prod_stripe_qa"}}}, "has_more": false})
	default:
		http.NotFound(w, r)
	}
}

func (q *qa) webhook(event map[string]any) (int, string) {
	body, _ := json.Marshal(event)
	ts := strconv.FormatInt(time.Now().Unix(), 10)
	mac := hmac.New(sha256.New, []byte(webhookSecret))
	mac.Write([]byte(ts + "."))
	mac.Write(body)
	req, _ := http.NewRequest("POST", q.svc+"/api/v1/webhooks/stripe", bytes.NewReader(body))
	req.Header.Set("Stripe-Signature", "t="+ts+",v1="+hex.EncodeToString(mac.Sum(nil)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := q.client.Do(req)
	if err != nil {
		return 502, err.Error()
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

// complete delivers a signed checkout.session.completed for the latest session (the buyer paying with a test card).
func (q *qa) complete(w http.ResponseWriter, r *http.Request) {
	q.mu.Lock()
	if len(q.sessions) == 0 {
		q.mu.Unlock()
		http.Error(w, "no checkout session yet: press Buy first", 409)
		return
	}
	id := q.sessions[len(q.sessions)-1]
	pi := "pi_qa_" + id
	q.completed[id] = pi
	q.mu.Unlock()
	obj := map[string]any{"id": id, "livemode": false, "payment_intent": pi, "amount_total": 499, "currency": "usd", "mode": "payment", "status": "complete", "payment_status": "paid"}
	code, msg := q.webhook(map[string]any{"id": "evt_qa_completed_" + id, "type": "checkout.session.completed", "livemode": false, "data": map[string]any{"object": obj}})
	w.WriteHeader(code)
	fmt.Fprintf(w, "completed %s: webhook HTTP %d %s\n", "session", code, msg)
}

// key is what the service's /api/v1/license returns for the paid session: the buyer's licence key, as the
// purchase page would show it. It is printed only for the e2e script to type into the app.
func (q *qa) key(w http.ResponseWriter, r *http.Request) {
	q.mu.Lock()
	var id string
	for _, s := range q.sessions {
		if _, ok := q.completed[s]; ok {
			id = s
		}
	}
	q.mu.Unlock()
	if id == "" {
		http.Error(w, "no paid session", 409)
		return
	}
	resp, err := q.client.Get(q.svc + "/api/v1/license?session_id=" + id)
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	defer resp.Body.Close()
	var out struct {
		LicenseKey string `json:"licenseKey"`
	}
	json.NewDecoder(resp.Body).Decode(&out)
	if resp.StatusCode != 200 || out.LicenseKey == "" {
		http.Error(w, "service said "+resp.Status, 502)
		return
	}
	fmt.Fprint(w, out.LicenseKey)
}

// refund delivers charge.refunded for the paid session (the 14-day refund).
func (q *qa) refund(w http.ResponseWriter, r *http.Request) {
	q.mu.Lock()
	var pi string
	for _, s := range q.sessions {
		if p, ok := q.completed[s]; ok {
			pi = p
		}
	}
	q.mu.Unlock()
	if pi == "" {
		http.Error(w, "no paid session", 409)
		return
	}
	obj := map[string]any{"id": "ch_qa_" + pi, "livemode": false, "payment_intent": pi, "amount": 499, "amount_refunded": 499, "refunded": true, "currency": "usd"}
	code, msg := q.webhook(map[string]any{"id": "evt_qa_refund_" + pi, "type": "charge.refunded", "livemode": false, "data": map[string]any{"object": obj}})
	w.WriteHeader(code)
	fmt.Fprintf(w, "refund webhook HTTP %d %s\n", code, msg)
}

// fill activates n other installations (the buyer's other PCs) so the next activation meets the two-PC limit.
func (q *qa) fill(w http.ResponseWriter, r *http.Request) {
	n, _ := strconv.Atoi(r.URL.Query().Get("n"))
	key := r.URL.Query().Get("key")
	if key == "" {
		resp, err := q.client.Get("http://" + r.Host + "/qa/key")
		if err == nil {
			b, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			key = string(b)
		}
	}
	for i := 0; i < n; i++ {
		b, _ := json.Marshal(map[string]string{"orderId": key, "installLabel": "qa-other-pc-" + strconv.Itoa(len(q.tokens)) + "-" + strconv.FormatInt(time.Now().UnixNano(), 36), "platform": "windows"})
		resp, err := q.client.Post(q.svc+"/api/v1/licenses/activate", "application/json", bytes.NewReader(b))
		if err != nil {
			http.Error(w, err.Error(), 502)
			return
		}
		var out struct{ Token string }
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		json.Unmarshal(raw, &out)
		if resp.StatusCode != 200 {
			http.Error(w, fmt.Sprintf("fill %d: HTTP %d %s", i, resp.StatusCode, raw), 502)
			return
		}
		q.mu.Lock()
		q.tokens = append(q.tokens, out.Token)
		q.mu.Unlock()
	}
	fmt.Fprintf(w, "filled %d\n", n)
}

// free releases the first filled installation (the buyer deactivated another PC).
func (q *qa) free(w http.ResponseWriter, r *http.Request) {
	q.mu.Lock()
	if len(q.tokens) == 0 {
		q.mu.Unlock()
		http.Error(w, "nothing filled", 409)
		return
	}
	tok := q.tokens[0]
	q.tokens = q.tokens[1:]
	q.mu.Unlock()
	b, _ := json.Marshal(map[string]string{"token": tok})
	resp, err := q.client.Post(q.svc+"/api/v1/licenses/deactivate", "application/json", bytes.NewReader(b))
	if err != nil {
		http.Error(w, err.Error(), 502)
		return
	}
	resp.Body.Close()
	fmt.Fprintf(w, "freed HTTP %d\n", resp.StatusCode)
}
