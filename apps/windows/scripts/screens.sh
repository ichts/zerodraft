#!/bin/sh
# The Mac pair for the cards, from the real window: Home, Rules, the activation card, Settings at 100% in the Mac's 1040 x 720 page
# area (the first 90 s of scripts/e2e.sh), then scripts/compare_mac.py against the Mac's own snapshots.
#   usage: MAC_SNAPSHOTS=/path scripts/screens.sh        evidence: $WID_EVIDENCE/e2e100/
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
cd "$R"
WID_E2E_UPTO=screens scripts/e2e.sh 100 0 >/dev/null
EV=${WID_EVIDENCE:-${TMPDIR:-/tmp}/wid-windows-evidence}
rc=0
echo "== picker (the Settings link has no Mac twin: SYNC.md row 36)"
python3 scripts/compare_mac.py "${MAC_SNAPSHOTS:?}/picker-light.png" "$EV/e2e100/100-08-home-after-session-2.png" --region card --drop-win-rows 1 || rc=1
echo "== activation (the field is the Mac's bezel against a bordered box: its detector rows differ, the pills and text rows are what is compared)"
python3 scripts/compare_mac.py "${MAC_SNAPSHOTS:?}/activation-light.png" "$EV/e2e100/100-09-upgrade-exhausted.png" --region card || rc=1
exit $rc
