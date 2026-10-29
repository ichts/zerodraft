//go:build windows

package main

import (
	"fmt"
	"unsafe"
)

// setDPI switches the primary display's scale (100, 125, 150 ...) through the same undocumented
// DisplayConfig packets Settings uses, so a capture run can be repeated at each scale. The harness records
// the starting scale and restores it.
var dpiVals = []int{100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500}

type luid struct {
	Lo uint32
	Hi int32
}

type dcHeader struct {
	Type, Size uint32
	Adapter    luid
	ID         uint32
}

type dpiGet struct {
	H             dcHeader
	Min, Cur, Max int32
}

type dpiSet struct {
	H     dcHeader
	Scale int32
}

var (
	pGetBufSizes = user32.NewProc("GetDisplayConfigBufferSizes")
	pQueryCfg    = user32.NewProc("QueryDisplayConfig")
	pDCGet       = user32.NewProc("DisplayConfigGetDeviceInfo")
	pDCSet       = user32.NewProc("DisplayConfigSetDeviceInfo")
)

func setDPI(pct int) string {
	var np, nm uint32
	if r, _, _ := pGetBufSizes.Call(2, uintptr(unsafe.Pointer(&np)), uintptr(unsafe.Pointer(&nm))); r != 0 {
		return fmt.Sprintf("GetDisplayConfigBufferSizes=%d", r)
	}
	paths := make([]byte, int(np)*72)
	modes := make([]byte, int(nm)*64)
	if r, _, _ := pQueryCfg.Call(2, uintptr(unsafe.Pointer(&np)), uintptr(unsafe.Pointer(&paths[0])), uintptr(unsafe.Pointer(&nm)), uintptr(unsafe.Pointer(&modes[0])), 0); r != 0 {
		return fmt.Sprintf("QueryDisplayConfig=%d", r)
	}
	// path 0, sourceInfo: adapterId (8) + id (4)
	ad := *(*luid)(unsafe.Pointer(&paths[0]))
	id := *(*uint32)(unsafe.Pointer(&paths[8]))
	g := dpiGet{H: dcHeader{Type: 0xFFFFFFFD, Size: uint32(unsafe.Sizeof(dpiGet{})), Adapter: ad, ID: id}}
	if r, _, _ := pDCGet.Call(uintptr(unsafe.Pointer(&g))); r != 0 {
		return fmt.Sprintf("get scale=%d", r)
	}
	rec := int(-g.Min) // steps between 100% and the recommended scale
	cur := dpiVals[rec+int(g.Cur)]
	want := -1
	for i, v := range dpiVals {
		if v == pct {
			want = i
		}
	}
	if want < 0 || want-rec < int(g.Min) || want-rec > int(g.Max) {
		return fmt.Sprintf("scale %d not available (min=%d cur=%d max=%d, now %d%%)", pct, g.Min, g.Cur, g.Max, cur)
	}
	s := dpiSet{H: dcHeader{Type: 0xFFFFFFFC, Size: uint32(unsafe.Sizeof(dpiSet{})), Adapter: ad, ID: id}, Scale: int32(want - rec)}
	r, _, _ := pDCSet.Call(uintptr(unsafe.Pointer(&s)))
	return fmt.Sprintf("was %d%%, set %d%% rel=%d result=%d", cur, pct, s.Scale, r)
}
