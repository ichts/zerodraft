package app

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// Prefs are the writing choices the Mac keeps in its settings file (session length and silence limit). They are
// not secret and not part of the licence, so they live in a plain file; the licence and the trial counter never do.
type Prefs struct {
	DurationSeconds int `json:"defaultDuration"`
	SilenceSeconds  int `json:"silenceLimit"`
	path            string
}

// LoadPrefs reads path; a missing or damaged file gives the defaults (60 s, standard 8 s).
func LoadPrefs(path string) *Prefs {
	p := &Prefs{DurationSeconds: tokens.DefaultSessionSecond, SilenceSeconds: tokens.SilenceStandard, path: path}
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, p)
	}
	if !slices.Contains(tokens.DurationChoices, p.DurationSeconds) {
		p.DurationSeconds = tokens.DefaultSessionSecond
	}
	if !slices.Contains(tokens.SilenceChoices, p.SilenceSeconds) {
		p.SilenceSeconds = tokens.SilenceStandard
	}
	return p
}

// Save writes the file; failure is silent, as on the Mac (the choice still holds for this launch).
func (p *Prefs) Save() {
	if p.path == "" {
		return
	}
	b, _ := json.Marshal(p)
	_ = os.MkdirAll(filepath.Dir(p.path), 0o755)
	_ = os.WriteFile(p.path, b, 0o644)
}
