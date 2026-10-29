// Package session is the pure session clock of the writing room: a port of the Mac SessionEngine.
// It holds no UI and reads no clock of its own; the caller passes the time, so tests drive it exactly.
package session

import (
	"strings"
	"time"
)

type Phase int

const (
	Idle Phase = iota
	Writing
	Danger
	Failure
	Success
)

func (p Phase) String() string {
	return [...]string{"idle", "writing", "danger", "failure", "success"}[p]
}

// Engine mirrors SessionEngine.swift: the first input starts the clock, the deadline and the wipe race as
// absolute deadlines, and a tie goes to the wipe.
type Engine struct {
	Phase         Phase
	Text          string
	WordCount     int
	Duration      time.Duration
	Silence       time.Duration
	Elapsed       time.Duration
	Remaining     time.Duration
	Idle          time.Duration
	WipedText     string
	UnusedSeconds int
	DeletionAt    int // whole seconds into the session at which the draft was deleted
	CopiedKept    bool
	ID            int
	started       bool
	startedAt     time.Time
	lastActivity  time.Time
}

func New(duration, silence time.Duration) *Engine {
	e := &Engine{Duration: duration, Silence: silence}
	e.Start(duration)
	return e
}

func (e *Engine) HasStarted() bool { return e.started }

// StartedAt is when the first input started the clock.
func (e *Engine) StartedAt() time.Time { return e.startedAt }

// Start begins a fresh, unstarted session (SessionEngine.start).
func (e *Engine) Start(d time.Duration) {
	e.ID++
	e.Duration, e.Remaining = d, d
	e.Elapsed, e.Idle = 0, 0
	e.WipedText, e.UnusedSeconds, e.DeletionAt, e.CopiedKept = "", 0, 0, false
	e.Text, e.WordCount = "", 0
	e.started = false
	e.Phase = Writing
}

// SecondsUntilDeletion is the warning numeral: ceil(silence - idle), never below zero.
func (e *Engine) SecondsUntilDeletion() int {
	r := e.Silence - e.Idle
	if r < 0 {
		return 0
	}
	return int((r + time.Second - 1) / time.Second)
}

// Tick advances the clock to now.
func (e *Engine) Tick(now time.Time) {
	if e.adjudicate(now) {
		return
	}
	if !e.started || (e.Phase != Writing && e.Phase != Danger) {
		return
	}
	e.Elapsed = clamp(now.Sub(e.startedAt), 0, e.Duration)
	e.Remaining = max(e.Duration-e.Elapsed, 0)
	e.Idle = max(now.Sub(e.lastActivity), 0)
	if e.Idle >= e.Silence-time.Duration(3)*time.Second {
		e.Phase = Danger
	} else {
		e.Phase = Writing
	}
}

// Committed registers text that really entered the draft (appended, or replacing the preedit range).
// replace is a rune range [from,to) of the previous text, or nil for an append.
func (e *Engine) Committed(now time.Time, text string, wordCount int) {
	if e.Phase != Writing && e.Phase != Danger || e.adjudicate(now) {
		return
	}
	if !e.started {
		e.started, e.startedAt = true, now
	}
	e.Text, e.WordCount = text, wordCount
	e.lastActivity, e.Idle = now, 0
	e.Phase = Writing
	e.Tick(now)
}

// MarkedActivity registers a preedit update: composition counts as activity but adds no words.
func (e *Engine) MarkedActivity(now time.Time) {
	if e.Phase != Writing && e.Phase != Danger || e.adjudicate(now) {
		return
	}
	if !e.started {
		e.started, e.startedAt = true, now
	}
	e.lastActivity, e.Idle = now, 0
	e.Phase = Writing
	e.Tick(now)
}

// SetText updates the draft text and its word count without counting as activity (preedit commits that the
// caller already registered). It exists so the editor stays the single owner of the text.
func (e *Engine) SetText(text string, wordCount int) { e.Text, e.WordCount = text, wordCount }

func (e *Engine) adjudicate(now time.Time) bool {
	if !e.started || (e.Phase != Writing && e.Phase != Danger) {
		return false
	}
	finish := e.startedAt.Add(e.Duration)
	wipe := e.lastActivity.Add(e.Silence)
	wipePassed, finishPassed := !now.Before(wipe), !now.Before(finish)
	if !wipePassed && !finishPassed {
		return false
	}
	empty := strings.TrimSpace(e.Text) == ""
	if wipePassed && (!finishPassed || !wipe.After(finish)) || finishPassed && empty {
		unused := finish.Sub(wipe)
		e.UnusedSeconds = max(0, int((unused+time.Second-1)/time.Second))
		cut := finish
		if wipePassed {
			cut = wipe
		}
		del := min(e.Duration, cut.Sub(e.startedAt))
		e.DeletionAt = max(0, int(del/time.Second))
		e.WipedText, e.Text, e.WordCount = e.Text, "", 0
		e.Phase = Failure
	} else {
		e.Elapsed, e.Remaining = e.Duration, 0
		e.Phase = Success
	}
	return true
}

// Abandon returns to the idle state (leaving the room).
func (e *Engine) Abandon() {
	e.Phase = Idle
	e.Elapsed, e.Remaining, e.Idle = 0, e.Duration, 0
	e.WipedText, e.UnusedSeconds, e.DeletionAt, e.CopiedKept = "", 0, 0, false
	e.Text, e.WordCount, e.started = "", 0, false
}

func clamp(d, lo, hi time.Duration) time.Duration { return min(max(d, lo), hi) }
