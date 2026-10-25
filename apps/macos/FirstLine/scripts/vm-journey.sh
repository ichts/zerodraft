#!/bin/bash
# [INPUT] <dmg-path> [evidence-dir]. Env: WID_VM_ROOT (default $HOME/wid-vm),
#         WID_VM_GOLDEN (default wid-golden), WID_VM_SSH_USER (default admin),
#         WID_VM_KEEP=1 to keep the clone for debugging, WID_VM_EXPECT_SHA to require
#         an exact DMG checksum (defaults to a sibling .sha256 file when present).
# [OUTPUT] A timestamped evidence bundle (evidence-dir, default
#          <root>/evidence/<timestamp>): the continuous screen.mov, per-step
#          screenshots and AX snapshots, journey.log, launch watchers, summary.json
#          and notes.md. Exit 0 only when the guest journey passed AND the returned
#          recording is intact; exit 1 otherwise; exit 2 on a rig setup error.
# [POS] apps/macos/FirstLine/scripts/vm-journey.sh - the recorded acceptance entry
#       point. Runs ON the Mac mini (everything heavy stays there): clones the
#       prepared golden VM, boots it headless, installs the DMG inside the guest,
#       drives the shipped app with real input while recording the guest screen,
#       copies the evidence back and destroys the clone.
# [PROTOCOL] One run = one clean clone. The Mini's own screen, login keychain and
#            GUI session are never used: the guest boots with --no-graphics and its
#            screen is captured inside the guest. A failed, interrupted or truncated
#            recording fails the run. Preparation lives in scripts/vm/prepare-guest.sh.
set -uo pipefail

dmg="${1:?usage: vm-journey.sh <dmg-path> [evidence-dir]}"
root="${WID_VM_ROOT:-$HOME/wid-vm}"
golden="${WID_VM_GOLDEN:-wid-golden}"
ssh_user="${WID_VM_SSH_USER:-admin}"
keep="${WID_VM_KEEP:-0}"
scripts="$(cd "$(dirname "$0")" && pwd)"
run_id="$(date +%Y%m%d-%H%M%S)"
vm="wid-run-$run_id"
evidence="${2:-$root/evidence/$run_id}"
key="$root/ssh/id_ed25519"

die() { printf 'vm-journey: ERROR: %s\n' "$*" >&2; exit 2; }
log() { printf 'vm-journey: %s\n' "$*"; }

[[ -f "$dmg" ]] || die "DMG not found: $dmg"
dmg="$(cd "$(dirname "$dmg")" && pwd -P)/$(basename "$dmg")"
command -v tart >/dev/null || die 'tart is not installed'
tart list | awk 'NR>1 && $2 == "'"$golden"'" { found = 1 } END { exit !found }' \
  || die "golden image $golden is missing; run scripts/vm/prepare-guest.sh first"
[[ -x "$root/bin/license-fixture" ]] || die "$root/bin/license-fixture is missing; re-run scripts/vm/prepare-guest.sh"
[[ -f "$key" ]] || die "$key is missing; re-run scripts/vm/prepare-guest.sh"
command -v ffprobe >/dev/null || die 'ffprobe is not installed (brew install ffmpeg)'

expected_sha="${WID_VM_EXPECT_SHA:-}"
if [[ -z "$expected_sha" && -f "$dmg.sha256" ]]; then
  expected_sha="$(cut -d' ' -f1 <"$dmg.sha256")"
fi

mkdir -p "$evidence"
evidence="$(cd "$evidence" && pwd -P)"
[[ -f "$evidence/journey.log" ]] && die "evidence directory is not fresh: $evidence"

guest_ssh() { ssh -i "$key" -o BatchMode=yes -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$ssh_user@$guest_ip" "$@"; }

vm_pid=''
guest_ip=''
cleanup() {
  local status=$?
  trap - EXIT
  [[ -n "$vm_pid" ]] && { kill -TERM "$vm_pid" 2>/dev/null; wait "$vm_pid" 2>/dev/null; }
  if [[ "$keep" == '1' ]]; then
    log "keeping the clone $vm (WID_VM_KEEP=1); stop and delete it yourself with tart stop/delete"
  else
    tart stop "$vm" >/dev/null 2>&1
    tart delete "$vm" >/dev/null 2>&1 || log "could not delete clone $vm"
  fi
  exit "$status"
}
trap cleanup EXIT

log "cloning $golden -> $vm"
tart clone "$golden" "$vm" || die 'could not clone the golden image'

log 'booting the clone headless'
tart run --no-graphics "$vm" >"$evidence/vm-run.log" 2>&1 &
vm_pid=$!

for _ in {1..90}; do
  guest_ip="$(tart ip "$vm" 2>/dev/null)"
  [[ -n "$guest_ip" ]] && guest_ssh true >/dev/null 2>&1 && break
  sleep 2
done
guest_ssh true >/dev/null 2>&1 || die 'the clone never became reachable over SSH'
log "guest reachable at $guest_ip"

log 'staging the DMG, licence fixture and journey script in the guest'
guest_ssh 'rm -rf /tmp/wid-run && mkdir -p /tmp/wid-run /tmp/wid-evidence' || die 'could not prepare the guest workspace'
cat "$dmg" | guest_ssh 'cat > /tmp/wid-run/'"$(basename "$dmg")" || die 'could not copy the DMG into the guest'
cat "$root/bin/license-fixture" | guest_ssh 'cat > /tmp/wid-run/license-fixture && chmod +x /tmp/wid-run/license-fixture' || die 'could not copy the license fixture'
cat "$scripts/vm/guest-journey.sh" | guest_ssh 'cat > /tmp/wid-run/guest-journey.sh && chmod +x /tmp/wid-run/guest-journey.sh' || die 'could not copy the journey script'
guest_ssh 'shasum -a 256 /tmp/wid-run/'"$(basename "$dmg")" | cut -d' ' -f1 >"$evidence/guest-sha256.txt"
[[ "$(cut -d' ' -f1 <"$evidence/guest-sha256.txt")" == "$(shasum -a 256 "$dmg" | cut -d' ' -f1)" ]] \
  || die 'the DMG changed while copying it into the guest'

log 'running the recorded journey inside the guest (this takes about four minutes)'
guest_status=0
guest_ssh "/bin/bash /tmp/wid-run/guest-journey.sh /tmp/wid-evidence /tmp/wid-run/$(basename "$dmg") '$expected_sha' /tmp/wid-run/license-fixture" \
  2>&1 | tee "$evidence/runner.log" || guest_status=$?

log 'copying the evidence bundle back'
if guest_ssh 'cd /tmp/wid-evidence && tar -cf - .' | tar -xf - -C "$evidence"; then
  log "evidence in $evidence"
else
  log 'ERROR: could not copy the evidence bundle back'
  [[ "$guest_status" -eq 0 ]] && guest_status=1
fi

if [[ -s "$evidence/screen.mov" ]]; then
  duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$evidence/screen.mov" 2>/dev/null || echo 0)"
  frames="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$evidence/screen.mov" 2>/dev/null || echo 0)"
  log "recording: ${duration}s, ${frames} frames, $(stat -f %z "$evidence/screen.mov") bytes"
  if awk -v d="$duration" 'BEGIN { exit !(d >= 60) }'; then
    log 'recording length is plausible for a full journey'
  else
    log 'ERROR: the recording is shorter than a full journey'
    guest_status=1
  fi
  printf '%s\t%s\t%s\n' "$duration" "$frames" "$(stat -f %z "$evidence/screen.mov")" >"$evidence/recording.tsv"
else
  log 'ERROR: no screen.mov came back from the guest'
  guest_status=1
fi

failures="$(grep -c '^FAIL ' "$evidence/journey.log" 2>/dev/null || echo 1)"
log "journey assertions failed: $failures; guest exit: $guest_status"
exit "$guest_status"
