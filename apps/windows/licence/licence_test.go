package licence

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

const product = "prod_test"

type fakeService struct {
	t        *testing.T
	pub      ed25519.PublicKey
	priv     ed25519.PrivateKey
	now      func() time.Time
	mu       sync.Mutex
	status   map[string]int // endpoint -> forced status
	detail   map[string]string
	requests []map[string]string
	paths    []string
	product  string
	label    string // installLabel bound into the next token (the label the client sent)
	lifetime int64
	srv      *httptest.Server
}

func newService(t *testing.T, now func() time.Time) *fakeService {
	pub, priv, _ := ed25519.GenerateKey(rand.Reader)
	f := &fakeService{t: t, pub: pub, priv: priv, now: now, status: map[string]int{}, detail: map[string]string{}, product: product, lifetime: Lifetime}
	f.srv = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeService) token(label string) string {
	n := f.now().Unix()
	c := Claims{LicenseID: "lic_1", ActivationID: "act_1", InstallLabel: label, Product: f.product, IssuedAt: n, ExpiresAt: n + f.lifetime}
	payload, _ := json.Marshal(c)
	enc := base64.RawURLEncoding.EncodeToString(payload)
	return enc + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(f.priv, []byte(enc)))
}

func (f *fakeService) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	var req map[string]string
	_ = json.Unmarshal(body, &req)
	ep := strings.TrimPrefix(r.URL.Path, "/api/v1/licenses/")
	f.mu.Lock()
	f.requests = append(f.requests, req)
	f.paths = append(f.paths, r.Method+" "+r.URL.Path+" "+r.Header.Get("Content-Type")+" auth="+r.Header.Get("Authorization"))
	st := f.status[ep]
	d := f.detail[ep]
	f.mu.Unlock()
	if st != 0 {
		if st >= 300 && st < 400 {
			w.Header().Set("Location", "http://example.invalid/")
		}
		http.Error(w, d, st)
		return
	}
	switch ep {
	case "activate":
		json.NewEncoder(w).Encode(map[string]string{"token": f.token(req["installLabel"])})
	case "validate":
		claims, _ := (&Verifier{key: f.pub, ProductID: f.product}).verifyAny(req["token"])
		json.NewEncoder(w).Encode(map[string]string{"token": f.token(claims.InstallLabel)})
	case "deactivate":
		w.Write([]byte(`{"status":"deactivated"}`))
	default:
		http.NotFound(w, r)
	}
}

// verifyAny reads claims ignoring time (the fake service only needs the label back).
func (v *Verifier) verifyAny(token string) (Claims, bool) {
	parts := strings.Split(token, ".")
	var c Claims
	if len(parts) != 2 {
		return c, false
	}
	b, ok := decode(parts[0])
	return c, ok && json.Unmarshal(b, &c) == nil
}

type clock struct{ t time.Time }

func (c *clock) Now() time.Time { return c.t }

type env struct {
	f     *fakeService
	clk   *clock
	vault *MemoryVault
	store *VaultStore
	c     *Client
	m     *Manager
}

func newEnv(t *testing.T) *env {
	clk := &clock{time.Unix(1_800_000_000, 0)}
	f := newService(t, clk.Now)
	e := &env{f: f, clk: clk, vault: &MemoryVault{}}
	e.store = &VaultStore{V: e.vault}
	e.build()
	return e
}

func (e *env) build() {
	e.c = NewClient(e.f.srv.URL, product, base64.StdEncoding.EncodeToString(e.f.pub), nil)
	e.c.Clock = e.clk.Now
	e.m = NewManager(&VaultStore{V: e.vault}, e.c, NewCheckoutClient(e.f.srv.URL, nil), product, e.clk.Now)
}

// relaunch builds a fresh manager over the same vault, as a new app launch does.
func (e *env) relaunch() { e.build() }

func (e *env) activate(key string) { e.m.Activate(context.Background(), key) }

func TestTokenContract(t *testing.T) {
	clk := &clock{time.Unix(1_800_000_000, 0)}
	f := newService(t, clk.Now)
	v, _ := NewVerifier(f.pub, product)
	good := f.token("label-1234")
	if _, err := v.Verify(good, "label-1234", clk.t); err != nil {
		t.Fatalf("good token: %v", err)
	}
	cases := map[string]func() (string, string, time.Time){
		"other install": func() (string, string, time.Time) { return good, "label-9999", clk.t },
		"expired": func() (string, string, time.Time) {
			return good, "label-1234", clk.t.Add(Lifetime*time.Second + time.Second)
		},
		"issued in future": func() (string, string, time.Time) { return good, "label-1234", clk.t.Add(-61 * time.Second) },
		"tampered payload": func() (string, string, time.Time) {
			p := strings.SplitN(good, ".", 2)
			return p[0][:len(p[0])-2] + "AA." + p[1], "label-1234", clk.t
		},
		"padded":      func() (string, string, time.Time) { return good + "=", "label-1234", clk.t },
		"one part":    func() (string, string, time.Time) { return "abc", "label-1234", clk.t },
		"empty label": func() (string, string, time.Time) { return good, "", clk.t },
	}
	for name, mk := range cases {
		tok, label, now := mk()
		if _, err := v.Verify(tok, label, now); !errors.Is(err, ErrInvalidToken) {
			t.Errorf("%s: want invalid, got %v", name, err)
		}
	}
	other, _ := NewVerifier(f.pub, "prod_other")
	if _, err := other.Verify(good, "label-1234", clk.t); err == nil {
		t.Error("a token for another product must be refused")
	}
	f.lifetime = Lifetime + 1
	if _, err := v.Verify(f.token("label-1234"), "label-1234", clk.t); err == nil {
		t.Error("a lifetime other than seven days must be refused")
	}
	// the signature covers the ENCODED payload text
	p := strings.SplitN(good, ".", 2)
	raw, _ := base64.RawURLEncoding.DecodeString(p[0])
	sig, _ := base64.RawURLEncoding.DecodeString(p[1])
	if ed25519.Verify(f.pub, raw, sig) || !ed25519.Verify(f.pub, []byte(p[0]), sig) {
		t.Error("signature must cover the encoded payload text, not the decoded JSON")
	}
}

func TestActivateWireContractAndAccess(t *testing.T) {
	e := newEnv(t)
	e.activate(" \t WID-ORDER-12345\r\n")
	if !e.m.HasFullAccess() {
		t.Fatalf("activation failed: %v", e.m.Snapshot().Err)
	}
	req := e.f.requests[0]
	if len(req) != 3 || req["orderId"] != "WID-ORDER-12345" || req["platform"] != "windows" || req["installLabel"] != e.m.InstallLabel() || len(e.m.InstallLabel()) != 36 {
		t.Errorf("request shape: %#v", req)
	}
	if got := e.f.paths[0]; got != "POST /api/v1/licenses/activate application/json auth=" {
		t.Errorf("request line: %q", got)
	}
	if e.m.AccessStatusText() != tokens.StatusActive {
		t.Errorf("status %q", e.m.AccessStatusText())
	}
	// the licence is stored only in the vault, never anywhere else, and survives a relaunch
	st := e.vault.M["state"]
	if !strings.Contains(string(st), "WID-ORDER-12345") {
		t.Error("state not in the vault")
	}
	e.relaunch()
	if !e.m.HasFullAccess() || e.m.TrialRemaining() != 0 {
		t.Error("licence must survive a relaunch and grant no trial")
	}
}

func TestActivationErrorStates(t *testing.T) {
	cases := []struct {
		name   string
		status int
		detail string
		kind   ActivationKind
		text   string
	}{
		{"unknown or revoked order", 403, "", KindInvalidKey, tokens.ErrInvalidKey},
		{"refunded", 404, "", KindInvalidKey, tokens.ErrInvalidKey},
		{"third install", 409, "device limit reached\n", KindActivationLimitReached, tokens.ErrActivationLimitReached},
		{"other 409 is not the limit", 409, "installation platform mismatch", KindUnexpected, "Activation failed (HTTP 409)."},
		{"rate limited", 429, "", KindNetworkFailure, tokens.ErrNetworkFailure},
		{"server error", 503, "", KindNetworkFailure, tokens.ErrNetworkFailure},
		{"bad request", 400, "", KindUnexpected, "Activation failed (HTTP 400)."},
		{"redirect is refused", 302, "", KindUnexpected, "Activation failed (HTTP 302)."},
	}
	for _, c := range cases {
		e := newEnv(t)
		e.f.status["activate"], e.f.detail["activate"] = c.status, c.detail
		e.activate("WID-ORDER-12345")
		err := e.m.Snapshot().Err
		if err == nil || err.Kind != c.kind || err.Error() != c.text {
			t.Errorf("%s: got %v want %q", c.name, err, c.text)
		}
		if e.m.HasFullAccess() || e.m.State().Token != "" {
			t.Errorf("%s: a failed activation must leave nothing behind", c.name)
		}
	}
	e := newEnv(t)
	e.activate("  \n\t ")
	if err := e.m.Snapshot().Err; err == nil || err.Kind != KindEmptyKey || len(e.f.requests) != 0 {
		t.Errorf("an empty key must be refused before any request: %v", err)
	}
	e.f.srv.Close()
	e.activate("WID-ORDER-12345")
	if err := e.m.Snapshot().Err; err == nil || err.Kind != KindNetworkFailure {
		t.Errorf("no network: %v", err)
	}
}

func TestWrongProductIsUndone(t *testing.T) {
	e := newEnv(t)
	e.f.product = "prod_someone_else"
	e.activate("WID-ORDER-12345")
	if err := e.m.Snapshot().Err; err == nil || err.Kind != KindInvalidToken {
		// the verifier already refuses a foreign product, before the manager looks at it
		t.Fatalf("foreign product: %v", err)
	}
	if e.m.HasFullAccess() || e.m.State().Token != "" {
		t.Error("no access from a foreign product")
	}
}

type failSave struct{ Store }

func (f failSave) Save(State) error { return errors.New("denied") }

func TestStorageFailureReleasesTheNewAllocation(t *testing.T) {
	e := newEnv(t)
	e.m = NewManager(failSave{&VaultStore{V: e.vault}}, e.c, NewCheckoutClient(e.f.srv.URL, nil), product, e.clk.Now)
	e.activate("WID-ORDER-12345")
	err := e.m.Snapshot().Err
	if err == nil || err.Kind != KindStorageFailure || err.Error() != tokens.ErrStorageFailure {
		t.Fatalf("storage failure: %v", err)
	}
	if e.m.HasFullAccess() {
		t.Error("no access granted that is not durable")
	}
	if !strings.HasSuffix(e.f.paths[len(e.f.paths)-1], "") || !strings.Contains(e.f.paths[len(e.f.paths)-1], "/deactivate") {
		t.Errorf("the new allocation must be deactivated: %v", e.f.paths)
	}
}

func TestRevocationLikeTheMac(t *testing.T) {
	e := newEnv(t)
	for i := 0; i < 3; i++ { // the trial is spent before the purchase
		e.m.ChargeTrial(uint64(i + 1))
	}
	// first licensed, then refunded: a full trial is gone and the refund does not bring it back
	e = newEnvWithTrial(t, 3)
	e.activate("WID-ORDER-12345")
	if !e.m.HasFullAccess() {
		t.Fatal("setup")
	}
	e.f.status["validate"] = 403
	e.clk.t = e.clk.t.Add(time.Hour)
	if got := e.m.Validate(context.Background()); got != Rejected {
		t.Fatalf("a refunded licence must be rejected, got %v", got)
	}
	if e.m.HasFullAccess() || e.m.Snapshot().Status != Revoked || e.m.AccessStatusText() != tokens.StatusRevoked {
		t.Errorf("revoked state: full=%v status=%v text=%q", e.m.HasFullAccess(), e.m.Snapshot().Status, e.m.AccessStatusText())
	}
	if e.m.TrialRemaining() != 0 || e.m.CanStartSession() {
		t.Error("a revoked licence must never fall back to the trial")
	}
	e.relaunch()
	if e.m.HasFullAccess() || e.m.TrialRemaining() != 0 {
		t.Error("revocation must persist across a relaunch")
	}
	// the buyer enters the order again: the service still says no, the state stays revoked and shows the error
	e.f.status["activate"] = 403
	e.activate("WID-ORDER-12345")
	if err := e.m.Snapshot().Err; err == nil || err.Kind != KindInvalidKey {
		t.Errorf("re-entering a refunded order: %v", err)
	}
}

func newEnvWithTrial(t *testing.T, used int) *env {
	e := newEnv(t)
	e.vault.Set("state", State{TrialSessionsUsed: used, Status: Inactive}.Marshal())
	e.relaunch()
	return e
}

func TestOfflineGraceNeverExtendsTheSevenDays(t *testing.T) {
	e := newEnv(t)
	e.activate("WID-ORDER-12345")
	e.f.srv.Close()
	e.clk.t = e.clk.t.Add(Grace - time.Second)
	if !e.m.HasFullAccess() {
		t.Error("valid until the seventh day")
	}
	if got := e.m.Validate(context.Background()); got != Undecided || !e.m.HasFullAccess() {
		t.Errorf("a transport failure inside the grace keeps access (got %v)", got)
	}
	e.clk.t = e.clk.t.Add(2 * time.Second)
	if e.m.HasFullAccess() {
		t.Error("access ends at seven days, offline")
	}
	e.m.Validate(context.Background())
	if e.m.Snapshot().Status != Unknown || e.m.AccessStatusText() != tokens.StatusUnknown {
		t.Errorf("after the grace offline: %v %q", e.m.Snapshot().Status, e.m.AccessStatusText())
	}
	if e.m.TrialRemaining() != 0 {
		t.Error("no trial from an expired licence")
	}
}

func TestRenewalReplacesTheToken(t *testing.T) {
	e := newEnv(t)
	e.activate("WID-ORDER-12345")
	old := e.m.State().Token
	e.clk.t = e.clk.t.Add(3 * 24 * time.Hour)
	if got := e.m.Validate(context.Background()); got != Valid {
		t.Fatalf("renewal: %v", got)
	}
	st := e.m.State()
	if st.Token == old || !st.LastValidatedAt.Equal(e.clk.t) || !e.m.HasFullAccess() {
		t.Error("renewal must replace the token and the validation time")
	}
	e.f.status["validate"] = 500
	if got := e.m.Validate(context.Background()); got != Undecided || !e.m.HasFullAccess() {
		t.Errorf("a 5xx must not revoke: %v", got)
	}
	e.f.status["validate"] = 418
	e.m.Validate(context.Background())
	if e.m.Snapshot().Status != Invalid {
		t.Error("an unexpected status is not a revocation but fails closed to invalid")
	}
}

func TestTrialLikeTheMac(t *testing.T) {
	e := newEnv(t)
	if e.m.TrialRemaining() != 3 || !e.m.CanStartSession() || e.m.AccessStatusText() != fmt.Sprintf(tokens.TrialLeftFormat, 3, 3) {
		t.Fatalf("fresh: %d %q", e.m.TrialRemaining(), e.m.AccessStatusText())
	}
	for id := uint64(1); id <= 3; id++ {
		if !e.m.ChargeTrial(id) || !e.m.ChargeTrial(id) { // the same session is charged once
			t.Fatalf("session %d refused", id)
		}
	}
	if e.m.TrialRemaining() != 0 || !e.m.TrialSpent() || e.m.ChargeTrial(4) || e.m.CanStartSession() {
		t.Error("three sessions, then nothing")
	}
	if !e.m.CanUseApp(3, true) || e.m.CanUseApp(4, true) {
		t.Error("the charged session may finish; another may not start")
	}
	e.relaunch()
	if e.m.TrialRemaining() != 0 {
		t.Error("the counter persists across a relaunch")
	}
	// a malformed counter exhausts only the trial
	e.vault.Set("state", []byte(`{"trialSessionsUsed":99,"licenseStatus":"inactive"}`))
	e.relaunch()
	if e.m.TrialRemaining() != 0 || !e.m.TrialSpent() {
		t.Error("a malformed counter exhausts the trial")
	}
	// an unreadable store closes trial access with a visible error
	e.m = NewManager(brokenStore{}, e.c, NewCheckoutClient(e.f.srv.URL, nil), product, e.clk.Now)
	if e.m.CanStartSession() || e.m.TrialAccessError() != tokens.TrialReadError || e.m.TrialSpent() {
		t.Error("unreadable usage must close the trial with a visible error")
	}
}

type brokenStore struct{}

func (brokenStore) Load() (State, error) { return State{}, errors.New("unreadable") }
func (brokenStore) Save(State) error     { return errors.New("unwritable") }
func (brokenStore) InstallID() string    { return NewUUID() }

func TestTrialSaveFailureRefusesTheInput(t *testing.T) {
	e := newEnv(t)
	e.m = NewManager(failSave{&VaultStore{V: e.vault}}, e.c, NewCheckoutClient(e.f.srv.URL, nil), product, e.clk.Now)
	if e.m.ChargeTrial(1) || e.m.TrialAccessError() != tokens.TrialSaveError || e.m.CanStartSession() {
		t.Error("a failed reservation closes the trial with a visible error")
	}
}

func TestLicenceResidueNeverFallsBackToTrial(t *testing.T) {
	e := newEnv(t)
	e.vault.Set("state", State{LicenseKey: "WID-ORDER-12345", Status: Inactive}.Marshal())
	e.relaunch()
	if e.m.TrialRemaining() != 0 || e.m.CanStartSession() || e.m.AccessStatusText() != tokens.StatusNotActivated {
		t.Errorf("residue: %d %q", e.m.TrialRemaining(), e.m.AccessStatusText())
	}
}

func TestSecondInstallAndThirdAreTheServicesBusiness(t *testing.T) {
	e := newEnv(t)
	e.f.status["activate"], e.f.detail["activate"] = 409, "device limit reached"
	e.activate("WID-ORDER-12345")
	if e.m.Snapshot().Err.Error() != "This license has reached its 2-PC activation limit." {
		t.Errorf("limit text: %q", e.m.Snapshot().Err.Error())
	}
	for _, s := range []string{tokens.ErrInvalidKey, tokens.ErrNetworkFailure, tokens.ErrEmptyKey, tokens.ErrStorageFailure, tokens.ErrCleanupFailure} {
		if strings.Contains(s, "Mac") || strings.Contains(s, "Waffo") {
			t.Errorf("Mac or Waffo wording left: %q", s)
		}
	}
}

func TestCheckoutContract(t *testing.T) {
	var method, accept, ct string
	var n int
	for _, c := range []struct {
		name, body string
		status     int
		ok         bool
	}{
		{"stripe", `{"url":"https://checkout.stripe.com/c/pay/cs_test_1"}`, 200, true},
		{"other host", `{"url":"https://example.com/pay"}`, 200, false},
		{"http", `{"url":"http://checkout.stripe.com/pay"}`, 200, false},
		{"userinfo", `{"url":"https://u:p@checkout.stripe.com/pay"}`, 200, false},
		{"lookalike", `{"url":"https://checkout.stripe.com.evil.com/pay"}`, 200, false},
		{"no url", `{}`, 200, false},
		{"503", `{"error":"checkout_not_configured"}`, 503, false},
		{"redirect", `{"url":"https://checkout.stripe.com/x"}`, 302, false},
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			n++
			method, accept, ct = r.Method, r.Header.Get("Accept"), r.Header.Get("Content-Type")
			b, _ := io.ReadAll(r.Body)
			if len(b) != 0 || r.URL.Path != "/api/v1/checkout" {
				t.Errorf("%s: body %q path %s", c.name, b, r.URL.Path)
			}
			if c.status == 302 {
				w.Header().Set("Location", "https://checkout.stripe.com/x")
			}
			w.WriteHeader(c.status)
			w.Write([]byte(c.body))
		}))
		got, err := NewCheckoutClient(srv.URL, nil).Session(context.Background())
		srv.Close()
		if (err == nil) != c.ok {
			t.Errorf("%s: err=%v got=%q", c.name, err, got)
		}
		if method != "POST" || accept != "application/json" || ct != "" {
			t.Errorf("%s: %s accept=%q ct=%q", c.name, method, accept, ct)
		}
	}
	// the manager falls back to the public purchase page on any failure
	e := newEnv(t)
	var opened string
	e.m.Checkout(context.Background(), func(u string) { opened = u })
	if opened != tokens.CheckoutFallbackURL { // the fake service has no /checkout
		t.Errorf("fallback: %q", opened)
	}
	if n == 0 {
		t.Error("no request made")
	}
}

func TestAllowedURL(t *testing.T) {
	for u, want := range map[string]bool{
		"https://licenses.writeitdown.app": true, "https://licenses.writeitdown.app/": true, "http://127.0.0.1:8060": true,
		"http://localhost:1": true, "http://example.com": false, "https://u@example.com": false, "https://example.com/x": false,
		"https://example.com?x=1": false, "https://example.com#f": false, "ftp://example.com": false, "": false,
	} {
		c := NewCheckoutClient(u, nil)
		if c.Configured() != want {
			t.Errorf("%q: got %v", u, c.Configured())
		}
	}
}

func TestStateRoundTripAndUUID(t *testing.T) {
	s := State{TrialSessionsUsed: 2, LicenseKey: "k", Status: Active, Token: "t", InstanceID: "i", ProductID: "p", ActivatedAt: time.Unix(5, 0).UTC()}
	got, err := ParseState(s.Marshal())
	if err != nil || got.TrialSessionsUsed != 2 || got.Status != Active || !got.ActivatedAt.Equal(s.ActivatedAt) || got.TrialUnreadable {
		t.Errorf("round trip: %#v %v", got, err)
	}
	if st, _ := ParseState([]byte(`{"licenseStatus":"weird"}`)); st.Status != Inactive {
		t.Error("an unknown status decodes as inactive")
	}
	if a, b := NewUUID(), NewUUID(); a == b || len(a) != 36 || a[14] != '4' {
		t.Errorf("uuid %q %q", a, b)
	}
	v := &MemoryVault{}
	a, b := (&VaultStore{V: v}).InstallID(), (&VaultStore{V: v}).InstallID()
	if a != b {
		t.Error("the install id must be stable")
	}
}
