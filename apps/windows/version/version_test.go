package version

import (
	"encoding/json"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"testing"
)

// TestVersionShape keeps the version one the Store accepts: Microsoft refuses a first section of 0, and the identity
// has exactly four numeric sections whose last one the Store reserves for itself.
func TestVersionShape(t *testing.T) {
	if !regexp.MustCompile(`^[1-9][0-9]*\.[0-9]+\.[0-9]+$`).MatchString(Version) {
		t.Fatalf("version.txt is %q: the Store refuses a first section of 0, so it must be a.b.c with a > 0", Version)
	}
	if PackVersion != Version+".0" {
		t.Fatalf("PackVersion is %q, want %q: the Store reserves the fourth section", PackVersion, Version+".0")
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

// TestManifestsCarryPackVersion proves every package flavour renders the version the app reports. It renders the
// manifests through the same script the CI gate uses, so a hardcoded VERSION in the packaging path fails here.
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
		if !strings.Contains(string(out), `Version="`+PackVersion+`"`) {
			t.Fatalf("the %s manifest does not carry Version=%q", flavour, PackVersion)
		}
	}
}
