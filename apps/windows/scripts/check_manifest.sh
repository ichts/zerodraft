#!/bin/sh
# MSIX manifest gate. Renders each flavour through `package-msix.sh <flavour> --manifest`, so it needs no Windows SDK
# and no PC, and asserts what each package must carry: the identity Partner Center reserved for the Store (STORE.md), the
# test-signing identity for the sideloads, one four-section version across every flavour whose first section is not 0
# (Microsoft refuses a first version section of 0) and whose fourth stays 0 (the Store reserves it), and the Windows 11
# TargetDeviceFamily floor on every flavour, because nothing below Windows 11 has been run. It ends with known-broken
# controls: a doctored manifest must be refused, so a gate that stopped biting cannot pass silently.
# The actual makeappx pack is not run here: the GitHub windows job builds, this gate only reads the rendered XML.
#   usage: scripts/check_manifest.sh
set -e
cd "$(dirname "$0")/.."
STORE_PUBLISHER='CN=E0C4C311-1698-4A16-BCE3-58C3DB5B825E'
WINDOWS11=10.0.22000.0   # every packaged flavour floors at Windows 11: nothing below it has been run
fail() { echo "check_manifest: $*" >&2; exit 1; }

# attr <manifest line> <attribute>: the value of one quoted manifest attribute
attr() { printf '%s\n' "$1" | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"; }

# numeric <version> <label>: four numeric sections, the shape an MSIX identity needs
numeric() {
  printf '%s\n' "$1" | grep -qxE '[0-9]+(\.[0-9]+){3}' || fail "$2 is not a four-section numeric version: $1"
}

# audit <flavour> <manifest> <identity name> <publisher>: every rule for one rendered manifest; sets V and M
audit() {
  f=$1; m=$2
  printf '%s\n' "$m" | grep -q '@[A-Z]*@' && fail "$f manifest has an unfilled placeholder"
  i=$(printf '%s\n' "$m" | grep '<Identity ') || fail "$f manifest has no Identity line"
  d=$(printf '%s\n' "$m" | grep '<TargetDeviceFamily ') || fail "$f manifest has no TargetDeviceFamily line"
  [ "$(attr "$i" ProcessorArchitecture)" = x64 ] || fail "$f Identity is: $i"
  V=$(attr "$i" Version); numeric "$V" "$f Version"
  case "$V" in 0.*) fail "$f Version is $V: Microsoft refuses a first section of 0" ;; esac
  case "$V" in *.0) ;; *) fail "$f Version is $V: the Store reserves the fourth section, keep it 0" ;; esac
  M=$(attr "$d" MinVersion); numeric "$M" "$f MinVersion"
  printf '%s\n' "$m" | grep -q '<PublisherDisplayName>Trefoil Studio</PublisherDisplayName>' ||
    fail "$f publisher display is not Trefoil Studio"
  [ "$(attr "$i" Name)" = "$3" ] || fail "$f Identity Name is: $i"
  [ "$(attr "$i" Publisher)" = "$4" ] || fail "$f Identity Publisher is: $i"
  [ "$M" = "$WINDOWS11" ] || fail "$f MinVersion is $M, want $WINDOWS11: every flavour floors at Windows 11"
  return 0
}

# want <flavour> <identity name> <publisher>: renders, audits, and reports one flavour; every flavour must agree on the
# version, since one file feeds the app's Settings screen and every package
want() {
  f=$1
  audit "$f" "$(scripts/package-msix.sh "$f" --manifest)" "$2" "$3"
  [ -z "$ONLY" ] || [ "$V" = "$ONLY" ] || fail "$f Version is $V, but $LAST had $ONLY"
  ONLY=$V; LAST=$f
  echo "$f: $2 / $3 / Version $V / MinVersion $M"
}
ONLY=
want store TrefoilStudio.WriteItDown "$STORE_PUBLISHER"
want release TrefoilStudio.WriteItDown 'CN=WID Test Signing'
want qa TrefoilStudio.WriteItDownQA 'CN=WID Test Signing'

# known-broken controls: each doctored manifest must be refused, and for its own reason
STORE_MANIFEST=$(scripts/package-msix.sh store --manifest)
RELEASE_MANIFEST=$(scripts/package-msix.sh release --manifest)
BELOW_FLOOR=$(printf '%s\n' "$WINDOWS11" | awk -F. '{ print $1 "." $2 "." ($3 - 1) "." $4 }')
refuse() { # what, the reason the refusal must give, then the audit arguments for the doctored manifest
  what=$1; reason=$2; shift 2
  out=$(audit "$@" 2>&1) && fail "the gate accepted a manifest with $what"
  printf '%s\n' "$out" | grep -q "$reason" || fail "the gate refused $what for the wrong reason: $out"
  echo "refused $what: $out"
}
refuse 'a version whose first section is 0' 'first section of 0' \
  store "$(printf '%s\n' "$STORE_MANIFEST" | sed '/<Identity /s|Version="[0-9.]*"|Version="0.2.0.0"|')" \
  TrefoilStudio.WriteItDown "$STORE_PUBLISHER"
refuse 'a Store manifest below the Windows 11 floor' "want $WINDOWS11" \
  store "$(printf '%s\n' "$STORE_MANIFEST" | sed "/<TargetDeviceFamily /s|MinVersion=\"[0-9.]*\"|MinVersion=\"$BELOW_FLOOR\"|")" \
  TrefoilStudio.WriteItDown "$STORE_PUBLISHER"
refuse 'the test-signing publisher' 'Identity Publisher' \
  store "$(printf '%s\n' "$STORE_MANIFEST" | sed '/<Identity /s|Publisher="[^"]*"|Publisher="CN=WID Test Signing"|')" \
  TrefoilStudio.WriteItDown "$STORE_PUBLISHER"
refuse 'a sideload manifest below the Windows 11 floor' "want $WINDOWS11" \
  release "$(printf '%s\n' "$RELEASE_MANIFEST" | sed "/<TargetDeviceFamily /s|MinVersion=\"[0-9.]*\"|MinVersion=\"$BELOW_FLOOR\"|")" \
  TrefoilStudio.WriteItDown 'CN=WID Test Signing'

# the Store flavour is unsigned and never installed: it must not call the signing or install scripts
sed -n '/\[ \$SIGN = 0 \]/,/^fi/p' scripts/package-msix.sh | grep -q 'install-msix' && fail "store flavour installs the package"
grep -q 'NoSign' scripts/package-msix.sh || fail "store flavour does not pass -NoSign"
echo "msix manifests OK"
