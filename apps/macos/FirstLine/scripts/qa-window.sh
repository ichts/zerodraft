#!/usr/bin/env bash
# Run this System Events/screencapture flow only in a graphical session with
# accessibility and screen-recording permissions. Background sessions cannot
# capture the display; Mini Computer Use is the alternative when these APIs fail.
set -euo pipefail

batch=${1:-}
if [[ "$batch" != 1 ]]; then
  echo 'Batch 1 is the only scripted window flow so far.' >&2
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
CFFIXED_USER_HOME="$qa_home" .build/debug/FirstLine >"$output/app.log" 2>&1 &
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
shot start
# Home has no Return binding in Batch 1; enter by clicking its primary button.
osascript -e 'tell application "System Events" to click button "Give it sixty seconds." of window 1 of process "FirstLine"'
sleep 1
type 'batch one draft'
shot typed
osascript -e 'tell application "System Events" to keystroke "2" using command down'
shot command-two
# Keep the draft alive until the sixty-second deadline, then capture the kept surface.
for _ in $(seq 1 10); do sleep 5; type ' keep'; done
sleep 11
shot kept
# Discard, then open Settings through the standard menu shortcut.
osascript -e 'tell application "System Events" to click button "Discard" of window 1 of process "FirstLine"'
osascript -e 'tell application "System Events" to keystroke "," using command down'
sleep 1
shot settings
printf 'Captured %s; inspect every image and record the result in docs/MANUAL_QA.md.\n' "$output"
