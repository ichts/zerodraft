//go:build realservice

package licence

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// TestRealServiceTestMode drives the Go client against the REAL licence service (built from services/license,
// unmodified) running in Stripe TEST mode behind a loopback fake Stripe: checkout, a paid session, activation,
// the two-PC limit, release of a slot, renewal, and refund revocation. Run it with
//
//	(cd ../../services/license && go build -o /tmp/wid-license-service .) && go build -o /tmp/wid-qaserver ./cmd/qaserver
//	WID_SERVICE_BIN=/tmp/wid-license-service WID_QASERVER_BIN=/tmp/wid-qaserver \
//	  go test -tags realservice -run TestRealServiceTestMode -v ./licence
//
// The key, webhook secret and Stripe API are generated placeholders on loopback (cmd/qaserver); no live key is involved.
// It is not in CI: it needs a POSIX signal to stop qaserver. Run it on macOS or Linux.
func TestRealServiceTestMode(t *testing.T) {
	svcBin, qaBin := os.Getenv("WID_SERVICE_BIN"), os.Getenv("WID_QASERVER_BIN")
	if svcBin == "" || qaBin == "" {
		t.Skip("WID_SERVICE_BIN and WID_QASERVER_BIN not set")
	}
	dir := t.TempDir()
	cmd := exec.Command(qaBin, "-service", svcBin, "-dir", dir, "-service-port", "18070", "-control-port", "18071", "-api-port", "18072")
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Logf("qaserver pid %d", cmd.Process.Pid)
	t.Cleanup(func() { cmd.Process.Signal(os.Interrupt); cmd.Wait() })
	waitHealth(t, "http://127.0.0.1:18070/api/v1/health")

	var cfg struct{ ServiceURL, ProductID, PublicKey string }
	b, _ := os.ReadFile(filepath.Join(dir, "config.json"))
	json.Unmarshal(b, &cfg)
	ctl := func(path string) (int, string) {
		resp, err := http.Get("http://127.0.0.1:18071" + path)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		return resp.StatusCode, string(b)
	}
	newPC := func() (*Manager, *MemoryVault) {
		v := &MemoryVault{}
		cl := NewClient(cfg.ServiceURL, cfg.ProductID, cfg.PublicKey, nil)
		return NewManager(&VaultStore{V: v}, cl, NewCheckoutClient(cfg.ServiceURL, nil), cfg.ProductID, nil), v
	}
	ctx := context.Background()

	pc1, _ := newPC()
	// the unpaid state: nothing to activate with
	pc1.Activate(ctx, "cs_test_does_not_exist_0001")
	if e := pc1.Snapshot().Err; e == nil || e.Kind != KindInvalidKey {
		t.Fatalf("unknown order: %v", e)
	}
	// Buy: the real service creates a session through the fake Stripe and returns a checkout.stripe.com URL
	var opened string
	pc1.Checkout(ctx, func(u string) { opened = u })
	if !strings.HasPrefix(opened, "https://checkout.stripe.com/c/pay/cs_test_qa_") {
		t.Fatalf("hand-off URL %q", opened)
	}
	// paid: the signed webhook reaches the service, which issues the key
	if code, msg := ctl("/qa/complete"); code != 200 {
		t.Fatalf("complete: %d %s", code, msg)
	}
	_, key := ctl("/qa/key")
	if len(key) < 8 {
		t.Fatalf("key %q", key)
	}
	pc1.Activate(ctx, "  "+key+"\r\n")
	if !pc1.HasFullAccess() {
		t.Fatalf("activation: %v", pc1.Snapshot().Err)
	}
	// the other PC takes the second slot; the third meets the limit with the service's own words
	if code, msg := ctl("/qa/fill?n=1&key=" + key); code != 200 {
		t.Fatalf("fill: %d %s", code, msg)
	}
	pc3, _ := newPC()
	pc3.Activate(ctx, key)
	if e := pc3.Snapshot().Err; e == nil || e.Kind != KindActivationLimitReached || e.Error() != tokens.ErrActivationLimitReached {
		t.Fatalf("third PC: %v", e)
	}
	if pc3.HasFullAccess() {
		t.Fatal("the third PC must not be licensed")
	}
	// a slot is freed: the same entry now succeeds
	ctl("/qa/free")
	pc3.Activate(ctx, key)
	if !pc3.HasFullAccess() {
		t.Fatalf("after freeing: %v", pc3.Snapshot().Err)
	}
	// renewal
	if got := pc1.Validate(ctx); got != Valid {
		t.Fatalf("renewal: %v", got)
	}
	// refund: the next validation revokes, activation is refused, no trial comes back
	if code, msg := ctl("/qa/refund"); code != 200 {
		t.Fatalf("refund: %d %s", code, msg)
	}
	if got := pc1.Validate(ctx); got != Rejected || pc1.HasFullAccess() || pc1.Snapshot().Status != Revoked || pc1.TrialRemaining() != 0 {
		t.Fatalf("after refund: %v full=%v %v", got, pc1.HasFullAccess(), pc1.Snapshot().Status)
	}
	pc4, _ := newPC()
	pc4.Activate(ctx, key)
	if e := pc4.Snapshot().Err; e == nil || e.Kind != KindInvalidKey {
		t.Fatalf("refunded order: %v", e)
	}
	// Buy falls back to the public page when Stripe is unavailable
	ctl("/qa/stripe-down?on=1")
	pc4.Checkout(ctx, func(u string) { opened = u })
	if opened != tokens.CheckoutFallbackURL {
		t.Fatalf("fallback %q", opened)
	}
}

func waitHealth(t *testing.T, url string) {
	for i := 0; i < 50; i++ {
		if resp, err := http.Get(url); err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("service did not come up")
}
