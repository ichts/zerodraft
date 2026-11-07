package room

import (
	"math"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/session"
)

func TestReturnRestartsTheStoppedRoom(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("hello")
	g.tt.Advance(9 * time.Second)
	if g.r.Engine().Phase != session.Failure {
		t.Fatalf("want failure, got %v", g.r.Engine().Phase)
	}
	g.tt.Key(0, ui.KeyEnter)
	g.tt.Advance(50 * time.Millisecond)
	if g.r.Engine().Phase != session.Writing || g.r.Engine().HasStarted() || g.r.Editor().Text() != "" {
		t.Fatalf("Return must open a fresh, unstarted room: phase %v started %v text %q", g.r.Engine().Phase, g.r.Engine().HasStarted(), g.r.Editor().Text())
	}
}

func TestTypingAfterTheWipeStartsAFreshSessionWithOnlyTheNewText(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("old draft")
	g.tt.Advance(9 * time.Second)
	g.tt.Type("n")
	if got := g.r.Editor().Text(); got != "n" || g.r.Engine().Phase != session.Writing {
		t.Fatalf("text %q phase %v", got, g.r.Engine().Phase)
	}
}

func TestExitNeedsTwoActsInsideTwoSeconds(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("hi")
	g.tt.Key(0, ui.KeyEscape)
	if g.quit {
		t.Fatal("one Esc must only arm the confirmation")
	}
	g.tt.Advance(2500 * time.Millisecond)
	g.tt.Key(0, ui.KeyEscape) // the window expired: this arms again
	if g.quit {
		t.Fatal("an Esc after the window must not leave")
	}
	g.tt.Advance(500 * time.Millisecond)
	g.tt.Key(0, ui.KeyEscape)
	if !g.quit {
		t.Fatal("the second Esc inside the window must leave")
	}
}

func TestTypingDismissesTheExitConfirmation(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("hi")
	g.tt.Key(0, ui.KeyEscape)
	g.tt.Type("x")
	g.tt.Key(0, ui.KeyEscape)
	if g.quit {
		t.Fatal("typing between the two Esc presses must disarm the exit")
	}
}

func TestFirstInputStartsTheClockAndNothingElseDoes(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Advance(30 * time.Second)
	if g.r.Engine().HasStarted() || g.r.Engine().Phase != session.Writing {
		t.Fatalf("the empty room must wait forever: started %v phase %v", g.r.Engine().HasStarted(), g.r.Engine().Phase)
	}
	g.tt.Type("a")
	if !g.r.Engine().HasStarted() {
		t.Fatal("the first input starts the clock")
	}
}

func TestPasteCutUndoSelectAllAreRefused(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("kept")
	for _, c := range []string{"paste", "cut", "undo", "redo", "selectAll", "delete"} {
		g.tt.Command(c)
	}
	for _, k := range []ui.Key{ui.KeyZ, ui.KeyY, ui.KeyV, ui.KeyX, ui.KeyA} {
		g.tt.Key(ui.Cmd, k)
	}
	if g.r.Editor().Text() != "kept" {
		t.Fatalf("draft changed: %q", g.r.Editor().Text())
	}
}

func TestPointerNeverMovesTheCaretOrEditsTheDraft(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("hello world")
	g.tt.ClickAt(300, 250)
	g.tt.Type("!")
	if g.r.Editor().Text() != "hello world!" {
		t.Fatalf("text %q", g.r.Editor().Text())
	}
}

func TestWashRampsOverTheThreeSecondsBeforeTheWipe(t *testing.T) {
	for _, c := range []struct {
		idle float64
		want float32
	}{{0, 0}, {4.999, 0}, {5, 0}, {6.5, 0.5}, {8, 1}, {9, 1}} {
		if got := WashFraction(c.idle, 8, false); math.Abs(float64(got-c.want)) > 1e-5 {
			t.Errorf("idle %.3f: %v want %v", c.idle, got, c.want)
		}
	}
	if WashFraction(5, 8, true) != 1 {
		t.Error("reduced motion paints the wash at once")
	}
}

func TestFailureCompositionKeepsTheLockedRatios(t *testing.T) {
	for _, w := range []float32{980, 1040, 760} {
		f := FailureFor(w)
		base := f.Base
		if base < 32 || base > 48 {
			t.Fatalf("base %v out of 32..48 at %v", base, w)
		}
		if math.Abs(float64(f.HeadlineGap/base-9.0/48)) > 1e-4 || math.Abs(float64(f.PillGap/base-24.0/48)) > 1e-4 ||
			math.Abs(float64(f.PillSide/base-20.0/48)) > 1e-4 || math.Abs(float64(f.NoteSize/base-15.0/48)) > 1e-4 {
			t.Errorf("ratios drifted at %v: %+v", w, f)
		}
		// the group's midpoint is on the 33% anchor
		top, h := f.GroupTop(656, base*1.1)
		if mid := float64(top + h/2); math.Abs(mid-0.33*656) > 1.5 {
			t.Errorf("midpoint %.1f vs %.1f", mid, 0.33*656)
		}
	}
	if FailureFor(980).Base != 48 {
		t.Errorf("at the minimum window the base is 48")
	}
}

func TestHistoryLadder(t *testing.T) {
	for d, want := range map[int]float32{0: 1, 1: 0.847, 2: 0.769, 3: -1} {
		if got := HistoryAlpha(d, false); got != want {
			t.Errorf("light distance %d: %v want %v", d, got, want)
		}
	}
	for d, want := range map[int]float32{1: 0.902, 2: 0.772, 3: -1} {
		if got := HistoryAlpha(d, true); got != want {
			t.Errorf("dark distance %d: %v want %v", d, got, want)
		}
	}
}

// Q-03: the empty caret sits on the measure centre, the first glyph is drawn at it, and the line does not move.
func TestEmptyCaretAndFirstGlyphShareTheInsertionColumn(t *testing.T) {
	g := newRig(t, 1040, 620)
	darkCols := func(rowLo, rowHi int) (lo, hi int) {
		img := g.tt.Image()
		lo, hi = 1<<30, -1
		for y := rowLo; y < rowHi; y++ {
			for x := 40; x < img.Bounds().Dx()-40; x++ {
				c := img.RGBAAt(x, y)
				if int(c.R) < 60 && int(c.G) < 60 && int(c.B) < 60 {
					lo, hi = min(lo, x), max(hi, x)
				}
			}
		}
		return
	}
	pr := PaperRect(1040, 620)
	anchor := int(pr.Y + AnchorY(pr.H))
	var cl, ch int
	for i := 0; i < 4 && ch < 0 || i == 0; i++ { // find a frame with the caret on (it blinks)
		g.tt.Advance(265 * time.Millisecond)
		cl, ch = darkCols(anchor-20, anchor+20)
		if ch >= 0 {
			break
		}
	}
	if ch < 0 {
		t.Fatal("no caret drawn on the empty writing line")
	}
	caretX := float64(cl+ch) / 2
	if math.Abs(caretX-float64(pr.X+pr.W/2)) > 1.5 {
		t.Fatalf("empty caret at x=%.1f, sheet centre %.1f", caretX, pr.X+pr.W/2)
	}
	g.tt.Type("a")
	g.tt.Advance(20 * time.Millisecond)
	gl, gh := darkCols(anchor-20, anchor+20)
	if gh < 0 {
		t.Fatal("first glyph not drawn")
	}
	if math.Abs(float64(gl+gh)/2-caretX) > 6 {
		t.Fatalf("first glyph centre %.1f, empty caret %.1f", float64(gl+gh)/2, caretX)
	}
}

func TestEscapeWorksOnTheKeptSheetAndTheStoppedSheet(t *testing.T) {
	g := newRig(t, 1040, 620)
	for i := 0; i < 15; i++ {
		g.tt.Type("A few more words in the draft. ")
		g.tt.Advance(4 * time.Second)
	}
	g.tt.Advance(20 * time.Second)
	if g.r.Engine().Phase != session.Success {
		t.Fatalf("phase %v", g.r.Engine().Phase)
	}
	g.tt.Key(0, ui.KeyEscape)
	if g.quit {
		t.Fatal("a single Esc on the kept sheet must only arm the exit")
	}
	g.tt.Advance(300 * time.Millisecond)
	g.tt.Key(0, ui.KeyEscape)
	if !g.quit {
		t.Fatal("two Esc presses on the kept sheet must leave the room")
	}
	// Return does not restart from the kept sheet; the stopped sheet takes Esc and Return
	g2 := newRig(t, 1040, 620)
	g2.tt.Type("x")
	g2.tt.Advance(9 * time.Second)
	g2.tt.Key(0, ui.KeyEscape)
	if g2.quit {
		t.Fatal("a single Esc on the stopped sheet must only arm the exit")
	}
	g2.tt.Advance(300 * time.Millisecond)
	g2.tt.Key(0, ui.KeyEscape)
	if !g2.quit {
		t.Fatal("two Esc presses on the stopped sheet must leave the room")
	}
}

// Q-10: completed lines do not move when the current line grows; only a new line shifts them, by one pitch.
func TestHistoryDoesNotMoveWhileTheCurrentLineGrows(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("first line of the draft that is long enough to wrap around the measure of the sheet and onto a second line")
	g.tt.Advance(400 * time.Millisecond) // the one-pitch shift has settled
	y0 := g.r.oy
	g.tt.Type(" a few")
	g.tt.Advance(300 * time.Millisecond)
	g.tt.Type(" more words")
	g.tt.Advance(300 * time.Millisecond)
	if g.r.oy != y0 {
		t.Fatalf("history moved while typing on the same line: %.2f -> %.2f", y0, g.r.oy)
	}
	g.tt.Type(" and enough extra words to push the draft onto a third line of the measure so that it shifts")
	g.tt.Advance(400 * time.Millisecond)
	pitch := float32(g.r.cfg.FontSize * 1.6)
	if d := y0 - g.r.oy; math.Abs(float64(d-pitch)) > 0.6 {
		t.Fatalf("a new line must shift the history by exactly one pitch (%.1f), got %.2f", pitch, d)
	}
}

// D-077: the first refused delete of a session names the rule for two seconds in the status slot; later refusals,
// paste, cut and undo only shake; an armed exit keeps the slot and the notice waits; a new session earns it again.
func TestFirstRefusedDeleteNamesTheRuleOncePerSession(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("private draft")
	g.tt.Advance(50 * time.Millisecond)
	g.tt.Command("paste")
	g.tt.Command("cut")
	g.tt.Key(ui.Cmd, ui.KeyZ)
	g.tt.Advance(50 * time.Millisecond)
	if !g.r.noticeUntil.IsZero() || !g.r.Engine().RefusalNoticeAt.IsZero() {
		t.Fatal("paste, cut and undo only shake: they must not earn the notice")
	}
	g.tt.Key(0, ui.KeyBackspace)
	g.tt.Advance(50 * time.Millisecond)
	until := g.r.noticeUntil
	if until.IsZero() {
		t.Fatal("the first refused delete must show the notice")
	}
	if d := until.Sub(g.r.Engine().RefusalNoticeAt); d != 2*time.Second {
		t.Fatalf("the notice lasts %v, want 2s", d)
	}
	g.tt.Key(0, ui.KeyDelete)
	g.tt.Advance(1500 * time.Millisecond)
	if !g.r.noticeUntil.Equal(until) {
		t.Fatal("a second refusal inside the window must not restart the notice")
	}
	g.tt.Type(" ")
	g.tt.Advance(700 * time.Millisecond)
	if !g.r.noticeUntil.IsZero() {
		t.Fatal("the slot must return after two seconds")
	}
	g.tt.Key(0, ui.KeyBackspace)
	g.tt.Advance(50 * time.Millisecond)
	if !g.r.noticeUntil.IsZero() {
		t.Fatal("a later refusal in the same session says nothing in the slot")
	}
}

func TestAnArmedExitKeepsTheSlotAndTheNoticeWaits(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("draft")
	g.tt.Key(0, ui.KeyEscape)
	g.tt.Key(0, ui.KeyBackspace)
	if !g.r.noticeUntil.IsZero() || !g.r.Engine().RefusalNoticeAt.IsZero() {
		t.Fatal("the notice must not be spent while the exit confirmation holds the slot")
	}
	g.tt.Type("x") // typing disarms the confirmation
	g.tt.Key(0, ui.KeyBackspace)
	if g.r.noticeUntil.IsZero() {
		t.Fatal("the waiting notice must show on the next refused delete")
	}
	g.tt.Key(0, ui.KeyEscape) // arming takes the slot back from a notice still showing
	if !g.r.noticeUntil.IsZero() || g.r.exitHintOff.IsZero() {
		t.Fatal("arming the exit takes the slot back")
	}
}

func TestANewSessionEarnsTheNoticeAgain(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.Type("draft")
	g.tt.Key(0, ui.KeyBackspace)
	g.tt.Advance(9 * time.Second) // the wipe ends the session and takes its notice
	if !g.r.noticeUntil.IsZero() {
		t.Fatal("a session that ends takes its notice with it")
	}
	g.tt.Type("again")
	g.tt.Key(0, ui.KeyBackspace)
	if g.r.noticeUntil.IsZero() {
		t.Fatal("the new session's first refused delete says it again")
	}
}

// D-088: every visual row of one line carries one colour, the ladder counts lines ended by Return from the end, and
// a full stop never steps it.
func TestHistorySpansColourWholeLines(t *testing.T) {
	g := newRig(t, 1040, 620)
	text := "First line is long and wraps. Still the first line.\nSecond line is long too.\nThird one. Same line.\nFourth is live"
	spans := g.r.historySpans(text, false)
	var got []float32
	for _, s := range spans {
		got = append(got, float32(s.Color.A)/255)
	}
	want := []float32{0, 0.769, 0.847, 1} // gone, two back, one back, live (alpha of the ink, 255 for the live line)
	if len(got) != len(want) {
		t.Fatalf("%d spans, want %d: %v", len(got), len(want), spans)
	}
	for i := range want {
		if math.Abs(float64(got[i]-want[i])) > 0.005 {
			t.Errorf("span %d alpha %.3f want %.3f", i, got[i], want[i])
		}
	}
}

func TestKeptSheetHasTheCaptionAndNoCornerCount(t *testing.T) {
	g := newRig(t, 1040, 720)
	for i := 0; i < 15; i++ {
		g.tt.Type("A few more words in the draft. ")
		g.tt.Advance(4 * time.Second)
	}
	g.tt.Advance(20 * time.Second)
	if g.r.Engine().Phase != session.Success {
		t.Fatalf("phase %v", g.r.Engine().Phase)
	}
	if g.r.cornerLabel(false, true) != "" || g.r.cornerLabel(false, false) == "" {
		t.Fatal("the corner count is silent on the kept sheet only")
	}
	k := g.r.keptGeo(1040, 720)
	// the Mac's kept block (SessionKeptView frames at 1040 x 720): heading box y=88, receipt box 148, actions 194..242,
	// caption box 254, the draft area from 304; each 13 pt label box is 26 tall
	bottom := k.copyRect.Y + k.copyRect.H
	if bottom != 242 || k.copyRect.Y != 194 {
		t.Fatalf("action row %.1f..%.1f, the Mac's is 194..242", k.copyRect.Y, bottom)
	}
	if k.area.Y != 304 {
		t.Fatalf("the draft area starts at %.1f, the Mac's at 304 (caption box 254 + 26 + 24)", k.area.Y)
	}
	if k.hy != 88 {
		t.Fatalf("heading box top %.1f, the Mac's is 88", k.hy)
	}
}

// D-076 item 2: the writing line holds the anchor for every draft length - the live line's box sits where the Mac's does
// (baseline half a pitch under the 33 percent anchor) for an empty draft, a short one and one that has scrolled.
func TestWritingLineHoldsTheAnchorForEveryDraftLength(t *testing.T) {
	var want float32
	for i, text := range []string{"", "short", "a draft long enough to wrap around the measure of the sheet and onto a second and a third row so that the history has scrolled, and more to be sure it has"} {
		g := newRig(t, 1040, 720)
		g.tt.Type(text)
		g.tt.Advance(400 * time.Millisecond) // the one-pitch shift has settled
		font := g.r.writingFont()
		pitch := font.Size * 1.6
		got := g.r.oy + g.r.scrollTgt*pitch + g.r.writingBaseline(font, pitch) // the live line's baseline, element coordinates
		if i == 0 {
			want = got
		}
		if math.Abs(float64(got-want)) > 0.01 {
			t.Fatalf("draft %d: live baseline %.2f, empty draft %.2f", i, got, want)
		}
	}
	if pr := PaperRect(1040, 720); math.Abs(float64(want-(pr.Y+AnchorY(pr.H)+44.8/2))) > 0.01 {
		t.Fatalf("baseline %.2f is not half a pitch under the anchor %.2f", want, pr.Y+AnchorY(pr.H))
	}
}
