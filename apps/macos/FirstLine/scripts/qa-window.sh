#!/usr/bin/env bash
# [INPUT] Optional screenshot/output directory (default /tmp/wid-qa/cua-<timestamp>);
#         app under test packaged at WID_APP_OUTPUT or dist/Write It Down.app.
# [OUTPUT] Per-stage screenshots, AX snapshots, app.log, and timing.txt in the
#          output directory; exit 0 only when every assertion below holds.
# [POS] apps/macos/FirstLine/scripts/qa-window.sh — real-window acceptance driven
#       through the cua-driver daemon (roadmap report section 6.9).
# [PROTOCOL] Accessibility/screen-recording permission belongs to the running
#            cua-driver daemon (com.trycua.driver), so this background shell needs
#            no TCC grants of its own. The app is launched directly (binary path,
#            fresh CFFIXED_USER_HOME) and every action is background-delivered:
#            no focus steal, no Computer Use dependency. Keys are addressed at the
#            room's AXTextArea token so delivery is read-back confirmed.
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
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$qa_home"
}
trap cleanup EXIT

CFFIXED_USER_HOME="$qa_home" "$bin" >"$output/app.log" 2>&1 &
pid=$!

cua() { cua-driver call "$1" "$2"; }

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

fail() {
  echo "FAIL: $1" >&2
  exit 1
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
# its JSON at last-poll.json for the caller.
poll() { # poll <name> <query>
  local name="$1" query="$2" file json
  snap_n=$((snap_n + 1))
  file="$output/$(printf '%02d' "$snap_n")-$name"
  json="$(cua get_window_state "{\"pid\":$pid,\"window_id\":$window_id,\"include_screenshot\":false,\"query\":\"$query\"}" | normalize)"
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

### 1. Home: duration buttons, silence radio, trial budget line
snap home >"$output/home.json"
assert_text "$output/home.json" 'Standard - 8s'
assert_text "$output/home.json" 'Mac trial: 0 of 3 sessions used.'
for b in 1 5 10 20 30; do
  [[ -n "$(token_of "$output/home.json" button "$b")" ]] || fail "home is missing duration button '$b'"
done

enter_room() { # enter_room <home-snapshot>
  local token
  token="$(token_of "$1" button '1')"
  [[ -n "$token" ]] || fail 'no element token for the 1-minute button'
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
  warn_min="$(awk -v t="$limit" 'BEGIN { print 0.6 * t - 0.5 }')"
  warn_max="$(awk -v t="$limit" 'BEGIN { print 0.625 * t + 2 }')"
  if [[ "$tier" == strict ]]; then warn_min=1.8; warn_max=4.5; fi
  wait_text "$tier-warn" 'KEEP TYPING' 'KEEP TYPING OR THE DRAFT IS DELETED.' "$max"
  assert_timing "$tier" warn "$warn_start" "$matched_at" "$warn_min" "$warn_max"
  snap "$tier-warn-full" >"$warn"
  assert_text "$warn" 'KEEP TYPING OR THE DRAFT IS DELETED.'
  jq -e '.window_markdown | test("AXStaticText = .[1-3].")' >/dev/null "$warn" \
    || fail "$tier warn state has no 3-2-1 numeral in AX"
  wipe_start="$(clock_now)"
  press k
  snap "$tier-recovered-state" >"$recovered"
  absent_text "$recovered" 'KEEP TYPING OR THE DRAFT IS DELETED.'
  [[ "$(draft_value "$recovered")" == "${before}k" ]] || fail "$tier recovery lost draft"
  wait_text "$tier-wiped" 'DRAFT WIPED' 'DRAFT WIPED - ' "$max"
  assert_timing "$tier" wipe "$wipe_start" "$matched_at" "$(awk -v t="$limit" 'BEGIN { print t - 0.5 }')" "$((limit + 3))"
  snap "$tier-wiped-full" >"$wiped"
  jq -e '.window_markdown | test("DRAFT WIPED - [0-9]+:[0-5][0-9] UNUSED\\. TYPE TO RESTART\\.")' >/dev/null "$wiped" \
    || fail "$tier wipe report is not the literal receipt"
  assert_text "$wiped" '0 WORDS'
  press escape
  snap "$tier-exit" >"$output/$tier-exit.json"
}

### 2. Enter the room via the 1-minute button
select_tier "$output/home.json" 'Standard - 8s' standard
enter_room "$output/selected-standard.json"
snap room >"$output/room.json"
assert_text "$output/room.json" 'Start typing.'
assert_text "$output/room.json" '1:00'
assert_text "$output/room.json" '0 WORDS'
assert_text "$output/room.json" 'ESC - EXIT'
jq -e '[.elements[] | select(.role == "AXTextArea")] | length > 0' >/dev/null "$output/room.json" \
  || fail 'no text area in the room'

### 3. Type; forward-only contract blocks delete
type_text 'hello world'
snap typed >"$output/typed.json"
[[ "$(draft_value "$output/typed.json")" == 'hello world' ]] || fail "draft is '$(draft_value "$output/typed.json")', expected 'hello world'"
assert_text "$output/typed.json" '2 WORDS'
press delete
snap deny >"$output/deny.json"
[[ "$(draft_value "$output/deny.json")" == 'hello world' ]] || fail 'Backspace mutated the draft; forward-only contract broken'

### 4. Standard: warn, recovery, wipe, exit
warn_start="$(clock_now)"
press x
check_warn_recovery_wipe standard 32 'hello worldx' 8 "$warn_start"
assert_text "$output/standard-exit.json" 'Standard - 8s'
assert_text "$output/standard-exit.json" 'Mac trial: 1 of 3 sessions used.'

### 5. Strict and Relaxed: each selection, warn, recovery, wipe, exit
for tier in strict relaxed; do
  home="$output/$tier-home.json"
  snap "$tier-home" >"$home"
  if [[ "$tier" == strict ]]; then
    label='Strict - 5s'
    budget=2
    max_polls=25
    silence_limit=5
  else
    label='Relaxed - 12s'
    budget=3
    max_polls=48
    silence_limit=12
  fi
  select_tier "$home" "$label" "$tier"
  enter_room "$output/selected-$tier.json"
  snap "$tier-room" >"$output/$tier-room.json"
  assert_text "$output/$tier-room.json" 'Start typing.'
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
  assert_text "$output/$tier-exit.json" "Mac trial: $budget of 3 sessions used."
done

### 6. Fourth start routes to Upgrade without billing another trial
enter_room "$output/relaxed-exit.json"
snap upgrade >"$output/upgrade.json"
assert_text "$output/upgrade.json" 'Trial complete'
assert_text "$output/upgrade.json" 'Three writing sessions used.'
absent_text "$output/upgrade.json" 'Start typing.'

### 7. Billing truth in the isolated home
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
pid=''
settings="$qa_home/Library/Application Support/WriteItDown/Config/settings.json"
[[ -f "$settings" ]] || fail 'settings.json missing in the isolated home'
used="$(jq -r '.trialSessionsUsed // 0' "$settings")"
[[ "$used" == '3' ]] || fail "trialSessionsUsed is $used, expected 3"

timing_summary="$(awk '{printf "%s%s %s", (NR > 1 ? ", " : ""), $1, $2 "=" $3} END {print ""}' "$output/timing.txt")"
printf 'QA PASS: %s stages captured in %s; %s\n' "$snap_n" "$output" "$timing_summary"
