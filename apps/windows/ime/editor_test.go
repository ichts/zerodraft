package ime

import (
	"testing"

	"github.com/egoist/mygo/ui"
)

// Table-driven contract tests against the client directly (the IMM32 bridge calls exactly these methods).
type probe struct {
	*Editor
	commits, marks, denies int
	gate                   bool
}

func newProbe() *probe {
	p := &probe{gate: true}
	p.Editor = New(Hooks{
		Gate:     func(bool) bool { return p.gate },
		OnCommit: func() { p.commits++ },
		OnMark:   func() { p.marks++ },
		OnDeny:   func(string) { p.denies++ },
	})
	return p
}

func rg(a, b int) *ui.TextInputRange { return &ui.TextInputRange{Start: a, End: b} }

func TestCommitAppendsAndPreeditReplaces(t *testing.T) {
	p := newProbe()
	p.SetMarkedText(nil, "ni", ui.TextInputRange{})
	p.SetMarkedText(nil, "nihao", ui.TextInputRange{})
	if p.Text() != "nihao" || !p.Composing() {
		t.Fatalf("text %q composing %v", p.Text(), p.Composing())
	}
	p.ReplaceText(nil, "你好")
	if p.Text() != "你好" || p.Composing() || p.commits != 1 || p.marks != 2 {
		t.Fatalf("text %q composing %v commits %d marks %d", p.Text(), p.Composing(), p.commits, p.marks)
	}
}

func TestEditsBehindTheEndAreDenied(t *testing.T) {
	p := newProbe()
	p.ReplaceText(nil, "hello")
	p.ReplaceText(rg(0, 2), "XX")                        // replace inside the draft
	p.ReplaceText(rg(1, 1), "X")                         // insert in the middle
	p.SetMarkedText(rg(0, 0), "ni", ui.TextInputRange{}) // preedit at the start
	if p.Text() != "hello" || p.denies != 3 {
		t.Fatalf("text %q denies %d", p.Text(), p.denies)
	}
	p.ReplaceText(rg(5, 5), "!") // explicit range at the end is the append
	if p.Text() != "hello!" {
		t.Fatalf("text %q", p.Text())
	}
}

func TestPreeditCanBeEditedInsideItsOwnRange(t *testing.T) {
	p := newProbe()
	p.ReplaceText(nil, "ab")
	p.SetMarkedText(nil, "zhongwen", ui.TextInputRange{})
	p.SetMarkedText(rg(2, 10), "zhongw", ui.TextInputRange{}) // IME rewrites its own preedit
	if p.Text() != "abzhongw" {
		t.Fatalf("text %q", p.Text())
	}
	p.SetMarkedText(rg(0, 1), "x", ui.TextInputRange{}) // outside the preedit
	if p.Text() != "abzhongw" || p.denies != 1 {
		t.Fatalf("text %q denies %d", p.Text(), p.denies)
	}
}

func TestSurrogatePairsKeepUTF16Ranges(t *testing.T) {
	p := newProbe()
	p.ReplaceText(nil, "a😀")
	if p.Len() != 3 {
		t.Fatalf("len %d", p.Len())
	}
	p.SetMarkedText(nil, "ni", ui.TextInputRange{})
	if m, _ := p.Marked(); m.Start != 3 || m.End != 5 {
		t.Fatalf("marked %v", m)
	}
}

func TestGateRefusesAndKeepsTheDraft(t *testing.T) {
	p := newProbe()
	p.ReplaceText(nil, "kept")
	p.gate = false
	p.ReplaceText(nil, "more")
	p.SetMarkedText(nil, "ni", ui.TextInputRange{})
	if p.Text() != "kept" || p.denies != 2 {
		t.Fatalf("text %q denies %d", p.Text(), p.denies)
	}
}

func TestKeysAreDeniedUnlessComposing(t *testing.T) {
	p := newProbe()
	p.ReplaceText(nil, "abc")
	for _, k := range []ui.Key{ui.KeyBackspace, ui.KeyDelete, ui.KeyLeft, ui.KeyRight, ui.KeyUp, ui.KeyDown, ui.KeyHome, ui.KeyEnd} {
		if !p.Input(ui.InputEvent{Kind: ui.InputKeyDown, Key: k}) {
			t.Errorf("key %v not taken", k)
		}
	}
	for _, k := range []ui.Key{ui.KeyZ, ui.KeyY, ui.KeyV, ui.KeyX, ui.KeyA} {
		if !p.Input(ui.InputEvent{Kind: ui.InputKeyDown, Key: k, Mods: ui.Cmd}) {
			t.Errorf("ctrl+%v not taken", k)
		}
	}
	p.Input(ui.InputEvent{Kind: ui.InputCommand, Text: "paste"})
	p.Input(ui.InputEvent{Kind: ui.InputPointerDown})
	if p.Text() != "abc" || p.denies != 8+5+2 {
		t.Fatalf("text %q denies %d", p.Text(), p.denies)
	}
	p.SetMarkedText(nil, "ni", ui.TextInputRange{})
	if p.Input(ui.InputEvent{Kind: ui.InputKeyDown, Key: ui.KeyBackspace}) {
		t.Error("Backspace must pass to the IME while composing")
	}
	if p.Input(ui.InputEvent{Kind: ui.InputKeyDown, Key: ui.KeyEnter}) {
		t.Error("Enter must pass to the IME while composing")
	}
}

func TestEnterAppendsALine(t *testing.T) {
	p := newProbe()
	p.ReplaceText(nil, "a")
	p.Input(ui.InputEvent{Kind: ui.InputKeyDown, Key: ui.KeyEnter})
	if p.Text() != "a\n" || p.commits != 2 {
		t.Fatalf("text %q commits %d", p.Text(), p.commits)
	}
}

func TestSelectionIsAlwaysTheEnd(t *testing.T) {
	p := newProbe()
	p.ReplaceText(nil, "你好")
	if s := p.Selection().Range; s.Start != 2 || s.End != 2 {
		t.Fatalf("selection %v", s)
	}
	if i, _ := p.IndexForPoint(ui.Point{X: 3, Y: 4}); i != 2 {
		t.Fatalf("index %d", i)
	}
}
