#!/bin/sh
# Builds the app with `mygo build` (icon, DPI manifest and version resources), wraps it as a test-signed MSIX on
# vivobook-1 (Windows SDK BuildTools makeappx + signtool from the Microsoft.Windows.SDK.BuildTools NuGet package in
# C:\wid\tools), installs it for the user and prints the package identity.
#   usage: scripts/package-msix.sh release|qa      (qa = the -tags widqa flavour that talks to the local TEST service)
set -e
WIDHOST=${WID_HOST:-vivobook-1}   # the Windows test PC (ssh alias)
R=$(cd "$(dirname "$0")/.." && pwd)
FLAVOUR=${1:-release}
cd "$R"
case "$FLAVOUR" in
  release) NAME=TrefoilStudio.WriteItDown; DISPLAY='Write It Down'; SHORT='Write It Down'; OUT=build ;;
  qa)      NAME=TrefoilStudio.WriteItDownQA; DISPLAY='Write It Down (QA)'; SHORT='WID QA'; OUT=build-qa; export GOFLAGS=-tags=widqa ;;
  *) echo "release|qa"; exit 2 ;;
esac
go run github.com/egoist/mygo/cmd/mygo build -platform windows/amd64 -o "$OUT" >/dev/null
EXE="$OUT/windows-amd64/Write It Down.exe"
ssh $WIDHOST "if not exist C:\\wid\\stage mkdir C:\\wid\\stage" </dev/null >/dev/null 2>&1 || true
scp -q "$EXE" $WIDHOST:C:/wid/stage/wid-$FLAVOUR.exe
ssh $WIDHOST "rmdir /s /q C:\\wid\\pkg2 & mkdir C:\\wid\\pkg2" </dev/null >/dev/null 2>&1 || true
scp -q -r packaging $WIDHOST:C:/wid/pkg2/
scripts/winrun.sh "
Get-Process wid -ErrorAction SilentlyContinue | Stop-Process -Force
& C:\\wid\\pkg2\\packaging\\make-msix.ps1 -Exe C:\\wid\\stage\\wid-$FLAVOUR.exe -Out C:\\wid\\out\\WriteItDown-$FLAVOUR.msix -Name '$NAME' -Display '$DISPLAY' -Short '$SHORT' 2>&1 | Select-Object -Last 4
& C:\\wid\\pkg2\\packaging\\install-msix.ps1 -Msix C:\\wid\\out\\WriteItDown-$FLAVOUR.msix -Name '$NAME'
" 240
