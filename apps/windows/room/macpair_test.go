package room

import (
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

// TestMacPairSnapshots renders the room states SnapshotTests.swift renders on the Mac, with the Mac fixtures' own
// draft, at the Mac window size (1040 x 720, light), under the Mac's file names, for scripts/compare_mac.py:
//
//	WID_SNAP_DIR=/tmp/win go test ./room -run MacPair
//
// It asserts nothing about pixels (that is the comparison's job); it only has to render.
func TestMacPairSnapshots(t *testing.T) {
	draft := func(g *rig) {
		g.tt.Type("cant say this out loud but")
		g.tt.Key(0, ui.KeyEnter)
		g.tt.Type("i dont want the promotion")
		g.tt.Key(0, ui.KeyEnter)
		g.tt.Type("promotion. i want time")
	}
	g := newRig(t, 1040, 720)
	g.snap("room-rest-light")

	g = newRig(t, 1040, 720)
	draft(g)
	g.tt.Advance(400 * time.Millisecond)
	g.snap("room-typing-light")
	g.tt.Key(0, ui.KeyEscape)
	g.snap("room-exit-hint-light")

	g = newRig(t, 1040, 720)
	draft(g)
	g.tt.Advance(5600 * time.Millisecond)
	g.snap("room-warning-light")

	g = newRig(t, 1040, 720)
	g.tt.Type("one sentence")
	g.tt.Advance(8100 * time.Millisecond)
	g.tt.Advance(400 * time.Millisecond)
	g.snap("room-deleted-light")

	g = newRig(t, 1040, 720)
	draft(g)
	for s := 4; s < 60; s += 4 {
		g.tt.Advance(4 * time.Second)
		g.tt.Compose("x", 1) // a preedit is activity without a word: the Mac fixture's registerMarkedTextActivity
		g.tt.Compose("", 0)
	}
	g.tt.Advance(5 * time.Second)
	g.snap("room-kept-light")
	if err := g.tt.Click("COPY TEXT"); err == nil {
		g.snap("room-copied-light")
	}
}
