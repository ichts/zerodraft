package session

import (
	"testing"
	"time"
)

var t0 = time.Date(2026, 10, 28, 0, 0, 0, 0, time.UTC)

func at(s float64) time.Time { return t0.Add(time.Duration(s * float64(time.Second))) }

func newEngine() *Engine { return New(60*time.Second, 8*time.Second) }

// The deadline arithmetic below is SessionEngine.swift's, case by case.
func TestDeadlines(t *testing.T) {
	cases := []struct {
		name  string
		at    float64
		phase Phase
	}{
		{"4.999 s of silence is still writing", 4.999, Writing},
		{"5.000 s of silence warns", 5.000, Danger},
		{"7.999 s warns", 7.999, Danger},
		{"8.000 s wipes", 8.000, Failure},
	}
	for _, c := range cases {
		e := newEngine()
		e.Committed(at(0), "hello", 1)
		e.Tick(at(c.at))
		if e.Phase != c.phase {
			t.Errorf("%s: got %v", c.name, e.Phase)
		}
	}
}

func TestWipeClearsDraftAndReportsUnused(t *testing.T) {
	e := newEngine()
	e.Committed(at(1), "hello", 1)
	e.Tick(at(9))
	if e.Phase != Failure || e.Text != "" || e.WipedText != "hello" {
		t.Fatalf("phase %v text %q wiped %q", e.Phase, e.Text, e.WipedText)
	}
	// wipe at 9 s of a 60 s session started at 1 s: finish 61, wipe 9 -> 52 unused (the Mac's 0:52)
	if e.UnusedSeconds != 52 || e.DeletionAt != 8 {
		t.Errorf("unused %d deletionAt %d", e.UnusedSeconds, e.DeletionAt)
	}
}

func TestDeadlineKeepsADraft(t *testing.T) {
	e := newEngine()
	for s := 0.0; s < 60; s += 4 {
		e.Committed(at(s), "words words", 2)
	}
	e.Tick(at(59.999))
	if e.Phase == Success || e.Phase == Failure {
		t.Fatalf("ended early: %v", e.Phase)
	}
	e.Tick(at(60))
	if e.Phase != Success || e.Remaining != 0 {
		t.Fatalf("got %v remaining %v", e.Phase, e.Remaining)
	}
}

func TestTieGoesToTheWipe(t *testing.T) {
	// last input at 52.0, deadline 60.0 and wipe 60.0 land together: the wipe wins, the draft is deleted
	e := newEngine()
	e.Committed(at(0), "x", 1)
	for s := 4.0; s <= 48; s += 4 {
		e.Committed(at(s), "x", 1)
	}
	e.Committed(at(52), "x", 1)
	e.Tick(at(60))
	if e.Phase != Failure {
		t.Fatalf("tie must wipe, got %v", e.Phase)
	}
}

func TestBlankDraftAtDeadlineIsAWipe(t *testing.T) {
	e := newEngine()
	e.Committed(at(0), " ", 0)
	for s := 4.0; s < 60; s += 4 {
		e.MarkedActivity(at(s))
	}
	e.Tick(at(60))
	if e.Phase != Failure {
		t.Fatalf("got %v", e.Phase)
	}
}

func TestMarkedTextIsActivityAndStartsTheClock(t *testing.T) {
	e := newEngine()
	e.MarkedActivity(at(0))
	if !e.HasStarted() {
		t.Fatal("first preedit must start the clock")
	}
	e.MarkedActivity(at(6))
	e.Tick(at(7))
	if e.Phase != Writing {
		t.Fatalf("preedit update must reset silence, got %v", e.Phase)
	}
}

func TestNumeral(t *testing.T) {
	e := newEngine()
	e.Committed(at(0), "a", 1)
	for _, c := range []struct {
		at float64
		n  int
	}{{5, 3}, {5.9, 3}, {6, 2}, {7, 1}, {7.9, 1}} {
		e.Tick(at(c.at))
		if got := e.SecondsUntilDeletion(); got != c.n {
			t.Errorf("at %.1f numeral %d, want %d", c.at, got, c.n)
		}
	}
}

func TestWordCount(t *testing.T) {
	for in, want := range map[string]int{
		"": 0, "hello world": 2, "don't stop": 2, "你好世界": 4, "你好 world": 3, "one, two... three!": 3,
		"well-known": 2, "😀 😀": 0, "我们 write 代码": 5, "1,000": 1,
	} {
		if got := WordCount(in); got != want {
			t.Errorf("WordCount(%q)=%d want %d", in, got, want)
		}
	}
}
