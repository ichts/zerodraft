// Package room is the Write It Down writing room on mygo native UI: the Windows counterpart of the Mac
// SessionViewController. State is one Room struct (the session engine plus presentation clocks); the view
// is drawn in one custom Draw so every number is ours (geometry.go), while the text input stays a real
// mygo element so Windows IMM32 composes into it.
package room

import (
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ELY-Open-Source/CrychicUI/sound"
	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/ime"
	"github.com/ichts/zerodraft/apps/windows/paper"
	"github.com/ichts/zerodraft/apps/windows/session"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// Config is what a launch can change; the zero value is the Mac default (60 s, 8 s).
type Config struct {
	Duration time.Duration
	Silence  time.Duration
	// Clock is the time source (time.Now unless a test drives it).
	Clock func() time.Time
	// Log receives one line per room event (IME suite evidence); nil disables it.
	Log func(format string, a ...any)
	// Quit leaves the room (second Esc). Defaults to mygo.App.Quit.
	Quit func()
	// SyncPaper renders the paper texture on the calling goroutine (first frame carries it, tests).
	SyncPaper bool
	// Writing font size in pt (28 is the Mac default).
	FontSize float32
	// Admit is the Mac prepareSessionInput gate for a session that has not started: it checks the licence or
	// charges one trial session before the first nonempty input is accepted. False refuses the input. Nil admits.
	Admit func(sessionID int, activity bool) bool
	// Restartable reports whether another session may start (licence or a free session left); when it says no the
	// room calls Blocked instead of restarting. Nil allows.
	Restartable func() bool
	Blocked     func()
	// Obstacle names why the next session cannot start, for the stopped sheet's spoken sentence.
	Obstacle func() Obstacle
}

// Obstacle is why the next session cannot start (Mac RoomPresentation.RestartObstacle).
type Obstacle int

const (
	ObstacleNone Obstacle = iota
	ObstacleTrialSpent
	ObstacleLicenseNeeded
)

type focusTarget int

const (
	focusCopy focusTarget = iota
	focusRun
)

// Room is the whole room state.
type Room struct {
	cfg Config
	eng *session.Engine
	ed  *ime.Editor
	ctx *ui.Context

	lastPhase   session.Phase
	lastNumeral int
	lastSize    string
	drawn       bool
	themes      map[bool]*ui.Theme
	started     bool

	// presentation clocks
	exitArmedAt time.Time
	exitHintOff time.Time
	cutUntil    time.Time
	lastWash    float32
	lastDeep    bool
	fadeStart   time.Time
	denyAt      time.Time
	denyShake0  float32
	copyLabel   string
	focus       focusTarget
	keyFocus    bool
	scrollTo    float32 // animated writing offset in rows
	scrollFrom  float32
	scrollAt    time.Time
	scrollTgt   float32
	keptScroll  float32
	hover       string // "exit" "copy" "run" "pill" or ""
	pressed     string

	// geometry published by the last frame for hit tests, relative to the element
	hit    map[string]ui.Rect
	ox, oy float32
	boxH   float32

	// layout cache
	layout    *ui.TextLayout
	layoutVer int
	layoutW   float32
	layoutKey string
	shapes    map[string]*ui.TextLayout

	// paper texture
	sheet    atomic.Pointer[sheetState]
	sheetKey atomic.Value // string: key being rendered
	sheetMu  sync.Mutex
	building bool

	// announcements queued from event callbacks
	announce []string
}

type sheetState struct {
	key    string
	bitmap *ui.Bitmap
	base   paper.RGB
	shift  paper.RGB
	w, h   int
}

// New builds a room.
func New(cfg Config) *Room {
	if cfg.Duration == 0 {
		cfg.Duration = tokens.DefaultSessionSecond * time.Second
	}
	if cfg.Silence == 0 {
		cfg.Silence = tokens.SilenceStandard * time.Second
	}
	if cfg.Clock == nil {
		cfg.Clock = time.Now
	}
	if cfg.FontSize == 0 {
		cfg.FontSize = tokens.WritingSizeMedium
	}
	if cfg.Quit == nil {
		cfg.Quit = func() { mygo.App.Quit() }
	}
	r := &Room{cfg: cfg, eng: session.New(cfg.Duration, cfg.Silence), copyLabel: tokens.StrCopyText,
		hit: map[string]ui.Rect{}, shapes: map[string]*ui.TextLayout{}}
	r.ed = r.newEditor()
	return r
}

func (r *Room) newEditor() *ime.Editor {
	return ime.New(ime.Hooks{
		Gate:     r.gate,
		OnCommit: r.onCommit,
		OnMark:   r.onMark,
		OnDeny:   r.onDeny,
		Bounds:   r.imeBounds,
		Log:      r.cfg.Log,
	})
}

func (r *Room) now() time.Time { return r.cfg.Clock() }

func (r *Room) logf(f string, a ...any) {
	if r.cfg.Log != nil {
		r.cfg.Log(f, a...)
	}
}

// Engine and Editor expose the state to tests and the IME suite.
func (r *Room) Engine() *session.Engine { return r.eng }
func (r *Room) Editor() *ime.Editor     { return r.ed }

// ---- hooks from the editor (UI thread)

// gate is Mac prepareSessionInput: input after a wipe restarts the room in place, input on the kept sheet is refused.
func (r *Room) gate(activity bool) bool {
	switch r.eng.Phase {
	case session.Success:
		return false
	case session.Failure:
		if !activity {
			return true
		}
		r.restart()
	case session.Idle:
		return false
	}
	r.eng.Tick(r.now())
	if r.eng.Phase != session.Writing && r.eng.Phase != session.Danger {
		return false
	}
	if !r.eng.HasStarted() && r.cfg.Admit != nil && !r.cfg.Admit(r.eng.ID, activity) {
		return false
	}
	return true
}

func (r *Room) onCommit() {
	r.dismissExit()
	r.eng.Committed(r.now(), r.ed.Text(), session.WordCount(r.ed.Text()))
	r.logf("STATE phase=%v text=%q words=%d marked=%v", r.eng.Phase, r.ed.Text(), r.eng.WordCount, r.ed.Composing())
	r.invalidate()
}

func (r *Room) onMark() {
	r.dismissExit()
	r.eng.MarkedActivity(r.now())
	// words count committed text only; the preedit is not yet a word
	r.logf("STATE phase=%v text=%q marked=%v", r.eng.Phase, r.ed.Text(), r.ed.Composing())
	r.invalidate()
}

func (r *Room) onDeny(why string) {
	r.denyShake0 = r.shakeOffset(r.now())
	r.denyAt = r.now()
	r.announce = append(r.announce, tokens.StrAnnounceBlocked)
	sound.Play(sound.Warning)
	r.invalidate()
}

func (r *Room) invalidate() {
	if r.ctx != nil {
		r.ctx.Invalidate()
	}
}

func (r *Room) restart() {
	if r.cfg.Restartable != nil && !r.cfg.Restartable() {
		if r.cfg.Blocked != nil {
			r.cfg.Blocked()
		}
		return
	}
	r.dismissExit()
	if r.ed.Text() != "" || r.ed.Composing() {
		if ime.Break != "keepeditor" {
			r.ed = r.newEditor()
		}
		r.layout = nil
	}
	r.eng.Start(r.cfg.Duration)
	r.cutUntil, r.lastWash = time.Time{}, 0
	r.copyLabel = tokens.StrCopyText
	r.scrollTgt, r.scrollTo = 0, 0
	r.logf("RESTART session=%d", r.eng.ID)
	r.invalidate()
}

func (r *Room) dismissExit() { r.exitArmedAt, r.exitHintOff = time.Time{}, time.Time{} }

// requestExit is the two-step exit: the first Esc or click arms the inline confirmation, a second inside the
// window leaves. Nothing is saved either way.
func (r *Room) requestExit() {
	now := r.now()
	if !r.exitArmedAt.IsZero() && now.Sub(r.exitArmedAt) <= tokens.ExitWindowSeconds*time.Second {
		r.logf("EXIT left the room")
		r.cfg.Quit()
		return
	}
	r.exitArmedAt = now
	r.exitHintOff = now.Add(tokens.ExitWindowSeconds * time.Second)
	sound.Play(sound.Open)
	r.announce = append(r.announce, tokens.StrExitHint)
	r.logf("EXIT armed")
	r.invalidate()
}

// ---- step: advances the clock and reacts to phase changes, once per frame

func (r *Room) step(now time.Time) {
	r.eng.Tick(now)
	if !r.exitHintOff.IsZero() && !now.Before(r.exitHintOff) {
		r.dismissExit()
	}
	ph := r.eng.Phase
	if ph == session.Danger {
		if n := r.eng.SecondsUntilDeletion(); n != r.lastNumeral {
			r.lastNumeral = n
			r.logf("NUMERAL %d idle=%.3f", n, r.eng.Idle.Seconds())
			sound.Play(sound.Tick)
		}
	}
	if ph == r.lastPhase {
		return
	}
	r.logf("PHASE %v -> %v idle=%.3f", r.lastPhase, ph, r.eng.Idle.Seconds())
	switch ph {
	case session.Danger:
		r.announce = append(r.announce, tokens.StrAnnounceDanger)
	case session.Failure:
		// A fresh client, not just an empty buffer: mygo resets the native IME composition when the client
		// changes, so a preedit that was open at the wipe cannot continue into the next session.
		if ime.Break != "keepeditor" {
			r.ed = r.newEditor()
		} else {
			r.ed.Clear()
		}
		r.layout = nil
		r.cutUntil = now.Add(200 * time.Millisecond)
		sound.Play(sound.Delete)
		said := fmt.Sprintf("You stopped. Draft deleted. %s unused.", session.Clock(r.eng.UnusedSeconds))
		if r.cfg.Obstacle != nil {
			switch r.cfg.Obstacle() {
			case ObstacleTrialSpent:
				said += " " + tokens.StrAnnounceTrialSpent
			case ObstacleLicenseNeeded:
				said += " " + tokens.StrAnnounceLicenseNeeded
			}
		}
		r.announce = append(r.announce, said)
	case session.Success:
		r.focus, r.keyFocus = focusCopy, false
		r.keptScroll = 0
		sound.Play(sound.Success)
		r.announce = append(r.announce, tokens.StrAnnounceKept)
	}
	r.lastPhase = ph
}

// ---- view

// View is the window content.
func (r *Room) View(c *ui.Context) {
	r.ctx = c
	now := r.now()
	r.step(now)
	for _, a := range r.announce {
		c.Announce(a)
	}
	r.announce = r.announce[:0]
	dark := c.Theme().Dark
	if r.themes[dark] == nil { // the theme is per frame in mygo: every frame sets the room's
		if r.themes == nil {
			r.themes = map[bool]*ui.Theme{}
		}
		r.themes[dark] = roomTheme(dark)
	}
	c.SetTheme(r.themes[dark])
	if r.eng.Phase != session.Writing && r.eng.Phase != session.Danger && c.Shortcut(0, ui.KeyEscape) {
		r.requestExit() // on the stopped and kept sheets a button holds the focus; Esc still asks to leave
	}
	W, H := c.Size()
	box := ui.Box(c).Fill().Background(rc(tokens.Page, dark)).Label("Writing room").Role(ui.RoleTextField).
		Value(r.ed.Text()).HandleInput(r.input).AutoFocus().KeepFocus().
		Cursor(pick(r.hover != "", ui.CursorPointer, ui.CursorDefault))
	if r.eng.Phase != session.Success {
		box = box.HandleTextInput(r.ed)
	} else {
		box = box.Focusable()
	}
	box.Draw(func(p *ui.Painter, rect ui.Rect) { r.draw(p, rect, now, dark) })
	box.Children(func() { r.pills(c, W, H, dark) })
	r.schedule(c, now)
}

// schedule asks for the next frame only when something moves.
func (r *Room) schedule(c *ui.Context, now time.Time) {
	switch {
	case r.eng.Phase == session.Failure && now.Before(r.cutUntil.Add(200*time.Millisecond)),
		!r.denyAt.IsZero() && now.Sub(r.denyAt) < 300*time.Millisecond,
		!r.scrollAt.IsZero() && now.Sub(r.scrollAt) < 250*time.Millisecond,
		!r.fadeStart.IsZero() && r.lastWash > 0:
		c.After(8 * time.Millisecond)
	case r.eng.Phase == session.Writing && r.eng.HasStarted(), r.eng.Phase == session.Danger:
		c.After(16 * time.Millisecond)
	case !r.exitHintOff.IsZero():
		c.After(50 * time.Millisecond)
	default:
		c.After(265 * time.Millisecond) // caret blink
	}
}

// input is the element's HandleInput: room keys first, then the forward-only editor.
func (r *Room) input(ev ui.InputEvent) bool {
	if ev.Kind != ui.InputPointerMove {
		r.logf("INPUT kind=%v key=%v mods=%v text=%q", ev.Kind, ev.Key, ev.Mods, ev.Text)
	}
	switch ev.Kind {
	case ui.InputKeyDown:
		if r.key(ev) {
			return true
		}
	case ui.InputPointerMove:
		r.hover = r.hitName(ev.X, ev.Y)
		return true
	case ui.InputPointerDown:
		r.pressed = r.hitName(ev.X, ev.Y)
		if r.pressed != "" {
			r.invalidate()
			return true
		}
	case ui.InputPointerUp:
		name := r.hitName(ev.X, ev.Y)
		pressed := r.pressed
		r.pressed = ""
		if name != "" && name == pressed {
			r.activate(name)
			return true
		}
		if pressed != "" {
			return true
		}
	case ui.InputScroll:
		if r.eng.Phase == session.Success {
			r.keptScroll += ev.DY
			r.invalidate()
			return true
		}
	}
	if r.eng.Phase == session.Success {
		return true
	}
	return r.ed.Input(ev)
}

func (r *Room) key(ev ui.InputEvent) bool {
	composing := r.ed.Composing()
	if ev.Key == ui.KeyEscape && !composing { // Esc is the IME's while it composes
		r.requestExit()
		return true
	}
	switch r.eng.Phase {
	case session.Failure:
		if (ev.Key == ui.KeyEnter) && !composing {
			r.activate("pill")
			return true
		}
	}
	return false
}

func (r *Room) activate(name string) {
	switch name {
	case "exit":
		r.requestExit()
	case "pill", "run":
		r.restart()
	case "copy":
		mygo.Clipboard.WriteText(r.eng.Text)
		r.eng.CopiedKept = true
		r.copyLabel = tokens.StrCopied
		r.announce = append(r.announce, "Copied.")
		r.logf("COPY %d words", r.eng.WordCount)
	}
	r.invalidate()
}

func (r *Room) hitName(x, y float32) string {
	for _, n := range []string{"exit"} {
		if rect, ok := r.hit[n]; ok && rect.Contains(x, y) {
			return n
		}
	}
	return ""
}

// imeBounds places candidate windows at the caret (or the preedit start) of the writing line.
func (r *Room) imeBounds(rg ui.TextInputRange) (ui.Rect, bool) {
	if r.layout == nil {
		return ui.Rect{}, false
	}
	cb := r.layout.Caret(rg.Start)
	x, y := r.textOrigin()
	return ui.Rect{X: x + cb.X, Y: y + cb.Y, W: max(cb.W, 1), H: cb.H}, true
}
