package room

import (
	"encoding/json"
	"image/png"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/fonts"
	"github.com/ichts/zerodraft/apps/windows/session"
)

func init() {
	if err := fonts.Register(); err != nil {
		panic(err)
	}
}

type rig struct {
	t    *testing.T
	tt   *ui.Tester
	r    *Room
	quit bool
}

func newRig(t *testing.T, w, h int) *rig {
	g := &rig{t: t}
	var tt *ui.Tester
	g.r = New(Config{Log: func(f string, a ...any) { t.Logf(f, a...) }, Clock: func() time.Time {
		if tt == nil {
			return time.Unix(1_800_000_000, 0)
		}
		return tt.Now()
	}, Copy: func(string) {}, Quit: func() { g.quit = true }})
	tt = ui.NewTester(g.r.View, w, h)
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

// The unit is always word or words, in every language (D-099); the shared fixture pins the numbers and labels.
func TestCountLabelIsAlwaysWords(t *testing.T) {
	raw, err := os.ReadFile("../../../tests/fixtures/word-count.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Labels []struct{ Text, Label string }
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	if len(fixture.Labels) == 0 {
		t.Fatal("the shared fixture has no labels")
	}
	for _, c := range fixture.Labels {
		if got := wordLabel(session.WordCount(c.Text)); got != c.Label {
			t.Errorf("wordLabel(%.20q) = %q, want %q", c.Text, got, c.Label)
		}
	}
	if got := keptReceipt(3, time.Minute); got != "1 minute. 3 words." {
		t.Fatalf("CJK receipt = %q", got)
	}
	if got := keptReceipt(1, time.Minute); got != "1 minute. 1 word." {
		t.Fatalf("receipt = %q", got)
	}
}

// The live corner slot reads the same for a Chinese draft: typed 你 is `1 word`, 你好 is `2 words`.
func TestCornerCountReadsWordsForAChineseDraft(t *testing.T) {
	g := newRig(t, 1040, 720)
	g.tt.Type("你")
	g.tt.Advance(100 * time.Millisecond)
	if got := g.r.cornerLabel(false, false); got != "1 word" {
		t.Fatalf("one Han character = %q", got)
	}
	g.tt.Type("好")
	g.tt.Advance(100 * time.Millisecond)
	if got := g.r.cornerLabel(false, false); got != "2 words" {
		t.Fatalf("two Han characters = %q", got)
	}
}

func TestSnapshots(t *testing.T) {
	g := newRig(t, 1040, 720)
	g.snap("00-empty")
	g.tt.Type("The first line of the draft goes here and keeps going until it wraps around the measure of the sheet.")
	g.tt.Advance(100 * time.Millisecond)
	g.snap("01-typing")
	if g.r.Engine().Phase != session.Writing || g.r.Editor().Text() == "" {
		t.Fatalf("phase %v text %q", g.r.Engine().Phase, g.r.Editor().Text())
	}
	g.tt.Advance(6 * time.Second)
	g.snap("02-warn")
	g.tt.Advance(2500 * time.Millisecond)
	g.snap("03-stopped")
	if g.r.Engine().Phase != session.Failure {
		t.Fatalf("want failure, got %v", g.r.Engine().Phase)
	}
}

func TestSnapshotsKept(t *testing.T) {
	g := newRig(t, 1040, 720)
	for i := 0; i < 15; i++ {
		g.tt.Type("A few more words in the draft. ")
		g.tt.Advance(4 * time.Second)
	}
	g.tt.Advance(20 * time.Second)
	g.snap("04-kept")
	if g.r.Engine().Phase != session.Success {
		t.Fatalf("want success, got %v (text %q)", g.r.Engine().Phase, g.r.Editor().Text())
	}
	g.tt.Key(0, ui.KeyTab)
	g.tt.Advance(50 * time.Millisecond)
	g.snap("05-kept-focus-run")
}

func TestSnapshotsExitAndDeny(t *testing.T) {
	g := newRig(t, 1040, 720)
	g.tt.Type("hello world")
	g.tt.Key(0, ui.KeyEscape)
	g.tt.Advance(30 * time.Millisecond)
	g.snap("06-exit-armed")
	g.tt.Key(0, ui.KeyBackspace)
	g.tt.Advance(60 * time.Millisecond)
	g.snap("07-deny")
	if g.r.Editor().Text() != "hello world" {
		t.Fatalf("backspace changed the draft: %q", g.r.Editor().Text())
	}
}

func TestBackspaceIsDeniedAndFlashes(t *testing.T) {
	g := newRig(t, 1040, 720)
	g.tt.Type("hello")
	g.tt.Key(0, ui.KeyBackspace)
	if g.r.denyAt.IsZero() {
		t.Fatal("Backspace must register a deny")
	}
	if g.r.Editor().Text() != "hello" {
		t.Fatalf("text %q", g.r.Editor().Text())
	}
}

// The ink pill must be exactly 48 DIP tall (48 px at scale 1): measured from the rendered frame.
func TestKeptPillIs48Tall(t *testing.T) {
	g := newRig(t, 1040, 620)
	for i := 0; i < 15; i++ {
		g.tt.Type("A few more words in the draft. ")
		g.tt.Advance(4 * time.Second)
	}
	g.tt.Advance(20 * time.Second)
	g.tt.Frame()
	img := g.tt.Image()
	best := 0
	for x := 0; x < img.Bounds().Dx(); x++ {
		run, mx := 0, 0
		for y := 150; y < 330; y++ {
			c := img.RGBAAt(x, y)
			if int(c.R) < 40 && int(c.G) < 38 && int(c.B) < 36 {
				run++
				mx = max(mx, run)
			} else {
				run = 0
			}
		}
		best = max(best, mx)
	}
	if best < 46 || best > 49 {
		t.Fatalf("tallest ink column %d px, want ~48", best)
	}
}

func TestSnapshotsDark(t *testing.T) {
	g := newRig(t, 1040, 620)
	g.tt.SetDark(true)
	g.tt.Type("The first line of the draft goes here and keeps going until it wraps around the measure of the sheet, and then one more line follows it.")
	g.tt.Advance(6 * time.Second)
	g.snap("08-dark-warn")
	g.tt.Advance(3 * time.Second)
	g.snap("09-dark-stopped")
}
