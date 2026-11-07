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
func TestTheLadderCountsLinesEndedByReturnNeverSentences(t *testing.T) {
	text := "First is long. Second is long.\nThird is long. Fourth is long.\nLive. Still live"
	lines := HistoryLines(text)
	var got []string
	for _, l := range lines {
		got = append(got, strings.TrimSpace(text[l.Start:l.End]))
	}
	want := []string{"First is long. Second is long.", "Third is long. Fourth is long.", "Live. Still live"}
	if !slices.Equal(got, want) {
		t.Fatalf("lines %q, want %q", got, want)
	}
	if !slices.Equal(rungs(text), []int{2, 1, 0}) {
		t.Fatalf("rungs %v", rungs(text))
	}
	if got := rungs("One. Two. Three."); !slices.Equal(got, []int{0}) {
		t.Fatalf("full stops never end a line: %v", got)
	}
	if !slices.Equal(rungs("only one"), []int{0}) || len(rungs("")) != 0 {
		t.Fatalf("one line %v, empty %v", rungs("only one"), rungs(""))
	}
}

func TestAHardBreakPutsTheWriterOnAFreshLiveLine(t *testing.T) {
	for text, want := range map[string][]int{
		"one\ntwo\n":    {2, 1},
		"one\ntwo":      {1, 0},
		"one\r\ntwo":    {1, 0},
		"a\r\nb\rc":     {2, 1, 0},
		"a\n\nb":        {2, 1, 0},
		"今天下雨。我在写字。":    {0},
		"今天下雨。\n我在写字。":  {1, 0},
		"a\nb\nc\nd\ne": {Gone, 3, 2, 1, 0},
	} {
		if got := rungs(text); !slices.Equal(got, want) {
			t.Errorf("%q: rungs %v, want %v", text, got, want)
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
