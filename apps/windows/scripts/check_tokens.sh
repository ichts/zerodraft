#!/bin/sh
# The SYNC.md drift gate. Fails when the Mac sources in this repository no longer generate exactly the committed
# tokens/tokens_gen.go, or when a shipped font differs from the Mac app's copy. Runs on any OS with python3 and gofmt
# (CI runs it on the Windows runner). The generator itself exits non-zero when a Mac sentence it copies has changed.
#   usage: scripts/check_tokens.sh [MAC_SOURCES_DIR]
set -e
cd "$(dirname "$0")/.."
PY=python3; command -v "$PY" >/dev/null 2>&1 || PY=python
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$PY" scripts/gen_tokens.py "$@" > "$T/gen.go"
gofmt "$T/gen.go" | tr -d '\r' > "$T/gen.fmt.go"
tr -d '\r' < tokens/tokens_gen.go > "$T/committed.go"
if cmp -s "$T/gen.fmt.go" "$T/committed.go"; then
  echo "tokens in sync with the Mac sources"
else
  diff "$T/committed.go" "$T/gen.fmt.go" | head -40 || true
  echo "tokens/tokens_gen.go is stale: run  python3 scripts/gen_tokens.py | gofmt > tokens/tokens_gen.go  (from apps/windows), review the parity rows in SYNC.md, commit both" >&2
  exit 1
fi
# Fonts are the Mac app's own files (go:embed cannot reach outside this module, so they are committed here).
MACRES=${1:-../macos/FirstLine/Sources/FirstLine}/Resources
for f in fonts/*.ttf; do
  cmp -s "$f" "$MACRES/$(basename "$f")" || { echo "$f differs from the Mac app's $MACRES/$(basename "$f")" >&2; exit 1; }
done
echo "fonts identical to the Mac app's"
