package room

import (
	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// What the screens around the room share with it: the same colours, theme, shadow and chrome font, so a card and
// the paper lift the same way and nothing is defined twice.

// Sans is the Windows system face the Mac's system sans maps to (SYNC.md row 22).
const Sans = sans

// Theme is the After theme for mygo's controls, light or dark.
func Theme(dark bool) *ui.Theme { return roomTheme(dark) }

// Color resolves a colour role.
func Color(r tokens.Role, dark bool) ui.Color { return rc(r, dark) }

// Alpha scales a colour's alpha.
func Alpha(c ui.Color, a float32) ui.Color { return withAlpha(c, a) }

// SheetShadow is the one shadow the product has (Mac FirstLineShadowView: sheet-shadow token).
func SheetShadow(p *ui.Painter, r ui.Rect, radius float32, dark bool) {
	p.Shadow(r, radius, 0, 1, 1, 0, withAlpha(ui.RGB(0, 0, 0), pick[float32](dark, 0.25, 0.05)))
	if dark {
		p.Shadow(r, radius, 0, 28, 28, 0, withAlpha(ui.RGB(0, 0, 0), 0.60))
		return
	}
	ink := rc(tokens.Ink, false)
	p.Shadow(r, radius, 0, 12, 12, 0, withAlpha(ink, 0.12))
	p.Shadow(r, radius, 0, 36, 36, 0, withAlpha(ink, 0.20))
}
