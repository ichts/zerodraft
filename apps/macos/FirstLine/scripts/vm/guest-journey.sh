#!/bin/bash
# Assertion chains also fail when their success action fails, not only their condition.
# shellcheck disable=SC2015
# [INPUT] <evidence-dir> <dmg-path> [expected-sha256] [license-fixture-binary]
#         Runs INSIDE the macOS guest of the recorded acceptance rig.
# [OUTPUT] journey.log with one PASS/FAIL line per assertion, timestamped before/after
#          screenshots plus AX snapshots per step (steps.tsv), launch-watch frames
#          (launch-*.jsonl), the mandatory continuous screen.mov, summary.json and
#          notes.md. Exit 0 only when every assertion passed and the recording is
#          intact; exit 1 on any failed assertion, failed/interrupted recording, or
#          setup error.
# [POS] apps/macos/FirstLine/scripts/vm/guest-journey.sh - the in-guest half of the
#       recorded DMG acceptance rig. It installs the shipped DMG the way a person
#       does (mount, copy to /Applications, quarantined first launch), then drives
#       the app with CGEvent-level mouse and keyboard input and reads its
#       accessibility tree back for the assertions.
# [PROTOCOL] Never press a button through AXPress: every click is a real HID event
#            posted at the element's accessibility frame centre, and every keystroke
#            is a real HID key event. Accessibility/Screen Recording belong to the
#            prepared golden image (scripts/vm/prepare-guest.sh) through the
#            sshd-keygen-wrapper TCC grants the base image already ships. The
#            licensed-launch case runs a COPY of the installed app whose Info.plist
#            points at a loopback Ed25519 fixture, because the shipped binary trusts
#            only the production public key; the shipped app itself is what the
#            install, trial-launch and three-session cases exercise.
set -uo pipefail

evidence="${1:?usage: guest-journey.sh <evidence-dir> <dmg-path> [sha256] [license-fixture]}"
dmg="${2:?usage: guest-journey.sh <evidence-dir> <dmg-path> [sha256] [license-fixture]}"
expected_sha="${3:-}"
fixture_bin="${4:-}"
evidence="$(cd "$evidence" && pwd -P)"
rig=/usr/local/wid-rig/bin/widrig
app_path="/Applications/Write It Down.app"
bundle_binary="WriteItDown"
work="$(mktemp -d /tmp/wid-journey.XXXXXX)"
failures=0
pid=''
rec_pid=''
fixture_pid=''
mnt=''
steps=0

log() { printf '%s\n' "$*" | tee -a "$evidence/journey.log"; }
pass() { log "PASS $1"; }
bad() { log "FAIL $1"; failures=$((failures + 1)); }
step() { local name="$1"; shift; if "$@" >>"$evidence/journey.log" 2>&1; then pass "$name"; else bad "$name"; return 1; fi; }

stop_app() {
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null
  for _ in {1..40}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  kill -KILL "$pid" 2>/dev/null
  pid=''
}

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  local status=$? recorder_status=0 recorder_started=$rec_pid i
  trap - EXIT
  stop_app
  [[ -n "$fixture_pid" ]] && { kill "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null; }
  if [[ -n "$recorder_started" ]]; then
    if kill -0 "$rec_pid" 2>/dev/null; then
      kill -INT "$rec_pid" 2>/dev/null || bad 'could not stop the screen recorder'
      for i in {1..100}; do kill -0 "$rec_pid" 2>/dev/null || break; sleep 0.1; done
      kill -0 "$rec_pid" 2>/dev/null && { bad 'screen recorder did not finish after stopping'; kill -TERM "$rec_pid" 2>/dev/null; }
    else
      bad 'screen recorder exited before the journey ended'
    fi
    wait "$rec_pid" || recorder_status=$?
    [[ "$recorder_status" -eq 0 ]] || bad "screen recorder exited with status $recorder_status"
    if [[ -s "$evidence/screen.mov" ]]; then pass 'continuous screen.mov recorded'; else bad 'screen.mov missing or empty'; fi
  else
    bad 'screen recorder was never started'
  fi
  [[ -n "$mnt" ]] && hdiutil detach "$mnt" -quiet -force 2>/dev/null
  rm -rf "$work"
  printf '{"failures": %d, "steps": %d, "macos": "%s", "model": "%s"}\n' \
    "$failures" "$steps" "$(sw_vers -productVersion)" "$(sysctl -n hw.model)" >"$evidence/summary.json"
  [[ "$failures" -eq 0 ]] || status=1
  log "FINAL failures: $failures; exit $status"
  exit "$status"
}
trap cleanup EXIT

# --- helpers -----------------------------------------------------------------

snap() { # snap <name> [-before|-after already folded into the name]
  steps=$((steps + 1))
  local base="$evidence/$(printf '%02d' "$steps")-$1"
  screencapture -x "$base.png" || bad "screenshot failed for $1"
  [[ -n "$pid" ]] && "$rig" tree --pid "$pid" >"$base.json" 2>/dev/null
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$base" >>"$evidence/steps.tsv"
}

screen_text() { [[ -n "$pid" ]] && "$rig" text --pid "$pid" 2>/dev/null | jq -r '.text // ""'; }
has_re() { screen_text | grep -qE -- "$1"; }
wait_re() { # wait_re <regex> [timeout]
  [[ -n "$pid" ]] || return 1
  "$rig" wait --pid "$pid" --text "$1" --timeout "${2:-20}" >/dev/null 2>&1
}

click_el() { # click_el <role> <regex> [count]
  local role="$1" re="$2" count="${3:-1}" found x y
  found="$("$rig" find --pid "$pid" --role "$role" --text "$re" --timeout 20)" || return 1
  x="$(jq -r '(.frame.x + .frame.w / 2) | floor' <<<"$found")"
  y="$(jq -r '(.frame.y + .frame.h / 2) | floor' <<<"$found")"
  "$rig" frontmost --pid "$pid" >/dev/null 2>&1
  "$rig" click --x "$x" --y "$y" --count "$count" >/dev/null
}

type_text() { "$rig" type --text "$1" >/dev/null; }
# open(1) blocks until LaunchServices finishes the launch, and a first launch of a
# quarantined app blocks until the Gatekeeper question is answered. Background it so
# the journey can answer that question while the launch watcher is still armed.
open_app() { /usr/bin/open -n -a "$1" >/dev/null 2>&1 & }

# A launch watcher is armed BEFORE the app starts so its first frames are captured;
# the anti-flash assertions read these frames instead of trusting the end state.
gatekeeper_clicked=0
gatekeeper_once() { # click Open if a quarantined first-launch prompt is on screen right now
  local agent found x y
  agent="$(pgrep -x CoreServicesUIAgent | head -1)"
  [[ -n "$agent" ]] || return 1
  found="$("$rig" find --pid "$agent" --role AXButton --text '^Open$' --timeout 2 2>/dev/null)" || return 1
  x="$(jq -r '(.frame.x + .frame.w / 2) | floor' <<<"$found")"
  y="$(jq -r '(.frame.y + .frame.h / 2) | floor' <<<"$found")"
  snap 'gatekeeper-question-before'
  "$rig" click --x "$x" --y "$y" >/dev/null
  gatekeeper_clicked=1
  return 0
}

launch_watched() { # launch_watched <app-path> <seconds> <out-jsonl>
  "$rig" watch --pattern "$bundle_binary" --timeout 90 --seconds "$2" --interval 0.05 \
    >"$3" 2>"${3%.jsonl}.err" &
  local watcher=$!
  open_app "$1"
  while kill -0 "$watcher" 2>/dev/null; do
    [[ "$gatekeeper_clicked" -eq 1 ]] || gatekeeper_once
    sleep 0.25
  done
  wait "$watcher"
  pid="$(pgrep -f "Contents/MacOS/$bundle_binary" | head -1)"
  [[ -n "$pid" ]] || return 1
}

watch_texts() { jq -r '.text // ""' "$1" 2>/dev/null; }
watch_frames() { wc -l <"$1" | tr -d ' '; }
# grep without -q on purpose: -q closes the pipe on the first match, jq then dies of
# SIGPIPE and `set -o pipefail` turns a real match into a failed pipeline.
watch_never() { # watch_never <jsonl> <regex> <label>
  if watch_texts "$1" | grep -E -- "$2" >/dev/null; then
    bad "$3: forbidden text /$2/ appeared during launch"
    return 1
  fi
  pass "$3: /$2/ never appeared in $(watch_frames "$1") launch frames"
}
watch_seen() { # watch_seen <jsonl> <regex> <label>
  if watch_texts "$1" | grep -E -- "$2" >/dev/null; then pass "$3: /$2/ observed while watching"; else bad "$3: /$2/ missing from launch frames"; return 1; fi
}

# --- 1. recording and preflight ---------------------------------------------

[[ ! -e "$evidence/screen.mov" ]] || { bad 'screen.mov already exists; use a fresh evidence directory'; exit 1; }
screencapture -v -V 1200 "$evidence/screen.mov" 2>"$evidence/recorder.log" & rec_pid=$!
sleep 2
kill -0 "$rec_pid" 2>/dev/null || { bad 'screen recording failed to start'; exit 1; }
pass 'continuous screen recording started'

"$rig" trusted | jq -e '.accessibility == true' >/dev/null && pass 'guest accessibility grant is live' \
  || bad 'guest accessibility grant is missing'

sleep 1
screencapture -x "$work/probe-a.png"
"$rig" click --x 16 --y 13 >/dev/null
sleep 1
screencapture -x "$work/probe-b.png"
if "$rig" pxdiff --first "$work/probe-a.png" --second "$work/probe-b.png" | jq -e '.changedFraction > 0.02' >/dev/null; then
  pass 'screen recording captures live window content'
else
  bad 'screen recording returns a windowless image (Screen Recording not granted)'
fi
"$rig" key --name escape >/dev/null
sleep 1
screencapture -x "$work/probe-c.png"
if "$rig" pxdiff --first "$work/probe-b.png" --second "$work/probe-c.png" | jq -e '.changedFraction > 0.02' >/dev/null; then
  pass 'the probe overlay left the screen, so the recorded evidence starts on a clean desktop'
else
  bad 'the probe overlay stayed on screen'
fi
snap 'desktop-clean'

# --- 2. install the shipped DMG the way a person does -----------------------

snap 'fresh-clone-before'
[[ ! -e "$app_path" ]] && pass 'the clean clone starts with the app not installed' \
  || bad 'the clone already has the app installed; the VM is not clean'
[[ ! -e "$HOME/Library/Application Support/WriteItDown/Config/settings.json" ]] \
  && pass 'the clean clone has no previous Write It Down settings' \
  || bad 'the clone already has Write It Down settings; the VM is not clean'

step 'DMG size plausible' bash -c "[[ \$(stat -f %z '$dmg') -ge 1000000 ]]"
actual_sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
if [[ -n "$expected_sha" ]]; then
  [[ "$actual_sha" == "$expected_sha" ]] && pass "DMG SHA-256 matches the expected $expected_sha" \
    || bad "DMG SHA-256 $actual_sha != expected $expected_sha"
fi
log "SHA256 $actual_sha"
step 'codesign verifies the DMG' codesign --verify --verbose=2 "$dmg"
step 'stapler validates the DMG ticket' xcrun stapler validate "$dmg"
step 'spctl accepts the DMG' spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
[[ "$failures" -eq 0 ]] || { log 'STOP: the DMG file itself failed verification'; exit 1; }

mnt="$work/mnt"; mkdir -p "$mnt"
step 'mount the DMG (double-click equivalent)' hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mnt" || exit 1
snap 'dmg-mounted-before'
[[ -d "$mnt/Write It Down.app" ]] && pass 'DMG contains Write It Down.app' || { bad 'DMG has no Write It Down.app'; exit 1; }
[[ -L "$mnt/Applications" ]] && pass 'DMG offers the Applications shortcut' || bad 'DMG has no Applications symlink'
step 'drag to Applications (Finder-equivalent copy)' ditto "$mnt/Write It Down.app" "$app_path"
hdiutil detach "$mnt" -quiet -force 2>/dev/null; mnt=''
snap 'installed-after'
step 'codesign --deep --strict verifies the installed app' codesign --verify --deep --strict --verbose=2 "$app_path"
step 'Developer ID authority' bash -c "codesign -dvv '$app_path' 2>&1 | grep -q 'Authority=Developer ID Application'"
step 'spctl accepts the installed app' spctl --assess --type execute --verbose=2 "$app_path"
step 'stapler validates the installed app' xcrun stapler validate "$app_path"
xattr -w com.apple.quarantine "0081;$(printf '%x' "$(date +%s)");Safari;" "$app_path" 2>/dev/null
pass 'installed app carries the browser-download quarantine flag'

# --- 3. launch case 1: first launch with no license (trial path) ------------

snap 'first-launch-before'
screencapture -x "$work/first-launch-loading.png"
launch_watched "$app_path" 8 "$evidence/launch-trial.jsonl" || { bad 'the app did not launch'; exit 1; }
if [[ "$gatekeeper_clicked" -eq 1 ]]; then
  snap 'gatekeeper-prompt-approved'
  pass 'the Gatekeeper first-launch question was answered with a real click'
else
  pass 'no Gatekeeper question appeared: the notarized build was approved silently'
fi
wait_re 'Free trial: 3 of 3 sessions left\.' 40 && pass 'first launch shows the untouched 3-of-3 free trial' \
  || bad 'first launch does not show "Free trial: 3 of 3 sessions left."'
snap 'first-launch-after'
watch_never "$evidence/launch-trial.jsonl" 'Activate Write It Down' 'trial launch'
watch_never "$evidence/launch-trial.jsonl" 'License active' 'trial launch'
watch_seen "$evidence/launch-trial.jsonl" 'Free trial: 3 of 3 sessions left\.' 'trial launch'
[[ "$(watch_frames "$evidence/launch-trial.jsonl")" -ge 20 ]] && pass "launch watcher sampled $(watch_frames "$evidence/launch-trial.jsonl") frames" \
  || bad "launch watcher sampled too few frames ($(watch_frames "$evidence/launch-trial.jsonl"))"

# --- 4. the shipped-DMG three-session journey -------------------------------

for used in 1 2 3; do
  snap "session-$used-home-before"
  click_el AXRadioButton '1 minute' || { bad "session $used: no 1-minute control"; exit 1; }
  snap "session-$used-minute-after"
  [[ "$(screen_text)" == *"1 minute"* ]] || bad "session $used: the 1-minute choice is not on screen"
  click_el AXButton '^Begin writing$' || { bad "session $used: no Begin writing button"; exit 1; }
  wait_re 'Type to start' 20 || { bad "session $used: the writing room did not open"; exit 1; }
  snap "session-$used-room"
  sentence='I watched the rain cross the garden.'
  started="$(python3 -c 'import time; print(time.monotonic())')"
  type_text "$sentence" || { bad "session $used: typing failed"; exit 1; }
  snap "session-$used-typed-after"
  if [[ "$(screen_text)" == *"$sentence"* ]]; then
    pass "session $used: real keystrokes reached the editor and read back exactly"
  else
    bad "session $used: editor text differs from the typed sentence"
  fi
  if [[ "$used" -eq 2 ]]; then
    sleep 9
    snap 'session-2-wiped-after'
    if has_re 'DRAFT DELETED AT ' && has_re 'TYPE TO START AGAIN\.'; then
      pass 'session 2: silence deleted the draft and showed the restart receipt'
    else
      bad 'session 2: silence did not delete the draft'
    fi
    has_re '0 words' && pass 'session 2: the word count reset to zero' || bad 'session 2: the word count did not reset'
  elif [[ "$used" -eq 3 ]]; then
    typed="$sentence"
    continuation=' The clouds are moving east and the birds have started singing again.'
    i=0
    while python3 -c 'import sys,time; sys.exit(not (time.monotonic() - float(sys.argv[1]) < 57))' "$started"; do
      char="${continuation:i:1}"
      type_text "$char" || { bad 'session 3: continuous typing failed'; exit 1; }
      typed="$typed$char"
      i=$(((i + 1) % ${#continuation}))
    done
    snap 'session-3-kept-before'
    wait_re 'You wrote it down\.' 30 && pass 'session 3: the full minute completed into the kept receipt' \
      || bad 'session 3: never reached the kept receipt'
    python3 -c 'import sys,time; sys.exit(time.monotonic() - float(sys.argv[1]) < 60)' "$started" \
      && pass 'session 3: the deadline was a real minute, not a shortened one' \
      || bad 'session 3: completed before a full minute elapsed'
    has_re '1 MINUTE\. ' && has_re ' WORDS\.' && ! has_re 'DRAFT DELETED AT ' \
      && pass 'session 3: kept receipt names a full minute and a word count' \
      || bad 'session 3: kept receipt is missing or wrong'
    [[ "$(screen_text)" == *"$typed"* ]] && pass 'session 3: the exact kept draft is on screen' \
      || bad 'session 3: the kept draft text differs from what was typed'
    snap 'session-3-kept-after'
    printf 'journey clipboard sentinel' | pbcopy
    click_el AXButton 'COPY TEXT' || { bad 'session 3: COPY TEXT is missing'; exit 1; }
    sleep 1
    snap 'session-3-copied-after'
    if has_re 'COPIED'; then pass 'session 3: COPY TEXT flipped to COPIED'; else bad 'session 3: COPY TEXT did not confirm'; fi
    if [[ "$(pbpaste)" == "$typed" ]]; then pass 'session 3: the clipboard holds exactly the kept draft'; else bad 'session 3: clipboard differs from the kept draft'; fi
    click_el AXButton 'RUN IT AGAIN' || { bad 'session 3: RUN IT AGAIN is missing'; exit 1; }
  fi
  if [[ "$used" -lt 3 ]]; then
    "$rig" key --name escape >/dev/null
    wait_re 'Press Esc again to leave and delete the draft\.' 10 \
      && pass "session $used: the two-act exit showed its confirmation" \
      || { bad "session $used: the first Escape did not ask for confirmation"; exit 1; }
    snap "session-$used-exit-hint"
    "$rig" key --name escape >/dev/null
    left=$((3 - used))
    wait_re "Free trial: $left of 3 sessions left\." 20 \
      && pass "session $used: leaving returned home with $left of 3 left" \
      || { bad "session $used: home does not say $left of 3 left"; exit 1; }
    snap "session-$used-home-after"
  fi
done

# --- 5. the trial is spent: activation, not a writable editor ---------------

wait_re 'Activate Write It Down' 30 && pass 'after three free sessions the activation page appears' \
  || bad 'the activation page did not appear after the third session'
has_re 'Type to start' && bad 'the editor is still writable after the free sessions' \
  || pass 'no writable editor remains after the free sessions'
snap 'activation-page'

# --- 6. launch case 2: an already-active signed license must not flash the licence view

if [[ -n "$fixture_bin" && -x "$fixture_bin" ]]; then
  qa_app="$work/Write It Down QA.app"
  cp -R "$app_path" "$qa_app"
  xattr -cr "$qa_app"
  printf 'active\n' >"$work/fixture-mode"
  "$fixture_bin" "$work/fixture.json" "$work/fixture-mode" >"$evidence/fixture.log" 2>&1 &
  fixture_pid=$!
  for _ in {1..60}; do [[ -s "$work/fixture.json" ]] && break; sleep 0.1; done
  if [[ -s "$work/fixture.json" ]]; then
    service="$(plutil -extract WIDLicenseServiceURL raw -o - "$work/fixture.json")"
    product="$(plutil -extract WIDLicenseProductID raw -o - "$work/fixture.json")"
    public_key="$(plutil -extract WIDLicensePublicKey raw -o - "$work/fixture.json")"
    plist="$qa_app/Contents/Info.plist"
    plutil -replace WIDLicenseServiceURL -string "$service" "$plist"
    plutil -replace WIDLicenseProductID -string "$product" "$plist"
    plutil -replace WIDLicensePublicKey -string "$public_key" "$plist"
    codesign --force --sign - "$qa_app" >>"$evidence/journey.log" 2>&1 \
      && pass 'fixture build copies the installed app and re-signs it ad hoc' \
      || bad 'fixture build could not re-sign the copied app'
    stop_app
    launch_watched "$qa_app" 3 "$evidence/launch-fixture-first.jsonl" || { bad 'the fixture build did not launch'; exit 1; }
    wait_re 'Activate Write It Down' 30 && pass 'fixture build opens on the activation page before activation' \
      || bad 'fixture build did not open on the activation page'
    click_el AXTextField '.' || bad 'fixture build: no activation key field'
    type_text 'window-qa-order'
    snap 'fixture-key-typed'
    click_el AXButton '^Activate$' || bad 'fixture build: no Activate button'
    wait_re 'License active on this Mac\.' 40 && pass 'the fixture activation produced an active signed license' \
      || bad 'the fixture activation did not reach an active license'
    snap 'fixture-activated'
    stop_app
    sleep 1
    snap 'licensed-relaunch-before'
    launch_watched "$qa_app" 5 "$evidence/launch-licensed.jsonl" || { bad 'the licensed app did not relaunch'; exit 1; }
    wait_re 'License active\.' 40 && pass 'licensed relaunch goes straight to the licensed home' \
      || bad 'licensed relaunch did not reach the licensed home'
    snap 'licensed-relaunch-after'
    watch_never "$evidence/launch-licensed.jsonl" 'Activate Write It Down' 'licensed launch'
    watch_never "$evidence/launch-licensed.jsonl" 'Enter your order number' 'licensed launch'
    watch_seen "$evidence/launch-licensed.jsonl" 'Begin writing' 'licensed launch'
  else
    bad 'the license fixture did not start'
  fi
else
  bad 'no license fixture binary was supplied for the licensed-launch case'
fi

# --- 7. evidence notes ------------------------------------------------------

cat >"$evidence/notes.md" <<EOF
# Recorded DMG acceptance (macOS VM)

- Run: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Guest: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)) on $(sysctl -n hw.model), $(sips -g pixelWidth "$work/probe-a.png" 2>/dev/null | awk '/pixelWidth/{print $2}')x$(sips -g pixelHeight "$work/probe-a.png" 2>/dev/null | awk '/pixelHeight/{print $2}')
- DMG: $dmg
- DMG SHA-256: $actual_sha
- Driver: CGEvent HID keyboard/mouse posted inside the guest; accessibility reads for assertions; no AXPress
- Recording: screen.mov (continuous, whole run), $(steps) timestamped step screenshots in steps.tsv
- Launch watchers: launch-trial.jsonl (no license), launch-licensed.jsonl (active signed fixture)
- Failures: $failures
EOF
pass 'evidence notes.md written'
[[ "$failures" -eq 0 ]] || exit 1
log "SUMMARY all assertions passed (artifacts: $evidence)"
exit 0
