#!/bin/sh
# The Mac pair on vivobook-1: every room state the Mac's SnapshotTests render, in the Mac's 1040 x 720 window at 100%, from
# the real window, then scripts/compare_mac.py against the Mac's own snapshots (produce those with
#   cd ../macos/FirstLine && WID_SNAPSHOT_DIR=$MAC_SNAPSHOTS swift test --filter SnapshotTests).
#   usage: MAC_SNAPSHOTS=/path scripts/pair.sh        evidence: $WID_EVIDENCE/pair100/
set -e
WIDHOST=${WID_HOST:-vivobook-1}
R=$(cd "$(dirname "$0")/.." && pwd)
EV=${WID_EVIDENCE:-${TMPDIR:-/tmp}/wid-windows-evidence}; export WID_EVIDENCE=$EV
cd "$R"
PAIR_EXE='C:\wid\stage\wid-pair.exe'   # WID_PREBUILT_EXE: an exe already on the PC (Smart App Control blocks a rebuilt one, see ime-suite.sh)
if [ -n "$WID_PREBUILT_EXE" ]; then PAIR_EXE=$WID_PREBUILT_EXE; else
  GOOS=windows GOARCH=amd64 go build -tags widqa -ldflags "-H=windowsgui" -o /tmp/wid-pair.exe ./cmd/wid
  ssh $WIDHOST "if not exist C:\\wid\\stage mkdir C:\\wid\\stage" </dev/null >/dev/null 2>&1 || true
  scp -q /tmp/wid-pair.exe $WIDHOST:C:/wid/stage/wid-pair.exe
fi
GOOS=windows GOARCH=amd64 go build -o cmd/drv/drv.exe ./cmd/drv
python3 scripts/mkpair.py pair100 "$PAIR_EXE" > /tmp/pair100.txt
for attempt in 1 2 3; do
  scripts/run-drv.sh pair100 /tmp/pair100.txt 200 >/dev/null || echo "driver run failed on attempt $attempt" >&2
  [ -s "$EV/pair100/app-a.log" ] && break
done
rc=0
for s in rest typing exit-hint warning deleted kept copied; do
  echo "== room-$s"
  python3 scripts/compare_mac.py "${MAC_SNAPSHOTS:?}/room-$s-light.png" "$EV/pair100/100-room-$s.png" --chrome || rc=1
done
exit $rc
