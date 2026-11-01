package room

import (
	"fmt"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/fonts"
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

	r.hit = map[string]ui.Rect{}
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

	r.drawChrome(p, pr, dark, quiet, danger, ink, failure)
}

func (r *Room) drawChrome(p *ui.Painter, pr ui.Rect, dark bool, quiet, danger, ink ui.Color, failure bool) {
	e := r.eng
	// clock, top right: system sans 15 / 600, monospaced digits; off on the stopped sheet
	if !failure {
		secs := int((e.Remaining + time.Second - 1) / time.Second)
		l := r.shape(textSpec{s: session.Clock(secs), family: sans, size: 15, weight: 600})
		w, _ := l.Size()
		p.TextLayout(l, pr.X+pr.W-tokens.RoomInset-w, pr.Y+18, ink)
	}
	rowY := pr.Y + pr.H - 16 - tokens.FooterHeight/2 // the footer row's centre
	// ESC - EXIT, bottom left: 13 / 500, 0.04 em tracking, on a 1.6 line box
	ex := r.shape(textSpec{s: tokens.StrExitLink, family: sans, size: 13, weight: 500, spacing: 0.04, lh: 1.6})
	exW, exH := ex.Size()
	exX := pr.X + tokens.RoomInset
	p.TextLayout(ex, exX, rowY-exH/2, pick(r.hover == "exit", ink, quiet))
	r.hit["exit"] = ui.Rect{X: exX - 6, Y: rowY - tokens.FooterHeight/2, W: exW + 12, H: tokens.FooterHeight}
	if !r.exitHintOff.IsZero() {
		h := r.shape(textSpec{s: tokens.StrExitHint, family: sans, size: 13, weight: 500, lh: 1.6})
		_, hh := h.Size()
		p.TextLayout(h, exX+exW+12, rowY-hh/2, danger)
	}
	// count, bottom right: 13 / 400, the instruction before the first key
	label := tokens.StrTypeToStart
	if e.HasStarted() || failure {
		label = wordLabel(e.WordCount)
	}
	cl := r.shape(textSpec{s: label, family: sans, size: 13, lh: 1.6})
	cw, ch := cl.Size()
	p.TextLayout(cl, pr.X+pr.W-tokens.RoomInset-cw, rowY-ch/2, quiet)
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
	key := fmt.Sprintf("%.1f|%v", mw, r.ed.Composing())
	if r.layout == nil || r.layoutVer != ver || r.layoutKey != key {
		r.layout = r.shapeWriting(text, mw, font)
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
	oy := anchor - (row*pitch + pitch/2)
	r.ox, r.oy = x0, oy

	area := ui.Rect{X: pr.X + 32, Y: pr.Y + 72, W: pr.W - 64, H: pr.H - 144}
	p.Clip(area, 0, func() {
		for d := 0; d <= 2; d++ {
			a := HistoryAlpha(d, dark)
			rowTop := oy + (r.scrollTgt-float32(d))*pitch
			if a <= 0 || r.scrollTgt-float32(d) < 0 {
				continue
			}
			band := ui.Rect{X: area.X, Y: rowTop, W: area.W, H: pitch}
			if d == 0 {
				band.H = pitch * 3 // the current row and anything a wrap just added below it
			}
			p.Clip(band, 0, func() { p.TextLayout(r.layout, x0, oy, withAlpha(ink, a)) })
		}
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

func abs32(v float32) float32 {
	if v < 0 {
		return -v
	}
	return v
}

// shapeWriting lays the draft out centred in the measure, the preedit underlined in ink.
func (r *Room) shapeWriting(text string, w float32, font ui.Font) *ui.TextLayout {
	ink := rc(tokens.Ink, false)
	spans := []ui.Span{{Text: text}}
	if m, ok := r.ed.Marked(); ok {
		a, z := ui.UTF16ByteOffset(text, m.Start), ui.UTF16ByteOffset(text, m.End)
		spans = []ui.Span{{Text: text[:a]}, {Text: text[a:z], Underline: true, DecorationColor: ink, DecorationThickness: 1.5}, {Text: text[z:]}}
	}
	return ui.ShapeRichTextWith(spans, font, ui.TextShape{Width: w, Align: ui.Center})
}

// drawWarning places the numeral and its line by their ink under the writing line (D-020).
func (r *Room) drawWarning(p *ui.Painter, pr ui.Rect, ink ui.Color, dark bool, anchor, pitch float32, font ui.Font) {
	m := ui.Font{Family: "Newsreader", Size: font.Size}.Metrics()
	baseline := anchor - pitch/2 + (pitch-(m.Ascent+m.Descent))/2 + m.Ascent
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
	g.headline = r.shape(textSpec{s: tokens.StrStopped, family: fonts.Stack, size: f.Base, weight: 500, lh: tokens.FailureHeadlineLH, width: pr.W - 96, center: true})
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
	hx, hy, rx, ry         float32
	copyRect, runRect      ui.Rect
	area                   ui.Rect
	bw, bodyH, docH        float32
}

func (r *Room) keptGeo(W, H float32) keptGeo {
	pr := PaperRect(W, H)
	e := r.eng
	var g keptGeo
	top := pr.Y + tokens.KeptVerticalInset
	hs := KeptHeadingSize(W)
	g.heading = r.shape(textSpec{s: tokens.StrKeptHeading, family: fonts.Stack, size: hs, weight: 500, width: pr.W - 72, center: true})
	_, hh := g.heading.Size()
	g.hx, g.hy = pr.X+36, top
	y := top + hh + 12
	g.receipt = r.shape(textSpec{s: keptReceipt(e.WordCount, e.Duration), family: sans, size: 13, weight: 500, spacing: 0.02})
	rw, rh := g.receipt.Size()
	g.rx, g.ry = pr.X+(pr.W-rw)/2, y
	y += rh + 20
	// the copy pill keeps the width of its widest label (COPY TEXT / COPIED / TRY COPY AGAIN), so the label swap
	// never moves the row or lands the neighbour under the pointer (Q-24)
	copyW := max(r.labelWidth(tokens.StrCopyText, 15, 500), r.labelWidth(tokens.StrCopied, 15, 500), r.labelWidth(tokens.StrCopyRetry, 15, 500)) + 48
	runW := r.labelWidth(tokens.StrRunAgain, 15, 500) + 40
	x := pr.X + (pr.W-(copyW+24+runW))/2
	g.copyRect = ui.Rect{X: x, Y: y, W: copyW, H: 48}
	g.runRect = ui.Rect{X: x + copyW + 24, Y: y, W: runW, H: 48}
	y += 48 + 24
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
	by := max((g.docH-g.bodyH)/2, 24)
	r.keptScroll = clampf(r.keptScroll, 0, max(0, g.docH-g.area.H))
	p.Clip(g.area, 0, func() {
		p.TextLayout(g.body, g.area.X+(g.area.W-g.bw)/2, g.area.Y+by-r.keptScroll, ink)
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
