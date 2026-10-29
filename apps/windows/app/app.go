// Package app is the product around the writing room: the home card, the rules sheet, the activation card, the
// settings card and the routing between them, the Windows counterpart of the Mac AppState surfaces. The licence
// and trial logic is the licence package's; the room is the room package's; this package decides which one the
// writer sees and calls the service from goroutines, never from the UI thread.
package app

import (
	"context"
	"slices"
	"time"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/licence"
	"github.com/ichts/zerodraft/apps/windows/room"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// Surface is what the window shows (Mac Surface; Rules is the Mac's sheet, drawn as a surface here).
type Surface int

const (
	Home Surface = iota
	Session
	Settings
	Upgrade
	Rules
)

// Env is everything that touches the platform, so the app runs headless in tests.
type Env struct {
	// OpenURL opens a URL in the default browser.
	OpenURL func(string)
	// Quit closes the window and the app.
	Quit func()
	// Post runs fn on the UI thread and draws a frame (mygo Window.Update); nil runs it inline (tests).
	Post func(fn func())
	// Go starts background work; nil is `go fn()` (tests make it synchronous).
	Go func(fn func())
	// Clock is the time source; nil is time.Now.
	Clock func() time.Time
	// Log receives one line per app event (evidence); nil disables it.
	Log func(format string, a ...any)
	// Bare opens the writing room at once with no home, trial or licence: the IME suite and the room captures (QA
	// builds only, never reachable in the release flavour).
	Bare bool
	// Version is shown in Settings > About.
	Version string
	// RoomConfig is the base room configuration (clock, log, test switches); the app adds its hooks.
	RoomConfig room.Config
}

// App is the whole product state above the room.
type App struct {
	env   Env
	lic   *licence.Manager
	prefs *Prefs

	surface Surface
	before  Surface // where Settings and Rules return to
	rm      *room.Room
	roomSeq uint64
	ctx     *ui.Context

	// the activation and settings fields
	key        string
	emptyShown bool // the "Enter your order number ... first." line of the upgrade card
	ui         uiState
}

// New builds the app and chooses the first surface like the Mac (launchInitialSurface): Home when the app can be
// used, the activation card when it cannot.
func New(lic *licence.Manager, prefs *Prefs, env Env) *App {
	if env.Clock == nil {
		env.Clock = time.Now
	}
	if env.Go == nil {
		env.Go = func(fn func()) { go fn() }
	}
	a := &App{env: env, lic: lic, prefs: prefs}
	a.ui.durIdx = max(0, slices.Index(tokens.DurationChoices, prefs.DurationSeconds))
	a.ui.silIdx = max(0, slices.Index(tokens.SilenceChoices, prefs.SilenceSeconds))
	a.surface = Home
	if !lic.CanStartSession() {
		a.surface = Upgrade
	}
	if env.Bare {
		a.Begin()
	}
	return a
}

// Surface reports the current surface (tests, evidence).
func (a *App) Surface() Surface { return a.surface }

// Room returns the live room, nil outside a session.
func (a *App) Room() *room.Room { return a.rm }

// Licence returns the manager (tests, evidence).
func (a *App) Licence() *licence.Manager { return a.lic }

func (a *App) logf(f string, args ...any) {
	if a.env.Log != nil {
		a.env.Log(f, args...)
	}
}

func (a *App) post(fn func()) {
	if a.env.Post != nil {
		a.env.Post(fn)
		return
	}
	fn()
}

func (a *App) invalidate() {
	if a.ctx != nil {
		a.ctx.Invalidate()
	}
}

// background runs work off the UI thread and then redraws on it.
func (a *App) background(work func(ctx context.Context), then func()) {
	a.env.Go(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		work(ctx)
		a.post(func() {
			if then != nil {
				then()
			}
			a.invalidate()
		})
	})
}

// ---- launch

// Start renews a stored licence behind the screen, as the Mac does at launch: access never waits for it, and a
// refund or a revoked licence is enforced as soon as the answer arrives.
func (a *App) Start() {
	a.background(func(ctx context.Context) { a.lic.Validate(ctx) }, a.afterValidation)
}

// afterValidation is the Mac validateLicenseIfNeeded epilogue: a licensed Mac on the activation card moves to
// Home; a Mac that lost access before a session started goes to the activation card.
func (a *App) afterValidation() {
	full := a.lic.HasFullAccess()
	switch {
	case full && a.surface == Upgrade && !a.lic.Snapshot().JustDone:
		a.surface = Home
	case !full && !a.roomStarted() && !a.lic.CanStartSession() && a.surface != Upgrade:
		a.rm = nil
		a.surface = Upgrade
	}
	a.logf("VALIDATED surface=%d full=%v status=%s", a.surface, full, a.lic.Snapshot().Status)
}

func (a *App) roomStarted() bool { return a.rm != nil && a.rm.Engine().HasStarted() }

// ---- navigation

// Begin starts a session: the activation card when nothing allows one, otherwise a fresh room (Mac startSession).
func (a *App) Begin() {
	if a.env.Bare {
		cfg := a.env.RoomConfig
		cfg.Quit = a.env.Quit
		a.rm, a.surface = room.New(cfg), Session
		return
	}
	if !a.lic.CanStartSession() {
		a.rm, a.surface = nil, Upgrade
		return
	}
	cfg := a.env.RoomConfig
	if cfg.Duration == 0 { // a test switch (WID_SESSION_SECONDS) wins over the picker
		cfg.Duration = time.Duration(a.prefs.DurationSeconds) * time.Second
	}
	if cfg.Silence == 0 {
		cfg.Silence = time.Duration(a.prefs.SilenceSeconds) * time.Second
	}
	cfg.Quit = a.leaveRoom
	a.roomSeq++
	seq := a.roomSeq
	// the room's own counter restarts at 1 in every room; the trial charges once per session across rooms
	cfg.Admit = func(id int, activity bool) bool { return a.admit(seq<<32|uint64(id), activity) }
	cfg.Restartable = a.lic.CanStartSession
	cfg.Blocked = func() { a.rm, a.surface = nil, Upgrade; a.invalidate() }
	cfg.Obstacle = a.obstacle
	a.rm = room.New(cfg)
	a.surface = Session
	a.logf("BEGIN duration=%d silence=%d", a.prefs.DurationSeconds, a.prefs.SilenceSeconds)
}

// admit is prepareSessionInput for a session that has not started: a licence passes, an exhausted trial goes to the
// activation card, a free session is charged before the input is accepted.
func (a *App) admit(sessionID uint64, activity bool) bool {
	defer func() {
		a.logf("ADMIT session=%d activity=%v full=%v trialLeft=%d", sessionID&0xffffffff, activity, a.lic.HasFullAccess(), a.lic.TrialRemaining())
	}()
	if a.lic.HasFullAccess() {
		return true
	}
	if !a.lic.CanStartSession() && !a.lic.CanUseApp(sessionID, false) {
		a.rm, a.surface = nil, Upgrade
		return false
	}
	if activity && !a.lic.ChargeTrial(sessionID) {
		a.rm, a.surface = nil, Upgrade
		return false
	}
	return true
}

func (a *App) obstacle() room.Obstacle {
	switch {
	case a.lic.CanStartSession():
		return room.ObstacleNone
	case a.lic.TrialSpent():
		return room.ObstacleTrialSpent
	}
	return room.ObstacleLicenseNeeded
}

// leaveRoom is Mac abandonSession: the draft is gone, Home when the app can still be used, otherwise the card.
func (a *App) leaveRoom() {
	a.rm = nil
	a.surface = Home
	if !a.lic.CanStartSession() {
		a.surface = Upgrade
	}
	a.logf("LEAVE surface=%d", a.surface)
	a.invalidate()
}

func (a *App) openSettings() {
	if a.surface == Settings || (a.surface == Session && a.roomStarted()) || !a.lic.CanStartSession() && a.surface != Upgrade {
		return
	}
	a.before, a.surface = a.surface, Settings
}

func (a *App) closeSettings() {
	a.surface = a.before
	if !a.lic.CanStartSession() {
		a.surface = Upgrade
	}
}

func (a *App) openRules()  { a.before, a.surface = a.surface, Rules }
func (a *App) closeRules() { a.surface = a.before }

// ---- actions from the cards

func (a *App) activate() {
	key := a.key
	if licence.TrimKey(key) == "" {
		a.emptyShown = true
		return
	}
	a.emptyShown = false
	a.background(func(ctx context.Context) { a.lic.Activate(ctx, key) }, func() {
		a.logf("ACTIVATED full=%v err=%v", a.lic.HasFullAccess(), a.lic.Snapshot().Err)
		if a.lic.HasFullAccess() {
			a.key = ""
		}
	})
	a.invalidate()
}

func (a *App) buy() {
	a.background(func(ctx context.Context) {
		u := a.lic.Checkout(ctx, func(u string) { a.env.OpenURL(u) })
		a.logf("CHECKOUT opened=%s", hostOf(u))
	}, nil)
	a.invalidate()
}

func (a *App) openWebTrial() { a.env.OpenURL(tokens.WebTrialURL) }

// startWriting is the licensed card's action (Mac startWritingTapped -> goHome).
func (a *App) startWriting() {
	a.lic.DismissSuccess()
	a.surface = Home
}

// setDuration and setSilence persist a changed choice (the pickers write their index every frame; only a change saves).
func (a *App) setDuration(sec int) {
	if a.prefs.DurationSeconds != sec {
		a.prefs.DurationSeconds = sec
		a.prefs.Save()
	}
}

func (a *App) setSilence(sec int) {
	if a.prefs.SilenceSeconds != sec {
		a.prefs.SilenceSeconds = sec
		a.prefs.Save()
	}
}

func hostOf(u string) string {
	for _, p := range []string{"https://", "http://"} {
		if len(u) > len(p) && u[:len(p)] == p {
			rest := u[len(p):]
			for i := 0; i < len(rest); i++ {
				if rest[i] == '/' || rest[i] == '?' {
					return rest[:i]
				}
			}
			return rest
		}
	}
	return ""
}
