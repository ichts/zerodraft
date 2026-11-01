package session

import (
	"slices"
	"strings"
	"testing"
)

func rungs(text string) []int {
	var out []int
	for _, l := range HistoryLines(text) {
		out = append(out, l.Rung)
	}
	return out
}

// The same cases as HistoryLinesTests.swift and writeitdown/session.test.mjs, so the three surfaces cannot drift.
func TestEverySentenceIsOneLineWithItsRungCountedFromTheEnd(t *testing.T) {
	text := "First is long. Second is long. Third is long. Fourth is long."
	lines := HistoryLines(text)
	var got []string
	for _, l := range lines {
		got = append(got, strings.TrimSpace(text[l.Start:l.End]))
	}
	want := []string{"First is long.", "Second is long.", "Third is long.", "Fourth is long."}
	if !slices.Equal(got, want) {
		t.Fatalf("lines %q, want %q", got, want)
	}
	if !slices.Equal(rungs(text), []int{Gone, 2, 1, 0}) {
		t.Fatalf("rungs %v", rungs(text))
	}
	if !slices.Equal(rungs("only one"), []int{0}) || len(rungs("")) != 0 {
		t.Fatalf("one line %v, empty %v", rungs("only one"), rungs(""))
	}
}

func TestAHardBreakPutsTheWriterOnAFreshLiveLine(t *testing.T) {
	if got := rungs("one\ntwo\n"); !slices.Equal(got, []int{2, 1}) {
		t.Fatalf("trailing break: %v", got)
	}
	if got := rungs("one\ntwo"); !slices.Equal(got, []int{1, 0}) {
		t.Fatalf("no trailing break: %v", got)
	}
	if got := rungs("one\r\ntwo"); !slices.Equal(got, []int{1, 0}) {
		t.Fatalf("CR LF is one break: %v", got)
	}
}

func TestCJKStopsSplitSentencesAndTheRangesCoverTheText(t *testing.T) {
	if got := rungs("今天下雨。我在写字。"); !slices.Equal(got, []int{1, 0}) {
		t.Fatalf("cjk: %v", got)
	}
	lines := HistoryLines("a. b. c")
	if lines[0].Start != 0 || lines[len(lines)-1].End != 7 {
		t.Fatalf("ranges %v", lines)
	}
}

// Rules that keep an ordinary sentence in one piece (UAX #29 SB6 to SB8a), which ICU applies on both other surfaces.
func TestSentencesThatDoNotEndAtTheirPeriod(t *testing.T) {
	for _, one := range []string{
		"Pi is 3.14 today and that is fine.",
		"We met in the U.S. last year.",
		"He said it was fine. then he left.",
		"Wait... what happened next?",
		"She paused (really.) and went on, quietly.",
	} {
		if got := len(HistoryLines(one)); got != 1 {
			t.Errorf("%q cut into %d lines", one, got)
		}
	}
	for text, n := range map[string]int{
		"Done. Next one.":                2,
		"Really? Yes! Fine.":             3,
		"He said \"stop.\" Then he ran.": 2,
		"No stop here":                   1,
	} {
		if got := len(HistoryLines(text)); got != n {
			t.Errorf("%q cut into %d lines, want %d", text, got, n)
		}
	}
}

func TestLineRangesAreContiguousAndOnRuneBoundaries(t *testing.T) {
	text := "héllo wörld. 你好。ok\nnext line… end"
	end := 0
	for _, l := range HistoryLines(text) {
		if l.Start != end || l.End <= l.Start {
			t.Fatalf("gap or empty line at %v", l)
		}
		end = l.End
	}
	if end != len(text) {
		t.Fatalf("lines end at %d of %d", end, len(text))
	}
}
