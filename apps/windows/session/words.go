package session

import "unicode"

// isCJK is a script written without spaces, so each character is one unit: Han, Hiragana, Katakana and the
// prolonged sound mark (D-095). The Mac and the web rooms use the same rule, pinned by
// tests/fixtures/word-count.json (D-099).
func isCJK(r rune) bool {
	return unicode.In(r, unicode.Han, unicode.Hiragana, unicode.Katakana) || r == '\u30FC'
}

// WordCount counts like the Mac room: each CJK character is one word, other words are runs of letters and
// digits (an apostrophe or a connecting mark inside a run stays in the word), punctuation and emoji do not
// count.
func WordCount(s string) int {
	n, in, afterCJK := 0, false, false
	rs := []rune(s)
	for i, r := range rs {
		if afterCJK && unicode.IsMark(r) {
			continue
		}
		afterCJK = false
		switch {
		case isCJK(r):
			n++
			in = false
			afterCJK = true
		case unicode.IsLetter(r) || unicode.IsDigit(r) || unicode.IsMark(r):
			if !in {
				n++
				in = true
			}
		case (r == '\'' || r == '\u2019') && in && i+1 < len(rs) && (unicode.IsLetter(rs[i+1]) || unicode.IsDigit(rs[i+1])):
			// don't, it's: one word
		case (r == ',' || r == '.') && in && i > 0 && i+1 < len(rs) && unicode.IsDigit(rs[i-1]) && unicode.IsDigit(rs[i+1]):
			// 1,000 and 3.14: one number
		default:
			in = false
		}
	}
	return n
}

// Clock formats seconds as M:SS, the room clock.
func Clock(seconds int) string {
	return itoa(seconds/60) + ":" + pad2(seconds%60)
}

func pad2(n int) string {
	if n < 10 {
		return "0" + itoa(n)
	}
	return itoa(n)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for ; n > 0; n /= 10 {
		b = append([]byte{byte('0' + n%10)}, b...)
	}
	return string(b)
}
