//go:build !widqa

package main

import "github.com/ichts/zerodraft/apps/windows/tokens"

// licenceSettings is the licence service this build talks to.
type licenceSettings struct {
	ServiceURL, ProductID, PublicKey string
	// CredentialService names the Windows Credential Manager entries of this flavour.
	CredentialService string
}

// licenceConfig is the production configuration, generated from the Mac Info.plist (tokens/tokens_gen.go). The
// release build has no way to point elsewhere: no environment variable, file or flag changes the service, product
// or public key.
func licenceConfig() licenceSettings {
	return licenceSettings{tokens.LicenseServiceURL, tokens.LicenseProductID, tokens.LicensePublicKey, "TrefoilStudio.WriteItDown"}
}

func qaNoBrowser() bool { return false }

func qaLogPath() string     { return "" }
func qaSessionSeconds() int { return 0 }

// bareMode is never on in the release flavour: there is no switch that skips the trial or the licence.
func bareMode() bool { return false }
