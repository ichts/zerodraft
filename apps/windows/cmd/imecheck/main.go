// imecheck judges one IME suite run: it reads the app log and the driver log of the same run, cuts the app
// events into the marked windows of mksuite.py and asserts the forward-only contract in each.
// usage: imecheck TIP APP_LOG DRV_LOG   (exit 1 on any failure)
package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

type ev struct {
	t      float64
	line   string
	state  bool
	phase  string
	text   string
	marked bool
}

var (
	reTime  = regexp.MustCompile(`^(\d+\.\d+) `)
	reState = regexp.MustCompile(`STATE phase=(\w+) text=("(?:[^"\\]|\\.)*") (?:words=\d+ )?marked=(true|false)`)
	reMark  = regexp.MustCompile(`^(\d+\.\d+) mark M (\w+) `)
	reBound = regexp.MustCompile(`IME BoundsForRange \{(\d+) (\d+)\} -> ([\d.]+),([\d.]+) `)
)

func readApp(path string) []ev {
	f, err := os.Open(path)
	if err != nil {
		fmt.Println("cannot read app log:", err)
		os.Exit(2)
	}
	defer f.Close()
	var out []ev
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		l := sc.Text()
		m := reTime.FindStringSubmatch(l)
		if m == nil {
			continue
		}
		t, _ := strconv.ParseFloat(m[1], 64)
		e := ev{t: t, line: l}
		if s := reState.FindStringSubmatch(l); s != nil {
			txt, _ := strconv.Unquote(s[2])
			e.state, e.phase, e.text, e.marked = true, s[1], txt, s[3] == "true"
		}
		out = append(out, e)
	}
	return out
}

type mark struct {
	id string
	t  float64
}

func readMarks(path string) []mark {
	f, err := os.Open(path)
	if err != nil {
		fmt.Println("cannot read driver log:", err)
		os.Exit(2)
	}
	defer f.Close()
	var out []mark
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if m := reMark.FindStringSubmatch(sc.Text()); m != nil {
			t, _ := strconv.ParseFloat(m[1], 64)
			out = append(out, mark{m[2], t})
		}
	}
	return out
}

type window struct {
	before string // text at the start of the window
	evs    []ev
}

func (w window) states() []ev {
	var s []ev
	for _, e := range w.evs {
		if e.state {
			s = append(s, e)
		}
	}
	return s
}
func (w window) last() (ev, bool) {
	s := w.states()
	if len(s) == 0 {
		return ev{}, false
	}
	return s[len(s)-1], true
}
func (w window) count(sub string) int {
	n := 0
	for _, e := range w.evs {
		if strings.Contains(e.line, sub) {
			n++
		}
	}
	return n
}
func (w window) composing() bool {
	for _, e := range w.states() {
		if e.marked {
			return true
		}
	}
	return false
}
func hasCJK(s string) bool {
	for _, r := range s {
		if unicode.Is(unicode.Han, r) || unicode.Is(unicode.Hiragana, r) || unicode.Is(unicode.Katakana, r) {
			return true
		}
	}
	return false
}

func main() {
	if len(os.Args) != 4 {
		fmt.Println("usage: imecheck TIP APP_LOG DRV_LOG")
		os.Exit(2)
	}
	tip := os.Args[1]
	app, marks := readApp(os.Args[2]), readMarks(os.Args[3])
	wins := map[string]window{}
	textAt := func(t float64) string {
		txt := ""
		for _, e := range app {
			if e.t > t {
				break
			}
			if e.state {
				txt = e.text
			}
		}
		return txt
	}
	for i, m := range marks {
		end := 1e18
		if i+1 < len(marks) {
			end = marks[i+1].t
		}
		w := window{before: textAt(m.t)}
		for _, e := range app {
			if e.t >= m.t && e.t < end {
				w.evs = append(w.evs, e)
			}
		}
		wins[m.id] = w
	}
	fails := 0
	// the run only counts if the requested input method was really the active text service
	{
		want := map[string]string{"pinyin": "81D4E9C9", "wetype": "86598FB9", "ja": "03B5835F"}[tip]
		data, _ := os.ReadFile(os.Args[3])
		okTip := strings.Contains(string(data), "tip "+tip+": activate hr=0x0 active hr=0x0") && strings.Contains(string(data), "clsid="+want)
		first, kana := "", tip != "ja"
		for _, e := range app {
			if e.state && e.marked {
				if first == "" {
					first = e.text
				}
				if tip == "ja" && strings.ContainsAny(e.text, "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん") {
					kana = true
					first = e.text
					break
				}
			}
		}
		if !okTip || !kana {
			fmt.Printf("FAIL [%s] ime_active              the requested IME was not the active text service (tip ok=%v first preedit %q)\n", tip, okTip, first)
			os.Exit(1)
		}
		fmt.Printf("PASS [%s] ime_active              %s is the active text service (first preedit %q)\n", tip, tip, first)
	}
	check := func(id, what string, ok bool, why string, a ...any) {
		if ok {
			fmt.Printf("PASS [%s] %-22s %s\n", tip, id, what)
		} else {
			fails++
			fmt.Printf("FAIL [%s] %-22s %s - %s\n", tip, id, what, fmt.Sprintf(why, a...))
		}
	}
	committedAt := func(id string) {
		w := wins[id]
		l, ok := w.last()
		grew := ok && len([]rune(l.text)) > len([]rune(w.before)) && strings.HasPrefix(l.text, w.before)
		check(id, "composes in place, commits at the end", w.composing() && ok && !l.marked && grew && l.phase != "failure",
			"composing=%v last=%+v before=%q", w.composing(), l, w.before)
	}
	committedAt("commit_space")
	committedAt("commit_number")
	committedAt("commit_enter")
	// preedit edit: a state exists where the preedit shrank while marked, and the commit still appended
	{
		w := wins["preedit_edit"]
		shrank, prev := false, ""
		for _, e := range w.states() {
			if e.marked && prev != "" && len(e.text) < len(prev) && strings.HasPrefix(prev, e.text[:max(0, len(e.text)-1)]) {
				shrank = true
			}
			if e.marked {
				prev = e.text
			}
		}
		l, ok := w.last()
		check("preedit_edit", "Backspace edits the preedit, commit appends", shrank && ok && !l.marked && strings.HasPrefix(l.text, w.before) && hasCJK(strings.TrimPrefix(l.text, w.before)) || (shrank && ok && !l.marked && strings.HasPrefix(l.text, w.before)),
			"shrank=%v last=%+v", shrank, l)
	}
	// wrap: candidate anchor moves to a lower row than the first one
	{
		w := wins["wrap"]
		minY, maxY := 1e9, 0.0
		for _, e := range w.evs {
			if m := reBound.FindStringSubmatch(e.line); m != nil {
				y, _ := strconv.ParseFloat(m[4], 64)
				minY, maxY = min(minY, y), max(maxY, y)
			}
		}
		l, ok := w.last()
		check("wrap", "candidate anchor follows the caret onto the wrapped row", maxY-minY >= 30 && ok && !l.marked,
			"anchor y range %.1f..%.1f", minY, maxY)
	}
	{
		w := wins["keys_while_composing"]
		l, ok := w.last()
		check("keys_while_composing", "Left/Home/Ctrl+A in the preedit do not break the append",
			w.composing() && ok && !l.marked && strings.HasPrefix(l.text, w.before) && len(l.text) > len(w.before) && w.count("DENY") == 0,
			"last=%+v denies=%d", l, w.count("DENY"))
	}
	{
		w := wins["denied_after_commit"]
		l, ok := w.last()
		same := !ok || l.text == w.before
		check("denied_after_commit", "13 edits refused, draft unchanged", w.count("DENY") >= 13 && same,
			"denies=%d unchanged=%v", w.count("DENY"), same)
	}
	{
		w := wins["click_denied"]
		l, ok := w.last()
		check("click_denied", "click refused, next input appends", w.count("DENY pointer") >= 1 && ok && strings.HasPrefix(l.text, w.before) && len(l.text) > len(w.before),
			"pointer denies=%d last=%+v", w.count("DENY pointer"), l)
	}
	{
		w := wins["wipe_during_preedit"]
		wiped := w.count("-> failure") > 0
		restarted := w.count("RESTART") > 0
		l, ok := w.last()
		// the old open preedit must not continue into the new session: only the new keys' text remains
		fresh := ok && l.phase == "writing" && len([]rune(l.text)) <= 2 && hasCJK(l.text)
		check("wipe_during_preedit", "wipe lands, the open preedit dies, next input starts a fresh session", wiped && restarted && fresh,
			"wiped=%v restarted=%v last=%+v", wiped, restarted, l)
	}
	{
		w := wins["wipe_restart"]
		wiped := w.count("-> failure") > 0
		restarted := w.count("RESTART") > 0
		l, ok := w.last()
		fresh := ok && l.phase == "writing" && len([]rune(l.text)) <= 6 && hasCJK(l.text)
		check("wipe_restart", "silence wipe, first IME key restarts with only the new text", wiped && restarted && fresh,
			"wiped=%v restarted=%v last=%+v", wiped, restarted, l)
	}
	if fails > 0 {
		fmt.Printf("%d check(s) failed for %s\n", fails, tip)
		os.Exit(1)
	}
	fmt.Printf("all checks passed for %s\n", tip)
}
