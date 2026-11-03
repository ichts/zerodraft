// Package version is the one place the Windows app's version is written. version.txt holds the marketing version;
// Settings > About shows it, scripts/package-msix.sh turns it into the MSIX identity (which the Store reserves a fourth
// section of), and mygo.json carries the copy `mygo build` puts in the exe's version resource. version_test.go keeps
// version.txt, mygo.json and the rendered manifests in step.
package version

import (
	_ "embed"
	"strings"
)

//go:embed version.txt
var file string

// Version is the version the app reports, e.g. "1.0.0". Bump it in version.txt, never inline.
var Version = strings.TrimSpace(file)

// PackVersion is the four-section version of the MSIX identity, e.g. "1.0.0.0": the Store reserves the fourth section.
var PackVersion = Version + ".0"
