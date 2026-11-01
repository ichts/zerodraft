//go:build imebreak

package ime

import "os"

// Known-broken builds for the suite's own regression proof: `-tags imebreak` plus WID_BREAK=<mode>.
func init() { Break = os.Getenv("WID_BREAK") }
