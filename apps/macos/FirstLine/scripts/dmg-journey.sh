#!/usr/bin/env bash
# [INPUT] Optional DMG path (default: download https://writeitdown.app/download/Write-It-Down-1.0.dmg)
#         and output dir (default /tmp/wid-dmg-journey/<timestamp>). Env:
#         WID_DMG_URL, WID_DMG_CLEAN_USER_EVIDENCE=<file> (see MANUAL below).
# [OUTPUT] Per-step PASS/FAIL lines, AX snapshots + screenshots, screen.mov when
#          screen recording is permitted, app.log, journey.log. Exit 0 only when
#          every automated step passed AND clean-user evidence was supplied;
#          exit 1 on any automated failure; exit 2 when automated steps passed
#          but the manual evidence is still missing (prints exactly what).
# [POS] apps/macos/FirstLine/scripts/dmg-journey.sh - release journey gate for the
#       SHIPPED Developer-ID DMG (no repackaging, no Info.plist edits, no license
#       fixture: the real build is exercised). Real-window driving reuses the
#       cua-driver conventions of qa-window.sh.
# [PROTOCOL] Accessibility/screen-recording belong to the cua-driver daemon. The app
#            is launched from the copied bundle binary with a fresh CFFIXED_USER_HOME
#            so it sees a never-used Mac. Gatekeeper is assessed with spctl on a
#            quarantined copy (launching the binary directly bypasses it).
#            MANUAL: a physically clean macOS user (fresh login, real Finder
#            drag-to-Applications, first-launch Gatekeeper dialog) cannot be
#            scripted from this session. Supply a file at WID_DMG_CLEAN_USER_EVIDENCE
#            (a recording or note of that run) to turn the final exit from 2 to 0.
set -uo pipefail

DMG_URL="${WID_DMG_URL:-https://writeitdown.app/download/Write-It-Down-1.0.dmg}"
PAGE_URL="${WID_DMG_PAGE_URL:-https://writeitdown.app/download/}"
out="${2:-/tmp/wid-dmg-journey/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"; out="$(cd "$out" && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/wid-dmg.XXXXXX")"; work="$(cd "$work" && pwd -P)"
failures=0; pid=''; rec_pid=''; mnt=''
log() { printf '%s\n' "$*" | tee -a "$out/journey.log"; }
pass() { log "PASS $1"; }
bad() { log "FAIL $1"; failures=$((failures + 1)); }
step() { local name="$1"; shift; if "$@" >>"$out/journey.log" 2>&1; then pass "$name"; else bad "$name"; return 1; fi; }
cleanup() {
  [[ -n "$pid" ]] && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
  [[ -n "$rec_pid" ]] && { kill -INT "$rec_pid" 2>/dev/null; sleep 4; kill -TERM "$rec_pid" 2>/dev/null; }
  [[ -n "$mnt" ]] && hdiutil detach "$mnt" -quiet -force 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# Screen recording (needs the invoking terminal to hold screen-recording permission).
if screencapture -v -V 600 "$out/screen.mov" 2>/dev/null & rec_pid=$!; sleep 2; ! kill -0 "$rec_pid" 2>/dev/null; then
  log 'WARN screen.mov not recorded (grant screen recording to this terminal); per-step screenshots are still captured'
  rec_pid=''
fi

# 1. Obtain the DMG and compare with the published checksum.
dmg="${1:-}"
if [[ -z "$dmg" ]]; then
  dmg="$work/Write-It-Down-1.0.dmg"
  step 'download DMG (HTTP 200)' curl -fsSL -o "$dmg" "$DMG_URL" || exit 1
fi
size="$(stat -f %z "$dmg")"
[[ "$size" -ge 1000000 ]] && pass "DMG size plausible ($size bytes)" || bad "DMG size implausible ($size bytes)"
actual="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
published="$(curl -fsSL "$PAGE_URL" | grep -o 'data-launch="sha256">[0-9a-f]\{64\}' | grep -o '[0-9a-f]\{64\}$' | head -1)"
[[ -n "$published" && "$actual" == "$published" ]] && pass 'SHA-256 equals the published checksum' \
  || bad "SHA-256 $actual != published '${published:-none}'"

# 2. DMG signature, notarization ticket, Gatekeeper.
step 'codesign verifies the DMG' codesign --verify --verbose=2 "$dmg"
step 'stapler validates the DMG ticket' xcrun stapler validate "$dmg"
step 'spctl accepts the DMG (open context)' spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

[[ "$failures" -eq 0 ]] || { log "STOP: $failures failure(s) on the DMG file itself; not mounting"; exit 1; }

# 3. Mount, inspect layout, drag-to-Applications.
mnt="$work/mnt"; mkdir -p "$mnt"
step 'hdiutil attach (read-only)' hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mnt" || exit 1
src="$mnt/Write It Down.app"
[[ -d "$src" ]] && pass 'DMG contains Write It Down.app' || { bad 'DMG has no Write It Down.app'; exit 1; }
[[ -L "$mnt/Applications" ]] && pass 'DMG offers the Applications shortcut' || bad 'DMG has no Applications symlink'
apps="$work/Applications"; mkdir -p "$apps"          # stands in for /Applications (no admin needed)
step 'drag-to-Applications copy' ditto "$src" "$apps/Write It Down.app"
app="$apps/Write It Down.app"
xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;" "$app"  # what a browser download leaves behind
step 'codesign --deep --strict verifies the copied app' codesign --verify --deep --strict --verbose=2 "$app"
step 'Developer ID authority' bash -c "codesign -dvv '$app' 2>&1 | grep -q 'Authority=Developer ID Application'"
step 'spctl accepts the quarantined app (Gatekeeper)' spctl --assess --type execute --verbose=2 "$app"
step 'stapler validates the app ticket' xcrun stapler validate "$app"
hdiutil detach "$mnt" -quiet -force 2>/dev/null; mnt=''
[[ "$failures" -eq 0 ]] || { log "STOP: $failures failure(s) before launch"; exit 1; }

# 4. Real-window first launch and the 3 free sessions, through cua-driver.
perms="$(cua-driver permissions status --json 2>/dev/null || true)"
jq -e '.accessibility == true and .screen_recording == true' >/dev/null 2>&1 <<<"$perms" \
  || { bad 'cua-driver daemon lacks accessibility/screen-recording permission (cua-driver permissions grant)'; exit 1; }
home="$work/home"; mkdir -p "$home"
cua() { cua-driver call "$1" "$2"; }
CFFIXED_USER_HOME="$home" "$app/Contents/MacOS/WriteItDown" >>"$out/app.log" 2>&1 & pid=$!
window_id=''
for _ in {1..40}; do
  window_id="$(cua list_windows "{\"pid\":$pid,\"on_screen_only\":false}" 2>/dev/null \
    | jq -r '[.windows[] | select(.layer == 0 and .title == "Write It Down")][0].window_id // empty' || true)"
  [[ -n "$window_id" ]] && break; sleep 0.5
done
[[ -n "$window_id" ]] && pass 'first launch opens the Write It Down window' || { bad 'no window within 20s'; exit 1; }

n=0; snapf=''
snap() { # snap <name> -> $snapf
  n=$((n + 1)); snapf="$out/$(printf '%02d' "$n")-$1.json"
  cua get_window_state "{\"pid\":$pid,\"window_id\":$window_id,\"screenshot_out_file\":\"${snapf%.json}.png\"}" \
    | jq '{elements: (.structuredContent.elements // .elements), md: (.structuredContent.tree_markdown // .tree_markdown)}' >"$snapf"
}
has() { jq -e --arg t "$1" '.md | contains($t)' >/dev/null "$snapf"; }
token() { jq -r --arg r "$1" --arg l "$2" '[.elements[] | select((.role|ascii_downcase)|contains($r)) | select((.label // "") == $l)][0].element_token // empty' "$snapf"; }
wait_has() { local i; for i in {1..40}; do snap "$1"; has "$2" && return 0; sleep 0.5; done; return 1; }
key() { local t; t="$(jq -r '[.elements[] | select(.role == "AXTextArea")][0].element_token // empty' "$snapf")"
  cua press_key "{\"pid\":$pid,\"window_id\":$window_id,\"element_token\":\"$t\",\"key\":\"$1\"}" >/dev/null; }

wait_has home 'Free trial: 3 of 3 sessions left' && pass 'fresh Mac shows "Free trial: 3 of 3 sessions left."' \
  || { bad 'fresh launch does not show 3 of 3 free sessions'; exit 1; }
for used in 1 2 3; do
  tok="$(token button '1')"; [[ -n "$tok" ]] || { bad "no 1-minute button (session $used)"; exit 1; }
  cua click "{\"pid\":$pid,\"element_token\":\"$tok\"}" >/dev/null
  wait_has "room-$used" 'Start typing' || wait_has "room-$used" 'WORDS' || { bad "session $used room did not open"; exit 1; }
  key a; sleep 0.5; key escape            # first character counts the session
  left=$((3 - used))
  if [[ "$left" -gt 0 ]]; then
    wait_has "home-$used" "Free trial: $left of 3 sessions left" && pass "session $used counted; $left left" \
      || { bad "after session $used the home does not say $left of 3 left"; exit 1; }
  else
    pass 'session 3 typed'
  fi
done
# 5. After the third session, writing needs a license: the activation page.
snap after-third
if ! has 'Activate Write It Down'; then
  tok="$(token button '1')"; [[ -n "$tok" ]] && cua click "{\"pid\":$pid,\"element_token\":\"$tok\"}" >/dev/null
  wait_has activation 'Activate Write It Down' || true
  snap activation
fi
has 'Activate Write It Down' && pass 'after 3 free sessions the activation page appears' \
  || bad 'activation page not shown after the third session'
has 'Start typing.' && bad 'editor is still writable after the free sessions' || pass 'no writable editor after the free sessions'

# 6. Manual remainder.
log "SUMMARY automated failures: $failures (artifacts: $out)"
[[ "$failures" -eq 0 ]] || exit 1
if [[ -n "${WID_DMG_CLEAN_USER_EVIDENCE:-}" && -s "$WID_DMG_CLEAN_USER_EVIDENCE" ]]; then
  log "PASS clean-user evidence supplied: $WID_DMG_CLEAN_USER_EVIDENCE"; exit 0
fi
cat <<'MSG' | tee -a "$out/journey.log"
MANUAL REMAINING (exit 2 until evidence is supplied):
  On a physically clean macOS user (fresh login, never ran Write It Down):
  1. Download the DMG from https://writeitdown.app/download/ in Safari.
  2. Open it, drag Write It Down to /Applications in Finder, eject.
  3. First launch from /Applications: confirm the Gatekeeper dialog names
     "Ziying WANG (Developer ID)" and Open succeeds with no "damaged" warning.
  4. Use 3 free sessions, confirm the activation page after the third.
  Record the screen, then re-run with WID_DMG_CLEAN_USER_EVIDENCE=<recording or note>.
MSG
exit 2
