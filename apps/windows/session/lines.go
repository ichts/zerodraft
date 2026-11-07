package session

// The history ladder's unit is the line the writer ended with Return (D-088, superseding D-077's sentence rule): the
// text up to a hard break, never a sentence and never a visual row, so every row of one wrapped line carries one
// opacity. A full stop does not end a line. The Mac cuts the same lines in HistoryLines.swift and the web in
// writeitdown/session.mjs; the three surfaces must not drift. The cases in lines_test.go are the ones
// HistoryLinesTests.swift and session.test.mjs pin.

// Gone is the rung of every line older than the ladder: it is not drawn.
const Gone = 3

// Line is one logical line: the byte range [Start, End) of the draft and its rung (0 live, 1 and 2 the readable steps,
// Gone for everything older).
type Line struct {
	Start, End int
	Rung       int
}

// HistoryLines cuts the draft into lines. A hard break is LF, CR LF or a lone CR and belongs to the line it ends. A
// trailing hard break means the writer is already on a fresh, empty line, so every written line sits one rung further
// back.
func HistoryLines(text string) []Line {
	var lines []Line
	start := 0
	for i := 0; i < len(text); i++ {
		c := text[i]
		if c != '\n' && (c != '\r' || (i+1 < len(text) && text[i+1] == '\n')) {
			continue
		}
		lines = append(lines, Line{Start: start, End: i + 1})
		start = i + 1
	}
	if start < len(text) {
		lines = append(lines, Line{Start: start, End: len(text)})
	}
	live := len(lines) - 1
	if len(text) > 0 && text[len(text)-1] == '\n' {
		live++
	}
	for i := range lines {
		lines[i].Rung = min(live-i, Gone)
	}
	return lines
}
