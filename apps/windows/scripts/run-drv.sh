#!/bin/sh
# usage: run-drv.sh OUTNAME SCRIPTFILE [max_wait_s]   (SCRIPT lines per cmd/drv/main.go)
# Pushes drv.exe + the script to vivobook-1, runs drv inside the interactive session, pulls C:\wid\out\OUTNAME back
# into $WID_EVIDENCE/OUTNAME and prints drv.log.
set -e
WIDHOST=${WID_HOST:-vivobook-1}   # the Windows test PC (ssh alias)
WIDUSER=${WID_USER:-zyz10}        # its interactive desktop user
R=$(cd "$(dirname "$0")/.." && pwd)
EV=${WID_EVIDENCE:-${TMPDIR:-/tmp}/wid-windows-evidence}
NAME=$1; SCRIPT=$2; MAXW=${3:-240}
ssh $WIDHOST "taskkill /f /im drv.exe & rmdir /s /q C:\\wid\\out\\$NAME & mkdir C:\\wid\\out" </dev/null >/dev/null 2>&1 || true
rm -rf "$EV/$NAME"
(cd "$R" && GOOS=windows GOARCH=amd64 go build -o cmd/drv/drv.exe ./cmd/drv)
scp -q "$R/cmd/drv/drv.exe" $WIDHOST:C:/wid/drv.exe
scp -q $SCRIPT $WIDHOST:C:/wid/$NAME.txt
ssh $WIDHOST "schtasks /create /tn wd_$NAME /tr \"C:\\wid\\drv.exe C:\\wid\\$NAME.txt C:\\wid\\out\\$NAME\" /sc once /st 23:59 /ru $WIDUSER /it /f && schtasks /run /tn wd_$NAME" </dev/null >/dev/null
i=0
while [ $i -lt $MAXW ]; do
  sleep 3; i=$((i+3))
  if ssh $WIDHOST "findstr /c:\" done\" C:\\wid\\out\\$NAME\\drv.log" </dev/null >/dev/null 2>&1; then break; fi
done
ssh $WIDHOST "schtasks /delete /tn wd_$NAME /f" </dev/null >/dev/null 2>&1 || true
mkdir -p "$EV"
scp -q -r $WIDHOST:C:/wid/out/$NAME "$EV/"
cat "$EV/$NAME/drv.log"
