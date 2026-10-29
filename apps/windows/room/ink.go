package room

import (
	"sync"

	"golang.org/x/image/font"
	"golang.org/x/image/font/sfnt"
	"golang.org/x/image/math/fixed"

	"github.com/ichts/zerodraft/apps/windows/fonts"
)

// Ink metrics of the numeral face. The Mac places the warning by its drawn ink, not by a line box
// (D-020), and mygo reports line boxes only, so the digits' real bounds come from the font file.
var (
	italicOnce sync.Once
	italicFont *sfnt.Font
	italicBuf  sfnt.Buffer
	inkMu      sync.Mutex
)

// DigitInk returns how far the ink of digit d reaches above the baseline at the given size (positive up)
// and below it (positive down), in DIPs.
func DigitInk(d rune, size float32) (above, below float32) {
	italicOnce.Do(func() {
		italicFont, _ = sfnt.Parse(fonts.Data("Newsreader-Italic-Variable.ttf"))
	})
	if italicFont == nil {
		return size * 0.7, 0
	}
	inkMu.Lock()
	defer inkMu.Unlock()
	idx, err := italicFont.GlyphIndex(&italicBuf, d)
	if err != nil || idx == 0 {
		return size * 0.7, 0
	}
	b, _, err := italicFont.GlyphBounds(&italicBuf, idx, fixed.I(int(size*64)), font.HintingNone)
	if err != nil {
		return size * 0.7, 0
	}
	// fixed is 26.6 at ppem=size*64 so bounds are already in 1/64 px of the requested size
	return -float32(b.Min.Y) / 64 / 64, float32(b.Max.Y) / 64 / 64
}
