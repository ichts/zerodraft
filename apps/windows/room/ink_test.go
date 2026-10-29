package room

import "testing"

func TestDigitInkIsPlausible(t *testing.T) {
	for _, d := range "0123456789" {
		a, b := DigitInk(d, 100)
		if a < 40 || a > 110 || b < 0 || b > 40 {
			t.Errorf("digit %c ink above %.1f below %.1f at 100", d, a, b)
		}
	}
	a1, _ := DigitInk('3', 100)
	a2, _ := DigitInk('3', 200)
	if d := a2 - 2*a1; d > 0.5 || d < -0.5 {
		t.Errorf("ink does not scale: %.2f vs %.2f", a1, a2)
	}
}
