#!/bin/sh
# The end-to-end proof on vivobook-1: starts the REAL licence service (Stripe TEST mode, unmodified binary built from
# services/license) with a loopback fake of Stripe's API, a reverse ssh tunnel to vivobook-1, runs the whole product with
# real input at one display scale, then stops everything it started on both machines.
#   usage: scripts/e2e.sh 150|100 [0]    (0 = no browser hand-off)
#   needs: the QA MSIX installed on the Windows test PC (scripts/package-msix.sh qa) and ssh access to it.
#   Builds the licence service from this repository (unmodified) and cmd/qaserver; evidence in $WID_EVIDENCE.
set -e
WIDHOST=${WID_HOST:-vivobook-1}   # the Windows test PC (ssh alias)
R=$(cd "$(dirname "$0")/.." && pwd)
EV=${WID_EVIDENCE:-${TMPDIR:-/tmp}/wid-windows-evidence}
S=${1:-150}
T=${TMPDIR:-/tmp}/wid-windows-e2e
W=$T/qa-$S
BROWSER=${2:-1}
NAME=e2e$S
cd "$R"
GOOS=windows GOARCH=amd64 go build -o cmd/drv/drv.exe ./cmd/drv
rm -rf "$W"; mkdir -p "$W" "$EV"; export WID_EVIDENCE=$EV
(cd "$R/../../services/license" && go build -o "$T/license-service" .)
go build -o "$T/qaserver" ./cmd/qaserver
cleanup() {
  [ -n "$TPID" ] && [ "$(ps -o command= -p $TPID 2>/dev/null | cut -c1-8)" = "ssh -N -" ] && kill "$TPID"
  [ -n "$QPID" ] && ps -o command= -p "$QPID" 2>/dev/null | grep -q qaserver && kill -INT "$QPID" && sleep 2
  ssh $WIDHOST 'taskkill /f /im wid.exe & del C:\wid\qa\config.json' </dev/null >/dev/null 2>&1
}
trap cleanup EXIT
"$T/qaserver" -service "$T/license-service" -dir "$W" $([ "$BROWSER" = 1 ] || echo -no-browser) > "$W/qaserver.log" 2>&1 & QPID=$!
echo "qaserver pid $QPID: $(ps -o command= -p $QPID | cut -c1-60)"
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q READY "$W/qaserver.log" && break; sleep 1; done
grep -q READY "$W/qaserver.log" || { cat "$W/qaserver.log"; exit 1; }
grep SERVICE_PID "$W/qaserver.log"
scp -q scripts/clearcred.ps1 $WIDHOST:C:/wid/qa/clearcred.ps1
ssh $WIDHOST 'del C:\wid\out\qa\app.log' </dev/null >/dev/null 2>&1 || true
scp -q "$W/config.json" $WIDHOST:C:/wid/qa/config.json
ssh -N -R 127.0.0.1:18060:127.0.0.1:18060 -R 127.0.0.1:18061:127.0.0.1:18061 $WIDHOST </dev/null & TPID=$!
echo "tunnel pid $TPID: $(ps -o command= -p $TPID | cut -c1-40)"
sleep 3
python3 scripts/mke2e.py "$S" "$NAME" "$BROWSER" > /tmp/$NAME.txt
scripts/run-drv.sh "$NAME" /tmp/$NAME.txt 420 | tail -80
scp -q $WIDHOST:C:/wid/out/qa/app.log "$EV/$NAME/app.log" || true
cp "$W/qaserver.log" "$EV/$NAME/qaserver.log"
curl -s http://127.0.0.1:18061/qa/status > "$EV/$NAME/qa-status.json" || true
