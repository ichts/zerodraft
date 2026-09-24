#!/usr/bin/env bash
# Run this System Events/screencapture flow only in a graphical session with
# accessibility and screen-recording permissions. Background sessions cannot
# capture the display; Mini Computer Use is the alternative when these APIs fail.
set -euo pipefail

batch=${1:-}
if [[ "$batch" != 1 && "$batch" != 2 && "$batch" != 3 && "$batch" != 4 ]]; then
  echo 'Only batches 1 through 4 have scripted window flows.' >&2
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
wait_for_button() {
  local title=$1
  for _ in {1..40}; do
    if [[ $(osascript -e "tell application \"System Events\" to exists button \"$title\" of window 1 of process \"WriteItDown\"" 2>/dev/null) == true ]]; then return 0; fi
    sleep 0.25
  done
  echo "Timed out waiting for $title" >&2
  return 1
}
wait_for_appearance() {
  local theme=$1
  local probe="$output/.appearance.png"
  for _ in {1..40}; do
    if screencapture -x -l "$wid" "$probe" && [[ $(swift -e 'import AppKit; import Foundation
let bitmap = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let color = bitmap.colorAt(x: 80, y: 200)!.usingColorSpace(.deviceRGB)!
print(color.redComponent > 0.5 ? "Light" : "Dark")' "$probe" 2>/dev/null) == "$theme" ]]; then
      rm -f "$probe"
      return 0
    fi
    sleep 0.25
  done
  rm -f "$probe"
  echo "Timed out waiting for rendered $theme appearance" >&2
  return 1
}
if [[ "$batch" == 4 ]]; then
  osascript -e 'tell application "System Events" to keystroke "," using command down'
  wait_for_button 'Done'
  osascript -e 'tell application "System Events" to click menu item "Light" of menu 1 of pop up button 1 of window 1 of process "WriteItDown"'
  osascript -e 'tell application "System Events" to click button "Done" of window 1 of process "WriteItDown"'
  wait_for_button 'Give it sixty seconds.'
  osascript -e 'tell application "System Events" to click button "Give it sixty seconds." of window 1 of process "WriteItDown"'
  sleep 1; shot rest-light
  type 'A'; sleep 0.2
  osascript -e 'tell application "System Events" to key code 51'
  type ' writing room stays alive'; shot typing-light
  sleep 5.5; shot warn-light
  type ' keep'; shot recovered-light
  sleep 8.3; shot wiped-light
  type 'fresh'; shot restarted-light
  for _ in $(seq 1 16); do
    sleep 4
    if [[ $(osascript -e 'tell application "System Events" to exists button "COPY TEXT" of window 1 of process "WriteItDown"') == true ]]; then break; fi
    type ' more'
  done
  wait_for_button 'COPY TEXT'; shot kept-light
  osascript -e 'tell application "System Events" to click button "COPY TEXT" of window 1 of process "WriteItDown"'
  shot copied-light
  pbpaste > "$output/copied.txt"
  osascript -e 'tell application "System Events" to click button "RUN IT AGAIN" of window 1 of process "WriteItDown"'
  shot again-light
  osascript -e 'tell application "System Events" to key code 53'
  wait_for_button 'Give it sixty seconds.'; shot exit-light
  # The independent graphical session additionally captures dark rest/warn/kept and reduced motion.
  printf 'Captured %s; inspect states, clipboard, dark appearance and reduced motion independently. The 280 ms deny frame is unverified by this script.\n' "$output"
  exit 0
fi
if [[ "$batch" == 3 ]]; then
  osascript -e 'tell application "System Events" to keystroke "," using command down'
  wait_for_button 'Done'
  osascript -e 'tell application "System Events" to click menu item "Light" of menu 1 of pop up button 1 of window 1 of process "WriteItDown"'
  wait_for_appearance 'Light'
  osascript -e 'tell application "System Events" to click button "Done" of window 1 of process "WriteItDown"'
  wait_for_button 'Give it sixty seconds.'
  wait_for_appearance 'Light'
  shot start-light
else
  shot start
fi
# Enter by clicking the primary button; Return is not a start shortcut yet.
osascript -e 'tell application "System Events" to click button "Give it sixty seconds." of window 1 of process "WriteItDown"'
if [[ "$batch" == 3 ]]; then
  wait_for_button 'Abandon - the text is lost'
  wait_for_appearance 'Light'
  shot room-light
  osascript -e 'tell application "System Events" to click button "Abandon - the text is lost" of window 1 of process "WriteItDown"'
  wait_for_button 'Give it sixty seconds.'
  osascript -e 'tell application "System Events" to keystroke "," using command down'
  wait_for_button 'Done'
  wait_for_appearance 'Light'
  shot settings-light
  osascript -e 'tell application "System Events" to click menu item "Dark" of menu 1 of pop up button 1 of window 1 of process "WriteItDown"'
  wait_for_appearance 'Dark'
  shot settings-dark
  osascript -e 'tell application "System Events" to click button "Done" of window 1 of process "WriteItDown"'
  wait_for_button 'Give it sixty seconds.'
  wait_for_appearance 'Dark'
  shot start-dark
  osascript -e 'tell application "System Events" to click button "Give it sixty seconds." of window 1 of process "WriteItDown"'
  wait_for_button 'Abandon - the text is lost'
  wait_for_appearance 'Dark'
  shot room-dark
  printf 'Captured %s; inspect every image in independent Computer Use acceptance.\n' "$output"
  exit 0
fi
sleep 1
if [[ "$batch" == 2 ]]; then
  sleep 3
  shot rest-after-three-seconds
  type 'batch two draft'
  shot typed
  sleep 5
  shot warn
  sleep 3
  shot wipe-in-room
  type 'new draft'
  shot restarted
  if [[ $(osascript -e 'tell application "System Events" to exists button "Finish" of window 1 of process "WriteItDown"') == true ]]; then
    echo 'Early Finish button still exists' >&2
    exit 1
  fi
else
  type 'batch one draft'
  shot typed
fi
osascript -e 'tell application "System Events" to keystroke "2" using command down'
shot command-two
# Keep typing until the sixty-second deadline produces the kept surface.
for _ in $(seq 1 16); do
  sleep 4
  if [[ $(osascript -e 'tell application "System Events" to exists button "Copy full text" of window 1 of process "WriteItDown"') == true ]]; then break; fi
  type ' keep'
done
if [[ $(osascript -e 'tell application "System Events" to exists button "Copy full text" of window 1 of process "WriteItDown"') != true ]]; then
  echo 'Kept surface did not appear' >&2
  exit 1
fi
shot kept
# Discard, then open Settings through the standard menu shortcut.
osascript -e 'tell application "System Events" to click button "Discard" of window 1 of process "WriteItDown"'
osascript -e 'tell application "System Events" to keystroke "," using command down'
sleep 1
shot settings
printf 'Captured %s; inspect every image and record the result in docs/MANUAL_QA.md.\n' "$output"
