package room

import (
	"fmt"
	"slices"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/fonts"
	"github.com/ichts/zerodraft/apps/windows/ime"
	"github.com/ichts/zerodraft/apps/windows/paper"
	"github.com/ichts/zerodraft/apps/windows/session"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

const (
	sans         = "Segoe UI Variable, Segoe UI"
	serifItalic  = "Newsreader Italic, Zhuque Fangsong"
	hairlineW    = 1
	focusRingW   = 2
	barHeight    = 2
	pillMinWidth = 0
)

func rc(r tokens.Role, dark bool) ui.Color {
	v, a := r.Light, r.LightAlpha
	if dark {
		v, a = r.Dark, r.DarkAlpha
	}
	return ui.RGBA(uint8(v>>16), uint8(v>>8), uint8(v), a)
}

func withAlpha(c ui.Color, a float32) ui.Color {
	c.A = uint8(float32(c.A)*clampf(a, 0, 1) + 0.5)
	return c
}

type textSpec struct {
	s       string
	family  string
	size    float32
	weight  int
	italic  bool
	spacing float32 // em
	lh      float32
	width   float32
	center  bool
}

// shape shapes (and caches) one run of chrome or display text.
func (r *Room) shape(t textSpec) *ui.TextLayout {
	key := fmt.Sprintf("%q|%s|%.2f|%d|%v|%.3f|%.2f|%.1f|%v", t.s, t.family, t.size, t.weight, t.italic, t.spacing, t.lh, t.width, t.center)
	if l, ok := r.shapes[key]; ok {
		return l
	}
	if len(r.shapes) > 200 {
		r.shapes = map[string]*ui.TextLayout{}
	}
	al := ui.Start
	if t.center {
		al = ui.Center
	}
	l := ui.ShapeRichTextWith([]ui.Span{{Text: t.s, LetterSpacing: t.spacing * t.size}},
		ui.Font{Family: t.family, Size: t.size, Weight: t.weight, Italic: t.italic, LineHeight: t.lh},
		ui.TextShape{Width: t.width, Align: al})
	r.shapes[key] = l
	return l
}

func (r *Room) writingFont() ui.Font {
	return ui.Font{Family: fonts.Stack, Size: r.cfg.FontSize, LineHeight: tokens.LineHeight}
}

func (r *Room) charW() float32 {
	w, _ := r.shape(textSpec{s: "0", family: fonts.Stack, size: r.cfg.FontSize, lh: tokens.LineHeight}).Size()
	return w
}

// textOrigin is where the writing layout's top-left sits, element relative (published by the last draw).
func (r *Room) textOrigin() (float32, float32) { return r.ox, r.oy }

// ---- the paper

func (r *Room) ensureSheet(wPx, hPx int, scale float32, dark bool) *sheetState {
	key := fmt.Sprintf("%dx%d@%.2f-%v", wPx, hPx, scale, dark)
	cur := r.sheet.Load()
	if cur != nil && cur.key == key {
		return cur
	}
	build := func() {
		s := paper.Render(wPx, hPx, float64(scale), dark)
		st := &sheetState{key: key, bitmap: ui.NewBitmap(s.Texture), base: s.Base, shift: s.Shift, w: wPx, h: hPx}
		r.sheet.Store(st)
		r.logf("PAPER rendered %s", key)
	}
	if cur == nil { // the first frame already carries the paper: never a flat sheet
		t0 := time.Now()
		build()
		r.logf("PAPER first render %.0f ms", float64(time.Since(t0).Microseconds())/1000)
		return r.sheet.Load()
	}
	r.sheetMu.Lock()
	if !r.building {
		r.building = true
		go func() {
			build()
			r.sheetMu.Lock()
			r.building = false
			r.sheetMu.Unlock()
			r.invalidate()
		}()
	}
	r.sheetMu.Unlock()
	return cur // the previous texture, stretched, until the new size is ready
}

func clampByte(v float64) uint8 {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return uint8(v + 0.5)
}

func (r *Room) draw(p *ui.Painter, box ui.Rect, now time.Time, dark bool) {
	W, H := box.W, box.H
	r.boxH = H
	if !r.drawn {
		r.drawn = true
		r.logf("FIRSTFRAME epoch_ms=%d", time.Now().UnixMilli())
	}
	if sz := fmt.Sprintf("%.1fx%.1f@%.2f", W, H, p.Scale()); sz != r.lastSize {
		r.lastSize = sz
		r.logf("SIZE %s", sz)
	}
	pr := PaperRect(W, H)
	scale := p.Scale()
	phase := r.eng.Phase
	failure := phase == session.Failure
	kept := phase == session.Success

	SheetShadow(p, pr, tokens.RadiusSheet, dark)

	dx := r.shakeOffset(now)
	p.Transform(ui.Translation(dx, 0), pr.X+pr.W/2, pr.Y+pr.H/2, func() {
		p.Clip(pr, tokens.RadiusSheet, func() {
			r.drawSheet(p, pr, now, dark, scale)
			r.drawContent(p, box, pr, now, dark, failure, kept)
			r.drawDenyOutline(p, pr, now, dark)
		})
		p.Stroke(pr, rc(tokens.SheetRing, dark), tokens.RadiusSheet, hairlineW)
	})
}

func pick[T any](c bool, a, b T) T {
	if c {
		return a
	}
	return b
}

func (r *Room) drawSheet(p *ui.Painter, pr ui.Rect, now time.Time, dark bool, scale float32) {
	wPx, hPx := int(float64(pr.W*scale)+0.5), int(float64(pr.H*scale)+0.5)
	st := r.ensureSheet(wPx, hPx, scale, dark)
	tone := rc(tokens.Paper, dark)
	baseC := ui.RGB(clampByte(float64(tone.R)+st.shift.R), clampByte(float64(tone.G)+st.shift.G), clampByte(float64(tone.B)+st.shift.B))
	p.Fill(pr, baseC, 0)
	full := ui.Rect{W: float32(st.w), H: float32(st.h)}
	p.ImageRegion(st.bitmap, full, pr, ui.ImageOptions{})
	frac, deep, alpha := r.wash(now)
	if alpha <= 0 {
		return
	}
	target := rc(pick(deep, tokens.PaperWashDeep, tokens.PaperWash), dark)
	mix := func(a, b uint8, shift float64) uint8 {
		return clampByte(float64(a) + (float64(b)-float64(a))*float64(frac) + shift)
	}
	tint := ui.RGB(mix(tone.R, target.R, st.shift.R), mix(tone.G, target.G, st.shift.G), mix(tone.B, target.B, st.shift.B))
	p.Fill(pr, withAlpha(tint, alpha), 0)
	white := ui.RGBA(255, 255, 255, alpha)
	p.ImageRegion(st.bitmap, full, pr, ui.ImageOptions{Tint: white})
}

// wash returns the sheet's warm tint 0..1, whether it is the deeper cut step, and its opacity (the exit is
// a 120 ms fade that keeps the last tint; the cut holds the deep step for 200 ms first).
func (r *Room) wash(now time.Time) (frac float32, deep bool, alpha float32) {
	reduce := r.ctx != nil && r.ctx.Preferences().ReduceMotion
	cur := float32(0)
	if r.eng.Phase == session.Danger {
		cur = WashFraction(r.eng.Idle.Seconds(), r.cfg.Silence.Seconds(), reduce)
	}
	switch {
	case !r.cutUntil.IsZero() && now.Before(r.cutUntil):
		r.lastWash, r.lastDeep, r.fadeStart = 1, true, r.cutUntil
		return 1, true, 1
	case cur > 0:
		r.lastWash, r.lastDeep, r.fadeStart = cur, false, time.Time{}
		return cur, false, 1
	case r.lastWash > 0:
		if r.fadeStart.IsZero() {
			r.fadeStart = now
		}
		a := 1 - float32(now.Sub(r.fadeStart))/float32(120*time.Millisecond)
		if reduce || a <= 0 {
			r.lastWash, r.lastDeep, r.fadeStart = 0, false, time.Time{}
			return 0, false, 0
		}
		return r.lastWash, r.lastDeep, a
	}
	return 0, false, 0
}

// shakeOffset and the hairline are the deny feedback (D-022): a 3 px paper shake and a red outline flash.
func (r *Room) shakeOffset(now time.Time) float32 {
	if r.denyAt.IsZero() || (r.ctx != nil && r.ctx.Preferences().ReduceMotion) {
		return 0
	}
	t := float32(now.Sub(r.denyAt)) / float32(200*time.Millisecond)
	if t >= 1 {
		return 0
	}
	return keyframes([]float32{r.denyShake0, -3, 2.5, -1, 0}, []float32{0, 0.18, 0.42, 0.7, 1}, easeOut(t))
}

func (r *Room) drawDenyOutline(p *ui.Painter, pr ui.Rect, now time.Time, dark bool) {
	if r.denyAt.IsZero() {
		return
	}
	t := float32(now.Sub(r.denyAt)) / float32(220*time.Millisecond)
	if t >= 1 {
		return
	}
	a := keyframes([]float32{0, 1, 1, 0}, []float32{0, 0.08, 0.55, 1}, easeOut(t))
	p.Stroke(pr, withAlpha(rc(tokens.Red, dark), a), tokens.RadiusSheet, hairlineW)
}

// ---- the content

func (r *Room) drawContent(p *ui.Painter, box, pr ui.Rect, now time.Time, dark, failure, kept bool) {
	ink, quiet, danger := rc(tokens.Ink, dark), rc(tokens.PaperQuiet, dark), rc(tokens.PaperDanger, dark)
	e := r.eng

	// the 2 px session bar: one continuous drain over the remaining time, off on the stopped sheet
	frac := float32(1)
	switch {
	case failure || kept:
		frac = 0
	case e.HasStarted():
		frac = clampf(1-float32(now.Sub(e.StartedAt()).Seconds()/e.Duration.Seconds()), 0, 1)
	}
	p.Fill(ui.Rect{X: pr.X, Y: pr.Y, W: pr.W * frac, H: barHeight}, ink, 0)

	switch {
	case kept:
		r.drawKept(p, box, pr, dark)
	case failure:
		r.drawStopped(p, box, pr, dark)
	default:
		r.drawWriting(p, box, pr, now, dark)
	}

	r.drawChrome(p, pr, dark, quiet, danger, ink, failure, kept)
}

func (r *Room) drawChrome(p *ui.Painter, pr ui.Rect, dark bool, quiet, danger, ink ui.Color, failure, kept bool) {
	e := r.eng
	// clock, top right: system sans 15 / 600, monospaced digits; off on the stopped sheet
	if !failure {
		secs := int((e.Remaining + time.Second - 1) / time.Second)
		l := r.shape(textSpec{s: session.Clock(secs), family: sans, size: 15, weight: 600})
		w, _ := l.Size()
		p.TextLayout(l, pr.X+pr.W-tokens.RoomInset-w, pr.Y+18, ink)
	}
	// the footer row: the Mac's 13 pt labels sit bottom-aligned in their 1.6 line box, so their baseline is 3 DIP above
	// the box's bottom edge, and the box ends 25 above the paper's (measured on the Mac room at 1040 x 720: 660 in a
	// 688 sheet, for the exit label and the count alike)
	base := pr.Y + pr.H - footerBaselineInset
	// the exit label, bottom left (D-090: one footer style, 13 / 400, no tracking, sentence case, like the count)
	ex := r.shape(textSpec{s: tokens.StrExitLink, family: sans, size: 13, weight: 400})
	exW, _ := ex.Size()
	exX := pr.X + tokens.RoomInset
	top := base - sansAscent(13, 400)
	// the status slot beside the exit link: the armed exit confirmation in the pen, else the first refused delete's
	// notice in the quiet role (the pen is kept for warnings); the slot is one place, so nothing moves
	switch {
	case !r.exitHintOff.IsZero():
		h := r.shape(textSpec{s: tokens.StrExitHint, family: sans, size: 13, weight: 400})
		p.TextLayout(h, exX+exW+12, top, danger)
	case !r.noticeUntil.IsZero():
		h := r.shape(textSpec{s: tokens.StrRefusalNotice, family: sans, size: 13, weight: 400})
		p.TextLayout(h, exX+exW+12, top, quiet)
	}
	label := r.cornerLabel(failure, kept)
	if label == "" {
		return
	}
	cl := r.shape(textSpec{s: label, family: sans, size: 13})
	cw, _ := cl.Size()
	p.TextLayout(cl, pr.X+pr.W-tokens.RoomInset-cw, base-sansAscent(13, 400), quiet)
}

// cornerLabel is the bottom-right slot: the instruction before the first key, then the live count (13 / 400). The
// kept sheet's receipt owns the count, so the slot is silent there (D-074).
func (r *Room) cornerLabel(failure, kept bool) string {
	switch {
	case kept && ime.Break != "keptcount": // keptcount is the known-broken build the capture gate must fail on
		return ""
	case r.eng.HasStarted() || failure:
		return wordLabel(r.eng.WordCount)
	}
	return tokens.StrTypeToBegin
}

func wordLabel(n int) string {
	if n == 1 {
		return "1 word"
	}
	return fmt.Sprintf("%d words", n)
}

// ---- writing

func (r *Room) drawWriting(p *ui.Painter, box, pr ui.Rect, now time.Time, dark bool) {
	ink := rc(tokens.Ink, dark)
	font := r.writingFont()
	pitch := font.Size * tokens.LineHeight
	mx, mw := Measure(pr.W, r.charW())
	x0 := pr.X + mx
	anchor := pr.Y + AnchorY(pr.H)

	text := r.ed.Text()
	ver := r.ed.Version
	alphas, dissolving := r.historyAlphas(text, dark, now)
	key := fmt.Sprintf("%.1f|%v|%v|%v", mw, r.ed.Composing(), dark, alphas)
	if r.layout == nil || r.layoutVer != ver || r.layoutKey != key || dissolving {
		r.layout = r.shapeWriting(text, mw, font, dark, alphas)
		r.layoutVer, r.layoutKey = ver, key
	}
	endIdx := r.ed.Len()
	cb := r.layout.Caret(endIdx)
	cur := float32(int(cb.Y/pitch + 0.5))
	if cur != r.scrollTgt {
		prev := r.scrollTo
		if r.scrollAt.IsZero() || now.Sub(r.scrollAt) >= 180*time.Millisecond {
			prev = r.scrollTgt
		} else {
			prev = lerp(r.scrollFrom, r.scrollTgt, easeOut(float32(now.Sub(r.scrollAt))/float32(180*time.Millisecond)))
		}
		if abs32(cur-prev) <= 2.5 && !(r.ctx != nil && r.ctx.Preferences().ReduceMotion) && r.started {
			r.scrollFrom, r.scrollAt = prev, now
		} else {
			r.scrollFrom, r.scrollAt = cur, time.Time{}
		}
		r.scrollTgt = cur
	}
	r.started = true
	row := r.scrollTgt
	if !r.scrollAt.IsZero() {
		t := float32(now.Sub(r.scrollAt)) / float32(180*time.Millisecond)
		if t >= 1 {
			r.scrollAt = time.Time{}
		} else {
			row = lerp(r.scrollFrom, r.scrollTgt, easeOut(t))
		}
	}
	// The live line's baseline sits half a pitch under the anchor: the Mac puts the glyphs at the bottom of their 1.6 line
	// box (all the leading above) and anchors the line there. mygo splits the leading evenly, so the box moves to land
	// the baseline on the Mac's (measured: baseline 270 on a sheet whose anchor is 248, at 1040 x 720).
	oy := anchor + pitch/2 - r.writingBaseline(font, pitch) - row*pitch
	r.ox, r.oy = x0, oy

	area := ui.Rect{X: pr.X + 32, Y: pr.Y + 72, W: pr.W - 64, H: pr.H - 144}
	p.Clip(area, 0, func() {
		// every span carries its own rung's colour (shapeWriting); the default colour is the gone rung, invisible
		p.TextLayout(r.layout, x0, oy, ui.RGBA(0, 0, 0, 0))
		if !r.ed.Composing() && r.eng.Phase != session.Failure && (now.UnixMilli()/530)%2 == 0 {
			m := ui.Font{Family: "Newsreader", Size: font.Size}.Metrics()
			ch := m.Ascent + m.Descent
			p.Fill(ui.Rect{X: x0 + cb.X, Y: oy + cb.Y + (pitch-ch)/2, W: 1.5, H: ch}, ink, 0)
		}
	})

	if r.eng.Phase == session.Danger {
		r.drawWarning(p, pr, ink, dark, anchor, pitch, font)
	}
}

// leadingAbove is how far the Mac's bottom-aligned glyphs sit lower in a 1.6 line box than mygo's evenly split leading
// puts them: half of the box's leading (D-077's lines and the kept draft are Newsreader in 1.6 boxes).
func (r *Room) leadingAbove() float32 {
	font := r.writingFont()
	m := ui.Font{Family: "Newsreader", Size: font.Size}.Metrics()
	return (font.Size*tokens.LineHeight - (m.Ascent + m.Descent)) / 2
}

// writingBaseline is the baseline's distance below the top of a writing line's box in mygo's layout.
func (r *Room) writingBaseline(font ui.Font, pitch float32) float32 {
	m := ui.Font{Family: "Newsreader", Size: font.Size}.Metrics()
	return (pitch-(m.Ascent+m.Descent))/2 + m.Ascent
}

func abs32(v float32) float32 {
	if v < 0 {
		return -v
	}
	return v
}

// historyAlphas is the opacity each line is drawn at now. A line that Return moves to its next step dissolves there
// over HistoryDissolve instead of jumping (D-092); a new line, a changed theme, Reduce Motion or a wiped draft is
// drawn at its step at once. dissolving is true while a frame still differs from the last one.
func (r *Room) historyAlphas(text string, dark bool, now time.Time) (alphas []float32, dissolving bool) {
	lines := session.HistoryLines(text)
	targets := make([]float32, len(lines))
	for i, l := range lines {
		targets[i] = max(HistoryAlpha(l.Rung, dark), 0)
	}
	known := len(r.hShown)
	reduce := r.ctx != nil && r.ctx.Preferences().ReduceMotion
	if r.hDark != dark || reduce || known == 0 || known > len(targets) {
		r.hShown, r.hFrom, r.hTo, r.hAt, r.hDark = targets, nil, targets, time.Time{}, dark
		return targets, false
	}
	// extend the running dissolve over lines that appeared since the last frame: they start at their step
	pad := func(v []float32) []float32 {
		for len(v) < len(targets) {
			v = append(v, targets[len(v)])
		}
		return v
	}
	moved := false
	for i := 0; i < known; i++ {
		if abs32(targets[i]-r.hTo[i]) > 0.0005 {
			moved = true
		}
	}
	if moved {
		r.hFrom, r.hAt = pad(append([]float32(nil), r.hShown...)), now
	} else if !r.hAt.IsZero() {
		r.hFrom = pad(r.hFrom)
	}
	r.hTo = targets
	if r.hAt.IsZero() {
		r.hShown = targets
		return targets, false
	}
	t := float32(now.Sub(r.hAt)) / float32(HistoryDissolve)
	if t >= 1 {
		r.hAt, r.hFrom, r.hShown = time.Time{}, nil, targets
		return targets, false
	}
	e := DissolveEase(t)
	shown := make([]float32, len(targets))
	for i := range shown {
		shown[i] = lerp(r.hFrom[i], targets[i], e)
	}
	r.hShown = shown
	return shown, true
}

// shapeWriting lays the draft out centred in the measure: one span per line (the text up to a hard break, D-088)
// in its alpha, so every visual row of one wrapped line shares one opacity and a full stop never steps the
// history. The preedit is underlined in ink.
func (r *Room) shapeWriting(text string, w float32, font ui.Font, dark bool, alphas []float32) *ui.TextLayout {
	return ui.ShapeRichTextWith(r.historySpansAt(text, dark, alphas), font, ui.TextShape{Width: w, Align: ui.Center})
}

// historySpans is the draft's spans at the history's resting steps.
func (r *Room) historySpans(text string, dark bool) []ui.Span {
	lines := session.HistoryLines(text)
	alphas := make([]float32, len(lines))
	for i, l := range lines {
		alphas[i] = max(HistoryAlpha(l.Rung, dark), 0)
	}
	return r.historySpansAt(text, dark, alphas)
}

func (r *Room) historySpansAt(text string, dark bool, alphas []float32) []ui.Span {
	ink := rc(tokens.Ink, dark)
	cuts := []int{0, len(text)}
	var markA, markZ int
	marked := false
	if m, ok := r.ed.Marked(); ok {
		markA, markZ = ui.UTF16ByteOffset(text, m.Start), ui.UTF16ByteOffset(text, m.End)
		marked = markZ > markA
		cuts = append(cuts, markA, markZ)
	}
	lines := session.HistoryLines(text)
	for _, l := range lines {
		cuts = append(cuts, l.Start, l.End)
	}
	slices.Sort(cuts)
	cuts = slices.Compact(cuts)
	var spans []ui.Span
	li := 0
	for i := 0; i+1 < len(cuts); i++ {
		a, z := cuts[i], cuts[i+1]
		for li < len(lines)-1 && lines[li].End <= a {
			li++
		}
		sp := ui.Span{Text: text[a:z]}
		if len(lines) > 0 && li < len(alphas) && alphas[li] > 0 {
			sp.Color = withAlpha(ink, alphas[li])
		}
		if marked && a >= markA && z <= markZ {
			sp.Underline, sp.DecorationColor, sp.DecorationThickness = true, ink, 1.5
		}
		spans = append(spans, sp)
	}
	if len(spans) == 0 {
		spans = []ui.Span{{Text: text}}
	}
	return spans
}

// drawWarning places the numeral and its line by their ink under the writing line (D-020).
func (r *Room) drawWarning(p *ui.Painter, pr ui.Rect, ink ui.Color, dark bool, anchor, pitch float32, font ui.Font) {
	baseline := anchor + pitch/2 // the writing line's baseline (see drawWriting)
	n := r.eng.SecondsUntilDeletion()
	size := round(min(r.winH()*0.18, 170))
	above, below := DigitInk(rune('0'+n%10), size)
	numTop := baseline + 44
	l := r.shape(textSpec{s: fmt.Sprint(n), family: serifItalic, size: size})
	w, _ := l.Size()
	p.TextLayout(l, pr.X+(pr.W-w)/2, numTop+above-r.ascent("Newsreader Italic", size), rc(tokens.PaperDanger, dark))
	capH := float32(13) * 0.70
	capTop := numTop + above + below + 20
	cap := r.shape(textSpec{s: tokens.StrWarning, family: sans, size: 13, weight: 500, spacing: 0.04, lh: 1.5})
	cw, ch := cap.Size()
	asc := r.ascent(sans, 13)
	lineTop := capTop + capH - asc - (ch-(asc+r.descent(sans, 13)))/2
	p.TextLayout(cap, pr.X+(pr.W-cw)/2, lineTop, ink)
}

func (r *Room) winH() float32 { return r.boxH }

func (r *Room) ascent(family string, size float32) float32 {
	return ui.Font{Family: family, Size: size}.Metrics().Ascent
}
func (r *Room) descent(family string, size float32) float32 {
	return ui.Font{Family: family, Size: size}.Metrics().Descent
}

// ---- stopped and kept: one geometry each, shared by the painter (text) and the view (the real pill buttons)

type stoppedGeo struct {
	f             Failure
	headline      *ui.TextLayout
	hx, hy        float32
	note          *ui.TextLayout
	nx, ny        float32
	pill          ui.Rect // window coordinates
	pillLabelSize float32
}

func (r *Room) stoppedGeo(W, H float32) stoppedGeo {
	pr := PaperRect(W, H)
	f := FailureFor(W)
	g := stoppedGeo{f: f, pillLabelSize: f.PillLabel}
	g.headline = r.shape(textSpec{s: tokens.StrStopped, family: fonts.DisplayStack, size: f.Base, weight: 500, lh: tokens.FailureHeadlineLH, width: pr.W - 96, center: true})
	_, hh := g.headline.Size()
	top, _ := f.GroupTop(pr.H, hh)
	y := pr.Y + top
	g.hx, g.hy = pr.X+48, y // the layout is as wide as its box (pr.W-96) and centres inside it
	y += hh + f.HeadlineGap
	g.note = r.shape(textSpec{s: tokens.StrDraftDeleted, family: sans, size: f.NoteSize, lh: tokens.FailureNoteLH})
	nw, nh := g.note.Size()
	g.nx, g.ny = pr.X+(pr.W-nw)/2, y+(f.NoteBox-nh)/2
	y += f.NoteBox + f.PillGap
	lw := r.labelWidth(tokens.StrBeginAgain, f.PillLabel, 600)
	pw := lw + 2*f.PillSide
	g.pill = ui.Rect{X: pr.X + (pr.W-pw)/2, Y: y, W: pw, H: f.Base}
	return g
}

func (r *Room) labelWidth(s string, size float32, weight int) float32 {
	w, _ := r.shape(textSpec{s: s, family: sans, size: size, weight: weight, spacing: 0.04, lh: 1.6}).Size()
	return w
}

func (r *Room) drawStopped(p *ui.Painter, box, pr ui.Rect, dark bool) {
	g := r.stoppedGeo(box.W, box.H)
	p.TextLayout(g.headline, g.hx, g.hy, rc(tokens.Ink, dark))
	p.TextLayout(g.note, g.nx, g.ny, rc(tokens.PaperQuiet, dark))
}

type keptGeo struct {
	heading, receipt, body *ui.TextLayout
	caption                *ui.TextLayout
	hx, hy, rx, ry, cx, cy float32
	copyRect, runRect      ui.Rect
	area                   ui.Rect
	bw, bodyH, docH        float32
}

func (r *Room) keptGeo(W, H float32) keptGeo {
	pr := PaperRect(W, H)
	e := r.eng
	var g keptGeo
	top := pr.Y + keptBlockTop
	hs := KeptHeadingSize(W)
	g.heading = r.shape(textSpec{s: tokens.StrKeptHeading, family: fonts.DisplayStack, size: hs, weight: 500, width: pr.W - 72, center: true})
	_, hh := g.heading.Size()
	g.hx, g.hy = pr.X+36, top
	y := top + hh + tokens.KeptHeadingGap
	// the receipt and the caption are 13 pt labels in the Mac's 1.6 line box, bottom-aligned: the next block starts a
	// whole box (macLabelBox) under the box's top, whatever the glyphs inside it do
	g.receipt = r.shape(textSpec{s: keptReceipt(e.WordCount, e.Duration), family: sans, size: 13, weight: 500, spacing: 0.02})
	rw, _ := g.receipt.Size()
	g.rx, g.ry = pr.X+(pr.W-rw)/2, labelBoxTop(y, 13, 500)
	y += macLabelBox(13) + tokens.KeptReceiptGap
	// the copy pill hugs its label but never narrows below the resting COPY TEXT width, so COPIED does not move the row
	// or land BEGIN AGAIN under the pointer; the longer retry label does widen it (D-076 item 7)
	copyW := max(r.labelWidth(tokens.StrCopyText, 15, 500), r.labelWidth(r.copyLabel, 15, 500)) + 48
	runW := r.labelWidth(tokens.StrKeptBeginAgain, 15, 500) + 40
	x := pr.X + (pr.W-(copyW+tokens.KeptActionSpacing+runW))/2
	g.copyRect = ui.Rect{X: x, Y: y, W: copyW, H: 48}
	g.runRect = ui.Rect{X: x + copyW + tokens.KeptActionSpacing, Y: y, W: runW, H: 48}
	y += 48 + tokens.KeptActionsGap
	// the one caption: the receipt owns the count, this line says what to do with the draft (D-074)
	g.caption = r.shape(textSpec{s: tokens.StrKeptCaption, family: sans, size: 13, weight: 500, spacing: 0.02})
	cw, _ := g.caption.Size()
	g.cx, g.cy = pr.X+(pr.W-cw)/2, labelBoxTop(y, 13, 500)
	y += macLabelBox(13) + tokens.KeptDraftGap
	// the draft under the actions: centred when short, from the top and scrollable when long
	g.area = ui.Rect{X: pr.X + 36, Y: y, W: pr.W - 72, H: pr.Y + pr.H - tokens.KeptVerticalInset - y}
	g.bw = round(min(tokens.KeptMeasure, g.area.W-48))
	g.body = r.shape(textSpec{s: orSpace(e.Text), family: fonts.Stack, size: r.cfg.FontSize, lh: tokens.LineHeight, width: g.bw, center: true})
	_, g.bodyH = g.body.Size()
	g.docH = max(g.area.H, g.bodyH+48)
	return g
}

func (r *Room) drawKept(p *ui.Painter, box, pr ui.Rect, dark bool) {
	g := r.keptGeo(box.W, box.H)
	ink, quiet := rc(tokens.Ink, dark), rc(tokens.PaperQuiet, dark)
	p.TextLayout(g.heading, g.hx, g.hy, ink)
	p.TextLayout(g.receipt, g.rx, g.ry, quiet)
	p.TextLayout(g.caption, g.cx, g.cy, quiet)
	by := max((g.docH-g.bodyH)/2, 24)
	r.keptScroll = clampf(r.keptScroll, 0, max(0, g.docH-g.area.H))
	p.Clip(g.area, 0, func() {
		p.TextLayout(g.body, g.area.X+(g.area.W-g.bw)/2, g.area.Y+by-r.keptScroll+r.leadingAbove(), ink)
	})
}

// labelTop places a pill label so its capital letters are centred in the pill: the baseline sits half a cap
// height under the pill's middle. The Mac's 5.25 pt lift is the same correction for AppKit's line box.
func labelTop(pillH, layoutH, size float32) float32 {
	m := ui.Font{Family: sans, Size: size}.Metrics()
	baselineInBox := (layoutH-(m.Ascent+m.Descent))/2 + m.Ascent
	return pillH/2 + sansCapHeight*size/2 - baselineInBox
}

// sansCapHeight is the cap height of the UI face (Segoe UI: 1434/2048).
const sansCapHeight = 0.70

func orSpace(s string) string {
	if s == "" {
		return " "
	}
	return s
}

// keptReceipt is RoomPresentation.keptReceipt: `1 MINUTE. 63 WORDS.`
func keptReceipt(words int, d time.Duration) string {
	minutes := max(int(d.Minutes()+0.5), 1)
	mu, wu := "MINUTES", "WORDS"
	if minutes == 1 {
		mu = "MINUTE"
	}
	if words == 1 {
		wu = "WORD"
	}
	return fmt.Sprintf("%d %s. %d %s.", minutes, mu, words, wu)
}
