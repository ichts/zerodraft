//go:build windows

package main

import (
	"fmt"
	"syscall"
	"unsafe"
)

// Deterministic input-method switching through ITfInputProcessorProfileMgr (Win+Space cycling cannot tell
// two Chinese IMEs apart: both report HKL 08040804).

type guid struct {
	D1 uint32
	D2 uint16
	D3 uint16
	D4 [8]byte
}

func mkguid(s string) guid {
	var g guid
	var d4 [8]uint
	fmt.Sscanf(s, "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x", &g.D1, &g.D2, &g.D3,
		&d4[0], &d4[1], &d4[2], &d4[3], &d4[4], &d4[5], &d4[6], &d4[7])
	for i := range d4 {
		g.D4[i] = byte(d4[i])
	}
	return g
}

type tip struct {
	lang        uint16
	clsid, prof guid
}

var tips = map[string]tip{
	"pinyin": {0x0804, mkguid("81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E"), mkguid("FA550B04-5AD7-411F-A5AC-CA038EC515D7")},
	"wetype": {0x0804, mkguid("86598FB9-66A2-463E-B9C2-AEB906D477AD"), mkguid("607FDF85-FCC8-4DBD-A365-41296F980C9C")},
	"ja":     {0x0411, mkguid("03B5835F-F03C-411B-9CE2-AA23E1171E36"), mkguid("A76C93D9-5523-4E90-AAFA-4DB112F9AC76")},
	"en":     {0x0409, guid{}, guid{}},
}

var (
	ole32               = syscall.NewLazyDLL("ole32.dll")
	pCoInit             = ole32.NewProc("CoInitializeEx")
	pCoCreate           = ole32.NewProc("CoCreateInstance")
	pLoadKbd            = user32.NewProc("ActivateKeyboardLayout")
	pLoadKeyboardLayout = user32.NewProc("LoadKeyboardLayoutW")
)

type tfProfile struct {
	ProfileType uint32
	Lang        uint16
	_           uint16
	Clsid       guid
	CatID       guid
	Hklsubst    uintptr
	Caps        uint32
	Hkl         uintptr
	Prof        guid
	Flags       uint32
}

func vcall(obj uintptr, idx int, args ...uintptr) uintptr {
	vt := *(*uintptr)(unsafe.Pointer(obj))
	fn := *(*uintptr)(unsafe.Pointer(vt + uintptr(idx)*unsafe.Sizeof(uintptr(0))))
	r, _, _ := syscall.SyscallN(fn, append([]uintptr{obj}, args...)...)
	return r
}

// activateTip switches the interactive session's active text service; it returns a description of the
// active keyboard profile afterwards.
func activateTip(name string) string {
	t, ok := tips[name]
	if !ok {
		return "unknown tip " + name
	}
	pCoInit.Call(0, 2)
	clsid := mkguid("33C53A50-F456-4884-B049-85FD643ECFED") // CLSID_TF_InputProcessorProfiles
	iid := mkguid("71C6E74C-0F28-11D8-A82A-00065B84435C")   // IID_ITfInputProcessorProfileMgr
	var mgr uintptr
	hr, _, _ := pCoCreate.Call(uintptr(unsafe.Pointer(&clsid)), 0, 1, uintptr(unsafe.Pointer(&iid)), uintptr(unsafe.Pointer(&mgr)))
	if hr != 0 {
		return fmt.Sprintf("CoCreateInstance hr=%#x", hr)
	}
	profType := uintptr(1)
	if name == "en" {
		profType = 2 // TF_PROFILETYPE_KEYBOARDLAYOUT
	}
	hkl := uintptr(0)
	if name == "en" {
		hkl = 0x04090409
	}
	// TF_IPPMF_FORSESSION | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE | TF_IPPMF_ENABLEPROFILE
	hr = vcall(mgr, 3, profType, uintptr(t.lang), uintptr(unsafe.Pointer(&t.clsid)), uintptr(unsafe.Pointer(&t.prof)), hkl, 0x20000000|0x4|0x1)
	if name == "en" { // a TSF keyboard-layout activation is not enough for an app that already has the IME: ask its window too
		h, _, _ := pGetForegroundWindow.Call()
		user32.NewProc("PostMessageW").Call(h, 0x50, 0, 0x04090409) // WM_INPUTLANGCHANGEREQUEST
	}
	// GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD) is vtable index 10
	cat := mkguid("34745C63-B2F0-4784-8B67-5E12C8701A31")
	var p tfProfile
	hr2 := vcall(mgr, 10, uintptr(unsafe.Pointer(&cat)), uintptr(unsafe.Pointer(&p)))
	return fmt.Sprintf("activate hr=%#x active hr=%#x lang=%#04x clsid=%08X-%04X prof=%08X hkl=%08x", hr, hr2, p.Lang, p.Clsid.D1, p.Clsid.D2, p.Prof.D1, p.Hkl)
}
