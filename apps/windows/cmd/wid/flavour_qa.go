//go:build widqa

package main

import (
	"encoding/json"
	"os"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// This file exists only in `-tags widqa` builds (never shipped). It points the app at a disposable local licence
// service in TEST mode and keeps its Credential Manager entries apart from the real app's.

type licenceSettings struct {
	ServiceURL, ProductID, PublicKey string
	CredentialService                string
	NoBrowser                        bool
	LogPath                          string
	SessionSeconds                   int
}

var qa = func() licenceSettings {
	s := licenceSettings{tokens.LicenseServiceURL, tokens.LicenseProductID, tokens.LicensePublicKey, "TrefoilStudio.WriteItDown.qa", false, "", 0}
	path := os.Getenv("WID_QA_CONFIG")
	if path == "" {
		path = `C:\wid\qa\config.json`
	}
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, &s)
	}
	return s
}()

func licenceConfig() licenceSettings { return qa }
func qaNoBrowser() bool              { return qa.NoBrowser }

func qaLogPath() string     { return qa.LogPath }
func qaSessionSeconds() int { return qa.SessionSeconds }

func bareMode() bool { return os.Getenv("WID_ROOM_ONLY") == "1" }
