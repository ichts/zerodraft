package room

import (
	"github.com/ELY-Open-Source/CrychicUI/button"
	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/session"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// The room's three action pills are CrychicUI buttons (button.Pill, button.Outline) on mygo's ButtonBase: press
// scale 0.97 (kit.Press, the Mac room primary's own press), keyboard focus ring, Enter and Space, an accessible
// button role, and a Tap cue wired through the sound package (off by default). The room's theme (roomTheme) is
// what turns them into the ink pill and the white outlined pill; nothing else of CrychicUI's look is used.

// roomTheme maps the After tokens onto mygo's theme, so every control inherits the room's colours.
func roomTheme(dark bool) *ui.Theme {
	t := ui.LightTheme()
	if dark {
		t = ui.DarkTheme()
	}
	ink, onInk := rc(tokens.Ink, dark), rc(tokens.OnInk, dark)
	t.Dark = dark
	t.Background = rc(tokens.Page, dark) // the window's own colour, so nothing flashes white before the first frame
	t.Surface = rc(tokens.Sheet, dark)
	t.Border = rc(tokens.HairStrong, dark)
	t.Text = ink
	t.TextMuted = rc(tokens.PaperQuiet, dark)
	t.Accent, t.AccentHover, t.AccentPressed, t.AccentText = ink, ink, ink, onInk
	t.Focus = ink
	t.Font = sans
	return t
}

// pills places the buttons of the stopped and kept screens as absolutely positioned children of the room.
func (r *Room) pills(c *ui.Context, W, H float32, dark bool) {
	switch r.eng.Phase {
	case session.Failure:
		g := r.stoppedGeo(W, H)
		b := button.Outline(c, tokens.StrBeginAgain)
		r.pillStyle(b, g.pill, g.pillLabelSize, 600, dark, true).KeepFocus().Label(tokens.StrBeginAgain)
		if b.Clicked() {
			r.activate("pill")
		}
	case session.Success:
		g := r.keptGeo(W, H)
		cp := button.Pill(c, r.copyLabel)
		r.pillStyle(cp, g.copyRect, 15, 500, dark, false).AutoFocus().Label(r.copyLabel)
		if cp.Clicked() {
			r.activate("copy")
		}
		rn := button.Outline(c, tokens.StrRunAgain)
		r.pillStyle(rn, g.runRect, 15, 500, dark, true).Label(tokens.StrRunAgain)
		if rn.Clicked() {
			r.activate("run")
		}
	}
}

// pillStyle sets the locked pill geometry: exact rect, full radius, 0.04 em tracking, the label's capitals on
// the pill's optical centre (labelTop, as a padding offset), and the stopped screen's shake.
func (r *Room) pillStyle(b ui.Element, rect ui.Rect, size float32, weight int, dark, outline bool) ui.Element {
	_, lh := r.shape(textSpec{s: "X", family: sans, size: size, weight: weight, lh: 1.6}).Size()
	off := labelTop(rect.H, lh, size) - (rect.H-lh)/2 // how far the label must move from plain centring
	top, bottom := float32(0), float32(0)
	if off >= 0 {
		top = 2 * off
	} else {
		bottom = -2 * off
	}
	if outline { // the Mac secondary pill is filled with the sheet colour, not the page's
		b = b.Background(rc(tokens.Sheet, dark))
	}
	return b.Absolute().Left(rect.X).Top(rect.Y).Width(rect.W).Height(rect.H).Radius(999).
		Padding(top, 0, bottom, 0).Justify(ui.Center).AlignItems(ui.Center).
		FontSize(size).FontWeight(weight).LetterSpacing(0.04*size).Translate(r.shakeOffset(r.now()), 0)
}
