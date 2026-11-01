package session

import "unicode"

// The history ladder's unit is the logical line (D-077): a sentence, or the text up to a hard line break, never a
// visual row, so every row of one sentence carries one opacity. The Mac cuts the lines with NSString `.bySentences` and
// the web with `Intl.Segmenter`, both ICU's UAX #29 sentence boundaries; Go has no such segmenter in its standard
// library, so sentenceEnd below implements the rules that matter for prose (SB3 to SB11) over Unicode's general
// categories. The cases in lines_test.go are the ones HistoryLinesTests.swift and writeitdown/session.test.mjs pin.

// Gone is the rung of every line older than the ladder: it is not drawn.
const Gone = 3

// Line is one logical line: the byte range [Start, End) of the draft and its rung (0 live, 1 and 2 the readable steps,
// Gone for everything older).
type Line struct {
	Start, End int
	Rung       int
}

// HistoryLines cuts the draft into logical lines. A trailing hard break means the writer is already on a fresh, empty
// line, so every written line sits one rung further back.
func HistoryLines(text string) []Line {
	rs := []rune(text)
	var cuts []int // byte offsets where a line ends
	offs := make([]int, len(rs)+1)
	for i, r := range rs {
		offs[i+1] = offs[i] + len(string(r))
	}
	for i := 0; i < len(rs); {
		i = sentenceEnd(rs, i)
		cuts = append(cuts, offs[i])
	}
	live := len(cuts) - 1
	if len(text) > 0 && text[len(text)-1] == '\n' {
		live++
	}
	lines := make([]Line, len(cuts))
	start := 0
	for i, end := range cuts {
		lines[i] = Line{Start: start, End: end, Rung: min(live-i, Gone)}
		start = end
	}
	return lines
}

func isSep(r rune) bool { return r == '\n' || r == '\r' || r == 0x85 || r == 0x2028 || r == 0x2029 }

func isSpace(r rune) bool { return !isSep(r) && unicode.IsSpace(r) }

func isATerm(r rune) bool { return r == '.' || r == 0x2024 || r == 0xFE52 || r == 0xFF0E }

func isSTerm(r rune) bool {
	switch r {
	case '!', '?', 0x0589, 0x061F, 0x06D4, 0x0964, 0x0965, 0x203C, 0x203D, 0x2047, 0x2048, 0x2049, 0x3002, 0xFE56,
		0xFE57, 0xFF01, 0xFF1F, 0xFF61:
		return true
	}
	return false
}

func isSATerm(r rune) bool { return isATerm(r) || isSTerm(r) }

func isClose(r rune) bool {
	return unicode.In(r, unicode.Ps, unicode.Pe, unicode.Pi, unicode.Pf) || r == '"' || r == '\'' ||
		r == 0xFF02 || r == 0xFF07
}

func isSContinue(r rune) bool {
	switch r {
	case ',', '-', ':', ';', 0x055D, 0x060C, 0x060D, 0x07F8, 0x1802, 0x1808, 0x2013, 0x2014, 0x3001, 0xFE10, 0xFE11,
		0xFE13, 0xFE31, 0xFE32, 0xFE50, 0xFE51, 0xFE55, 0xFE58, 0xFE63, 0xFF0C, 0xFF0D, 0xFF1A, 0xFF1B, 0xFF64:
		return true
	}
	return false
}

// isExtend is a combining mark or a format character: it never starts a boundary (SB5).
func isExtend(r rune) bool {
	return unicode.In(r, unicode.Mn, unicode.Me, unicode.Mc, unicode.Cf) && r != 0x200B
}

func isOLetter(r rune) bool { return unicode.IsLetter(r) && !unicode.IsLower(r) && !unicode.IsUpper(r) }

// skipExtend steps over Extend and Format characters at i.
func skipExtend(rs []rune, i int) int {
	for i < len(rs) && isExtend(rs[i]) {
		i++
	}
	return i
}

// sentenceEnd returns the end of the sentence that starts at from.
func sentenceEnd(rs []rune, from int) int {
	for i := from; i < len(rs); i++ {
		r := rs[i]
		switch {
		case isSep(r): // SB3 keeps CR LF together; SB4 breaks after a paragraph separator
			if r == '\r' && i+1 < len(rs) && rs[i+1] == '\n' {
				return i + 2
			}
			return i + 1
		case isSATerm(r):
			if end, ok := terminatorEnd(rs, i); ok {
				return end
			}
		}
	}
	return len(rs)
}

// terminatorEnd decides whether the sentence terminator at i ends the sentence and where (SB6 to SB11).
func terminatorEnd(rs []rune, i int) (int, bool) {
	aterm := isATerm(rs[i])
	j := skipExtend(rs, i+1)
	if aterm && j < len(rs) && unicode.IsDigit(rs[j]) { // SB6: 3.14
		return 0, false
	}
	if aterm && j < len(rs) && unicode.IsUpper(rs[j]) && i > 0 && (unicode.IsUpper(rs[i-1]) || unicode.IsLower(rs[i-1])) {
		return 0, false // SB7: U.S.
	}
	for j < len(rs) && (isClose(rs[j]) || isExtend(rs[j])) {
		j++
	}
	k := j
	for k < len(rs) && (isSpace(rs[k]) || isExtend(rs[k])) {
		k++
	}
	if k < len(rs) && (isSContinue(rs[k]) || isSATerm(rs[k])) && !isSep(rs[k]) { // SB8a
		return 0, false
	}
	if aterm { // SB8: a lowercase letter continues the sentence past any run of non-letters
		for m := k; m < len(rs); m++ {
			r := rs[m]
			if unicode.IsLower(r) {
				return 0, false
			}
			if isOLetter(r) || unicode.IsUpper(r) || isSep(r) || isSATerm(r) {
				break
			}
		}
	}
	if k < len(rs) && isSep(rs[k]) { // SB9, SB11: the paragraph separator belongs to the sentence
		if rs[k] == '\r' && k+1 < len(rs) && rs[k+1] == '\n' {
			return k + 2, true
		}
		return k + 1, true
	}
	return k, true
}
