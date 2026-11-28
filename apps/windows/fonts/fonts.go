// Package fonts embeds the shared writing faces (D-125): Allo at the Mac's weight for each role, and Resource Han
// Rounded for the same roles in Chinese, all derived from the Mac app's own files (scripts/gen_fonts.py).
package fonts

import (
	"embed"

	"github.com/egoist/mygo/ui"
)

//go:embed *.ttf
var files embed.FS

// Stack is the writing font list: Allo at 410 first, Resource Han Rounded for the characters Allo lacks.
const Stack = "Allo, Resource Han Rounded"

// DisplayStack is the heading list: Allo at 540 (kept heading, stopped headline, rules).
const DisplayStack = "Allo Display, Resource Han Rounded"

// Numeral is the warning numeral's face: Allo at 360, upright.
const Numeral = "Allo Numeral"

// Register adds every shipped face, one family per role because mygo picks a face by family.
func Register() error {
	for file, family := range map[string]string{
		"Allo-Text.ttf":          "Allo",
		"Allo-Display.ttf":       "Allo Display",
		"Allo-Numeral.ttf":       Numeral,
		"ResourceHanRounded.ttf": "Resource Han Rounded",
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
