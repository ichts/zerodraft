#!/bin/sh
# Builds the app with `mygo build` (icon, DPI manifest and version resources), wraps it as a test-signed MSIX on
# vivobook-1 (Windows SDK BuildTools makeappx + signtool from the Microsoft.Windows.SDK.BuildTools NuGet package in
# C:\wid\tools), installs it for the user and prints the package identity.
#   usage: scripts/package-msix.sh release|qa|store [--manifest]
#     qa    = the -tags widqa flavour that talks to the local TEST service
#     store = the release binary as an UNSIGNED MSIX with the identity Partner Center reserved (packaging/STORE.md):
#             packed on the PC, copied back to build-store/, never installed, never signed (the Store signs it)
#     --manifest prints the AppxManifest.xml the flavour gets and exits (no build, no PC); scripts/check_manifest.sh
#             asserts it. The Version's 4th number stays 0: the Store reserves it.
set -e
WIDHOST=${WID_HOST:-vivobook-1}   # the Windows test PC (ssh alias)
R=$(cd "$(dirname "$0")/.." && pwd)
FLAVOUR=${1:-release}
cd "$R"
PUBLISHER='CN=WID Test Signing'; PUBDISPLAY='Trefoil Studio'; VERSION=0.2.0.0; SIGN=1
case "$FLAVOUR" in
  release) NAME=TrefoilStudio.WriteItDown; DISPLAY='Write It Down'; SHORT='Write It Down'; OUT=build ;;
  qa)      NAME=TrefoilStudio.WriteItDownQA; DISPLAY='Write It Down (QA)'; SHORT='WID QA'; OUT=build-qa; export GOFLAGS=-tags=widqa ;;
  store)   NAME=TrefoilStudio.WriteItDown; PUBLISHER=CN=E0C4C311-1698-4A16-BCE3-58C3DB5B825E; DISPLAY='Write It Down'; SHORT='Write It Down'; OUT=build-store; SIGN=0 ;;
  *) echo "release|qa|store [--manifest]"; exit 2 ;;
esac
if [ "$2" = --manifest ]; then
  sed -e "s|@EXE@|wid.exe|g" -e "s|@NAME@|$NAME|g" -e "s|@DISPLAY@|$DISPLAY|g" -e "s|@SHORT@|$SHORT|g" \
      -e "s|@PUBLISHER@|$PUBLISHER|g" -e "s|@PUBDISPLAY@|$PUBDISPLAY|g" -e "s|@VERSION@|$VERSION|g" packaging/AppxManifest.xml
  exit 0
fi
go run github.com/egoist/mygo/cmd/mygo build -platform windows/amd64 -o "$OUT" >/dev/null
EXE="$OUT/windows-amd64/Write It Down.exe"
ssh $WIDHOST "if not exist C:\\wid\\stage mkdir C:\\wid\\stage" </dev/null >/dev/null 2>&1 || true
scp -q "$EXE" $WIDHOST:C:/wid/stage/wid-$FLAVOUR.exe
ssh $WIDHOST "rmdir /s /q C:\\wid\\pkg2 & mkdir C:\\wid\\pkg2" </dev/null >/dev/null 2>&1 || true
scp -q -r packaging $WIDHOST:C:/wid/pkg2/
MAKE="& C:\\wid\\pkg2\\packaging\\make-msix.ps1 -Exe C:\\wid\\stage\\wid-$FLAVOUR.exe -Out C:\\wid\\out\\WriteItDown-$FLAVOUR.msix -Name '$NAME' -Display '$DISPLAY' -Short '$SHORT' -Publisher '$PUBLISHER' -PublisherDisplay '$PUBDISPLAY' -Version '$VERSION'"
if [ $SIGN = 0 ]; then
  scripts/winrun.sh "
$MAKE -NoSign 2>&1 | Select-Object -Last 4
" 240
  scp -q $WIDHOST:C:/wid/out/WriteItDown-$FLAVOUR.msix "$OUT/"
  echo "unsigned Store package: $R/$OUT/WriteItDown-$FLAVOUR.msix"
  exit 0
fi
scripts/winrun.sh "
Get-Process wid -ErrorAction SilentlyContinue | Stop-Process -Force
$MAKE 2>&1 | Select-Object -Last 4
& C:\\wid\\pkg2\\packaging\\install-msix.ps1 -Msix C:\\wid\\out\\WriteItDown-$FLAVOUR.msix -Name '$NAME'
" 240
