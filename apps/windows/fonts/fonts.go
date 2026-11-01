// Package fonts embeds the shared type set (the Mac app's Newsreader + Zhuque Fangsong) and registers it with mygo.
// Newsreader is the Mac's variable font pinned to the optical size the Mac draws each role at (scripts/gen_fonts.py).
package fonts

import (
	"embed"

	"github.com/egoist/mygo/ui"
)

//go:embed *.ttf
var files embed.FS

// Stack is the writing font list: Newsreader first, Zhuque Fangsong for the characters Newsreader lacks.
const Stack = "Newsreader, Zhuque Fangsong"

// DisplayStack is the heading list: the 500 weight at the display optical size (kept heading, stopped headline, rules).
const DisplayStack = "Newsreader Display, Zhuque Fangsong"

// Register adds every shipped face. Newsreader's italic registers as its own family because the
// numeral is italic and mygo picks styles inside one registered family by the font's own style bits.
func Register() error {
	for file, family := range map[string]string{
		"Newsreader-Text.ttf":        "Newsreader",
		"Newsreader-Display.ttf":     "Newsreader Display",
		"Newsreader-Numeral.ttf":     "Newsreader Italic",
		"ZhuqueFangsong-Regular.ttf": "Zhuque Fangsong",
	} {
		data, err := files.ReadFile(file)
		if err != nil {
			return err
		}
		if err := ui.RegisterFont(data, family); err != nil {
			return err
		}
	}
	return nil
}

// Data returns a shipped font file's bytes.
func Data(name string) []byte {
	b, _ := files.ReadFile(name)
	return b
}
