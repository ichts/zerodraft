package version

import (
	"encoding/json"
	"encoding/xml"
	"os"
	"os/exec"
	"regexp"
	"testing"
)

var (
	// appVersion is version.txt's shape: three sections, the first not 0 because Microsoft refuses a first section of 0.
	appVersion = regexp.MustCompile(`^[1-9][0-9]*\.[0-9]+\.[0-9]+$`)
	// packVersion is the identity's shape: four sections, the first not 0, the fourth 0 because the Store reserves it.
	packVersion = regexp.MustCompile(`^[1-9][0-9]*\.[0-9]+\.[0-9]+\.0$`)
)

// TestVersionShape keeps the version one the Store accepts: Microsoft refuses a first section of 0.
func TestVersionShape(t *testing.T) {
	if !appVersion.MatchString(Version) {
		t.Fatalf("version.txt is %q: the Store refuses a first section of 0, so it must be a.b.c with a > 0", Version)
	}
}

// TestMygoJSONAgrees guards the one copy of the version the build tool owns: mygo.json's version becomes the exe's
// version resource, so a bump that misses it would leave Explorer and Settings showing different versions.
func TestMygoJSONAgrees(t *testing.T) {
	b, err := os.ReadFile("../mygo.json")
	if err != nil {
		t.Fatalf("read mygo.json: %v", err)
	}
	var c struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(b, &c); err != nil {
		t.Fatalf("parse mygo.json: %v", err)
	}
	if c.Version != Version {
		t.Fatalf("mygo.json version is %q and version.txt is %q: set both (the exe's version resource and Settings "+
			"would disagree)", c.Version, Version)
	}
}

// manifestIdentity is the identity the packaging script rendered into an AppxManifest.xml.
type manifestIdentity struct {
	Identity struct {
		Version string `xml:"Version,attr"`
	} `xml:"Identity"`
}

// TestManifestsCarryPackVersion proves every package flavour renders the app's version with the Store's reserved fourth
// section, in the four-section shape the Store accepts. It renders the manifests through the same script the CI gate
// uses, so a hardcoded or wrongly derived version in the packaging path fails here.
func TestManifestsCarryPackVersion(t *testing.T) {
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh on this runner: scripts/check_manifest.sh owns the same check in the Windows CI job")
	}
	for _, flavour := range []string{"release", "qa", "store"} {
		out, err := exec.Command(sh, "../scripts/package-msix.sh", flavour, "--manifest").Output()
		if err != nil {
			t.Fatalf("render the %s manifest: %v", flavour, err)
		}
		var m manifestIdentity
		if err := xml.Unmarshal(out, &m); err != nil {
			t.Fatalf("parse the %s manifest: %v", flavour, err)
		}
		if !packVersion.MatchString(m.Identity.Version) {
			t.Fatalf("the %s manifest carries Version=%q: the Store needs a.b.c.0 with a > 0 and the fourth section 0",
				flavour, m.Identity.Version)
		}
		if m.Identity.Version != PackVersion {
			t.Fatalf("the %s manifest carries Version=%q and the app reports %q", flavour, m.Identity.Version, PackVersion)
		}
	}
}
