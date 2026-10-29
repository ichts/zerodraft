package app

import (
	"context"
	"fmt"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/fonts"
	"github.com/ichts/zerodraft/apps/windows/licence"
	"github.com/ichts/zerodraft/apps/windows/licence/fakeservice"
	"github.com/ichts/zerodraft/apps/windows/session"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

func init() {
	if err := fonts.Register(); err != nil {
		panic(err)
	}
}

const testProduct = "prod_test"

type rig struct {
	t      *testing.T
	tt     *ui.Tester
	a      *App
	svc    *fakeservice.Service
	vault  *licence.MemoryVault
	opened []string
	left   bool
}

func newRig(t *testing.T) *rig { return newRigWith(t, &licence.MemoryVault{}, nil) }

func newRigWith(t *testing.T, vault *licence.MemoryVault, svc *fakeservice.Service) *rig {
	g := &rig{t: t, vault: vault}
	var tt *ui.Tester
	start := time.Now()
	now := func() time.Time {
		if tt == nil {
			return start
		}
		return tt.Now()
	}
	if svc == nil {
		svc = fakeservice.New(testProduct, now)
		t.Cleanup(svc.Close)
	}
	g.svc = svc
	client := licence.NewClient(svc.URL, testProduct, svc.PublicKey, nil)
	client.Clock = now
	mgr := licence.NewManager(&licence.VaultStore{V: vault}, client, licence.NewCheckoutClient(svc.URL, nil), testProduct, now)
	prefs := LoadPrefs("")
	g.a = New(mgr, prefs, Env{
		OpenURL: func(u string) { g.opened = append(g.opened, u) },
		Go:      func(fn func()) { fn() },
		Clock:   now, Version: "test",
	})
	g.a.env.RoomConfig.Clock = now
	g.a.env.RoomConfig.SyncPaper = true
	tt = ui.NewTester(g.a.View, 1040, 620)
	g.tt = tt
	tt.Frame()
	return g
}

func (g *rig) snap(name string) {
	g.tt.Frame()
	dir := os.Getenv("WID_SNAP_DIR")
	if dir == "" {
		return
	}
	os.MkdirAll(dir, 0o755)
	f, _ := os.Create(filepath.Join(dir, name+".png"))
	png.Encode(f, g.tt.Image())
	f.Close()
}

func (g *rig) click(label string) {
	g.t.Helper()
	if err := g.tt.Click(label); err != nil {
		g.t.Fatalf("click %q: %v (texts %q)", label, err, g.tt.Texts())
	}
}

func (g *rig) wantText(s string) {
	g.t.Helper()
	if !g.tt.HasText(s) {
		g.t.Fatalf("no %q on screen: %q", s, g.tt.Texts())
	}
}

// spend runs one trial session: begin, type, stay silent until the wipe, return to the stopped sheet.
func (g *rig) spend() {
	g.t.Helper()
	g.click("Begin writing")
	if g.a.Surface() != Session {
		g.t.Fatalf("not in the room: %d", g.a.Surface())
	}
	g.tt.Type("a")
	g.tt.Advance(9 * time.Second)
	if g.a.Room().Engine().Phase != session.Failure {
		g.t.Fatalf("phase %v", g.a.Room().Engine().Phase)
	}
}

func TestHomeAndTheThreeFreeSessions(t *testing.T) {
	g := newRig(t)
	g.snap("home-fresh")
	g.wantText("How long?")
	g.wantText(fmt.Sprintf(tokens.TrialLeftFormat, 3, 3))
	// entering an empty room and leaving it spends nothing
	g.click("Begin writing")
	g.tt.Key(0, ui.KeyEscape)
	g.tt.Key(0, ui.KeyEscape)
	if g.a.Surface() != Home || g.a.Licence().TrialRemaining() != 3 {
		t.Fatalf("an empty room costs nothing: surface %d left %d", g.a.Surface(), g.a.Licence().TrialRemaining())
	}
	g.wantText(fmt.Sprintf(tokens.TrialLeftFormat, 3, 3))
	for i := 1; i <= 3; i++ {
		g.spend()
		if got, want := g.a.Licence().TrialRemaining(), 3-i; got != want {
			t.Fatalf("after session %d: %d left, want %d", i, got, want)
		}
		if i < 3 {
			g.tt.Key(0, ui.KeyEscape)
			g.tt.Key(0, ui.KeyEscape) // leave to Home
			if g.a.Surface() != Home {
				t.Fatalf("left the room to %d", g.a.Surface())
			}
		}
	}
	g.snap("stopped-trial-spent")
	// the last trial wiped; restarting opens the existing activation card, wipe itself never routes there
	if g.a.Surface() != Session {
		t.Fatal("a wipe must not route to checkout")
	}
	g.tt.Key(0, ui.KeyEnter)
	if g.a.Surface() != Upgrade {
		t.Fatalf("restart after exhaustion must open activation, got %d", g.a.Surface())
	}
	g.snap("upgrade-exhausted")
	g.wantText("Activate Write It Down")
	g.wantText("One payment. 2 PCs. 14-day refund.")
	// the counter survives a relaunch
	g2 := newRigWith(t, g.vault, g.svc)
	if g2.a.Surface() != Upgrade || g2.a.Licence().TrialRemaining() != 0 {
		t.Fatalf("relaunch: surface %d", g2.a.Surface())
	}
}

func TestBuyHandsOffToTheStripeCheckoutAndFallsBack(t *testing.T) {
	g := newRigWith(t, &licence.MemoryVault{}, nil)
	g.vault.Set("state", licence.State{TrialSessionsUsed: 3, Status: licence.Inactive}.Marshal())
	g = newRigWith(t, g.vault, g.svc)
	if g.a.Surface() != Upgrade {
		t.Fatal("exhausted trial opens the card")
	}
	g.click("Buy a license, $4.99 once")
	if len(g.opened) != 1 || g.opened[0] != g.svc.CheckoutURL {
		t.Fatalf("hand-off: %v", g.opened)
	}
	g.svc.Status["checkout"] = 503
	g.click("Buy a license, $4.99 once")
	if len(g.opened) != 2 || g.opened[1] != tokens.CheckoutFallbackURL {
		t.Fatalf("fallback: %v", g.opened)
	}
	g.click(tokens.UpgradeWebTrial)
	if g.opened[2] != tokens.WebTrialURL {
		t.Fatalf("web trial: %v", g.opened)
	}
}

func TestActivationFlow(t *testing.T) {
	vault := &licence.MemoryVault{}
	vault.Set("state", licence.State{TrialSessionsUsed: 3, Status: licence.Inactive}.Marshal())
	g := newRigWith(t, vault, nil)
	// empty submission is refused before any request
	g.click("Activate")
	g.wantText(tokens.UpgradeEnterFirst)
	if len(g.svc.Requests) != 0 {
		t.Fatal("an empty key must not reach the service")
	}
	g.snap("upgrade-empty")
	for status, want := range map[int]string{
		403: tokens.ErrInvalidKey, 404: tokens.ErrInvalidKey, 503: tokens.ErrNetworkFailure, 400: "Activation failed (HTTP 400).",
	} {
		g.svc.Status["activate"] = status
		g.click(tokens.UpgradePlaceholder)
		g.tt.Type("WID-ORDER-1234")
		g.click("Activate")
		g.wantText(want)
		g.tt.Key(ui.Cmd, ui.KeyA)
		g.tt.Key(0, ui.KeyBackspace)
	}
	g.svc.Status["activate"], g.svc.Detail["activate"] = 409, "device limit reached"
	g.click(tokens.UpgradePlaceholder)
	g.tt.Type("WID-ORDER-1234")
	g.click("Activate")
	g.wantText("This license has reached its 2-PC activation limit.")
	g.snap("upgrade-limit")
	g.svc.Status["activate"] = 0
	g.click("Activate")
	g.wantText("This PC is licensed.")
	g.wantText("Start writing")
	g.snap("upgrade-licensed")
	if !g.a.Licence().HasFullAccess() || g.a.key != "" {
		t.Fatal("licensed and the field cleared")
	}
	g.click("Start writing")
	if g.a.Surface() != Home || g.tt.HasText("Free trial") || g.tt.HasText("Activate this PC") {
		t.Fatalf("a licensed Home shows no access line: %q", g.tt.Texts())
	}
	g.snap("home-licensed")
	// licensed sessions spend nothing
	g.spend()
	if got := g.a.Licence().State().TrialSessionsUsed; got != 3 {
		t.Errorf("licensed sessions must leave the counter: %d", got)
	}
	// the stopped sheet restarts in place when licensed
	g.tt.Key(0, ui.KeyEnter)
	if g.a.Surface() != Session {
		t.Errorf("surface %d", g.a.Surface())
	}
}

func TestRefundedLicenceIsEnforcedAtLaunch(t *testing.T) {
	g := newRig(t)
	vault := g.vault
	g.a.Licence().Activate(nilCtx(), "WID-ORDER-1234")
	if !g.a.Licence().HasFullAccess() {
		t.Fatal("setup")
	}
	// a relaunch while the service now says the order is refunded: Home first (access never waits), then the card
	g.svc.Status["validate"] = 403
	g2 := newRigWith(t, vault, g.svc)
	if g2.a.Surface() != Home {
		t.Fatalf("launch opens Home from the stored token, got %d", g2.a.Surface())
	}
	g2.a.Start()
	g2.tt.Frame()
	if g2.a.Surface() != Upgrade {
		t.Fatalf("after the answer: %d", g2.a.Surface())
	}
	g2.wantText(tokens.StatusRevoked)
	g2.snap("upgrade-revoked")
	if g2.a.Licence().TrialRemaining() != 0 {
		t.Error("a refund never returns free sessions")
	}
}

func TestOfflineKeepsAccessAndRevalidationFailureDoesNotRevoke(t *testing.T) {
	g := newRig(t)
	g.a.Licence().Activate(nilCtx(), "WID-ORDER-1234")
	g.svc.Status["validate"] = 500
	g2 := newRigWith(t, g.vault, g.svc)
	g2.a.Start()
	g2.tt.Frame()
	if g2.a.Surface() != Home || !g2.a.Licence().HasFullAccess() {
		t.Fatalf("a 5xx must not revoke: %d", g2.a.Surface())
	}
}

func TestSettingsRulesAndTheOtherScreensRender(t *testing.T) {
	g := newRig(t)
	g.click("How it works")
	g.wantText("Forward only. Nothing kept.")
	g.snap("rules")
	g.click("Close how it works")
	g.click("Settings")
	g.wantText("License")
	g.wantText(tokens.SettingsExplanation)
	g.snap("settings-unlicensed")
	g.click("Done")
	if g.a.Surface() != Home {
		t.Fatalf("surface %d", g.a.Surface())
	}
	g.a.Licence().Activate(nilCtx(), "WID-ORDER-1234")
	g.tt.Frame()
	g.click("Settings")
	g.wantText(tokens.StatusActive)
	g.snap("settings-licensed")
	g.tt.SetDark(true)
	g.tt.Key(0, ui.KeyEscape)
	g.snap("home-dark")
	g.click("Settings")
	g.snap("settings-dark")
	if strings.Contains(strings.Join(g.tt.Texts(), "|"), "Mac") {
		t.Error("Mac wording on a Windows screen")
	}
}

func TestPickersPersist(t *testing.T) {
	g := newRig(t)
	path := filepath.Join(t.TempDir(), "settings.json")
	g.a.prefs = LoadPrefs(path)
	g.click("5")
	g.click("Relaxed 12 s")
	p := LoadPrefs(path)
	if p.DurationSeconds != 300 || p.SilenceSeconds != 12 {
		t.Fatalf("prefs %+v", p)
	}
	g.click("Begin writing")
	if e := g.a.Room().Engine(); e == nil {
		t.Fatal("room")
	}
}

func nilCtx() context.Context { return context.Background() }
