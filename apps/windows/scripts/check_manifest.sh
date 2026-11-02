#!/bin/sh
# MSIX identity gate. The Store flavour's manifest must carry exactly the identity Partner Center reserved (STORE.md),
# with the Version's 4th number 0; the sideload flavours must keep the test-signing identity and never the Store one.
# Renders the manifests through `package-msix.sh <flavour> --manifest`, so it needs no Windows SDK and no PC. The actual
# makeappx pack of the store flavour is not run here.
#   usage: scripts/check_manifest.sh
set -e
cd "$(dirname "$0")/.."
STORE_PUBLISHER='CN=E0C4C311-1698-4A16-BCE3-58C3DB5B825E'
fail() { echo "check_manifest: $*" >&2; exit 1; }
identity() { scripts/package-msix.sh "$1" --manifest | grep '<Identity '; }
pubdisplay() { scripts/package-msix.sh "$1" --manifest | grep '<PublisherDisplayName>'; }
want() { # flavour, expected Identity attributes, expected publisher display
  I=$(identity "$1"); P=$(pubdisplay "$1")
  [ "$I" = "  <Identity Name=\"$2\" Publisher=\"$3\" Version=\"0.2.0.0\" ProcessorArchitecture=\"x64\" />" ] || fail "$1 Identity is: $I"
  [ "$P" = "    <PublisherDisplayName>Trefoil Studio</PublisherDisplayName>" ] || fail "$1 publisher display is: $P"
  scripts/package-msix.sh "$1" --manifest | grep -q '@[A-Z]*@' && fail "$1 manifest has an unfilled placeholder"
  echo "$1: $2 / $3"
}
want store TrefoilStudio.WriteItDown "$STORE_PUBLISHER"
want release TrefoilStudio.WriteItDown 'CN=WID Test Signing'
want qa TrefoilStudio.WriteItDownQA 'CN=WID Test Signing'
for f in release qa; do
  scripts/package-msix.sh $f --manifest | grep -q "E0C4C311" && fail "$f manifest carries the Store publisher"
done
# the Store flavour is unsigned and never installed: it must not call the signing or install scripts
sed -n '/\[ \$SIGN = 0 \]/,/^fi/p' scripts/package-msix.sh | grep -q 'install-msix' && fail "store flavour installs the package"
grep -q 'NoSign' scripts/package-msix.sh || fail "store flavour does not pass -NoSign"
echo "msix identity OK"
