// papershot writes a PNG of the paper (texture over base) for eyeballing and for the evidence set.
package main

import (
	"flag"
	"image"
	"image/draw"
	"image/png"
	"os"

	"github.com/ichts/zerodraft/apps/windows/paper"
)

func main() {
	w, h := flag.Int("w", 900, "px"), flag.Int("h", 600, "px")
	scale, dark, out := flag.Float64("scale", 1.5, "dpr"), flag.Bool("dark", false, "dark"), flag.String("o", "/tmp/paper.png", "out")
	flag.Parse()
	s := paper.Render(*w, *h, *scale, *dark)
	base := image.NewRGBA(image.Rect(0, 0, *w, *h))
	cl := func(v float64) uint8 { return uint8(max(0, min(255, v+0.5))) }
	for i := 0; i < len(base.Pix); i += 4 {
		base.Pix[i], base.Pix[i+1], base.Pix[i+2], base.Pix[i+3] = cl(s.Base.R), cl(s.Base.G), cl(s.Base.B), 255
	}
	draw.Draw(base, base.Rect, s.Texture, image.Point{}, draw.Over)
	f, _ := os.Create(*out)
	png.Encode(f, base)
	f.Close()
}
