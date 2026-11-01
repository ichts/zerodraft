// Package paper renders the Wheat sheet's texture: a Go port of the Mac PaperField (PaperSheetView.swift),
// which is itself the web's paper.js (same PRNG, seeds, amplitudes and pigments). It returns the texture as
// its own transparent layer plus the flat colour the layer sits on, so the warn wash can tint the base and
// leave the texture alone (D-056). Render costs a few hundred ms: call it once per size, never while typing.
package paper

import (
	"fmt"
	"image"
	"math"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

type RGB struct{ R, G, B float64 }

// Sheet is one rendered paper.
type Sheet struct {
	// Texture is premultiplied RGBA at device pixels: both mottle scales and the grain at the locked strength.
	Texture *image.RGBA
	// Base is the flat colour the texture must sit on so the finished sheet's mean equals the locked tone
	// (D-073). Shift is Base minus the tone: add it to any wash tint to keep the washed sheet's corrected mean.
	Base  RGB
	Shift RGB
}

func tone(dark bool) RGB {
	r := tokens.Paper.Light
	if dark {
		r = tokens.Paper.Dark
	}
	return RGB{float64(r >> 16 & 255), float64(r >> 8 & 255), float64(r & 255)}
}

type rng struct{ s uint32 }

func (r *rng) next() float64 {
	r.s += 0x6d2b79f5
	t := r.s
	t = (t ^ (t >> 15)) * (1 | r.s)
	t = (t + ((t ^ (t >> 7)) * (61 | t))) ^ t
	return float64(t^(t>>14)) / 4294967296.0
}

func seed(text string) uint32 {
	h := uint32(2166136261)
	for _, b := range []byte(text) {
		h = (h ^ uint32(b)) * 16777619
	}
	return h
}

func hexOf(t RGB) string { return fmt.Sprintf("#%02x%02x%02x", int(t.R), int(t.G), int(t.B)) }

func alphaOf(delta float64, t RGB) float64 {
	avg := (t.R + t.G + t.B) / 3
	room := avg
	if delta > 0 {
		room = 255 - avg
	}
	return math.Min(1, math.Abs(delta)/math.Max(10, room))
}

// noise fills a w*h premultiplied image with black/white deviations of the locked amount.
func noise(w, h int, amount float64, t RGB, r *rng) *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for i := 0; i < w*h; i++ {
		v := ((r.next() + r.next() + r.next()) - 1.5) / 1.5 * amount
		a := uint8(math.Round(alphaOf(v, t) * 255))
		c := uint8(0)
		if v >= 0 {
			c = a
		}
		img.Pix[i*4], img.Pix[i*4+1], img.Pix[i*4+2], img.Pix[i*4+3] = c, c, c, a
	}
	return img
}

// over composites premultiplied src onto dst (same size) with a global alpha.
func over(dst, src *image.RGBA, g float64) {
	for i := 0; i < len(dst.Pix); i += 4 {
		sa := float64(src.Pix[i+3]) * g
		if sa == 0 {
			continue
		}
		k := 1 - sa/255
		for c := 0; c < 3; c++ {
			dst.Pix[i+c] = uint8(math.Min(255, float64(src.Pix[i+c])*g+float64(dst.Pix[i+c])*k+0.5))
		}
		dst.Pix[i+3] = uint8(math.Min(255, sa+float64(dst.Pix[i+3])*k+0.5))
	}
}

// overScaled composites a small premultiplied image stretched to dst with bilinear smoothing.
func overScaled(dst, small *image.RGBA) {
	W, H := dst.Rect.Dx(), dst.Rect.Dy()
	sw, sh := small.Rect.Dx(), small.Rect.Dy()
	for y := 0; y < H; y++ {
		fy := (float64(y)+0.5)*float64(sh)/float64(H) - 0.5
		y0 := int(math.Floor(fy))
		ty := fy - float64(y0)
		ya, yb := clampi(y0, sh), clampi(y0+1, sh)
		for x := 0; x < W; x++ {
			fx := (float64(x)+0.5)*float64(sw)/float64(W) - 0.5
			x0 := int(math.Floor(fx))
			tx := fx - float64(x0)
			xa, xb := clampi(x0, sw), clampi(x0+1, sw)
			var s [4]float64
			for c := 0; c < 4; c++ {
				p00 := float64(small.Pix[(ya*sw+xa)*4+c])
				p10 := float64(small.Pix[(ya*sw+xb)*4+c])
				p01 := float64(small.Pix[(yb*sw+xa)*4+c])
				p11 := float64(small.Pix[(yb*sw+xb)*4+c])
				s[c] = (p00*(1-tx)+p10*tx)*(1-ty) + (p01*(1-tx)+p11*tx)*ty
			}
			if s[3] == 0 {
				continue
			}
			i := (y*W + x) * 4
			k := 1 - s[3]/255
			for c := 0; c < 3; c++ {
				dst.Pix[i+c] = uint8(math.Min(255, s[c]+float64(dst.Pix[i+c])*k+0.5))
			}
			dst.Pix[i+3] = uint8(math.Min(255, s[3]+float64(dst.Pix[i+3])*k+0.5))
		}
	}
}

func clampi(v, n int) int { return max(0, min(n-1, v)) }

// blend draws one anti-aliased coverage sample of premultiplied colour (c is 0 or 255) at alpha a.
func blend(img *image.RGBA, x, y int, c, a float64) {
	if x < 0 || y < 0 || x >= img.Rect.Dx() || y >= img.Rect.Dy() || a <= 0 {
		return
	}
	i := (y*img.Rect.Dx() + x) * 4
	k := 1 - a
	for ch := 0; ch < 3; ch++ {
		img.Pix[i+ch] = uint8(math.Min(255, c*a+float64(img.Pix[i+ch])*k+0.5))
	}
	img.Pix[i+3] = uint8(math.Min(255, 255*a+float64(img.Pix[i+3])*k+0.5))
}

func distSeg(px, py, ax, ay, bx, by float64) float64 {
	dx, dy := bx-ax, by-ay
	l := dx*dx + dy*dy
	t := 0.0
	if l > 0 {
		t = math.Max(0, math.Min(1, ((px-ax)*dx+(py-ay)*dy)/l))
	}
	return math.Hypot(px-(ax+t*dx), py-(ay+t*dy))
}

func fibres(img *image.RGBA, scale float64, t RGB, r *rng, dark bool) {
	W, H := img.Rect.Dx(), img.Rect.Dy()
	count := int(math.Round(float64(W*H) / (scale * scale) * 0.0026))
	for n := 0; n < count; n++ {
		pale := r.next() < pick(dark, 0.2, 0.44)
		spread := (12 + r.next()*34) * pick(dark, 0.32, 1) * pick(pale, 0.7, 1)
		sign := -1.0
		if pale {
			sign = 1
		}
		alpha := alphaOf(sign*spread, t) * (0.55 + r.next()*0.45)
		width := (0.5 + r.next()*0.7) * scale
		x, y := r.next()*float64(W), r.next()*float64(H)
		length := (2 + r.next()*7) * tokens.PaperSize * scale
		ang := r.next() * math.Pi * 2
		bow := (r.next() - 0.5) * 2.2 * scale
		cx := x + math.Cos(ang)*length*0.5 - math.Sin(ang)*bow
		cy := y + math.Sin(ang)*length*0.5 + math.Cos(ang)*bow
		ex, ey := x+math.Cos(ang)*length, y+math.Sin(ang)*length
		var px, py [9]float64
		for i := 0; i <= 8; i++ { // quadratic curve sampled into a polyline
			u := float64(i) / 8
			px[i] = (1-u)*(1-u)*x + 2*(1-u)*u*cx + u*u*ex
			py[i] = (1-u)*(1-u)*y + 2*(1-u)*u*cy + u*u*ey
		}
		rad := width / 2
		x0, x1 := int(math.Floor(math.Min(x, ex)-rad-2)), int(math.Ceil(math.Max(x, ex)+rad+2))
		y0, y1 := int(math.Floor(math.Min(y, ey)-rad-2)), int(math.Ceil(math.Max(y, ey)+rad+2))
		col := 0.0
		if pale {
			col = 255
		}
		for yy := y0; yy <= y1; yy++ {
			for xx := x0; xx <= x1; xx++ {
				d := math.MaxFloat64
				for i := 0; i < 8; i++ {
					d = math.Min(d, distSeg(float64(xx)+0.5, float64(yy)+0.5, px[i], py[i], px[i+1], py[i+1]))
				}
				cov := math.Max(0, math.Min(1, rad+0.5-d))
				blend(img, xx, yy, col, cov*alpha)
			}
		}
	}
}

func flecks(img *image.RGBA, scale float64, r *rng, dark bool) {
	W, H := img.Rect.Dx(), img.Rect.Dy()
	count := int(math.Round(float64(W*H) / (scale * scale) * 0.0030 * pick(dark, 0.22, 1)))
	for n := 0; n < count; n++ {
		x, y := r.next()*float64(W), r.next()*float64(H)
		pale := r.next() < 0.14
		var pig [3]float64
		switch {
		case pale:
			pig = [3]float64{255, 250, 240}
		case r.next() < 0.7:
			pig = [3]float64{36, 29, 21}
		default:
			pig = [3]float64{91, 67, 39}
		}
		var alpha float64
		if pale {
			alpha = (0.16 + r.next()*0.24) * pick(dark, 0.5, 1)
		} else {
			alpha = (0.26 + r.next()*0.46) * pick(dark, 0.5, 1)
		}
		radius := (0.4 + r.next()*1.0) * scale * math.Max(0.7, tokens.PaperSize*0.85)
		lobes := 2
		if r.next() < 0.7 {
			lobes = 1
		}
		for l := 0; l < lobes; l++ {
			ox, oy := (r.next()-0.5)*radius*1.6, (r.next()-0.5)*radius*1.6
			rx, ry := radius*(0.45+r.next()*0.7), radius*(0.28+r.next()*0.5)
			rot := r.next() * math.Pi
			cs, sn := math.Cos(rot), math.Sin(rot)
			cx, cy := x+ox, y+oy
			ext := math.Max(rx, ry) + 1
			for yy := int(cy - ext); yy <= int(cy+ext); yy++ {
				for xx := int(cx - ext); xx <= int(cx+ext); xx++ {
					dx, dy := float64(xx)+0.5-cx, float64(yy)+0.5-cy
					u, v := (dx*cs+dy*sn)/rx, (-dx*sn+dy*cs)/ry
					d := math.Sqrt(u*u + v*v) // 1 on the edge; convert to a pixel-ish ramp
					cov := math.Max(0, math.Min(1, (1-d)*math.Min(rx, ry)+0.5))
					if cov > 0 {
						blendRGB(img, xx, yy, pig, cov*alpha)
					}
				}
			}
		}
	}
}

func blendRGB(img *image.RGBA, x, y int, c [3]float64, a float64) {
	if x < 0 || y < 0 || x >= img.Rect.Dx() || y >= img.Rect.Dy() {
		return
	}
	i := (y*img.Rect.Dx() + x) * 4
	k := 1 - a
	for ch := 0; ch < 3; ch++ {
		img.Pix[i+ch] = uint8(math.Min(255, c[ch]*a+float64(img.Pix[i+ch])*k+0.5))
	}
	img.Pix[i+3] = uint8(math.Min(255, 255*a+float64(img.Pix[i+3])*k+0.5))
}

func pick[T any](c bool, a, b T) T {
	if c {
		return a
	}
	return b
}

// Render paints the sheet for a device-pixel size. scale is device pixels per DIP (1, 1.5, 2).
func Render(width, height int, scale float64, dark bool) *Sheet {
	t := tone(dark)
	tex := image.NewRGBA(image.Rect(0, 0, width, height))
	coarse := &rng{seed("coarse" + hexOf(t))}
	fine := &rng{seed("fine" + hexOf(t))}
	for i, l := range []struct {
		cell int
		amt  float64
	}{{max(2, int(math.Round(34*scale))), 9}, {max(2, int(math.Round(9*scale))), 4.5}} {
		sw, sh := max(2, (width+l.cell-1)/l.cell), max(2, (height+l.cell-1)/l.cell)
		r := coarse
		if i == 1 {
			r = fine
		}
		overScaled(tex, noise(sw, sh, l.amt, t, r))
	}
	grain := image.NewRGBA(image.Rect(0, 0, width, height))
	r := &rng{seed("tooth" + hexOf(t) + "1")}
	lift := pick(dark, 0.4, 1.0)
	over(grain, noise(width, height, tokens.PaperTooth*lift, t, r), 1)
	pc := max(2, int(math.Round(scale*0.8)))
	overScaled(grain, noise(max(2, (width+pc-1)/pc), max(2, (height+pc-1)/pc), tokens.PaperPulp*lift, t, r))
	fibres(grain, scale, t, r, dark)
	flecks(grain, scale, r, dark)
	over(tex, grain, tokens.PaperGrain)

	// The locked tone wins at the pixel: choose the base so the finished mean equals the token.
	var sum [3]float64
	var asum float64
	for i := 0; i < len(tex.Pix); i += 4 {
		sum[0] += float64(tex.Pix[i])
		sum[1] += float64(tex.Pix[i+1])
		sum[2] += float64(tex.Pix[i+2])
		asum += float64(tex.Pix[i+3])
	}
	n := float64(width * height)
	keep := 1 - asum/n/255
	base := RGB{(t.R - sum[0]/n) / keep, (t.G - sum[1]/n) / keep, (t.B - sum[2]/n) / keep}
	return &Sheet{Texture: tex, Base: base, Shift: RGB{base.R - t.R, base.G - t.G, base.B - t.B}}
}
