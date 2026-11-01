package session

import (
	"unicode"
)

// WordCount counts like the Mac room: each Han character is one word, other words are runs of letters and
// digits (an apostrophe or a connecting mark inside a run stays in the word), punctuation and emoji do not
// count. NLTokenizer is not available off Apple platforms, so this is the same rule written down (SYNC.md:
// deliberately different mechanism, same stated rule; kana runs count as one word per run).
func WordCount(s string) int {
	n, in := 0, false
	rs := []rune(s)
	for i, r := range rs {
		switch {
		case unicode.Is(unicode.Han, r):
			n++
			in = false
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
