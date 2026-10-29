#!/bin/sh
# One command: builds the room, runs the scripted IME regression suite with real keystrokes on vivobook-1
# (Microsoft Pinyin, WeType, Japanese Microsoft IME), prints PASS/FAIL per check. Evidence lands in
# $WID_EVIDENCE/ime-suite/<tip>/ (default /tmp/wid-windows-evidence) (window captures, app.log, drv.log).
#   usage: scripts/ime-suite.sh [pinyin] [wetype] [ja]     (default: all three)
set -e
WIDHOST=${WID_HOST:-vivobook-1}   # the Windows test PC (ssh alias)
R=$(cd "$(dirname "$0")/.." && pwd)
EV=${WID_EVIDENCE:-${TMPDIR:-/tmp}/wid-windows-evidence}; export WID_EVIDENCE=$EV
EVID=$EV/ime-suite${WID_BREAK:+-broken-$WID_BREAK}
TIPS=${*:-pinyin wetype ja}
cd "$R"
TAGS=""; [ -n "$WID_BREAK" ] && TAGS=" imebreak"   # known-broken proof: WID_BREAK=nodeny|keepeditor
GOOS=windows GOARCH=amd64 go build -tags "widqa$TAGS" -ldflags "-H=windowsgui" -o /tmp/wid-suite.exe ./cmd/wid
GOOS=windows GOARCH=amd64 go build -o cmd/drv/drv.exe ./cmd/drv
go build -o /tmp/imecheck ./cmd/imecheck
ssh $WIDHOST "if not exist C:\\wid\\stage mkdir C:\\wid\\stage" </dev/null >/dev/null 2>&1 || true
scp -q /tmp/wid-suite.exe $WIDHOST:C:/wid/stage/wid-suite.exe
rc=0
mkdir -p "$EVID"
for tip in $TIPS; do
  name=suite-$tip
  python3 scripts/mksuite.py "$tip" "$name" 'C:\wid\stage\wid-suite.exe' > /tmp/$name.txt
  [ -n "$WID_BREAK" ] && { printf "setenv WID_BREAK=%s\n" "$WID_BREAK"; cat /tmp/$name.txt; } > /tmp/$name.brk && mv /tmp/$name.brk /tmp/$name.txt || true
  for attempt in 1 2 3; do # the remote desktop session occasionally drops the first launch: retry once
    scripts/run-drv.sh "$name" /tmp/$name.txt 300 >/dev/null || echo "driver run failed on attempt $attempt" >&2
    [ -s "$EV/$name/app.log" ] && break
    echo "no app log on attempt $attempt, retrying" >&2
  done
  rm -rf "$EVID/$tip"; mv "$EV/$name" "$EVID/$tip"
  /tmp/imecheck "$tip" "$EVID/$tip/app.log" "$EVID/$tip/drv.log" | tee "$EVID/$tip/result.txt" || rc=1
done
exit $rc
