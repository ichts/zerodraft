package room

import (
	"math"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/ime"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// Pure geometry of the room, all in DIPs. Nothing here touches mygo's runtime, so the numbers are asserted
// in geometry_test.go and in the real-window measurements (see report).

func round(v float32) float32 { return float32(math.Round(float64(v))) }
func clampf(v, lo, hi float32) float32 {
	return float32(math.Max(float64(lo), math.Min(float64(hi), float64(v))))
}

// PaperRect is the Wheat sheet: inset 32 from the window on every side (installConstraints).
func PaperRect(w, h float32) ui.Rect {
	return ui.Rect{X: tokens.PaperMargin, Y: tokens.PaperMargin, W: w - 2*tokens.PaperMargin, H: h - 2*tokens.PaperMargin}
}

// AnchorY is the one anchor, as a distance from the top of the paper: the active writing line's middle and the
// stopped group's midpoint both sit here (D-070).
func AnchorY(paperH float32) float32 {
	if ime.Break == "anchor35" { // known-broken build for the geometry gate's own proof (the web trial's old 35%)
		return round(paperH * 0.35)
	}
	return round(paperH * tokens.AnchorFraction)
}

// Measure is the writing column: 62 characters of the writing face, never wider than the scroll area minus 16
// (updateTextMeasure). charW is the advance of "0" at the writing size.
func Measure(paperW, charW float32) (x, w float32) {
	scroll := paperW - 64 // scrollView is 32 in from each side of the paper
	w = min(float32(tokens.MeasureNarrowChars)*charW, max(scroll-16, 160))
	inset := max((scroll-w)/2, 8)
	return 32 + inset, w
}

// Failure is the stopped screen's composition: one group placed by its own midpoint on the anchor. Every
// value is a share of base, the pill height, so the locked ratios hold at any window (D-070).
type Failure struct {
	Base, HeadlineGap, PillGap, NoteSize, NoteBox, PillLabel, PillSide float32
}

func FailureFor(windowW float32) Failure {
	base := round(clampf(windowW*0.05, 32, tokens.FailureReferenceBase))
	k := base / tokens.FailureReferenceBase
	f := Failure{Base: base}
	f.HeadlineGap = base * 9 / tokens.FailureReferenceBase
	f.PillGap = base * 24 / tokens.FailureReferenceBase
	f.NoteSize = 15 * k
	f.NoteBox = round(f.NoteSize * tokens.FailureNoteLH)
	f.PillLabel = 15 * k
	f.PillSide = base * 20 / tokens.FailureReferenceBase
	return f
}

// GroupTop is the group's top edge from the paper top: the midpoint on the anchor, clamped onto the sheet.
func (f Failure) GroupTop(paperH, headlineH float32) (top, height float32) {
	height = headlineH + f.HeadlineGap + f.NoteBox + f.PillGap + f.Base
	top = round(paperH*tokens.AnchorFraction - height/2)
	top = max(0, min(top, round(paperH-height)))
	return top, height
}

// WipeWash is the warn ramp 0..1: zero until three seconds before the wipe, then linear over those seconds.
func WashFraction(idleSeconds, silenceSeconds float64, reduceMotion bool) float32 {
	warnAt := silenceSeconds - tokens.WarnLeadSeconds
	if idleSeconds < warnAt {
		return 0
	}
	if reduceMotion {
		return 1
	}
	return float32(math.Min(math.Max((idleSeconds-warnAt)/tokens.WarnLeadSeconds, 0), 1))
}

// HistoryAlpha is the history's opacity by rung (D-092): the live line is 0, older lines step back to .22 and .07
// (light; .16 and .05 dark); lines beyond the steps are gone (-1).
func HistoryAlpha(rung int, dark bool) float32 {
	l := tokens.HistoryOpacitiesLight
	if dark {
		l = tokens.HistoryOpacitiesDark
	}
	switch {
	case rung <= 0:
		return 1
	case rung < len(l):
		return l[rung]
	}
	return -1
}

// HistoryDissolve is how long the lines above take to reach their next step when Return lands (D-092); the web's
// transition and the Mac's timer are the same 320 ms.
const HistoryDissolve = 320 * time.Millisecond

// DissolveEase is CSS ease-out, cubic-bezier(0, 0, .58, 1), the curve the web's dissolve uses.
func DissolveEase(t float32) float32 {
	if t <= 0 {
		return 0
	}
	if t >= 1 {
		return 1
	}
	bez := func(u, a, b float32) float32 { return 3*a*u*(1-u)*(1-u) + 3*b*u*u*(1-u) + u*u*u }
	lo, hi := float32(0), float32(1)
	for i := 0; i < 24; i++ {
		mid := (lo + hi) / 2
		if bez(mid, 0, 0.58) < t {
			lo = mid
		} else {
			hi = mid
		}
	}
	return bez((lo+hi)/2, 0, 1)
}

// KeptHeadingSize is clamp(5% of the window, 32, 48), the live heading's own rule.
func KeptHeadingSize(windowW float32) float32 { return round(clampf(windowW*0.05, 32, 48)) }

// ease is the ease-out cubic the Mac's CAMediaTimingFunction(.easeOut) approximates.
func easeOut(t float32) float32 {
	t = clampf(t, 0, 1)
	return 1 - (1-t)*(1-t)*(1-t)
}

func lerp(a, b, t float32) float32 { return a + (b-a)*t }

// keyframes interpolates values at keyTimes over t in 0..1.
func keyframes(vals, times []float32, t float32) float32 {
	for i := 1; i < len(vals); i++ {
		if t <= times[i] {
			span := times[i] - times[i-1]
			if span <= 0 {
				return vals[i]
			}
			return lerp(vals[i-1], vals[i], (t-times[i-1])/span)
		}
	}
	return vals[len(vals)-1]
}

// The Mac's 13 pt labels (receipt, caption, footer row) are NSTextFields with a 1.6 line height multiple: the box is
// 1.6 natural lines tall and the text sits at its bottom, descent above the edge. Windows draws the same boxes, so the
// rows land where the Mac's do whatever the system face is (Segoe UI Variable, not SF).
const (
	// keptBlockTop is where the kept heading's box starts under the paper's top edge. SessionKeptView pins its header 16
	// DIP above verticalInset (72): the Mac's heading frame is y=88 on a sheet at y=32 in a 1040 x 720 window.
	keptBlockTop = 56
	// footerBaselineInset is the footer row's baseline above the paper's bottom edge: box bottom 25 up, descent 3.
	footerBaselineInset = 28
)

// macLabelBox is the height of a label with the 1.6 line height multiple: 1.6 of the system face's natural line (1.2 em).
func macLabelBox(size float32) float32 { return round(1.6 * round(size*1.2)) }

// labelBoxTop is the y to draw a natural-line-height layout so its baseline sits where the Mac puts it in a label box that
// starts at boxTop: bottom-aligned, a descent (0.2 em) above the box's lower edge.
func labelBoxTop(boxTop, size float32, weight int) float32 {
	return boxTop + macLabelBox(size) - round(0.2*size) - sansAscent(size, weight)
}

// sansAscent is the ascent of the system sans at a size and weight.
func sansAscent(size float32, weight int) float32 {
	return ui.Font{Family: sans, Size: size, Weight: weight}.Metrics().Ascent
}
