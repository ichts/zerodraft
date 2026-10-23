#!/usr/bin/env bash
# Assertion chains also fail when their success action fails, not only their condition.
# shellcheck disable=SC2015
# [INPUT] Optional DMG path (default: download https://writeitdown.app/download/Write-It-Down-1.0.dmg)
#         and output dir (default /tmp/wid-dmg-journey/<timestamp>). Env:
#         WID_DMG_URL, WID_DMG_CLEAN_USER_EVIDENCE=<directory> (see MANUAL below).
# [OUTPUT] Per-step PASS/FAIL lines, AX snapshots + screenshots, required screen.mov,
#          app.log, journey.log. Covers input, silence deletion, timed kept/copy,
#          and exhausted-trial activation. Exit 0 only when every automated step
#          passed AND clean-user evidence was supplied;
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
#            scripted from this session. WID_DMG_CLEAN_USER_EVIDENCE must contain
#            a nonempty .mov/.mp4 recording and notes.md or notes.txt for exit 0.
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
# Invoked indirectly by the EXIT trap below.
# shellcheck disable=SC2329
cleanup() {
  local status=$? recorder_status=0 i
  trap - EXIT
  [[ -n "$pid" ]] && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
  if [[ -n "$rec_pid" ]]; then
    if kill -0 "$rec_pid" 2>/dev/null; then
      kill -INT "$rec_pid" 2>/dev/null || bad 'could not stop screen recorder'
      for i in {1..50}; do
        kill -0 "$rec_pid" 2>/dev/null || break
        sleep 0.1
      done
      if kill -0 "$rec_pid" 2>/dev/null; then
        bad 'screen recorder failed to finish after stopping'
        kill -TERM "$rec_pid" 2>/dev/null
      fi
    else
      bad 'screen recorder exited before the journey ended'
    fi
    wait "$rec_pid" || recorder_status=$?
    [[ "$recorder_status" -eq 0 ]] || bad "screen recorder exited with status $recorder_status"
    [[ -s "$out/screen.mov" ]] && pass 'nonempty screen.mov recorded' || bad 'screen.mov missing or empty'
  else
    bad 'screen recorder was not started'
  fi
  [[ -n "$mnt" ]] && hdiutil detach "$mnt" -quiet -force 2>/dev/null
  rm -rf "$work"
  [[ "$failures" -eq 0 ]] || status=1
  log "FINAL automated failures: $failures; exit $status"
  exit "$status"
}
trap cleanup EXIT

[[ ! -e "$out/screen.mov" ]] || { bad 'screen.mov already exists; use a fresh output directory'; exit 1; }
screencapture -v -V 600 "$out/screen.mov" 2>"$out/recorder.log" & rec_pid=$!
sleep 2
if ! kill -0 "$rec_pid" 2>/dev/null; then
  bad 'screen recording failed to start (check terminal screen-recording permission)'
  exit 1
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
type_text() {
  local i char
  for ((i = 0; i < ${#1}; i++)); do
    char="${1:i:1}"
    [[ "$char" == ' ' ]] && char=space
    key "$char" || return 1
    sleep 0.09
  done
}
clock_now() { python3 -c 'import time; print(time.monotonic())'; }

wait_has home 'Free trial: 3 of 3 sessions left' && pass 'fresh Mac shows "Free trial: 3 of 3 sessions left."' \
  || { bad 'fresh launch does not show 3 of 3 free sessions'; exit 1; }
for used in 1 2 3; do
  tok="$(token radio '1 minute')"; [[ -n "$tok" ]] || { bad "no 1-minute radio (session $used)"; exit 1; }
  cua click "{\"pid\":$pid,\"element_token\":\"$tok\"}" >/dev/null
  snap "selected-minute-$used"
  jq -e '[.elements[] | select(.role == "AXRadioButton" and .label == "1 minute" and (.value | tostring) == "1")] | length == 1' "$snapf" >/dev/null \
    || { bad "session $used did not select 1 minute"; exit 1; }
  tok="$(token button 'Begin writing')"; [[ -n "$tok" ]] || { bad "no Begin button (session $used)"; exit 1; }
  cua click "{\"pid\":$pid,\"element_token\":\"$tok\"}" >/dev/null
  wait_has "room-$used" 'Start typing.' || { bad "session $used room did not open"; exit 1; }
  sentence='I watched the rain cross the garden.'
  started="$(clock_now)" || { bad 'monotonic clock unavailable'; exit 1; }
  type_text "$sentence" || { bad "session $used key delivery failed"; exit 1; }
  snap "typed-$used"
  jq -e --arg text "$sentence" '[.elements[] | select(.role == "AXTextArea" and .value == $text)] | length == 1' "$snapf" >/dev/null \
    && pass "session $used editor contains the typed sentence" \
    || { bad "session $used editor text differs from the typed sentence"; exit 1; }
  if [[ "$used" -eq 2 ]]; then
    sleep 9
    snap wiped-second
    has 'Draft deleted at ' && has 'Type to start again.' \
      && jq -e '[.elements[] | select(.role == "AXTextArea" and .value == "")] | length == 1' "$snapf" >/dev/null \
      && ! has 'Copy text' \
      && pass 'session 2 silence deleted the draft with a restart receipt' \
      || { bad 'session 2 did not delete the draft after nine seconds of silence'; exit 1; }
  elif [[ "$used" -eq 3 ]]; then
    typed="$sentence"
    continuation=' The clouds are moving east and the birds have started singing again.'
    i=0
    while python3 -c 'import sys,time; sys.exit(not (time.monotonic() - float(sys.argv[1]) < 57))' "$started"; do
      char="${continuation:i:1}"
      type_text "$char" || { bad 'session 3 continuous input failed'; exit 1; }
      typed="$typed$char"
      i=$(((i + 1) % ${#continuation}))
    done
    wait_has kept-third 'Not saved. Copy it before you leave.' || { bad 'session 3 never reached the kept receipt'; exit 1; }
    python3 -c 'import sys,time; sys.exit(time.monotonic() - float(sys.argv[1]) < 60)' "$started" \
      || { bad 'session 3 completed before a full minute'; exit 1; }
    has '1 minute, done' && has '0:00' && has 'Esc to leave' && ! has 'Draft deleted at ' \
      && jq -e --arg text "$typed" '[.elements[] | select(.role == "AXTextArea" and .value == $text)] | length > 0' "$snapf" >/dev/null \
      || { bad 'session 3 kept text or receipt differs from the completed draft'; exit 1; }
    tok="$(token button 'Copy text')"
    [[ -n "$tok" ]] || { bad 'session 3 COPY TEXT affordance missing'; exit 1; }
    pass 'session 3 completed a full minute with exact kept text and COPY TEXT'
    printf 'journey clipboard sentinel' | pbcopy || { bad 'could not seed clipboard for the copy assertion'; exit 1; }
    cua click "{\"pid\":$pid,\"element_token\":\"$tok\"}" >/dev/null \
      && wait_has copied-third 'Copied' \
      && python3 -c 'import subprocess,sys; sys.exit(subprocess.check_output(["pbpaste"]).decode() != sys.argv[1])' "$typed" \
      && pass 'session 3 copied exactly the kept draft' \
      || { bad 'session 3 copy failed or clipboard differs from kept text'; exit 1; }
    tok="$(token button 'Run it again')"
    [[ -n "$tok" ]] && cua click "{\"pid\":$pid,\"element_token\":\"$tok\"}" >/dev/null \
      || { bad 'session 3 restart affordance missing or failed'; exit 1; }
  fi
  if [[ "$used" -lt 3 ]]; then
    key escape || { bad "session $used exit failed"; exit 1; }
  fi
  left=$((3 - used))
  if [[ "$left" -gt 0 ]]; then
    wait_has "home-$used" "Free trial: $left of 3 sessions left" && pass "session $used counted; $left left" \
      || { bad "after session $used the home does not say $left of 3 left"; exit 1; }
  fi
done
# 5. After the third session, writing needs a license: the activation page.
wait_has activation 'Activate Write It Down' && pass 'after 3 free sessions the activation page appears' \
  || bad 'activation page not shown after the third session'
has 'Start typing.' && bad 'editor is still writable after the free sessions' || pass 'no writable editor after the free sessions'

# 6. Manual remainder.
log "SUMMARY automated failures: $failures (artifacts: $out)"
[[ "$failures" -eq 0 ]] || exit 1
evidence="${WID_DMG_CLEAN_USER_EVIDENCE:-}"
if [[ -d "$evidence" ]]; then
  recording=''
  for candidate in "$evidence"/*.mov "$evidence"/*.mp4; do
    [[ -f "$candidate" && -s "$candidate" ]] && { recording="$candidate"; break; }
  done
  if [[ -n "$recording" ]] && { [[ -f "$evidence/notes.md" && -s "$evidence/notes.md" ]] || [[ -f "$evidence/notes.txt" && -s "$evidence/notes.txt" ]]; }; then
    log "PASS clean-user evidence supplied: $evidence"; exit 0
  fi
fi
cat <<'MSG' | tee -a "$out/journey.log"
MANUAL REMAINING (exit 2 until evidence is supplied):
  On a physically clean macOS user (fresh login, never ran Write It Down):
  1. Download the DMG from https://writeitdown.app/download/ in Safari.
  2. Open it, drag Write It Down to /Applications in Finder, eject.
  3. First launch from /Applications: confirm the Gatekeeper dialog names
     "Ziying WANG (Developer ID)" and Open succeeds with no "damaged" warning.
  4. Use 3 free sessions, confirm the activation page after the third.
  Record the screen, then re-run with WID_DMG_CLEAN_USER_EVIDENCE=<directory>.
  The directory must contain a nonempty .mov or .mp4 recording AND a nonempty
  notes.md or notes.txt describing the user, build checksum, steps and outcomes.
MSG
exit 2
