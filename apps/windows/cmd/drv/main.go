//go:build windows

// drv: a tiny scripted Windows desktop driver for the WID probe. It runs inside the interactive
// session (via a scheduled task with /IT), reads a script file, and: launches apps, injects real
// keyboard input with SendInput (so the Microsoft Pinyin IME sees it), captures the desktop
// (including the IME candidate window) to JPEG/PNG, records frame sequences, samples memory.
//
// Script lines:  shot NAME | sleep MS | type TEXT | vk NAME [mods] | launch EXE [ARGS] | killall IMAGE
//
//	frames NAME FPS  (start background capture)  | framesstop | mem NAME IMAGE... | ime zh|en|ja
//	mark TEXT (append wall clock + text to out/marks.log) | clip (print clipboard unused) | echo TEXT
package main

import (
	"bufio"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	shcore   = syscall.NewLazyDLL("shcore.dll")

	pSendInput                = user32.NewProc("SendInput")
	pGetDC                    = user32.NewProc("GetDC")
	pReleaseDC                = user32.NewProc("ReleaseDC")
	pGetSystemMetrics         = user32.NewProc("GetSystemMetrics")
	pGetForegroundWindow      = user32.NewProc("GetForegroundWindow")
	pGetWindowTextW           = user32.NewProc("GetWindowTextW")
	pGetKeyboardLayout        = user32.NewProc("GetKeyboardLayout")
	pGetWindowThreadProcessId = user32.NewProc("GetWindowThreadProcessId")
	pMapVirtualKeyW           = user32.NewProc("MapVirtualKeyW")
	pCreateCompatibleDC       = gdi32.NewProc("CreateCompatibleDC")
	pCreateDIBSection         = gdi32.NewProc("CreateDIBSection")
	pSelectObject             = gdi32.NewProc("SelectObject")
	pBitBlt                   = gdi32.NewProc("BitBlt")
	pDeleteObject             = gdi32.NewProc("DeleteObject")
	pDeleteDC                 = gdi32.NewProc("DeleteDC")
	pSetDpiAware              = shcore.NewProc("SetProcessDpiAwareness")
	pGetDpiForSystem          = user32.NewProc("GetDpiForSystem")
	pEnumWindows              = user32.NewProc("EnumWindows")
	pIsWindowVisible          = user32.NewProc("IsWindowVisible")
	pGetClassNameW            = user32.NewProc("GetClassNameW")
	pGetWindowRect            = user32.NewProc("GetWindowRect")
	pSetForegroundWindow      = user32.NewProc("SetForegroundWindow")
	pShowWindow               = user32.NewProc("ShowWindow")
	pMoveWindow               = user32.NewProc("MoveWindow")
)

var out string
var wg sync.WaitGroup

func screenSize() (int, int) {
	w, _, _ := pGetSystemMetrics.Call(0)
	h, _, _ := pGetSystemMetrics.Call(1)
	return int(w), int(h)
}

type bmi struct {
	Size          uint32
	W, H          int32
	Planes, Bits  uint16
	Comp, ImgSize uint32
	X, Y          int32
	Used, Imp     uint32
}

func capture() *image.RGBA {
	w, h := screenSize()
	sdc, _, _ := pGetDC.Call(0)
	defer pReleaseDC.Call(0, sdc)
	mdc, _, _ := pCreateCompatibleDC.Call(sdc)
	defer pDeleteDC.Call(mdc)
	hd := bmi{Size: 40, W: int32(w), H: -int32(h), Planes: 1, Bits: 32}
	var bits unsafe.Pointer
	bm, _, _ := pCreateDIBSection.Call(sdc, uintptr(unsafe.Pointer(&hd)), 0, uintptr(unsafe.Pointer(&bits)), 0, 0)
	defer pDeleteObject.Call(bm)
	old, _, _ := pSelectObject.Call(mdc, bm)
	defer pSelectObject.Call(mdc, old)
	// SRCCOPY | CAPTUREBLT so layered windows (IME candidate list) are included
	pBitBlt.Call(mdc, 0, 0, uintptr(w), uintptr(h), sdc, 0, 0, 0x00CC0020|0x40000000)
	src := unsafe.Slice((*byte)(bits), w*h*4)
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for i := 0; i < w*h; i++ {
		img.Pix[i*4] = src[i*4+2]
		img.Pix[i*4+1] = src[i*4+1]
		img.Pix[i*4+2] = src[i*4]
		img.Pix[i*4+3] = 255
	}
	return img
}

func savePNG(name string) {
	f, _ := os.Create(filepath.Join(out, name+".png"))
	png.Encode(f, capture())
	f.Close()
}

type kbdInput struct {
	Type     uint32
	_        uint32
	VK, Scan uint16
	Flags    uint32
	Time     uint32
	Extra    uintptr
	_        [8]byte
}

func sendKey(vk uint16, up bool, ext bool) {
	scan, _, _ := pMapVirtualKeyW.Call(uintptr(vk), 0)
	in := kbdInput{Type: 1, VK: vk, Scan: uint16(scan)}
	if up {
		in.Flags |= 2
	}
	if ext {
		in.Flags |= 1
	}
	pSendInput.Call(1, uintptr(unsafe.Pointer(&in)), unsafe.Sizeof(in))
}

func tap(vk uint16, mods ...uint16) {
	for _, m := range mods {
		sendKey(m, false, false)
	}
	sendKey(vk, false, false)
	time.Sleep(15 * time.Millisecond)
	sendKey(vk, true, false)
	for i := len(mods) - 1; i >= 0; i-- {
		sendKey(mods[i], true, false)
	}
}

var vkNames = map[string]uint16{
	"f4": 0x73, "space": 0x20, "enter": 0x0D, "backspace": 0x08, "esc": 0x1B, "left": 0x25, "up": 0x26, "right": 0x27,
	"down": 0x28, "delete": 0x2E, "shift": 0x10, "ctrl": 0x11, "alt": 0x12, "win": 0x5B, "tab": 0x09,
	"home": 0x24, "end": 0x23, "1": 0x31, "2": 0x32, "3": 0x33, "4": 0x34, "5": 0x35, "pgdn": 0x22, "pgup": 0x21,
	"kanji": 0x19, "imeon": 0x16, "a": 0x41, "v": 0x56, "z": 0x5A, "x": 0x58, "c": 0x43, "minus": 0xBD, "equal": 0xBB, "comma": 0xBC, "period": 0xBE,
}

func typeText(s string, gap time.Duration) {
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z':
			tap(uint16('A' + (r - 'a')))
		case r >= 'A' && r <= 'Z':
			tap(uint16(r), 0x10)
		case r >= '0' && r <= '9':
			tap(uint16(r))
		case r == ' ':
			tap(0x20)
		case r == '\'':
			tap(0xDE)
		case r == '.':
			tap(0xBE)
		case r == '-':
			tap(0xBD)
		case r == '_':
			tap(0xBD, 0x10)
		case r == ',':
			tap(0xBC)
		}
		time.Sleep(gap)
	}
}

func fgTitle() string {
	h, _, _ := pGetForegroundWindow.Call()
	b := make([]uint16, 256)
	pGetWindowTextW.Call(h, uintptr(unsafe.Pointer(&b[0])), 256)
	return syscall.UTF16ToString(b)
}

func fgLayout() string {
	h, _, _ := pGetForegroundWindow.Call()
	tid, _, _ := pGetWindowThreadProcessId.Call(h, 0)
	l, _, _ := pGetKeyboardLayout.Call(tid)
	return fmt.Sprintf("%08x", uint32(l))
}

type win struct {
	h            uintptr
	title, class string
	l, t, r, b   int32
}

func windows() []win {
	var ws []win
	cb := syscall.NewCallback(func(h uintptr, _ uintptr) uintptr {
		v, _, _ := pIsWindowVisible.Call(h)
		if v == 0 {
			return 1
		}
		tb := make([]uint16, 256)
		pGetWindowTextW.Call(h, uintptr(unsafe.Pointer(&tb[0])), 256)
		cb := make([]uint16, 256)
		pGetClassNameW.Call(h, uintptr(unsafe.Pointer(&cb[0])), 256)
		var rc [4]int32
		pGetWindowRect.Call(h, uintptr(unsafe.Pointer(&rc)))
		ws = append(ws, win{h, syscall.UTF16ToString(tb), syscall.UTF16ToString(cb), rc[0], rc[1], rc[2], rc[3]})
		return 1
	})
	pEnumWindows.Call(cb, 0)
	return ws
}

func logf(format string, a ...any) {
	line := fmt.Sprintf("%d.%06d ", time.Now().Unix(), time.Now().Nanosecond()/1000) + fmt.Sprintf(format, a...)
	fmt.Println(line)
	f, _ := os.OpenFile(filepath.Join(out, "drv.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	f.WriteString(line + "\n")
	f.Close()
}

var stopFrames chan struct{}

func startFrames(name string, fps int) {
	dir := filepath.Join(out, name)
	os.MkdirAll(dir, 0755)
	stopFrames = make(chan struct{})
	wg.Add(1)
	go func() {
		defer wg.Done()
		t := time.NewTicker(time.Second / time.Duration(fps))
		defer t.Stop()
		n := 0
		start := time.Now()
		for {
			select {
			case <-stopFrames:
				logf("frames %s count=%d dur=%s", name, n, time.Since(start))
				return
			case <-t.C:
				f, _ := os.Create(filepath.Join(dir, fmt.Sprintf("%06d_%d.jpg", n, time.Now().UnixMilli())))
				jpeg.Encode(f, capture(), &jpeg.Options{Quality: 85})
				f.Close()
				n++
			}
		}
	}()
}

func init() { runtime.LockOSThread() } // COM (TSF profile switching) lives on one thread

func main() {
	pSetDpiAware.Call(2)
	out = os.Args[2]
	os.MkdirAll(out, 0755)
	f, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	w, h := screenSize()
	dpi, _, _ := pGetDpiForSystem.Call()
	logf("start screen=%dx%d dpi=%d fg=%q layout=%s", w, h, dpi, fgTitle(), fgLayout())
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		line := strings.TrimRight(sc.Text(), "\r")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		cmd, arg, _ := strings.Cut(line, " ")
		switch cmd {
		case "shot":
			savePNG(arg)
			logf("shot %s fg=%q layout=%s", arg, fgTitle(), fgLayout())
		case "sleep":
			ms, _ := strconv.Atoi(arg)
			time.Sleep(time.Duration(ms) * time.Millisecond)
		case "type":
			typeText(arg, 90*time.Millisecond)
			logf("typed %q", arg)
		case "typefast":
			typeText(arg, 20*time.Millisecond)
			logf("typed %q", arg)
		case "vk":
			parts := strings.Fields(arg)
			var mods []uint16
			for _, m := range parts[1:] {
				mods = append(mods, vkNames[m])
			}
			vk, ok := vkNames[parts[0]]
			if !ok {
				vk = uint16(strings.ToUpper(parts[0])[0])
			}
			tap(vk, mods...)
			logf("vk %s", arg)
		case "launch":
			parts := strings.SplitN(arg, " ", 2)
			c := exec.Command(parts[0])
			if len(parts) > 1 {
				c.SysProcAttr = &syscall.SysProcAttr{CmdLine: `"` + parts[0] + `" ` + parts[1]}
			}
			c.Env = os.Environ()
			t0 := time.Now()
			if err := c.Start(); err != nil {
				logf("launch ERROR %v", err)
			}
			logf("launch %s pid=%d t0=%d.%06d", arg, c.Process.Pid, t0.Unix(), t0.Nanosecond()/1000)
			go c.Wait()
		case "shotwin": // shotwin NAME TITLE... : the window's rectangle only (DPI-aware physical pixels)
			name, title, _ := strings.Cut(arg, " ")
			for _, w := range windows() {
				if strings.HasPrefix(w.title, title) {
					saveCrop(name, w.l, w.t, w.r, w.b)
					logf("shotwin %s rect=%d,%d,%d,%d", name, w.l, w.t, w.r, w.b)
					break
				}
			}
		case "dpi":
			pct, _ := strconv.Atoi(arg)
			logf("dpi %d: %s", pct, setDPI(pct))
			time.Sleep(2500 * time.Millisecond)
		case "waitwin": // waitwin TITLE... : logs how long after this command the window became visible
			t0 := time.Now()
			ok := false
			for time.Since(t0) < 15*time.Second && !ok {
				for _, w := range windows() {
					if strings.HasPrefix(w.title, arg) {
						ok = true
					}
				}
				time.Sleep(10 * time.Millisecond)
			}
			logf("waitwin %q visible=%v after %d ms", arg, ok, time.Since(t0).Milliseconds())
		case "wins":
			for _, w := range windows() {
				if w.title != "" {
					logf("win %q class=%s rect=%d,%d,%d,%d", w.title, w.class, w.l, w.t, w.r, w.b)
				}
			}
		case "focus":
			for _, w := range windows() {
				if strings.HasPrefix(w.title, arg) {
					pShowWindow.Call(w.h, 9)
					pSetForegroundWindow.Call(w.h)
					logf("focus %q rect=%d,%d,%d,%d", w.title, w.l, w.t, w.r, w.b)
					break
				}
			}
		case "move":
			p := strings.Fields(arg) // title... x y w h
			title := strings.Join(p[:len(p)-4], " ")
			p = p[len(p)-4:]
			for _, w := range windows() {
				if strings.HasPrefix(w.title, title) {
					x, _ := strconv.Atoi(p[0])
					y, _ := strconv.Atoi(p[1])
					ww, _ := strconv.Atoi(p[2])
					hh, _ := strconv.Atoi(p[3])
					pMoveWindow.Call(w.h, uintptr(x), uintptr(y), uintptr(ww), uintptr(hh), 1)
					logf("move %q", w.title)
					break
				}
			}
		case "clickwin": // clickwin TITLE... dipX dipY : a real mouse click at DIP coordinates in the window's client area
			p := strings.Fields(arg)
			title := strings.Join(p[:len(p)-2], " ")
			dx, _ := strconv.ParseFloat(p[len(p)-2], 64)
			dy, _ := strconv.ParseFloat(p[len(p)-1], 64)
			for _, w := range windows() {
				if strings.HasPrefix(w.title, title) {
					dpiW, _, _ := user32.NewProc("GetDpiForWindow").Call(w.h)
					sc := float64(dpiW) / 96
					var pt [2]int32
					user32.NewProc("ClientToScreen").Call(w.h, uintptr(unsafe.Pointer(&pt)))
					x, y := int(float64(pt[0])+dx*sc), int(float64(pt[1])+dy*sc)
					user32.NewProc("SetCursorPos").Call(uintptr(x), uintptr(y))
					time.Sleep(150 * time.Millisecond)
					mouse := user32.NewProc("mouse_event")
					mouse.Call(0x2, 0, 0, 0, 0)
					time.Sleep(60 * time.Millisecond)
					mouse.Call(0x4, 0, 0, 0, 0)
					logf("clickwin %q dip=%.1f,%.1f screen=%d,%d scale=%.2f", w.title, dx, dy, x, y, sc)
					break
				}
			}
		case "http": // http METHOD URL : a control request (the QA server, through the reverse tunnel); logs the status and body
			m, u, _ := strings.Cut(arg, " ")
			req, _ := http.NewRequest(m, u, nil)
			resp, err := (&http.Client{Timeout: 20 * time.Second}).Do(req)
			if err != nil {
				logf("http %s %s ERROR %v", m, u, err)
				break
			}
			b, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			logf("http %s %s -> %d %s", m, u, resp.StatusCode, strings.TrimSpace(string(b)))
		case "typehttp": // typehttp URL : GET the URL and type the response body with real keystrokes (a key pasted from a page)
			resp, err := (&http.Client{Timeout: 20 * time.Second}).Get(arg)
			if err != nil {
				logf("typehttp %s ERROR %v", arg, err)
				break
			}
			b, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			typeText(strings.TrimSpace(string(b)), 20*time.Millisecond)
			logf("typehttp %s -> typed %d characters", arg, len(strings.TrimSpace(string(b))))
		case "run": // run CMD ARGS... : run a program and log its output (cmdkey, powershell)
			c := exec.Command("cmd", "/c", arg)
			o, err := c.CombinedOutput()
			logf("run %s -> %v %s", arg, err, strings.TrimSpace(string(o)))
		case "killall":
			exec.Command("taskkill", "/F", "/T", "/IM", arg).Run()
			logf("killall %s", arg)
		case "frames":
			p := strings.Fields(arg)
			fps, _ := strconv.Atoi(p[1])
			startFrames(p[0], fps)
		case "framesstop":
			close(stopFrames)
			wg.Wait()
		case "mem":
			p := strings.Fields(arg)
			logf("mem %s %s", p[0], memTree(p[1]))
		case "click":
			p := strings.Fields(arg)
			x, _ := strconv.Atoi(p[0])
			y, _ := strconv.Atoi(p[1])
			user32.NewProc("SetCursorPos").Call(uintptr(x), uintptr(y))
			time.Sleep(100 * time.Millisecond)
			mouse := user32.NewProc("mouse_event")
			mouse.Call(0x2, 0, 0, 0, 0)
			time.Sleep(50 * time.Millisecond)
			mouse.Call(0x4, 0, 0, 0, 0)
			logf("click %d %d", x, y)
		case "layout":
			want := map[string]string{"zh": "08040804", "ja": "04110411", "en": "04090409"}[arg]
			for i := 0; i < 8 && fgLayout() != want; i++ {
				tap(0x20, 0x5B)
				time.Sleep(800 * time.Millisecond)
			}
			logf("layout %s -> %s", arg, fgLayout())
		case "tip":
			logf("tip %s: %s fg=%q layout=%s", arg, activateTip(arg), fgTitle(), fgLayout())
			time.Sleep(700 * time.Millisecond)
		case "setenv":
			k, v, _ := strings.Cut(arg, "=")
			os.Setenv(k, v)
		case "mark", "echo":
			logf("%s %s", cmd, arg)
		case "ime":
			// switch input language using the same path as Win+Space: set via the language bar hotkey
			// target layouts: zh=0x0804, ja=0x0411, en=0x0409 -- handled by script using 'vk space win'
			logf("ime %s: layout switching is done with vk (win+space)", arg)
		default:
			logf("unknown %q", line)
		}
	}
	logf("done")
}

var (
	pCreateSnap  = kernel32.NewProc("CreateToolhelp32Snapshot")
	pProc32First = kernel32.NewProc("Process32FirstW")
	pProc32Next  = kernel32.NewProc("Process32NextW")
	pOpenProcess = kernel32.NewProc("OpenProcess")
	pCloseHandle = kernel32.NewProc("CloseHandle")
	pGetPMI      = syscall.NewLazyDLL("psapi.dll").NewProc("GetProcessMemoryInfo")
)

type procEntry struct {
	Size, Usage, PID uint32
	_                uintptr
	_, Threads, PPID uint32
	_                int32
	Flags            uint32
	Exe              [260]uint16
}

type pmc struct {
	CB, PageFaults                                     uint32
	Peak, WS, QPP, QNPP, PF, PeakPF, Pagefile, Private uintptr
}

// memTree sums working set and private bytes of every process named root (without .exe) and its descendants.
func memTree(root string) string {
	snap, _, _ := pCreateSnap.Call(2, 0)
	defer pCloseHandle.Call(snap)
	type pr struct {
		pid, ppid uint32
		name      string
	}
	var all []pr
	e := procEntry{Size: uint32(unsafe.Sizeof(procEntry{}))}
	r, _, _ := pProc32First.Call(snap, uintptr(unsafe.Pointer(&e)))
	for r != 0 {
		all = append(all, pr{e.PID, e.PPID, syscall.UTF16ToString(e.Exe[:])})
		r, _, _ = pProc32Next.Call(snap, uintptr(unsafe.Pointer(&e)))
	}
	in := map[uint32]bool{}
	for _, a := range all {
		if strings.EqualFold(a.name, root+".exe") {
			in[a.pid] = true
		}
	}
	for changed := true; changed; {
		changed = false
		for _, a := range all {
			if !in[a.pid] && in[a.ppid] {
				in[a.pid] = true
				changed = true
			}
		}
	}
	var ws, priv uintptr
	var names []string
	for _, a := range all {
		if !in[a.pid] {
			continue
		}
		h, _, _ := pOpenProcess.Call(0x1000|0x0010, 0, uintptr(a.pid))
		if h == 0 {
			continue
		}
		var m pmc
		m.CB = uint32(unsafe.Sizeof(m))
		pGetPMI.Call(h, uintptr(unsafe.Pointer(&m)), uintptr(m.CB))
		pCloseHandle.Call(h)
		ws += m.WS
		priv += m.Private
		names = append(names, fmt.Sprintf("%s:%d:%d", a.name, m.WS, m.Private))
	}
	return fmt.Sprintf("count=%d ws=%d private=%d names=%s", len(names), ws, priv, strings.Join(names, ","))
}

func saveCrop(name string, l, t, r, b int32) {
	img := capture()
	rc := image.Rect(int(l), int(t), int(r), int(b)).Intersect(img.Rect)
	f, _ := os.Create(filepath.Join(out, name+".png"))
	png.Encode(f, img.SubImage(rc))
	f.Close()
}
