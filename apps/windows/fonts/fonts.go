// Package fonts embeds the shared type set (the Mac app's Newsreader + Zhuque Fangsong) and registers it with mygo.
package fonts

import (
	"embed"

	"github.com/egoist/mygo/ui"
)

//go:embed *.ttf
var files embed.FS

// Stack is the writing font list: Newsreader first, Zhuque Fangsong for the characters Newsreader lacks.
const Stack = "Newsreader, Zhuque Fangsong"

// Register adds every shipped face. Newsreader's italic registers as its own family because the
// numeral is italic and mygo picks styles inside one registered family by the font's own style bits.
func Register() error {
	for file, family := range map[string]string{
		"Newsreader-Variable.ttf":        "Newsreader",
		"Newsreader-Italic-Variable.ttf": "Newsreader Italic",
		"ZhuqueFangsong-Regular.ttf":     "Zhuque Fangsong",
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
