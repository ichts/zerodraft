#!/bin/sh
# One command per display scale: builds the room, runs every state on vivobook-1 at SCALE percent, restores the
# machine's scale, and measures the captures (scripts/measure.py). Evidence: $WID_EVIDENCE/cap<SCALE>[-broken-<mode>]/.
#   usage: scripts/capture.sh 100|125|150        known-broken proof: WID_BREAK=anchor35 scripts/capture.sh 150
set -e
WIDHOST=${WID_HOST:-vivobook-1}   # the Windows test PC (ssh alias)
R=$(cd "$(dirname "$0")/.." && pwd)
EV=${WID_EVIDENCE:-${TMPDIR:-/tmp}/wid-windows-evidence}; export WID_EVIDENCE=$EV
S=${1:-150}
cd "$R"
TAGS=""; [ -n "$WID_BREAK" ] && TAGS=" imebreak"
GOOS=windows GOARCH=amd64 go build -tags "widqa$TAGS" -ldflags "-H=windowsgui" -o /tmp/wid-cap.exe ./cmd/wid
GOOS=windows GOARCH=amd64 go build -o cmd/drv/drv.exe ./cmd/drv
scp -q /tmp/wid-cap.exe $WIDHOST:C:/wid/stage/wid-cap.exe
NAME=cap$S${WID_BREAK:+-broken-$WID_BREAK}
python3 scripts/mkcapture.py "$S" "$NAME" 'C:\wid\stage\wid-cap.exe' > /tmp/$NAME.txt
[ -n "$WID_BREAK" ] && { printf "setenv WID_BREAK=%s\n" "$WID_BREAK"; cat /tmp/$NAME.txt; } > /tmp/$NAME.brk && mv /tmp/$NAME.brk /tmp/$NAME.txt || true
for attempt in 1 2 3; do
  scripts/run-drv.sh "$NAME" /tmp/$NAME.txt 240 >/dev/null || echo "driver run failed on attempt $attempt" >&2
  [ -s "$EV/$NAME/app-$S-a.log" ] && break
done
python3 scripts/measure.py "$EV/$NAME" "$S"
