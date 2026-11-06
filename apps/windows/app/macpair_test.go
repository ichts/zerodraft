package app

import (
	"testing"

	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/licence"
)

// TestMacPairSnapshots renders the screens SnapshotTests.swift renders on the Mac, in the same states, at the Mac window
// size (1040 x 720, light), under the Mac's file names, for scripts/compare_mac.py --region card:
//
//	WID_SNAP_DIR=/tmp/win go test ./app -run MacPair
func TestMacPairSnapshots(t *testing.T) {
	used := func(n int, opts ...rigOpt) *rig {
		v := &licence.MemoryVault{}
		v.Set("state", licence.State{TrialSessionsUsed: n, Status: licence.Inactive}.Marshal())
		g := newRigWith(t, v, nil, opts...)
		g.tt.SetSize(1040, 720)
		g.tt.Frame()
		return g
	}
	g := used(2) // the Mac picker snapshot: two sessions used, "1 of 3 sessions left"
	g.snap("picker-light")
	g.click("How it works")
	g.snap("rules-light")

	g = used(3)
	g.snap("activation-light")
	g = used(3, rigOpt{noCheckout: true})
	g.snap("activation-unavailable-light")

	g = used(3)
	g.tt.Key(ui.Cmd, ui.KeyComma) // the Windows shortcut for the Mac's Cmd+, (the card has no Settings link)
	g.snap("settings-entry-light")

	g = used(3)
	g.a.Licence().Activate(nilCtx(), "WID-ORDER-1234")
	g.tt.Frame()
	g.snap("activation-active-light")
	g.click("Begin")
	g.click("Settings")
	g.snap("settings-light")
}
