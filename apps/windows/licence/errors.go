package licence

import (
	"fmt"

	"github.com/ichts/zerodraft/apps/windows/tokens"
)

// ActivationKind is the Mac LicenseActivationError case.
type ActivationKind int

const (
	KindInvalidKey ActivationKind = iota
	KindActivationLimitReached
	KindNetworkFailure
	KindEmptyKey
	KindUnexpected
	KindStorageFailure
	KindProductNotConfigured
	KindWrongProduct
	KindInvalidToken
	KindCleanupFailure
)

// ActivationError is a typed activation failure; Error() is the Mac's sentence in Windows wording.
type ActivationError struct {
	Kind   ActivationKind
	Status int // HTTP status for KindUnexpected
}

func (e *ActivationError) Error() string {
	switch e.Kind {
	case KindInvalidKey:
		return tokens.ErrInvalidKey
	case KindActivationLimitReached:
		return tokens.ErrActivationLimitReached
	case KindNetworkFailure:
		return tokens.ErrNetworkFailure
	case KindEmptyKey:
		return tokens.ErrEmptyKey
	case KindUnexpected:
		return fmt.Sprintf(tokens.ErrUnexpected, e.Status)
	case KindStorageFailure:
		return tokens.ErrStorageFailure
	case KindProductNotConfigured:
		return tokens.ErrProductNotConfigured
	case KindWrongProduct:
		return tokens.ErrWrongProduct
	case KindInvalidToken:
		return tokens.ErrInvalidToken
	case KindCleanupFailure:
		return tokens.ErrCleanupFailure
	}
	return ""
}

func actErr(k ActivationKind) *ActivationError { return &ActivationError{Kind: k} }

// ValidationKind is the Mac LicenseValidationError case.
type ValidationKind int

const (
	ValNetwork ValidationKind = iota
	ValUnexpected
	ValInvalidToken
)

// ValidationError is a failed renewal that is not an explicit revocation (revocation is HTTP 403).
type ValidationError struct {
	Kind   ValidationKind
	Status int
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("licence validation failed (kind %d, HTTP %d)", e.Kind, e.Status)
}
