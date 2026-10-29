package licence

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// Grace is the offline grace: a network failure never extends a signed token's seven days (Mac
// licenseOfflineGraceInterval).
const Grace = time.Duration(tokens.LicenseOfflineGraceSeconds) * time.Second

// Outcome is the Mac's `Bool?` of validateLicenseIfNeeded.
type Outcome int

const (
	Undecided Outcome = iota // nil: nothing to validate, or a transport failure
	Valid                    // true
	Rejected                 // false: revoked or invalid
)

// Manager is the licence half of the Mac AppState: entitlement, the three-session trial, activation, renewal,
// revocation and rollback. It is safe for concurrent use; network calls run without the lock held and the revision
// counters (as the Mac's) drop results that a newer activation or validation has overtaken.
type Manager struct {
	mu       sync.Mutex
	store    Store
	client   *Client
	checkout *CheckoutClient
	clock    func() time.Time
	product  string
	label    string

	st               State
	trialAccessError string
	activationErr    *ActivationError
	validating       bool
	activating       bool
	checkingOut      bool
	justActivated    bool
	actRev, valRev   int
	charged          uint64 // session id already charged to the trial (0: none)
	accessCache      accessCache
}

type accessCache struct {
	at   int64
	ok   bool
	have bool
}

// NewManager loads the stored state. A store that cannot be read exhausts the trial with a visible error rather
// than silently granting another session (Mac AppState.init).
func NewManager(store Store, client *Client, checkout *CheckoutClient, productID string, clock func() time.Time) *Manager {
	if clock == nil {
		clock = time.Now
	}
	m := &Manager{store: store, client: client, checkout: checkout, clock: clock, product: productID, label: store.InstallID()}
	st, err := store.Load()
	if err != nil {
		st = State{TrialSessionsUsed: tokens.TrialSessionLimit}
		m.trialAccessError = tokens.TrialReadError
	} else if st.TrialUnreadable {
		st.TrialSessionsUsed = tokens.TrialSessionLimit
	}
	if st.Status == "" {
		st.Status = Inactive
	}
	m.st = st
	m.validating = (st.Status == Active || st.Status == Unknown) && st.hasKey() && st.InstanceID != ""
	return m
}

// InstallLabel is the full install UUID sent as `installLabel`.
func (m *Manager) InstallLabel() string { return m.label }

// ---- reads

// trialBudgetApplies: the clean local trial still governs access (no licence residue, no access error).
func (m *Manager) trialBudgetApplies() bool {
	s := m.st
	return m.trialAccessError == "" && (m.activationErr == nil || m.activationErr.Kind != KindCleanupFailure) &&
		s.Status == Inactive && !s.hasKey() && s.Token == "" && s.InstanceID == "" && s.ProductID == "" &&
		s.ActivatedAt.IsZero() && s.LastValidatedAt.IsZero()
}

// TrialRemaining is the free sessions left; zero whenever any licence record exists.
func (m *Manager) TrialRemaining() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.trialRemaining()
}

func (m *Manager) trialRemaining() int {
	if !m.trialBudgetApplies() {
		return 0
	}
	return max(0, tokens.TrialSessionLimit-m.st.TrialSessionsUsed)
}

// TrialSpent is true only when the free sessions themselves are spent, so the stopped sheet can name the real
// reason a restart is blocked (D-070).
func (m *Manager) TrialSpent() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.trialBudgetApplies() && m.st.TrialSessionsUsed >= tokens.TrialSessionLimit
}

// HasFullAccess is a licence verified locally; a revalidation in flight never withholds it.
func (m *Manager) HasFullAccess() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.hasFullAccess()
}

func (m *Manager) hasFullAccess() bool {
	s := m.st
	if s.Status != Active || !s.hasKey() || s.InstanceID == "" || m.product == "" || !m.client.Configured() || s.ProductID != m.product {
		return false
	}
	now := m.clock()
	if m.accessCache.have && m.accessCache.at == now.Unix() {
		return m.accessCache.ok
	}
	ok := m.withinGrace(now)
	m.accessCache = accessCache{at: now.Unix(), ok: ok, have: true}
	return ok
}

func (m *Manager) withinGrace(now time.Time) bool {
	s := m.st
	if s.Token == "" || s.InstanceID == "" {
		return false
	}
	last := s.LastValidatedAt
	if last.IsZero() {
		last = s.ActivatedAt
	}
	if last.IsZero() {
		return false
	}
	age := now.Sub(last)
	return age >= -60*time.Second && age < Grace && m.client.PermitsAccess(s.Token, s.InstanceID, m.label, now)
}

// CanStartSession: a licence, or a free session left.
func (m *Manager) CanStartSession() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.hasFullAccess() || m.trialRemaining() > 0
}

// CanUseApp is CanStartSession, or a session that was already charged and has started.
func (m *Manager) CanUseApp(sessionID uint64, started bool) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.hasFullAccess() || m.trialRemaining() > 0 || (m.charged == sessionID && sessionID != 0 && started)
}

// TrialAccessError is the visible reason the trial counter could not be read or saved ("" when none).
func (m *Manager) TrialAccessError() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.trialAccessError
}

// AccessStatusText is the line the home card shows (Mac accessStatusText).
func (m *Manager) AccessStatusText() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.accessStatusText()
}

func (m *Manager) accessStatusText() string {
	if m.hasFullAccess() {
		return m.licenseStatusText()
	}
	if m.trialAccessError != "" {
		return m.trialAccessError
	}
	if n := m.trialRemaining(); n > 0 {
		return fmt.Sprintf(tokens.TrialLeftFormat, n, tokens.TrialSessionLimit)
	}
	return m.licenseStatusText()
}

// LicenseStatusText is the Mac licenseStatusText.
func (m *Manager) LicenseStatusText() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.licenseStatusText()
}

func (m *Manager) licenseStatusText() string {
	s := m.st
	if m.validating {
		return tokens.StatusChecking
	}
	if s.LicenseKey != "" && s.InstanceID == "" {
		return tokens.StatusNotActivated
	}
	if s.Status == Active && !m.hasFullAccessLocked() {
		if s.LicenseKey != "" && m.product != "" && s.ProductID == m.product && !m.withinGrace(m.clock()) {
			return tokens.StatusNeedsValidation
		}
		return tokens.StatusWrongProduct
	}
	switch s.Status {
	case Active:
		return tokens.StatusActive
	case Revoked:
		return tokens.StatusRevoked
	case Invalid:
		return tokens.StatusInvalid
	case Unknown:
		return tokens.StatusUnknown
	}
	return tokens.StatusInactive
}

// hasFullAccessLocked is hasFullAccess without the cache (status text is rare).
func (m *Manager) hasFullAccessLocked() bool {
	m.accessCache.have = false
	return m.hasFullAccess()
}

// Snapshot is the licence view the screens render.
type Snapshot struct {
	Full        bool
	Status      Status
	Validating  bool
	Activating  bool
	CheckingOut bool
	JustDone    bool
	Err         *ActivationError
	StatusText  string
	AccessText  string
	TrialError  string
	ActivatedAt time.Time
	ValidatedAt time.Time
	CheckoutOK  bool
}

// Snapshot reads everything a screen needs at once.
func (m *Manager) Snapshot() Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	return Snapshot{Full: m.hasFullAccess(), Status: m.st.Status, Validating: m.validating, Activating: m.activating,
		CheckingOut: m.checkingOut, JustDone: m.justActivated, Err: m.activationErr,
		StatusText: m.licenseStatusText(), AccessText: m.accessStatusText(), TrialError: m.trialAccessError,
		ActivatedAt: m.st.ActivatedAt, ValidatedAt: m.st.LastValidatedAt,
		CheckoutOK: m.checkout.Configured() && tokens.CheckoutFallbackURL != ""}
}

// ---- trial

// ChargeTrial spends one free session for sessionID before the first nonempty input is accepted (Mac
// chargeTrialSession). A session is charged once; a failed write refuses the input with a visible error. A
// licensed install never spends. It is called on every first input and must be idempotent for one session.
func (m *Manager) ChargeTrial(sessionID uint64) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.hasFullAccess() || m.charged == sessionID {
		return true
	}
	if m.trialRemaining() <= 0 {
		return false
	}
	prev := m.st
	m.st.TrialSessionsUsed++
	if err := m.store.Save(m.st); err != nil {
		m.st = prev
		m.trialAccessError = tokens.TrialSaveError
		return false
	}
	m.charged = sessionID
	return true
}

// ---- activation, validation

// ClearActivationError forgets the last activation error unless it is the cleanup failure the writer must see.
func (m *Manager) ClearActivationError() {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.activationErr == nil || m.activationErr.Kind != KindCleanupFailure {
		m.activationErr = nil
	}
}

// DismissSuccess clears the just-activated feedback.
func (m *Manager) DismissSuccess() {
	m.mu.Lock()
	m.justActivated = false
	m.mu.Unlock()
}

// SetEmptyKeyError is the "Enter your order number..." state for an empty submission.
func (m *Manager) SetEmptyKeyError() {
	m.mu.Lock()
	m.activationErr = actErr(KindEmptyKey)
	m.mu.Unlock()
}

// Activate is the Mac activateLicense: trim, skip a re-activation of the key already held by renewing it, call the
// service, check product and signature, persist, and on a failed write undo only the new allocation.
func (m *Manager) Activate(ctx context.Context, key string) {
	m.mu.Lock()
	if m.activating {
		m.mu.Unlock()
		return
	}
	licenseKey := TrimKey(key)
	if licenseKey == "" {
		m.activationErr = actErr(KindEmptyKey)
		m.mu.Unlock()
		return
	}
	m.activating, m.activationErr, m.justActivated = true, nil, false
	defer func() { m.mu.Lock(); m.activating = false; m.mu.Unlock() }()
	if m.product == "" || !m.client.Configured() {
		m.activationErr = actErr(KindProductNotConfigured)
		m.mu.Unlock()
		return
	}
	held := m.st.LicenseKey == licenseKey && m.st.InstanceID != "" && m.st.Token != "" && m.st.ProductID == m.product
	m.mu.Unlock()
	if held {
		switch m.validate(ctx, true) {
		case Valid:
			return
		case Undecided:
			m.setActErr(actErr(KindNetworkFailure))
			return
		case Rejected:
			m.mu.Lock()
			m.st.InstanceID = ""
			m.persistLocked()
			m.mu.Unlock()
		}
	}
	act, err := m.client.Activate(ctx, licenseKey, m.label)
	if err != nil {
		var ae *ActivationError
		if errors.As(err, &ae) {
			m.setActErr(ae)
		} else {
			m.setActErr(&ActivationError{Kind: KindUnexpected, Status: -1})
		}
		return
	}
	if act.ProductID != m.product {
		m.rejectActivation(ctx, act, KindWrongProduct)
		return
	}
	if !m.client.PermitsAccess(act.Token, act.InstanceID, m.label, m.clock()) {
		m.setActErr(actErr(KindInvalidToken))
		return
	}
	m.mu.Lock()
	pre, now := m.st, m.clock()
	m.st.LicenseKey, m.st.Status, m.st.InstanceID, m.st.ProductID, m.st.Token = licenseKey, Active, act.InstanceID, m.product, act.Token
	m.st.ActivatedAt, m.st.LastValidatedAt = now, now
	m.accessCache.have = false
	if err := m.store.Save(m.st); err != nil {
		m.st = pre
		m.mu.Unlock()
		m.rejectActivation(ctx, act, KindStorageFailure)
		return
	}
	m.actRev++
	m.validating, m.justActivated = false, true
	m.mu.Unlock()
}

func (m *Manager) setActErr(e *ActivationError) { m.mu.Lock(); m.activationErr = e; m.mu.Unlock() }

// rejectActivation releases only the new allocation: never the instance the app already holds.
func (m *Manager) rejectActivation(ctx context.Context, act Activation, reason ActivationKind) {
	m.mu.Lock()
	same := act.InstanceID == m.st.InstanceID
	m.mu.Unlock()
	if same {
		m.setActErr(actErr(reason))
		return
	}
	if err := m.client.Deactivate(ctx, act.Token); err != nil {
		m.setActErr(actErr(KindCleanupFailure))
		return
	}
	m.setActErr(actErr(reason))
}

// Validate renews the stored token when there is one (Mac validateLicenseIfNeeded).
func (m *Manager) Validate(ctx context.Context) Outcome { return m.validate(ctx, false) }

func (m *Manager) validate(ctx context.Context, allowInactive bool) Outcome {
	m.mu.Lock()
	s := m.st
	eligible := s.Status == Active || s.Status == Unknown || (allowInactive && (s.Status == Revoked || s.Status == Invalid))
	if !eligible || !s.hasKey() || s.InstanceID == "" {
		m.mu.Unlock()
		return Undecided
	}
	key, inst, tok := s.LicenseKey, s.InstanceID, s.Token
	m.validating = true
	m.valRev++
	reqRev, rev := m.valRev, m.actRev
	m.mu.Unlock()
	defer func() {
		m.mu.Lock()
		if m.actRev == rev && m.valRev == reqRev {
			m.validating = false
		}
		m.mu.Unlock()
	}()
	if m.product == "" || !m.client.Configured() || s.ProductID != m.product || tok == "" {
		return Undecided
	}
	renewed, revoked, err := m.client.Validate(ctx, tok)
	m.mu.Lock()
	defer m.mu.Unlock()
	stale := m.actRev != rev || m.valRev != reqRev || m.st.LicenseKey != key || m.st.InstanceID != inst || m.st.ProductID != m.product
	if err != nil {
		if stale {
			return Undecided
		}
		var ve *ValidationError
		if errors.As(err, &ve) && ve.Kind == ValNetwork {
			if !m.withinGrace(m.clock()) { // applyOfflineGraceDecision
				m.st.Status = Unknown
				m.persistLocked()
			}
		} else {
			m.st.Status = Invalid
			m.persistLocked()
		}
		return Undecided
	}
	if stale {
		return Undecided
	}
	if revoked {
		m.st.Status = Revoked
		m.persistLocked()
		return Rejected
	}
	if !m.client.PermitsAccess(renewed, inst, m.label, m.clock()) {
		m.st.Status = Invalid
		m.persistLocked()
		return Rejected
	}
	prev := m.st
	m.st.Status, m.st.Token, m.st.LastValidatedAt = Active, renewed, m.clock()
	m.accessCache.have = false
	if e := m.store.Save(m.st); e != nil {
		m.st = prev
		m.activationErr = actErr(KindStorageFailure)
		return Undecided
	}
	return Valid
}

func (m *Manager) persistLocked() {
	m.accessCache.have = false
	_ = m.store.Save(m.st)
}

// ---- checkout

// Checkout asks the service for the hosted checkout URL and hands it to open; any failure opens the public
// purchase page instead. Neither URL nor buyer data is logged. It returns the URL that was opened.
func (m *Manager) Checkout(ctx context.Context, open func(string)) string {
	m.mu.Lock()
	if m.checkingOut {
		m.mu.Unlock()
		return ""
	}
	m.checkingOut = true
	m.mu.Unlock()
	defer func() { m.mu.Lock(); m.checkingOut = false; m.mu.Unlock() }()
	url, err := m.checkout.Session(ctx)
	if err != nil {
		url = tokens.CheckoutFallbackURL
	}
	if url != "" {
		open(url)
	}
	return url
}

// Opened returns the install label and persisted state for tests.
func (m *Manager) State() State { m.mu.Lock(); defer m.mu.Unlock(); return m.st }
