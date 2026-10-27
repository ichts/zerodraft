#!/usr/bin/env bash
# [INPUT] Optional screenshot/output directory (default /tmp/wid-qa/cua-<timestamp>);
#         app under test packaged at WID_APP_OUTPUT or dist/Write It Down.app.
#         Spends three native trial sessions, then activates a copied app through a disposable loopback fixture,
#         never a Waffo purchase. WID_QA_LICENSE_ONLY=1 skips motion timing checks.
#         WID_QA_THEME=light|dark presets appearance only, never entitlement.
# [OUTPUT] Per-stage screenshots, AX snapshots, geometry.jsonl (element frames and
#          the cross-element frame comparisons), app.log, and timing.txt in the
#          output directory; exit 0 only when every assertion below holds.
#          AX exposes no insertion-point frame, so caret/placeholder/first-glyph
#          equality is bound to RoundThreeTests in the deterministic suite.
# [POS] apps/macos/FirstLine/scripts/qa-window.sh — real-window acceptance driven
#       through the cua-driver daemon (roadmap report section 6.9).
# [PROTOCOL] Accessibility/screen-recording permission belongs to the running
#            cua-driver daemon (com.trycua.driver), so this background shell needs
#            no TCC grants of its own. The app is launched directly (binary path,
#            fresh CFFIXED_USER_HOME) and every action is background-delivered:
#            no focus steal, no Computer Use dependency. Keys are addressed at the
#            room's AXTextArea token so delivery is read-back confirmed. Warn/wipe
#            waits poll the full AX tree; a no-match driver query returns an empty
#            tree and can stall the snapshot.
set -euo pipefail

cd "$(dirname "$0")/.."
output="${1:-/tmp/wid-qa/cua-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$output"
output="$(cd "$output" && pwd -P)"   # screenshot_out_file refuses symlinked ancestors

perms="$(cua-driver permissions status --json 2>/dev/null || true)"
if ! jq -e '.accessibility == true and .screen_recording == true' >/dev/null 2>&1 <<<"$perms"; then
  echo 'cua-driver daemon lacks accessibility/screen-recording permission; run: cua-driver permissions grant' >&2
  exit 1
fi

scripts/package-app.sh --adhoc
app="${WID_APP_OUTPUT:-$PWD/dist/Write It Down.app}"
bin="$app/Contents/MacOS/WriteItDown"
qa_home="$(mktemp -d "${TMPDIR:-/tmp}/wid-qa-home.XXXXXX")"
qa_home="$(cd "$qa_home" && pwd -P)"
pid=''
fixture_pid=''
license_only="${WID_QA_LICENSE_ONLY:-0}"
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  if [[ -n "$fixture_pid" ]]; then kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; fi
  rm -rf "$qa_home"
}
trap cleanup EXIT

go build -o "$output/license-fixture" scripts/qa-license-fixture.go
  printf 'active\n' >"$output/fixture-mode"
  "$output/license-fixture" "$qa_home/fixture.json" "$output/fixture-mode" >"$output/fixture.log" 2>&1 &
  fixture_pid=$!
  for _ in {1..40}; do [[ -s "$qa_home/fixture.json" ]] && break; sleep 0.1; done
  qa_app="$qa_home/Write It Down QA.app"
  cp -R "$app" "$qa_app"
  python3 - "$qa_app/Contents/Info.plist" "$qa_home/fixture.json" <<'PY'
import json, plistlib, sys
with open(sys.argv[1], 'rb') as f:
    config = plistlib.load(f)
with open(sys.argv[2]) as f:
    config.update(json.load(f))
config['WIDCheckoutURL'] = ''
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(config, f)
PY
  codesign --force --sign - "$qa_app"
  bin="$qa_app/Contents/MacOS/WriteItDown"

cua() { cua-driver call "$1" "$2"; }

launch_app() {
  CFFIXED_USER_HOME="$qa_home" "$bin" >>"$output/app.log" 2>&1 &
  pid=$!
  window_id=''
  for _ in {1..40}; do
    window_id="$(cua list_windows "{\"pid\":$pid,\"on_screen_only\":false}" 2>/dev/null \
      | jq -r '[.windows[] | select(.layer == 0 and .title == "Write It Down")][0].window_id // empty' || true)"
    [[ -n "$window_id" ]] && break
    sleep 0.5
  done
  if [[ -z "$window_id" ]]; then
    echo 'No Write It Down window appeared within 20s' >&2
    exit 1
  fi
}
if [[ -n "${WID_QA_THEME:-}" ]]; then
  case "$WID_QA_THEME" in light|dark) ;; *) echo 'WID_QA_THEME must be light or dark' >&2; exit 2 ;; esac
  config="$qa_home/Library/Application Support/WriteItDown/Config"
  mkdir -p "$config"
  printf '{"theme":"%s","defaultDuration":60,"reducedMotion":"always"}\n' "$WID_QA_THEME" >"$config/settings.json"
fi
launch_app

fail() {
  echo "FAIL: $1" >&2
  exit 1
}


# Frame of the first element with this role whose text matches (regex, jq syntax).
frame_of() { # frame_of <snapshot-file> <role> <regex>
  jq -c --arg r "$2" --arg re "$3" '
    [.elements[] | select(.role == $r)
      | select((((.value // .label) // "") | tostring) | test($re))][0]
    | if . == null then empty
      else {role: $r, text: (((.value // .label) // "") | tostring),
            x: .frame.x, y: .frame.y, w: .frame.w, h: .frame.h} end
  ' "$1"
}

record_geometry() { # record_geometry <stage> <json-object>
  jq -cn --arg stage "$1" --argjson g "$2" '{stage: $stage, geometry: $g}' >>"$output/geometry.jsonl"
}

# The empty room has no hint near the line; its instruction is the bottom-right
# count prompt ("Type to start"), which must share the footer row with ESC - EXIT.
# AX has no caret frame, so the caret/line origin equality is bound to the
# deterministic RoundThreeTests.
assert_room_geometry() { # assert_room_geometry <room-snapshot>
  local ta prompt exit
  ta="$(frame_of "$1" AXTextArea '')"
  prompt="$(frame_of "$1" AXStaticText '^Type to start$')"
  exit="$(frame_of "$1" AXButton '^ESC - EXIT$')"
  [[ -n "$ta" && -n "$prompt" && -n "$exit" ]] || fail 'room geometry: missing text area, count prompt or exit frame'
  record_geometry room "$(jq -cn --argjson ta "$ta" --argjson prompt "$prompt" --argjson exit "$exit" \
    '{textArea: $ta, countPrompt: $prompt, exit: $exit}')"
  jq -en --argjson prompt "$prompt" --argjson exit "$exit" '
    def d(a; b): (a - b) | if . < 0 then -. else . end;
    d(($prompt.y + $prompt.h / 2); ($exit.y + $exit.h / 2)) <= 1
  ' >/dev/null || fail 'the Type to start prompt is not on the footer row'
}

# The numeral is directly under the writing line: its top is above the text
# area's vertical centre, and the caption sits below the numeral but inside the
# text area (never at the paper's bottom edge).
assert_warn_geometry() { # assert_warn_geometry <warn-snapshot>
  local ta num hint
  ta="$(frame_of "$1" AXTextArea '')"
  num="$(frame_of "$1" AXStaticText '^[123]$')"
  hint="$(frame_of "$1" AXStaticText '^KEEP TYPING OR THE DRAFT IS DELETED\.$')"
  [[ -n "$ta" && -n "$num" && -n "$hint" ]] || fail 'warn geometry: missing text area, numeral or caption frame'
  record_geometry warn "$(jq -cn --argjson ta "$ta" --argjson num "$num" --argjson hint "$hint"     '{textArea: $ta, numeral: $num, caption: $hint}')"
  jq -en --argjson ta "$ta" --argjson num "$num" --argjson hint "$hint" '
    def d(a; b): (a - b) | if . < 0 then -. else . end;
    (($num.y + $num.h) > ($ta.y + $ta.h / 2))
    and (($hint.y + $hint.h) < ($num.y + 1))
    and ($hint.y > ($ta.y + 16))
  ' >/dev/null || fail 'the warning numeral/caption is not under the writing line'
}

# The inline confirmation, the ESC - EXIT link and the count share one row.
# Equal centres plus the shared 13 pt 1.6 line box put all three on one baseline;
# the caption's exact baseline equality is measured in RoundThreeTests.
assert_exit_row_geometry() { # assert_exit_row_geometry <snapshot>
  local exit hint count
  exit="$(frame_of "$1" AXButton '^ESC - EXIT$')"
  hint="$(frame_of "$1" AXStaticText '^Press Esc again to leave and delete the draft\.$')"
  count="$(frame_of "$1" AXStaticText '^([0-9]+ words?|Type to start)$')"
  [[ -n "$exit" && -n "$hint" && -n "$count" ]] || fail 'exit row geometry: missing a row element'
  record_geometry exit-row "$(jq -cn --argjson exit "$exit" --argjson hint "$hint" --argjson count "$count"     '{exit: $exit, confirmation: $hint, count: $count}')"
  jq -en --argjson exit "$exit" --argjson hint "$hint" --argjson count "$count" '
    def d(a; b): (a - b) | if . < 0 then -. else . end;
    d(($hint.y + $hint.h / 2); ($exit.y + $exit.h / 2)) <= 1
    and d(($count.y + $count.h / 2); ($exit.y + $exit.h / 2)) <= 1
    and ($hint.h >= 20) and ($count.h >= 20)
  ' >/dev/null || fail 'the exit row is not on one baseline'
}

# The daemon reports actionable elements separately from static AX tree text.
normalize() {
  jq '{
    elements: (.structuredContent.elements // .elements),
    window_markdown: ((.structuredContent.tree_markdown // .tree_markdown)
      | split("\n") | map(select(test("AXMenu") | not)) | join("\n")),
    window_title: (.structuredContent.window_title // .window_title)
  }'
}

# Full snapshot: AX tree + evidence PNG. Replaces the daemon's snapshot cache, so
# every call re-reads the fresh AXTextArea token used by press().
snap_n=0
snap() { # snap <name> [query]
  local name="$1" query="${2:-}" file args json
  snap_n=$((snap_n + 1))
  file="$output/$(printf '%02d' "$snap_n")-$name"
  args="{\"pid\":$pid,\"window_id\":$window_id,\"screenshot_out_file\":\"$file.png\""
  if [[ -n "$query" ]]; then args="$args,\"query\":\"$query\""; fi
  args="$args}"
  json="$(cua get_window_state "$args" | normalize)"
  printf '%s\n' "$json" >"$file.json"
  ta_token="$(jq -r '[.elements[] | select(.role == "AXTextArea")][0].element_token // empty' "$file.json")"
  printf '%s\n' "$json"
}

# Cheap poll: AX only, no capture; used while racing the warn window. Also keeps
# its JSON at last-poll.json for the caller. The second argument is a caller label
# only: do not send it as a driver query, because a miss empties the tree.
poll() { # poll <name> [label]
  local name="$1" file json
  snap_n=$((snap_n + 1))
  file="$output/$(printf '%02d' "$snap_n")-$name"
  json="$(cua get_window_state "{\"pid\":$pid,\"window_id\":$window_id,\"include_screenshot\":false}" | normalize)"
  printf '%s\n' "$json" | tee "$file.json" >"$output/last-poll.json"
  ta_token="$(jq -r '[.elements[] | select(.role == "AXTextArea")][0].element_token // empty' "$output/last-poll.json")"
}

assert_text() { # assert_text <snapshot-file> <substring>
  jq -e --arg t "$2" '.window_markdown | contains($t)' >/dev/null "$1" \
    || fail "expected AX text '$2' in $(basename "$1")"
}

absent_text() { # absent_text <snapshot-file> <substring>
  jq -e --arg t "$2" '(.window_markdown | contains($t)) | not' >/dev/null "$1" \
    || fail "AX text '$2' must be absent in $(basename "$1")"
}

draft_value() { jq -r '[.elements[] | select(.role == "AXTextArea")][0].value // empty' "$1"; }

token_of() { # token_of <snapshot-file> <role-substring> <label>
  jq -r --arg r "$2" --arg l "$3" \
    '[.elements[] | select((.role | ascii_downcase) | contains($r)) | select((.label // "") == $l)][0].element_token // empty' "$1"
}

press() {
  [[ -n "$ta_token" ]] || fail 'no live AXTextArea token for key delivery'
  cua press_key "{\"pid\":$pid,\"window_id\":$window_id,\"element_token\":\"$ta_token\",\"key\":\"$1\"}" >/dev/null
}

type_text() {
  local char i
  for ((i = 0; i < ${#1}; i++)); do
    char="${1:i:1}"
    [[ "$char" == ' ' ]] && char='space'
    press "$char"
  done
}

assert_exit_hint() { # first Escape/click must arm the inline confirmation, not leave
  poll exit-hint
  assert_text "$output/last-poll.json" 'Press Esc again to leave and delete the draft.'
  assert_exit_row_geometry "$output/last-poll.json"
}

exit_room_by_key() {
  press escape
  assert_exit_hint
  press escape
}

exit_room_by_click() {
  local token
  poll exit-before-click
  token="$(token_of "$output/last-poll.json" button 'ESC - EXIT')"
  [[ -n "$token" ]] || fail 'no ESC - EXIT button in the room'
  cua click "{\"pid\":$pid,\"element_token\":\"$token\"}" >/dev/null
  assert_exit_hint
  token="$(token_of "$output/last-poll.json" button 'ESC - EXIT')"
  [[ -n "$token" ]] || fail 'no ESC - EXIT button after the exit hint'
  cua click "{\"pid\":$pid,\"element_token\":\"$token\"}" >/dev/null
}

wait_text() { # wait_text <stage> <ax-query> <expected-substring> <max-polls>
  local stage="$1" query="$2" text="$3" max="$4" i
  for ((i = 1; i <= max; i++)); do
    poll "$stage-wait" "$query"
    if jq -e --arg t "$text" '.window_markdown | contains($t)' >/dev/null 2>&1 "$output/last-poll.json"; then
      matched_at="$(python3 -c 'import time; print(time.monotonic())')"
      cp "$output/last-poll.json" "$output/last-match.json"
      return 0
    fi
    sleep 0.4
  done
  fail "timed out waiting for AX text '$text'"
}

clock_now() { python3 -c 'import time; print(time.monotonic())'; }

assert_timing() {
  local tier="$1" phase="$2" start="$3" end="$4" lower="$5" upper="$6" elapsed
  elapsed="$(awk -v start="$start" -v end="$end" 'BEGIN { printf "%.3f", end - start }')"
  printf '%s %s %ss\n' "$tier" "$phase" "$elapsed" >>"$output/timing.txt"
  awk -v elapsed="$elapsed" -v lower="$lower" -v upper="$upper" \
    'BEGIN { exit !(elapsed >= lower && elapsed <= upper) }' \
    || fail "$tier $phase observed at ${elapsed}s, outside ${lower}-${upper}s"
}

enter_room() { # enter_room <home-snapshot>
  local token
  token="$(token_of "$1" radio '1 minute')"
  [[ -n "$token" ]] || fail 'no element token for the 1-minute radio'
  cua click "{\"pid\":$pid,\"element_token\":\"$token\"}" >/dev/null
  snap selected-minute >"$output/selected-minute.json"
  jq -e '[.elements[] | select(.role == "AXRadioButton" and .label == "1 minute" and (.value | tostring) == "1")] | length == 1' \
    >/dev/null "$output/selected-minute.json" || fail '1 minute is not selected'
  token="$(token_of "$output/selected-minute.json" button 'Begin writing')"
  [[ -n "$token" ]] || fail 'no element token for Begin'
  cua click "{\"pid\":$pid,\"element_token\":\"$token\"}" >/dev/null
}

select_tier() { # select_tier <home-snapshot> <label> <tier>
  local token
  token="$(token_of "$1" radio "$2")"
  [[ -n "$token" ]] || fail "no radio button for '$2'"
  cua click "{\"pid\":$pid,\"element_token\":\"$token\"}" >/dev/null
  snap "selected-$3" >"$output/selected-$3.json"
  assert_text "$output/selected-$3.json" "$2"
  jq -e --arg label "$2" '[.elements[] | select(.role == "AXRadioButton" and .label == $label and (.value | tostring) == "1")] | length == 1' \
    >/dev/null "$output/selected-$3.json" || fail "'$2' radio is not selected"
}

check_warn_recovery_wipe() {
  local tier="$1" max="$2" before="$3" limit="$4" warn_start="$5"
  local warn="$output/$tier-warn.json" recovered="$output/$tier-recovered.json" wiped="$output/$tier-wiped.json" wipe_start warn_min warn_max
  warn_min="$(awk -v t="$limit" 'BEGIN { print t - 3 - 0.5 }')"
  warn_max="$(awk -v t="$limit" 'BEGIN { print t - 3 + 2.5 }')"
  wait_text "$tier-warn" 'KEEP TYPING OR THE DRAFT IS DELETED.' 'KEEP TYPING OR THE DRAFT IS DELETED.' "$max"
  assert_timing "$tier" warn "$warn_start" "$matched_at" "$warn_min" "$warn_max"
  snap "$tier-warn-full" >"$warn"
  assert_text "$warn" 'KEEP TYPING OR THE DRAFT IS DELETED.'
  assert_text "$warn" 'ESC - EXIT'
  jq -e '.window_markdown | test("AXStaticText = .[1-3].")' >/dev/null "$warn" \
    || fail "$tier warn state has no 3-2-1 numeral in AX"
  assert_warn_geometry "$warn"
  wipe_start="$(clock_now)"
  press k
  snap "$tier-recovered-state" >"$recovered"
  absent_text "$recovered" 'KEEP TYPING'
  [[ "$(draft_value "$recovered")" == "${before}k" ]] || fail "$tier recovery lost draft"
  wait_text "$tier-wiped" 'You stopped.' 'You stopped.' "$max"
  assert_timing "$tier" wipe "$wipe_start" "$matched_at" "$(awk -v t="$limit" 'BEGIN { print t - 0.5 }')" "$((limit + 3))"
  snap "$tier-wiped-full" >"$wiped"
  # The stopped screen is one group with the chrome off (D-070): no receipt sentence, no clock.
  assert_text "$wiped" 'You stopped.'
  assert_text "$wiped" 'Draft deleted.'
  assert_text "$wiped" 'Begin again'
  assert_text "$wiped" '0 words'
  absent_text "$wiped" 'DRAFT DELETED AT'
  absent_text "$wiped" '1:00'
  [[ "$(draft_value "$wiped")" == '' ]] || fail "$tier wipe retained editor text"
  exit_room_by_key
  snap "$tier-exit" >"$output/$tier-exit.json"
}

### 1. Empty rooms cost nothing; each first input spends one of three sessions.
snap fresh-trial >"$output/fresh-trial.json"
assert_text "$output/fresh-trial.json" 'Free trial: 3 of 3 sessions left.'
enter_room "$output/fresh-trial.json"
snap empty-trial >"$output/empty-trial.json"
exit_room_by_key
snap unspent-trial >"$output/unspent-trial.json"
assert_text "$output/unspent-trial.json" 'Free trial: 3 of 3 sessions left.'
for used in 1 2 3; do
  snap "trial-$used-home" >"$output/trial-home.json"
  enter_room "$output/trial-home.json"
  snap "trial-$used-room" >"$output/trial-room.json"
  press a
  snap "trial-$used-input" >"$output/trial-input.json"
  [[ "$(draft_value "$output/trial-input.json")" == a ]] || fail 'trial input was blocked'
  # Escape may cancel an active IME composition instead of leaving the room.
  if [[ "$used" == 3 ]]; then
    wait_text last-trial-wiped 'You stopped.' 'You stopped.' 32
    snap last-trial-wiped-full >"$output/last-trial-wiped.json"
    assert_text "$output/last-trial-wiped.json" 'Draft deleted.'
    assert_text "$output/last-trial-wiped.json" 'Begin again'
    absent_text "$output/last-trial-wiped.json" 'ACTIVATE TO KEEP WRITING'
    press a
    snap trial-exhausted-input >"$output/trial-exhausted-input.json"
    assert_text "$output/trial-exhausted-input.json" 'Activate Write It Down'
  else
    exit_room_by_click
    snap "trial-$used-exit" >"$output/trial-exit.json"
    assert_text "$output/trial-exit.json" "Free trial: $((3 - used)) of 3 sessions left."
  fi
done
kill "$pid"; wait "$pid" 2>/dev/null || true; pid=''
launch_app
snap trial-exhausted-restart >"$output/upgrade.json"
assert_text "$output/upgrade.json" 'Activate Write It Down'
assert_text "$output/upgrade.json" 'After 3 free sessions, a license is required to keep writing.'
assert_text "$output/upgrade.json" 'Try the full web app at writeitdown.app'
absent_text "$output/upgrade.json" 'Back to Home'
absent_text "$output/upgrade.json" 'Type to start'
absent_text "$output/upgrade.json" 'Mac trial:'

### 2. Activate the real client against a disposable signed fixture.
field="$(jq -r '[.elements[] | select(.role == "AXTextField")][0].element_token // empty' "$output/upgrade.json")"
[[ -n "$field" ]] || fail 'order-number field missing'
cua type_text "{\"pid\":$pid,\"element_token\":\"$field\",\"text\":\"window-qa-order\"}" >/dev/null
snap order-entered >"$output/order-entered.json"
activate="$(token_of "$output/order-entered.json" button 'Activate')"
cua click "{\"pid\":$pid,\"element_token\":\"$activate\"}" >/dev/null
wait_text activated 'This Mac is licensed.' 'This Mac is licensed.' 30
snap activated >"$output/activated.json"
start="$(token_of "$output/activated.json" button 'Start writing')"
cua click "{\"pid\":$pid,\"element_token\":\"$start\"}" >/dev/null
snap activated-home >"$output/activated-home.json"

if [[ "$license_only" != 1 ]]; then
### 1. Home: duration buttons, silence radio, license status
snap home >"$output/home.json"
assert_text "$output/home.json" 'Standard 8 s'
for b in 1 5 10 20 30; do
  label="$b minutes"
  [[ "$b" == 1 ]] && label='1 minute'
  [[ -n "$(token_of "$output/home.json" radio "$label")" ]] || fail "home is missing duration radio '$label'"
done

### 2. Enter the room via the 1-minute button
select_tier "$output/home.json" 'Standard 8 s' standard
enter_room "$output/selected-standard.json"
snap room >"$output/room.json"
assert_text "$output/room.json" 'Type to start'
assert_text "$output/room.json" '1:00'
assert_text "$output/room.json" 'ESC - EXIT'
jq -e '[.elements[] | select(.role == "AXTextArea")] | length > 0' >/dev/null "$output/room.json" \
  || fail 'no text area in the room'
assert_room_geometry "$output/room.json"

### 3. Type; forward-only contract blocks delete
type_text 'hello world'
snap typed >"$output/typed.json"
[[ "$(draft_value "$output/typed.json")" == 'hello world' ]] || fail "draft is '$(draft_value "$output/typed.json")', expected 'hello world'"
assert_text "$output/typed.json" '2 words'
press delete
snap deny >"$output/deny.json"
[[ "$(draft_value "$output/deny.json")" == 'hello world' ]] || fail 'Backspace mutated the draft; forward-only contract broken'

### 4. Standard: warn, recovery, wipe, exit
warn_start="$(clock_now)"
press x
check_warn_recovery_wipe standard 32 'hello worldx' 8 "$warn_start"
assert_text "$output/standard-exit.json" 'Standard 8 s'

### 5. Strict and Relaxed: each selection, warn, recovery, wipe, exit
for tier in strict relaxed; do
  home="$output/$tier-home.json"
  snap "$tier-home" >"$home"
  if [[ "$tier" == strict ]]; then
    label='Strict 5 s'
    max_polls=25
    silence_limit=5
  else
    label='Relaxed 12 s'
    max_polls=48
    silence_limit=12
  fi
  select_tier "$home" "$label" "$tier"
  enter_room "$output/selected-$tier.json"
  snap "$tier-room" >"$output/$tier-room.json"
  assert_text "$output/$tier-room.json" 'Type to start'
  # The daemon confirms a key only after delivery; that round trip can exceed a
  # second. Bracket the input: Strict's 2s warn needs the early clock, while
  # Relaxed's 9s warn needs the late clock to avoid counting delivery latency.
  if [[ "$tier" == strict ]]; then warn_start="$(clock_now)"; fi
  press a
  if [[ "$tier" == relaxed ]]; then warn_start="$(clock_now)"; fi
  snap "$tier-typed" >"$output/$tier-typed.json"
  [[ "$(draft_value "$output/$tier-typed.json")" == 'a' ]] || fail "$tier first input missing"
  check_warn_recovery_wipe "$tier" "$max_polls" 'a' "$silence_limit" "$warn_start"
  assert_text "$output/$tier-exit.json" "$label"
  done

fi

snap licensed-home >"$output/licensed-home.json"
enter_room "$output/licensed-home.json"
snap activated-room >"$output/activated-room.json"
press a
snap paid-input >"$output/paid-input.json"
[[ "$(draft_value "$output/paid-input.json")" == a ]] || fail 'activated input was blocked'
exit_room_by_key

### 3. Restart offline, then with an explicit refund response.
for mode in offline refunded; do
  kill "$pid"; wait "$pid" 2>/dev/null || true; pid=''
  printf '%s\n' "$mode" >"$output/fixture-mode"
  launch_app
  if [[ "$mode" == offline ]]; then expected='License active.'; else expected='License revoked.'; fi
  wait_text "$mode-license" 'License' "$expected" 30
  snap "$mode-result" >"$output/$mode-result.json"
  if [[ "$mode" == offline ]]; then
    enter_room "$output/$mode-result.json"
    snap offline-room >"$output/offline-room.json"
    assert_text "$output/offline-room.json" 'Type to start'
  else
    assert_text "$output/$mode-result.json" 'Activate Write It Down'
    absent_text "$output/$mode-result.json" 'Type to start'
    absent_text "$output/$mode-result.json" 'Back to Home'
  fi
done

kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
pid=''
settings="$qa_home/Library/Application Support/WriteItDown/Config/settings.json"
[[ -f "$settings" ]] || fail 'settings.json missing in the isolated home'
jq -e '.licenseStatus == "revoked" and .trialSessionsUsed == 3' "$settings" >/dev/null \
  || fail 'refunded settings must remain revoked with the exhausted trial counter'

timing_summary='three-session trial, signed activation, offline and refund fixture; motion timing not exercised'
if [[ "$license_only" != 1 ]]; then
  timing_summary="$(awk '{printf "%s%s %s", (NR > 1 ? ", " : ""), $1, $2 "=" $3} END {print ""}' "$output/timing.txt")"
fi
printf 'QA PASS: %s stages captured in %s; %s\n' "$snap_n" "$output" "$timing_summary"
