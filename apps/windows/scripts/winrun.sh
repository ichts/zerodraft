#!/bin/sh
# usage: winrun.sh 'powershell command string' [timeout_s]
# Runs a command on vivobook-1 INSIDE the interactive desktop session of $WID_USER (default zyz10) (scheduled task /it, highest
# rights) and prints its combined output. Needed for anything the SSH logon cannot do (package deployment,
# GUI, input injection).
set -e
WIDHOST=${WID_HOST:-vivobook-1}   # the Windows test PC (ssh alias)
WIDUSER=${WID_USER:-zyz10}        # its interactive desktop user
CMD=$1; TMO=${2:-120}
T=wid_run_$$
printf '%s\r\n' "$CMD" > /tmp/$T.ps1
printf 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$PSDefaultParameterValues[\x27Out-File:Encoding\x27]=\x27ascii\x27; & C:\\wid\\%s.ps1 *> C:\\wid\\%s.log; Add-Content C:\\wid\\%s.log EXIT -Encoding ascii"\r\n' $T $T $T > /tmp/$T.cmd
scp -q /tmp/$T.ps1 /tmp/$T.cmd $WIDHOST:C:/wid/
ssh $WIDHOST "schtasks /create /tn $T /tr C:\\wid\\$T.cmd /sc once /st 23:59 /ru $WIDUSER /it /rl highest /f && schtasks /run /tn $T" </dev/null >/dev/null
i=0
while [ $i -lt $TMO ]; do
  sleep 2; i=$((i+2))
  if ssh $WIDHOST "findstr /b EXIT C:\\wid\\$T.log" </dev/null >/dev/null 2>&1; then break; fi
done
ssh $WIDHOST "type C:\\wid\\$T.log & schtasks /delete /tn $T /f >nul & del C:\\wid\\$T.ps1 C:\\wid\\$T.cmd C:\\wid\\$T.log" </dev/null 2>&1 | grep -v '^EXIT' || true
rm -f /tmp/$T.ps1 /tmp/$T.cmd
