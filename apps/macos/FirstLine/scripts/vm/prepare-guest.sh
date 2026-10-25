#!/bin/bash
# [INPUT] Runs ON the Mac mini host with Tart installed. Env:
#         WID_VM_ROOT (default $HOME/wid-vm)  WID_VM_BASE (default wid-base)
#         WID_VM_GOLDEN (default wid-golden)  WID_VM_CPUS (default 4)
#         WID_VM_MEMORY (default 8192)        WID_VM_DISPLAY (default 1440x900)
#         WID_VM_BASE_IMAGE (default ghcr.io/cirruslabs/macos-tahoe-base:latest)
# [OUTPUT] A golden macOS VM: SSH key auth for the rig, /usr/local/wid-rig/bin/widrig
#          and the license fixture installed, a tidied desktop, and a verification
#          pass proving Accessibility, Screen Recording and HID input work from an
#          SSH session inside the guest. Exit 0 only when every check passes.
# [POS] apps/macos/FirstLine/scripts/vm/prepare-guest.sh - one-time (and repeatable)
#       preparation of the image every recorded acceptance run clones.
# [PROTOCOL] The Cirrus base image already carries the CI TCC grants
#            (sshd-keygen-wrapper holds Accessibility, ScreenCapture, PostEvent)
#            and SIP disabled, so no permission is granted interactively here. The
#            guest admin account is the image default admin/admin inside a
#            disposable VM; no host keychain, signing identity or Mini credential is
#            touched. Widgets, restored Terminal windows and saved application state
#            are removed so evidence frames show the app, not the VM's leftovers.
set -uo pipefail

root="${WID_VM_ROOT:-$HOME/wid-vm}"
base="${WID_VM_BASE:-wid-base}"
golden="${WID_VM_GOLDEN:-wid-golden}"
base_image="${WID_VM_BASE_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
cpus="${WID_VM_CPUS:-4}"
memory="${WID_VM_MEMORY:-8192}"
display="${WID_VM_DISPLAY:-1440x900}"
repo_scripts="$(cd "$(dirname "$0")" && pwd)"

log() { printf '%s\n' "prepare-guest: $*"; }
die() { printf '%s\n' "prepare-guest: ERROR: $*" >&2; exit 1; }

command -v tart >/dev/null || die 'tart is not installed (brew install cirruslabs/cli/tart)'
command -v swiftc >/dev/null || die 'swiftc is missing (install Xcode command line tools)'
command -v go >/dev/null || die 'go is missing (needed to build the license fixture)'

mkdir -p "$root/bin" "$root/ssh"

if ! tart list | awk 'NR>1 && $2 == "'"$base"'" { found = 1 } END { exit !found }'; then
  log "pulling the base image $base_image (this is a one-time ~26 GB download)"
  tart clone "$base_image" "$base" || die 'could not pull the base image'
fi

[[ -f "$root/ssh/id_ed25519" ]] || ssh-keygen -t ed25519 -N '' -C wid-vm-rig -f "$root/ssh/id_ed25519" >/dev/null

log 'building widrig'
swiftc -O -target arm64-apple-macos14.0 -o "$root/bin/widrig" "$repo_scripts/widrig.swift" || die 'widrig failed to build'
codesign --force --sign - --identifier dev.wid.rig.widrig "$root/bin/widrig" || die 'widrig failed to sign'

log 'building the loopback license fixture'
go build -o "$root/bin/license-fixture" "$repo_scripts/../qa-license-fixture.go" || die 'license fixture failed to build'

if tart list | awk 'NR>1 && $2 == "'"$golden"'" { found = 1 } END { exit !found }'; then
  log "replacing the existing golden image $golden"
  tart stop "$golden" >/dev/null 2>&1
  tart delete "$golden" >/dev/null 2>&1
fi
log "cloning $base -> $golden"
tart clone "$base" "$golden" || die 'could not clone the base image'
tart set "$golden" --cpu "$cpus" --memory "$memory" --display "$display" >/dev/null || die 'could not configure the golden image'

guest_ssh() { ssh -i "$root/ssh/id_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "admin@$(tart ip "$golden" 2>/dev/null)" "$@"; }

vm_pid=''
stop_vm() {
  [[ -n "$vm_pid" ]] && { kill -TERM "$vm_pid" 2>/dev/null; wait "$vm_pid" 2>/dev/null; }
  tart stop "$golden" >/dev/null 2>&1
  vm_pid=''
}
trap 'stop_vm' EXIT

log "booting $golden headless"
tart run --no-graphics "$golden" >"$root/golden-run.log" 2>&1 &
vm_pid=$!

guest_ip=''
for _ in {1..60}; do
  guest_ip="$(tart ip "$golden" 2>/dev/null)"
  [[ -n "$guest_ip" ]] && ping -c1 -W1 "$guest_ip" >/dev/null 2>&1 && break
  sleep 2
done
[[ -n "$guest_ip" ]] || die 'the golden VM never got an IP address'

log 'installing the rig SSH key'
pubkey="$(cat "$root/ssh/id_ed25519.pub")"
tart exec "$golden" /bin/sh -c "mkdir -p /Users/admin/.ssh; chmod 700 /Users/admin/.ssh; touch /Users/admin/.ssh/authorized_keys; grep -qF '$pubkey' /Users/admin/.ssh/authorized_keys || printf '%s\n' '$pubkey' >> /Users/admin/.ssh/authorized_keys; chmod 600 /Users/admin/.ssh/authorized_keys" \
  || die 'could not install the rig SSH key'

for _ in {1..60}; do guest_ssh true >/dev/null 2>&1 && break; sleep 2; done
guest_ssh true >/dev/null 2>&1 || die 'SSH into the golden VM never came up'

log 'installing the rig tools'
cat "$root/bin/widrig" | guest_ssh 'cat > /tmp/widrig && chmod +x /tmp/widrig' || die 'could not copy widrig'
cat "$root/bin/license-fixture" | guest_ssh 'cat > /tmp/license-fixture && chmod +x /tmp/license-fixture' || die 'could not copy the license fixture'
cat "$repo_scripts/guest-journey.sh" | guest_ssh 'cat > /tmp/guest-journey.sh && chmod +x /tmp/guest-journey.sh' || die 'could not copy the journey script'
guest_ssh "echo admin | sudo -S -p '' /bin/sh -c '
  mkdir -p /usr/local/wid-rig/bin /usr/local/wid-rig/scripts &&
  mv /tmp/widrig /usr/local/wid-rig/bin/widrig &&
  mv /tmp/license-fixture /usr/local/wid-rig/bin/license-fixture &&
  mv /tmp/guest-journey.sh /usr/local/wid-rig/scripts/guest-journey.sh &&
  chmod 755 /usr/local/wid-rig/bin/widrig /usr/local/wid-rig/bin/license-fixture /usr/local/wid-rig/scripts/guest-journey.sh &&
  chown -R root:wheel /usr/local/wid-rig'" >/dev/null 2>&1 || die 'could not install the rig tools into /usr/local/wid-rig'

log 'tidying the guest desktop'
guest_ssh 'pkill -x Terminal 2>/dev/null; pkill -x TextEdit 2>/dev/null; true
  rm -rf "$HOME/Library/Saved Application State/"*.savedState 2>/dev/null
  rm -rf "$HOME/Library/Containers/com.apple.TextEdit/Data/Documents/"* 2>/dev/null
  rm -rf "$HOME/Library/Containers/com.apple.TextEdit/Data/Library/Autosave Information/"* 2>/dev/null
  rm -rf "$HOME/Library/Containers/com.apple.TextEdit/Data/Library/Saved Application State/"* 2>/dev/null
  defaults write -g NSQuitAlwaysKeepsWindows -bool false
  defaults write com.apple.WindowManager StandardHideWidgets -bool true 2>/dev/null
  defaults write com.apple.WindowManager StageManagerHideWidgets -bool true 2>/dev/null
  rm -rf /tmp/wid* /tmp/shot-*.png /tmp/c1.png /tmp/c2.png /tmp/p-*.png /tmp/m-*.png 2>/dev/null
  true' >/dev/null 2>&1
guest_ssh '/usr/local/wid-rig/bin/widrig click --x 700 --y 450 >/dev/null 2>&1; /usr/local/wid-rig/bin/widrig key --name w --command >/dev/null 2>&1' >/dev/null 2>&1
sleep 2

log 'verifying Accessibility, Screen Recording and HID input'
guest_ssh '/usr/local/wid-rig/bin/widrig trusted' | grep -q '"accessibility":true' \
  || die 'the guest Accessibility grant is not live for SSH sessions'
# The Screen Recording probe opens the Apple menu: a transient overlay proves the
# capture sees live window content while leaving no window, document or saved state
# behind in the image every acceptance run clones.
guest_ssh 'screencapture -x /tmp/wid-prep-a.png; /usr/local/wid-rig/bin/widrig click --x 16 --y 13 >/dev/null; sleep 1; screencapture -x /tmp/wid-prep-b.png; /usr/local/wid-rig/bin/widrig key --name escape >/dev/null; sleep 1; screencapture -x /tmp/wid-prep-c.png' >/dev/null 2>&1
capture="$(guest_ssh '/usr/local/wid-rig/bin/widrig pxdiff --first /tmp/wid-prep-a.png --second /tmp/wid-prep-b.png >/dev/null && echo CAPTURE-OK || echo CAPTURE-FAILED')"
[[ "$capture" == 'CAPTURE-OK' ]] || die 'Screen Recording is not usable from an SSH session in the guest'
restored="$(guest_ssh '/usr/local/wid-rig/bin/widrig pxdiff --first /tmp/wid-prep-b.png --second /tmp/wid-prep-c.png >/dev/null && echo CLEAN-OK || echo DIRTY')"
[[ "$restored" == 'CLEAN-OK' ]] || die 'the probe overlay did not leave the guest desktop'
input="$(guest_ssh '/usr/local/wid-rig/bin/widrig key --name space --command >/dev/null; sleep 3
  /usr/local/wid-rig/bin/widrig type --text "rig input probe" >/dev/null; sleep 1
  p=$(pgrep -x Spotlight | head -1)
  /usr/local/wid-rig/bin/widrig text --pid "$p" | grep -q "rig input probe" && echo INPUT-OK || echo INPUT-FAILED
  /usr/local/wid-rig/bin/widrig key --name escape >/dev/null')"
[[ "$input" == 'INPUT-OK' ]] || die 'HID keyboard input does not reach the focused app in the guest'
# Spotlight is the input probe because it takes keystrokes, exposes them through
# accessibility and closes on Escape: no document, no window and no saved state is
# left behind for the next clone to inherit.
guest_ssh 'pkill -x TextEdit; pkill -x Spotlight; sleep 3
  rm -rf "$HOME/Library/Containers/com.apple.TextEdit/Data/Documents/"* "$HOME/Library/Containers/com.apple.TextEdit/Data/Library/Autosave Information/"* "$HOME/Library/Containers/com.apple.TextEdit/Data/Library/Saved Application State/"* 2>/dev/null
  true' >/dev/null 2>&1
leftover="$(guest_ssh 'screencapture -x /tmp/wid-prep-d.png; /usr/local/wid-rig/bin/widrig pxdiff --first /tmp/wid-prep-a.png --second /tmp/wid-prep-d.png | jq -r .changedFraction' 2>/dev/null)"
log "desktop drift after the probes: ${leftover:-unknown} (notification banners are transient; a large value means the probes left something behind)"
guest_ssh 'rm -f /tmp/wid-prep-*.png' >/dev/null 2>&1
screencapture_desktop="$root/golden-desktop.png"
guest_ssh 'screencapture -x /tmp/golden-desktop.png' >/dev/null 2>&1
cat <(guest_ssh 'cat /tmp/golden-desktop.png') >"$screencapture_desktop" 2>/dev/null || true
guest_ssh 'rm -f /tmp/golden-desktop.png' >/dev/null 2>&1
log 'Accessibility, Screen Recording and real HID input all verified inside the guest'

log 'shutting the golden image down'
stop_vm
log "done: golden image $golden is ready for $(basename "$repo_scripts/../vm-journey.sh")"
