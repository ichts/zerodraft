// wid is Write It Down for Windows on mygo native UI: the home card, the three-session trial, the writing room,
// purchase hand-off and licence activation against the existing Stripe licence service.
package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/ELY-Open-Source/CrychicUI/sound"
	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"

	"github.com/ichts/zerodraft/apps/windows/app"
	"github.com/ichts/zerodraft/apps/windows/fonts"
	"github.com/ichts/zerodraft/apps/windows/licence"
	"github.com/ichts/zerodraft/apps/windows/room"
	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// version is the Windows app's own version (the MSIX identity carries 0.2.0.0).
const version = "0.2.0"

var logMu sync.Mutex

func main() {
	if err := fonts.Register(); err != nil {
		log.Fatal(err)
	}
	// CrychicUI's sound cues are wired to the room's events and OFF by default (WID_SOUND=1 turns them on to listen).
	sound.SetEnabled(os.Getenv("WID_SOUND") == "1")
	rcfg := room.Config{}
	// Test and evidence switches; the shipped shortcut sets none of them.
	if v, _ := strconv.Atoi(os.Getenv("WID_SESSION_SECONDS")); v > 0 {
		rcfg.Duration = time.Duration(v) * time.Second
	}
	if v, _ := strconv.Atoi(os.Getenv("WID_SILENCE_SECONDS")); v > 0 {
		rcfg.Silence = time.Duration(v) * time.Second
	}
	if v := qaSessionSeconds(); v > 0 {
		rcfg.Duration = time.Duration(v) * time.Second
	}
	var logf func(string, ...any)
	logPath := os.Getenv("WID_LOG")
	if logPath == "" {
		logPath = qaLogPath() // empty in the release build
	}
	if p := logPath; p != "" {
		if f, err := os.OpenFile(p, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644); err == nil {
			start := time.Now()
			fmt.Fprintf(f, "%d.%06d MAIN\n", start.Unix(), start.Nanosecond()/1000)
			logf = func(format string, a ...any) {
				logMu.Lock()
				defer logMu.Unlock()
				n := time.Now()
				fmt.Fprintf(f, "%d.%06d +%.3f %s\n", n.Unix(), n.Nanosecond()/1000, float64(time.Since(start).Microseconds())/1000, fmt.Sprintf(format, a...))
			}
			rcfg.Log = logf
		}
	}

	cfg := licenceConfig()
	store := &licence.VaultStore{V: secretVault{mygo.Secrets.Service(cfg.CredentialService)}}
	client := licence.NewClient(cfg.ServiceURL, cfg.ProductID, cfg.PublicKey, nil)
	mgr := licence.NewManager(store, client, licence.NewCheckoutClient(cfg.ServiceURL, nil), cfg.ProductID, nil)
	prefs := app.LoadPrefs(prefsPath())

	var win *mygo.Window
	a := app.New(mgr, prefs, app.Env{
		OpenURL: func(u string) { openURL(u, logf) },
		Quit:    func() { mygo.App.Quit() },
		Post: func(fn func()) {
			if win != nil {
				win.Update(fn)
			}
		},
		Log:        logf,
		Bare:       bareMode(),
		Version:    version,
		RoomConfig: rcfg,
	})
	mygo.App.WhenReady(func() {
		win = mygo.NewWindow(mygo.WindowOptions{
			Title: "Write It Down", Width: 1040, Height: 620, MinWidth: 760, MinHeight: 480,
			Content: ui.View(a.View),
		})
		a.Start()
	})
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
	_ = tokens.DisplayPrice
}

// secretVault is the Windows Credential Manager through mygo.Secrets (a generic credential per key, encrypted for
// the user by the system), adapted to the licence package's Vault.
type secretVault struct{ s mygo.SecretsModule }

func (v secretVault) Get(key string) ([]byte, error) {
	b, err := v.s.Get(key)
	if err == mygo.ErrSecretNotFound {
		return nil, licence.ErrNotFound
	}
	return b, err
}
func (v secretVault) Set(key string, val []byte) error { return v.s.Set(key, val) }
func (v secretVault) Delete(key string) error          { return v.s.Delete(key) }

func prefsPath() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(dir, "WriteItDown", "settings.json")
}

func openURL(u string, logf func(string, ...any)) {
	if logf != nil {
		logf("OPENURL %s", u)
	}
	if qaNoBrowser() {
		return
	}
	if err := mygo.Shell.OpenExternal(u); err != nil && logf != nil {
		logf("OPENURL error %v", err)
	}
}
