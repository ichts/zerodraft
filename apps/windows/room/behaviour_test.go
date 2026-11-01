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
