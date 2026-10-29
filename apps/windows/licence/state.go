package licence

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// Status is the Mac LicenseStatus; an unknown value decodes as inactive.
type Status string

const (
	Inactive Status = "inactive"
	Active   Status = "active"
	Invalid  Status = "invalid"
	Revoked  Status = "revoked"
	Unknown  Status = "unknown"
)

// State is everything the licence layer persists (Mac AppSettings, licence and trial fields only). The draft is
// never part of it. The names follow the Mac's persisted keys.
type State struct {
	TrialSessionsUsed int       `json:"trialSessionsUsed"`
	LicenseKey        string    `json:"licenseKey,omitempty"` // the order number, the historical name
	Status            Status    `json:"licenseStatus"`
	ActivatedAt       time.Time `json:"licenseActivatedAt,omitempty"`
	LastValidatedAt   time.Time `json:"licenseLastValidatedAt,omitempty"`
	InstanceID        string    `json:"licenseInstanceID,omitempty"`
	ProductID         string    `json:"licenseProductID,omitempty"`
	Token             string    `json:"licenseToken,omitempty"`
	// TrialUnreadable marks a counter that could not be read or was malformed: the trial budget is exhausted,
	// a separately stored licence stays eligible (Mac SettingsStore).
	TrialUnreadable bool `json:"-"`
}

// TrimKey trims only leading and trailing ASCII SPACE, TAB, CR and LF (Mac AppSettings.trimmedLicenseKey):
// a key pasted from an email carries that noise; NBSP and everything inside stay byte for byte.
func TrimKey(k string) string { return strings.Trim(k, " \t\r\n") }

func (s State) hasKey() bool { return TrimKey(s.LicenseKey) != "" }

// Marshal encodes the state; Parse decodes it with the Mac's tolerance for a malformed counter.
func (s State) Marshal() []byte {
	s.TrialSessionsUsed = min(tokens.TrialSessionLimit, max(0, s.TrialSessionsUsed))
	b, _ := json.Marshal(s)
	return b
}

// ParseState decodes a stored state. A counter outside 0..limit exhausts the trial budget only.
func ParseState(b []byte) (State, error) {
	var raw struct {
		State
		Trial json.RawMessage `json:"trialSessionsUsed"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		return State{}, err
	}
	s := raw.State
	s.TrialSessionsUsed = 0
	if len(raw.Trial) > 0 {
		var n int
		if json.Unmarshal(raw.Trial, &n) != nil || n < 0 || n > tokens.TrialSessionLimit {
			n = tokens.TrialSessionLimit
			s.TrialUnreadable = true
		}
		s.TrialSessionsUsed = n
	}
	switch s.Status {
	case Inactive, Active, Invalid, Revoked, Unknown:
	default:
		s.Status = Inactive
	}
	return s, nil
}

// Vault is the system credential store (the Windows Credential Manager through mygo.Secrets).
type Vault interface {
	Get(key string) ([]byte, error)
	Set(key string, value []byte) error
	Delete(key string) error
}

// ErrNotFound is what a Vault's Get returns when nothing is stored.
var ErrNotFound = errors.New("licence: not stored")

// Store persists the State and the install identity.
type Store interface {
	// Load returns the stored state; a store with nothing in it returns the zero State (fresh install).
	Load() (State, error)
	Save(State) error
	// InstallID is the stable random install UUID, the device binding of the licence (never a hardware id).
	InstallID() string
}

const (
	keyState   = "state"
	keyInstall = "install-id"
)

// VaultStore keeps state and install id as two secrets in a Vault: nothing about the licence touches a plain file.
type VaultStore struct {
	V  Vault
	id string
}

// Load reads the state secret.
func (s *VaultStore) Load() (State, error) {
	b, err := s.V.Get(keyState)
	if errors.Is(err, ErrNotFound) {
		return State{}, nil
	}
	if err != nil {
		return State{}, err
	}
	return ParseState(b)
}

// Save replaces the state secret.
func (s *VaultStore) Save(st State) error { return s.V.Set(keyState, st.Marshal()) }

// InstallID returns the saved id, or makes and saves a new random UUID; a failing store falls back to a
// memory-only id so the app still starts (Mac InstallIDStore).
func (s *VaultStore) InstallID() string {
	if s.id != "" {
		return s.id
	}
	if b, err := s.V.Get(keyInstall); err == nil && len(b) > 0 {
		s.id = string(b)
		return s.id
	}
	s.id = NewUUID()
	_ = s.V.Set(keyInstall, []byte(s.id))
	return s.id
}

// NewUUID is a random RFC 4122 version 4 UUID in canonical lower-case form (a full UUID, as the Mac sends).
func NewUUID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// MemoryVault is an in-memory Vault for tests and non-Windows runs.
type MemoryVault struct{ M map[string][]byte }

func (m *MemoryVault) Get(k string) ([]byte, error) {
	if v, ok := m.M[k]; ok {
		return v, nil
	}
	return nil, ErrNotFound
}
func (m *MemoryVault) Set(k string, v []byte) error {
	if m.M == nil {
		m.M = map[string][]byte{}
	}
	m.M[k] = append([]byte(nil), v...)
	return nil
}
func (m *MemoryVault) Delete(k string) error { delete(m.M, k); return nil }
