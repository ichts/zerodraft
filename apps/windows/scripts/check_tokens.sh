#!/bin/sh
# The SYNC.md drift gate. Fails when the Mac sources in this repository no longer generate exactly the committed
# tokens/tokens_gen.go, or when Zhuque Fangsong, a derived Newsreader face or the lockup differs from the Mac app's. Runs on any OS with python3 and gofmt
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
# Zhuque Fangsong is the Mac app's own file (go:embed cannot reach outside this module, so it is committed here).
MACRES=${1:-../macos/FirstLine/Sources/FirstLine}/Resources
cmp -s fonts/ZhuqueFangsong-Regular.ttf "$MACRES/ZhuqueFangsong-Regular.ttf" || { echo "fonts/ZhuqueFangsong-Regular.ttf differs from the Mac app's" >&2; exit 1; }
echo "Zhuque Fangsong identical to the Mac app's"
# Newsreader is derived: the Mac's variable fonts with the optical size the Mac draws each role at, pinned (gen_fonts.py).
"$PY" -c "import fontTools" 2>/dev/null || { echo "fonttools is needed to check the derived Newsreader faces: pip install fonttools==4.68.0" >&2; exit 1; }
mkdir "$T/fonts"
"$PY" scripts/gen_fonts.py "$MACRES" "$T/fonts" >/dev/null
for f in Newsreader-Text.ttf Newsreader-Display.ttf Newsreader-Numeral.ttf; do
  cmp -s "fonts/$f" "$T/fonts/$f" || { echo "fonts/$f is stale: run  python3 scripts/gen_fonts.py  (from apps/windows, fonttools 4.68.0), commit the result" >&2; exit 1; }
done
echo "Newsreader faces match their derivation from the Mac's variable fonts"
# The lockup (chip glyph layer and wordmark) is the Mac app's own SVG, also copied because go:embed cannot leave the module.
cmp -s app/lockup.svg "$MACRES/write-it-down-lockup.svg" || { echo "app/lockup.svg differs from the Mac app's $MACRES/write-it-down-lockup.svg" >&2; exit 1; }
echo "lockup identical to the Mac app's"
