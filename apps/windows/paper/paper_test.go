package paper

import (
	"math"
	"testing"
)

// The locked contract (D-069/D-073): the texture over the base measures the token within a few levels.
func meanOver(s *Sheet) RGB {
	var sum RGB
	w, h := s.Texture.Rect.Dx(), s.Texture.Rect.Dy()
	for i := 0; i < len(s.Texture.Pix); i += 4 {
		k := 1 - float64(s.Texture.Pix[i+3])/255
		sum.R += float64(s.Texture.Pix[i]) + clamp(s.Base.R)*k
		sum.G += float64(s.Texture.Pix[i+1]) + clamp(s.Base.G)*k
		sum.B += float64(s.Texture.Pix[i+2]) + clamp(s.Base.B)*k
	}
	n := float64(w * h)
	return RGB{sum.R / n, sum.G / n, sum.B / n}
}

func clamp(v float64) float64 { return math.Max(0, math.Min(255, v)) }

func TestMeanIsTheLockedTone(t *testing.T) {
	for _, dark := range []bool{false, true} {
		s := Render(600, 400, 1.5, dark)
		m, want := meanOver(s), tone(dark)
		tol := 6.0
		if dark {
			tol = 10
		}
		for name, d := range map[string]float64{"r": m.R - want.R, "g": m.G - want.G, "b": m.B - want.B} {
			if math.Abs(d) > tol {
				t.Errorf("dark=%v channel %s mean off by %.1f", dark, name, d)
			}
		}
	}
}

func TestDeterministic(t *testing.T) {
	a, b := Render(200, 120, 1, false), Render(200, 120, 1, false)
	for i := range a.Texture.Pix {
		if a.Texture.Pix[i] != b.Texture.Pix[i] {
			t.Fatal("same size must give the same sheet")
		}
	}
}

func TestTextureIsNotFlat(t *testing.T) {
	s := Render(300, 300, 1, false)
	min, max := 255, 0
	for i := 3; i < len(s.Texture.Pix); i += 4 {
		v := int(s.Texture.Pix[i])
		if v < min {
			min = v
		}
		if v > max {
			max = v
		}
	}
	if max-min < 30 {
		t.Fatalf("texture alpha range %d..%d is too flat", min, max)
	}
}

func BenchmarkRender150(b *testing.B) {
	for i := 0; i < b.N; i++ {
		Render(2850, 1500, 1.5, false)
	}
}
