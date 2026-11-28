package fonts

import (
	"testing"

	"golang.org/x/image/font/sfnt"
)

// Each Allo role is its own family inside the file, not only in Register's map: DirectWrite matches a face by the
// font's own name table, so three files that all said "Allo Variable" would collapse into one family (D-125).
func TestEveryAlloRoleNamesItsOwnFamily(t *testing.T) {
	var buf sfnt.Buffer
	for file, want := range map[string]string{"Allo-Text.ttf": "Allo", "Allo-Display.ttf": "Allo Display", "Allo-Numeral.ttf": Numeral} {
		f, err := sfnt.Parse(Data(file))
		if err != nil {
			t.Fatalf("%s: %v", file, err)
		}
		got, err := f.Name(&buf, sfnt.NameIDFamily)
		if err != nil || got != want {
			t.Fatalf("%s names its family %q, want %q (%v)", file, got, want, err)
		}
	}
}
