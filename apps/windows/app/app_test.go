package app

import (
	"context"
	"fmt"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/fonts"
	"github.com/ichts/zerodraft/apps/windows/licence"
	"github.com/ichts/zerodraft/apps/windows/licence/fakeservice"
	"github.com/ichts/zerodraft/apps/windows/room"
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

// noCheckout builds the rig with no checkout service configured (Buy has nothing to open).
type rigOpt struct{ noCheckout bool }

func newRigWith(t *testing.T, vault *licence.MemoryVault, svc *fakeservice.Service, opts ...rigOpt) *rig {
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
	checkoutBase := svc.URL
	if len(opts) > 0 && opts[0].noCheckout {
		checkoutBase = ""
	}
	mgr := licence.NewManager(&licence.VaultStore{V: vault}, client, licence.NewCheckoutClient(checkoutBase, nil), testProduct, now)
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

// clickKeyField focuses the licence field. Its label above it and its placeholder say the same words (one
// string on both surfaces), so a click by text would land on the label; the field is the 44 DIP box 8 DIPs
// under the label, centred on the card.
func (g *rig) clickKeyField() {
	g.t.Helper()
	label, ok := g.tt.Find(tokens.UpgradeFieldLabel)
	if !ok {
		g.t.Fatalf("no field label on screen: %q", g.tt.Texts())
	}
	g.tt.ClickAt(520, label.Y+label.H+8+22)
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
	g.wantText(fmt.Sprintf(tokens.TrialLeftFormat, 3))
	// entering an empty room and leaving it spends nothing
	g.click("Begin writing")
	g.tt.Key(0, ui.KeyEscape)
	g.tt.Key(0, ui.KeyEscape)
	if g.a.Surface() != Home || g.a.Licence().TrialRemaining() != 3 {
		t.Fatalf("an empty room costs nothing: surface %d left %d", g.a.Surface(), g.a.Licence().TrialRemaining())
	}
	g.wantText(fmt.Sprintf(tokens.TrialLeftFormat, 3))
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
	// Next to Buy, the sentence the Mac card shows word for word.
	g.wantText(tokens.UpgradeCheckoutNote)
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
		403: tokens.ErrInvalidKey, 404: tokens.ErrInvalidKey, 503: tokens.ErrNetworkFailure, 400: tokens.ErrUnexpected,
	} {
		g.svc.Status["activate"] = status
		g.clickKeyField()
		g.tt.Type("WID-ORDER-1234")
		g.click("Activate")
		g.wantText(want)
		g.tt.Key(ui.Cmd, ui.KeyA)
		g.tt.Key(0, ui.KeyBackspace)
	}
	g.svc.Status["activate"], g.svc.Detail["activate"] = 409, "device limit reached"
	g.clickKeyField()
	g.tt.Type("WID-ORDER-1234")
	g.click("Activate")
	g.wantText(tokens.ErrActivationLimitReached)
	g.snap("upgrade-limit")
	g.svc.Status["activate"] = 0
	g.click("Activate")
	g.wantText("This PC is licensed.")
	g.wantText("Begin")
	g.snap("upgrade-licensed")
	if !g.a.Licence().HasFullAccess() || g.a.key != "" {
		t.Fatal("licensed and the field cleared")
	}
	g.click("Begin")
	if g.a.Surface() != Home || g.tt.HasText("free sessions left") || g.tt.HasText("Activate this PC") {
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
	g.wantText(tokens.SettingsFieldPlaceholder)
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

// D-076 item 3: the card offers nothing it cannot complete. With checkout unavailable there is no Buy at all, and the
// free route is a real 48 DIP outlined control, not a caption-shaped link.
func TestUpgradeCardOffersNothingItCannotComplete(t *testing.T) {
	vault := &licence.MemoryVault{}
	vault.Set("state", licence.State{TrialSessionsUsed: 3, Status: licence.Inactive}.Marshal())
	g := newRigWith(t, vault, nil, rigOpt{noCheckout: true})
	if g.a.Surface() != Upgrade {
		t.Fatal("exhausted trial opens the card")
	}
	if g.tt.HasText("Buy a license, $4.99 once") {
		t.Fatalf("no Buy without checkout: %q", g.tt.Texts())
	}
	if g.tt.HasText(tokens.UpgradeCheckoutNote) {
		t.Fatalf("the checkout note describes a Buy that is not on the card: %q", g.tt.Texts())
	}
	g.wantText(tokens.UpgradeCheckoutUnavailable)
	g.wantText(tokens.UpgradeSubtitle)
	g.snap("upgrade-no-checkout")
	r, ok := g.tt.Find(tokens.UpgradeWebTrial)
	if !ok || r.H < 47.5 || r.H > 48.5 {
		t.Fatalf("the free web room control is %v, want 48 DIP tall", r)
	}
	g.click(tokens.UpgradeWebTrial)
	if len(g.opened) != 1 || g.opened[0] != tokens.WebTrialURL {
		t.Fatalf("opened %v", g.opened)
	}
}

// While a key check runs the card says so and the paid path waits.
func TestActivationInFlightSaysCheckingYourKey(t *testing.T) {
	vault := &licence.MemoryVault{}
	vault.Set("state", licence.State{TrialSessionsUsed: 3, Status: licence.Inactive}.Marshal())
	g := newRigWith(t, vault, nil)
	g.svc.Status["activate"] = 503
	g.clickKeyField()
	g.tt.Type("WID-ORDER-1234")
	snap := g.a.Licence().Snapshot()
	if snap.Activating {
		t.Fatal("setup: nothing in flight yet")
	}
	if msg, bad := g.a.feedback(licence.Snapshot{Activating: true}); msg != tokens.UpgradeChecking || bad {
		t.Fatalf("feedback while activating: %q bad=%v", msg, bad)
	}
}

// D-076 item 5: the rules sheet is the scale's 15 pt on a 1.5 line box over a 60 character measure, and each rule
// title is never smaller than its paragraph.
func TestRulesSheetFollowsTheTypeScale(t *testing.T) {
	g := newRig(t)
	g.click("How it works")
	title, ok1 := g.tt.Find(tokens.Rule1Title)
	body, ok2 := g.tt.Find(tokens.Rule1Body)
	if !ok1 || !ok2 {
		t.Fatalf("rules not on screen: %q", g.tt.Texts())
	}
	const line = 15 * tokens.RulesBodyLeading
	if title.H != line {
		t.Errorf("rule title box %.2f tall, want one %.1f line", title.H, line)
	}
	if lines := body.H / line; lines != float32(int(lines)) || lines < 1 {
		t.Errorf("rule body %.2f tall: not a whole number of %.1f lines", body.H, line)
	}
	measure := float32(math.Round(float64(tokens.RulesMeasureChars * room.TextWidth("0", 15, 400))))
	if body.W > measure+0.5 || measure < 480 {
		t.Errorf("rule body %.1f wide on a %.1f measure", body.W, measure)
	}
	g.snap("rules-scale")
}

// D-091: the help button is a 32 DIP circle on the lockup's centre line, flush with the card's inner padding.
func TestHelpButtonSitsOnTheLogoRowAndTheCardPadding(t *testing.T) {
	g := newRig(t)
	help, ok1 := g.tt.Find(tokens.HomeRulesHelp)
	title, ok2 := g.tt.Find(tokens.HomeTitle)
	if !ok1 || !ok2 {
		t.Fatalf("help or title not on screen: %q", g.tt.Texts())
	}
	// the lockup sits 17 DIP above the title (homeView's first gap); its box is the chip's measured size
	const chipH = tokens.ChipPickerTypeSize * tokens.ChipEmHeight
	lockupMid := title.Y - 17 - chipH/2
	if help.W != 32 || help.H != 32 {
		t.Errorf("help button %.2f x %.2f, want 32 x 32", help.W, help.H)
	}
	if d := (help.Y + help.H/2) - lockupMid; d < -0.5 || d > 0.5 {
		t.Errorf("help centre is %.2f off the lockup centre line", d)
	}
	const cardW, pad, windowW = 560, 48 + 1, 1040 // padding plus the card ring
	if d := (help.X + help.W) - (float32(windowW-cardW)/2 + cardW - pad); d < -0.5 || d > 0.5 {
		t.Errorf("help right edge is %.2f off the card's inner padding", d)
	}
}
