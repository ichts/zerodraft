// Package ime is the one risky layer of the Windows room: the forward-only text buffer behind mygo's
// ui.TextInputClient (IMM32 on Windows). It owns the draft text and the preedit range, allows input only at
// the end of the draft (or inside the preedit), and reports commits, preedit updates and denials through
// hooks. It knows nothing about phases, painting or the session clock.
//
// Why not mygo's ui.TextArea (evidence/ta-*, report section 2): it passes composition, wrapped-line candidates,
// key/paste denial and fonts, but exposes no composition callback, so a preedit update cannot count as
// activity, which the Mac room (and the forward-only contract) require.
package ime

import (
	"fmt"

	"github.com/egoist/mygo/ui"
)

// Break selects a deliberately broken behaviour in `-tags imebreak` builds so the suite can prove it fails
// on a known-broken state: "nodeny" lets Backspace, arrows and shortcuts through unreported, "keepeditor"
// is read by the room (the editor survives a wipe). Empty in every shipped build.
var Break string

// Hooks connect the editor to the room. Every field is optional.
type Hooks struct {
	// Gate runs before any input changes the buffer; activity is true for text and preedit. Returning
	// false refuses the input (the room is kept, or a restart is refused). The room may reset the editor
	// (Clear) inside Gate to restart after a wipe.
	Gate func(activity bool) bool
	// OnCommit runs after text entered the draft (commit, Enter); OnMark after a preedit update.
	OnCommit func()
	OnMark   func()
	// OnDeny runs for a refused edit: Backspace, arrows, undo, paste, a click, an out-of-range replace.
	OnDeny func(why string)
	// Bounds returns element-relative geometry (caret, or the preedit rect) so candidate windows follow it.
	Bounds func(rg ui.TextInputRange) (ui.Rect, bool)
	// Log receives one line per input-method callback (IME suite evidence); nil disables it.
	Log func(format string, args ...any)
}

// Editor implements ui.TextInputClient.
type Editor struct {
	Hooks
	text       string
	marked     *ui.TextInputRange // UTF-16 units, within text
	lastBounds string
	// Version increments on every text or preedit change so views can cache layouts.
	Version int
}

func New(h Hooks) *Editor { return &Editor{Hooks: h} }

// Text is the draft including any preedit text.
func (e *Editor) Text() string { return e.text }

// Marked is the preedit range in UTF-16 units.
func (e *Editor) Marked() (ui.TextInputRange, bool) {
	if e.marked == nil {
		return ui.TextInputRange{}, false
	}
	return *e.marked, true
}

func (e *Editor) Composing() bool { return e.marked != nil }

// Clear drops the draft and any preedit (a wipe, a restart).
func (e *Editor) Clear() {
	e.text, e.marked = "", nil
	e.Version++
}

// Len is the text length in UTF-16 units.
func (e *Editor) Len() int { return ui.UTF16Len(e.text) }

func (e *Editor) logf(f string, a ...any) {
	if e.Log != nil {
		e.Log(f, a...)
	}
}

func (e *Editor) deny(why string) {
	e.logf("DENY %s", why)
	if e.OnDeny != nil {
		e.OnDeny(why)
	}
}

// ---- ui.TextInputClient

func (e *Editor) TextForRange(rg ui.TextInputRange) (string, ui.TextInputRange) {
	a, z := ui.UTF16ByteOffset(e.text, rg.Start), ui.UTF16ByteOffset(e.text, rg.End)
	return e.text[a:z], ui.TextInputRange{Start: ui.UTF16Len(e.text[:a]), End: ui.UTF16Len(e.text[:z])}
}

// Selection is always the caret at the end: nothing else can be selected.
func (e *Editor) Selection() ui.TextInputSelection {
	n := e.Len()
	return ui.TextInputSelection{Range: ui.TextInputRange{Start: n, End: n}}
}

func (e *Editor) MarkedRange() (ui.TextInputRange, bool) { return e.Marked() }

// target resolves the range a replace or preedit call wants, and whether forward-only allows it.
func (e *Editor) target(rg *ui.TextInputRange) (ui.TextInputRange, bool) {
	n := e.Len()
	if e.marked != nil {
		if rg == nil || (rg.Start >= e.marked.Start && rg.End <= e.marked.End) || (rg.Start == n && rg.End == n) {
			return *e.marked, true
		}
		return ui.TextInputRange{}, false
	}
	if rg == nil || (rg.Start == n && rg.End == n) {
		return ui.TextInputRange{Start: n, End: n}, true
	}
	return ui.TextInputRange{}, false
}

func (e *Editor) splice(w ui.TextInputRange, s string) {
	a, z := ui.UTF16ByteOffset(e.text, w.Start), ui.UTF16ByteOffset(e.text, w.End)
	e.text = e.text[:a] + s + e.text[z:]
	e.Version++
}

func rgs(rg *ui.TextInputRange) string {
	if rg == nil {
		return "nil"
	}
	return fmt.Sprintf("%d-%d", rg.Start, rg.End)
}

func (e *Editor) allow(activity bool) bool {
	return e.Gate == nil || e.Gate(activity)
}

func (e *Editor) ReplaceText(rg *ui.TextInputRange, s string) {
	e.logf("IME ReplaceText range=%s text=%q marked=%v", rgs(rg), s, e.marked)
	w, ok := e.target(rg)
	if !ok {
		e.deny("ReplaceText outside the end range=" + rgs(rg))
		return
	}
	if (s != "" || e.marked != nil) && !e.allow(true) {
		e.deny("ReplaceText refused by the room")
		return
	}
	// the gate may have restarted the room and cleared the buffer: resolve the target again
	if w, ok = e.target(rg); !ok {
		w = ui.TextInputRange{Start: e.Len(), End: e.Len()}
	}
	e.splice(w, s)
	e.marked = nil
	if s != "" && e.OnCommit != nil {
		e.OnCommit()
	}
}

func (e *Editor) SetMarkedText(rg *ui.TextInputRange, s string, sel ui.TextInputRange) {
	e.logf("IME SetMarkedText text=%q sel=%v marked=%v", s, sel, e.marked)
	if _, ok := e.target(rg); !ok {
		e.deny("SetMarkedText outside the end")
		return
	}
	if !e.allow(true) {
		e.deny("SetMarkedText refused by the room")
		return
	}
	w, ok := e.target(rg)
	if !ok {
		w = ui.TextInputRange{Start: e.Len(), End: e.Len()}
	}
	e.splice(w, s)
	if s == "" {
		e.marked = nil
	} else {
		e.marked = &ui.TextInputRange{Start: w.Start, End: w.Start + ui.UTF16Len(s)}
	}
	if e.OnMark != nil {
		e.OnMark()
	}
}

func (e *Editor) UnmarkText() {
	e.logf("IME UnmarkText marked=%v", e.marked)
	if e.marked != nil {
		e.marked = nil
		e.Version++
		if e.OnCommit != nil { // the preedit became text as it stood
			e.OnCommit()
		}
	}
}

func (e *Editor) BoundsForRange(rg ui.TextInputRange) (ui.Rect, ui.TextInputRange, bool) {
	if e.Bounds == nil {
		return ui.Rect{}, rg, false
	}
	r, ok := e.Bounds(rg)
	if line := fmt.Sprintf("IME BoundsForRange %v -> %.1f,%.1f %.1fx%.1f ok=%v", rg, r.X, r.Y, r.W, r.H, ok); line != e.lastBounds {
		e.lastBounds = line
		e.logf("%s", line)
	}
	return r, rg, ok
}

// IndexForPoint always answers the end: a point can never place the caret.
func (e *Editor) IndexForPoint(ui.Point) (int, bool) { return e.Len(), true }

// ---- HandleInput

// Input is the element's HandleInput: it refuses everything that is not appending. While composing, the IME
// owns the keys, so Backspace, arrows and Enter pass through to it.
func (e *Editor) Input(ev ui.InputEvent) bool {
	if Break == "nodeny" {
		return false
	}
	switch ev.Kind {
	case ui.InputKeyDown:
		if e.marked != nil {
			return false
		}
		switch ev.Key {
		case ui.KeyBackspace, ui.KeyDelete, ui.KeyLeft, ui.KeyRight, ui.KeyUp, ui.KeyDown, ui.KeyHome, ui.KeyEnd,
			ui.KeyPageUp, ui.KeyPageDown:
			e.deny(fmt.Sprintf("key %v mods %v", ev.Key, ev.Mods))
			return true
		case ui.KeyEnter:
			if e.allow(true) {
				e.text += "\n"
				e.Version++
				e.logf("KEY Enter appended")
				if e.OnCommit != nil {
					e.OnCommit()
				}
			} else {
				e.deny("Enter refused by the room")
			}
			return true
		case ui.KeyTab:
			return true
		}
		if ev.Mods&ui.Cmd != 0 { // Ctrl on Windows
			switch ev.Key {
			case ui.KeyZ, ui.KeyY, ui.KeyV, ui.KeyX, ui.KeyA:
				e.deny(fmt.Sprintf("shortcut ctrl+%v", ev.Key))
				return true
			case ui.KeyC:
				return true // nothing can be selected, so there is nothing to copy
			}
		}
	case ui.InputPointerDown, ui.InputPointerMove, ui.InputPointerUp:
		if ev.Kind == ui.InputPointerDown {
			e.deny("pointer")
		}
		return true
	case ui.InputCommand:
		e.deny("command " + ev.Text)
		return true
	}
	return false
}
