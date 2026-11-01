package room

import (
	"math"

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

// HistoryAlpha is the D-069 ladder by distance above the writing line; lines beyond it are gone (-1).
func HistoryAlpha(distance int, dark bool) float32 {
	l := tokens.HistoryOpacitiesLight
	if dark {
		l = tokens.HistoryOpacitiesDark
	}
	switch {
	case distance <= 0:
		return 1
	case distance < len(l):
		return l[distance]
	}
	return -1
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
