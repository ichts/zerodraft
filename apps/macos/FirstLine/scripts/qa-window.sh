#!/usr/bin/env bash
# Run this System Events/screencapture flow only in a graphical session with
# accessibility and screen-recording permissions. Background sessions cannot
# capture the display; Mini Computer Use is the alternative when these APIs fail.
set -euo pipefail

batch=${1:-}
if [[ "$batch" != 5 && "$batch" != 6 ]]; then
  echo 'Only Batches 5 and 6 have scripted window flows; historical batches 1-4 are unavailable.' >&2
  exit 2
fi
cd "$(dirname "$0")/.."
output="/tmp/wid-qa/$batch"
mkdir -p "$output"
qa_home=$(mktemp -d "${TMPDIR:-/tmp}/wid-qa-home.XXXXXX")
pid=''
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$qa_home"
}
trap cleanup EXIT
swift build
CFFIXED_USER_HOME="$qa_home" .build/debug/WriteItDown >"$output/app.log" 2>&1 &
pid=$!
sleep 2

window_id() {
  swift -e 'import CoreGraphics; import Foundation
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid && (window[kCGWindowLayer as String] as? Int) == 0 {
    print(window[kCGWindowNumber as String]!)
    break
}' "$pid" | tail -1
}
wid=$(window_id)
if [[ ! "$wid" =~ ^[0-9]+$ ]]; then echo 'No app window found' >&2; exit 1; fi
shot() { screencapture -x -l "$wid" "$output/$1.png"; }
type() { osascript -e 'tell application "System Events" to repeat with characterToType in characters of '"\"$1\"" -e 'keystroke characterToType' -e 'end repeat'; }
wait_for_radio_button() {
  local title=$1
  for _ in {1..40}; do
    if [[ $(osascript -e "tell application \"System Events\" to exists radio button \"$title\" of window 1 of process \"WriteItDown\"" 2>/dev/null) == true ]]; then return 0; fi
    sleep 0.25
  done
  echo "Timed out waiting for $title" >&2
  return 1
}
if [[ "$batch" == 6 ]]; then
  shot start-light
  for trial in 1 2 3; do
    wait_for_radio_button 'Standard - 8s'
    osascript -e 'tell application "System Events" to click button "1" of window 1 of process "WriteItDown"'
    type "trial $trial"
    shot "trial-$trial-typing"
    sleep 8.3
    shot "trial-$trial-wiped"
    osascript -e 'tell application "System Events" to key code 53'
  done
  wait_for_radio_button 'Standard - 8s'
  osascript -e 'tell application "System Events" to click button "1" of window 1 of process "WriteItDown"'
  shot upgrade-after-three-trials
  echo 'Inspect Upgrade, configured Buy URL and active-license state with independent Computer Use. Without a Dodo test key, activation is NOT VERIFIED.'
  exit 0
fi
shot start-light
osascript -e 'tell application "System Events" to click button "1" of window 1 of process "WriteItDown"'
sleep 1; shot rest-standard
type 'standard draft'; sleep 5.2; shot warn-standard
type ' again'; shot recovered-standard
sleep 8.2; shot wiped-standard
osascript -e 'tell application "System Events" to key code 53'
wait_for_radio_button 'Strict - 5s'
osascript -e 'tell application "System Events" to click radio button "Strict - 5s" of window 1 of process "WriteItDown"'
osascript -e 'tell application "System Events" to click button "1" of window 1 of process "WriteItDown"'
type 'strict draft'; sleep 2.2; shot warn-strict
type ' again'; shot recovered-strict
sleep 5.2; shot wiped-strict
osascript -e 'tell application "System Events" to key code 53'
wait_for_radio_button 'Relaxed - 12s'
osascript -e 'tell application "System Events" to click radio button "Relaxed - 12s" of window 1 of process "WriteItDown"'
osascript -e 'tell application "System Events" to click button "1" of window 1 of process "WriteItDown"'
type 'relaxed draft'; sleep 9.2; shot warn-relaxed
type ' again'; shot recovered-relaxed
sleep 12.2; shot wiped-relaxed
printf 'Captured %s; independent Computer Use must additionally verify real-window focus, keyboard-only kept flow, visual settings, appearance, persistence and clipboard.\n' "$output"
