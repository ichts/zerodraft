#!/bin/bash
# [INPUT] <dmg-or-app-path> [evidence-dir]. A .dmg runs the full shipped-DMG
#         acceptance; an .app bundle runs the licensed-launch proof instead (install
#         the bundle the way the DMG payload is installed, activate, relaunch three
#         times). Env: WID_VM_ROOT (default $HOME/wid-vm),
#         WID_VM_GOLDEN (default wid-golden), WID_VM_SSH_USER (default admin),
#         WID_VM_KEEP=1 to keep the clone for debugging, WID_VM_EXPECT_SHA to require
#         an exact DMG checksum (defaults to a sibling .sha256 file when present).
#         WID_VM_NO_LAUNCHD=1 to keep the run in the caller's process tree.
# [OUTPUT] A timestamped evidence bundle (evidence-dir, default
#          <root>/evidence/<timestamp>): screen.mov assembled from the guest's
#          timestamped frame stream, per-step screenshots and AX snapshots,
#          journey.log, launch watchers, panel/ (the six-lens review of this same
#          bundle), summary.json and notes.md. Exit 0 only when the guest journey
#          passed, the assembled recording covers the whole run without a gap, both
#          analyser stages recorded an assertion and all six lenses completed; exit 1
#          when the run is rejected; exit 78 when the only failing assertion is the
#          declared known defect; exit 79 when the six-lens review did not complete;
#          exit 2 on a rig setup error.
# [POS] apps/macos/FirstLine/scripts/vm-journey.sh - the recorded acceptance entry
#       point. Runs ON the Mac mini (everything heavy stays there): clones the
#       prepared golden VM, boots it headless, installs the DMG inside the guest,
#       drives the shipped app with real input while recording the guest screen,
#       copies the evidence back and destroys the clone.
# [PROTOCOL] One run = one clean clone. The Mini's own screen, login keychain and
#            GUI session are never used: the guest boots with --no-graphics and its
#            screen is captured inside the guest. A failed, interrupted or truncated
#            recording fails the run. Preparation lives in scripts/vm/prepare-guest.sh.
#            Assertions are never weakened. One artifact may carry a declared known
#            defect (a checksum plus one assertion id plus a reference). That run
#            exits 78, never 0: it reproduces a defect and is not a pass. The run
#            fails when the declared defect no longer reproduces. The six-lens review
#            is the last stage of the run; when no reviewer answered, the bundle
#            records "panel not run" with the exact re-run command and the run exits
#            79 instead of signing off. Sign-off asserts the six lenses by name, not
#            the panel's own count.
set -uo pipefail

artifact="${1:?usage: vm-journey.sh <dmg-or-app-path> [evidence-dir]}"
artifact_kind=dmg
[[ "$artifact" == *.app ]] && artifact_kind=app
dmg="$artifact"
root="${WID_VM_ROOT:-$HOME/wid-vm}"
golden="${WID_VM_GOLDEN:-wid-golden}"
ssh_user="${WID_VM_SSH_USER:-admin}"
keep="${WID_VM_KEEP:-0}"
scripts="$(cd "$(dirname "$0")" && pwd)"
die() { printf 'vm-journey: ERROR: %s\n' "$*" >&2; exit 2; }
# macOS Local Network Privacy blocks the guest address for an app that was never
# granted local network access, and every connection then fails with EHOSTUNREACH
# even though the VM is up. A launchd job is not blocked, so the run moves there.
# shellcheck source=vm/launchd-host.sh
. "$scripts/vm/launchd-host.sh" || die "could not load $scripts/vm/launchd-host.sh"
command -v wid_launchd_reexec >/dev/null || die "wid_launchd_reexec is missing from $scripts/vm/launchd-host.sh"
wid_launchd_reexec "$0" "$@"
run_id="$(date +%Y%m%d-%H%M%S)"
vm="wid-run-$run_id"
evidence="${2:-$root/evidence/$run_id}"
key="$root/ssh/id_ed25519"

log() { printf 'vm-journey: %s\n' "$*"; }

if [[ "$artifact_kind" == 'app' ]]; then
  [[ -d "$artifact" ]] || die "app bundle not found: $artifact"
else
  [[ -f "$artifact" ]] || die "DMG not found: $artifact"
fi
dmg="$(cd "$(dirname "$artifact")" && pwd -P)/$(basename "$artifact")"
command -v tart >/dev/null || die 'tart is not installed'
tart list | awk 'NR>1 && $2 == "'"$golden"'" { found = 1 } END { exit !found }' \
  || die "golden image $golden is missing; run scripts/vm/prepare-guest.sh first"
[[ -x "$root/bin/license-fixture" ]] || die "$root/bin/license-fixture is missing; re-run scripts/vm/prepare-guest.sh"
[[ -f "$key" ]] || die "$key is missing; re-run scripts/vm/prepare-guest.sh"
command -v ffprobe >/dev/null || die 'ffprobe is not installed (brew install ffmpeg)'

expected_sha="${WID_VM_EXPECT_SHA:-}"
if [[ -z "$expected_sha" && "$artifact_kind" == 'dmg' && -f "$dmg.sha256" ]]; then
  expected_sha="$(cut -d' ' -f1 <"$dmg.sha256")"
fi
artifact_sha=''
[[ "$artifact_kind" == 'dmg' ]] && artifact_sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"

# A declared known defect: an artifact whose acceptance is understood to fail one
# exact assertion for a documented reason. The key is the artifact checksum plus the
# assertion id, so no other artifact and no other assertion can borrow it, and a run
# whose declared assertion passes fails instead (the declaration must then be removed).
known_defect_sha='5b8483bd210e5f4c697265fad0c447b4bc88b9265a1999bd9a7566be74bf4bc4'
known_defect_id='licensed-launch-no-activation-page'
known_defect_reference='PR 62 https://github.com/ichts/zerodraft/pull/62 fixes this on main; the 1.0 DMG predates it. A licensed Mac opened the activation card until license revalidation returned, because entitlement required that no validation be in flight and the launch validation always starts in flight.'
declared_defect=0
[[ -n "$artifact_sha" && "$artifact_sha" == "$known_defect_sha" ]] && declared_defect=1


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

log 'staging the artifact, licence fixture and journey script in the guest'
guest_ssh 'rm -rf /tmp/wid-run && mkdir -p /tmp/wid-run /tmp/wid-evidence' || die 'could not prepare the guest workspace'
if [[ "$artifact_kind" == 'app' ]]; then
  tar -cf - -C "$(dirname "$dmg")" "$(basename "$dmg")" \
    | guest_ssh 'tar -xf - -C /tmp/wid-run' || die 'could not copy the app bundle into the guest'
else
  cat "$dmg" | guest_ssh "cat > $(printf '%q' "/tmp/wid-run/$(basename "$dmg")")" || die 'could not copy the DMG into the guest'
fi
cat "$root/bin/license-fixture" | guest_ssh 'cat > /tmp/wid-run/license-fixture && chmod +x /tmp/wid-run/license-fixture' || die 'could not copy the license fixture'
cat "$scripts/vm/guest-journey.sh" | guest_ssh 'cat > /tmp/wid-run/guest-journey.sh && chmod +x /tmp/wid-run/guest-journey.sh' || die 'could not copy the journey script'
if [[ "$artifact_kind" == 'dmg' ]]; then
  guest_ssh 'shasum -a 256 /tmp/wid-run/'"$(basename "$dmg")" | cut -d' ' -f1 >"$evidence/guest-sha256.txt"
  [[ "$(cut -d' ' -f1 <"$evidence/guest-sha256.txt")" == "$artifact_sha" ]] \
    || die 'the DMG changed while copying it into the guest'
else
  # The digest covers file contents in path order with the leading directory
  # stripped, so the copy inside the guest and the copy here hash the same bytes.
  guest_ssh 'cd /tmp/wid-run && find "'"$(basename "$dmg")"'" -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | cut -d" " -f1 | shasum -a 256' \
    | cut -d' ' -f1 >"$evidence/guest-sha256.txt"
  ( cd "$dmg" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | cut -d' ' -f1 | shasum -a 256 ) \
    | cut -d' ' -f1 >"$evidence/host-sha256.txt"
  [[ "$(cat "$evidence/guest-sha256.txt")" == "$(cat "$evidence/host-sha256.txt")" ]] \
    || die 'the app bundle changed while copying it into the guest'
fi

guest_mode=''
[[ "$artifact_kind" == 'app' ]] && guest_mode='--licensed-only'
if [[ "$artifact_kind" == 'app' ]]; then
  log 'running the licensed-launch proof inside the guest (three relaunches)'
else
  log 'running the recorded journey inside the guest (this takes about four minutes)'
fi
guest_status=0
remote_artifact="/tmp/wid-run/$(basename "$dmg")"
guest_command="/bin/bash /tmp/wid-run/guest-journey.sh /tmp/wid-evidence $(printf '%q' "$remote_artifact") $(printf '%q' "$expected_sha") /tmp/wid-run/license-fixture $guest_mode"
guest_ssh "$guest_command" 2>&1 | tee "$evidence/runner.log" || guest_status=$?

log 'copying the evidence bundle back'
if guest_ssh 'cd /tmp/wid-evidence && tar -cf - .' | tar -xf - -C "$evidence"; then
  log "evidence in $evidence"
else
  log 'ERROR: could not copy the evidence bundle back'
  [[ "$guest_status" -eq 0 ]] && guest_status=1
fi

# The guest records one timestamped JPEG per tick (see scripts/vm/guest-journey.sh).
# The video is assembled here, where the encoder costs the VM nothing, and a broken,
# interrupted or gapped frame stream fails the run instead of quietly becoming a
# shorter clip that looks fine.
minimum_duration=60
[[ "$artifact_kind" == 'app' ]] && minimum_duration=20
assemble_recording() {
  local dir="$evidence/frames" manifest="$evidence/frames.tsv" list="$evidence/frames.concat"
  local count span max_gap duration size
  [[ -s "$manifest" ]] || { log 'ERROR: the guest returned no frame stream'; return 1; }
  count="$(wc -l <"$manifest" | tr -d ' ')"
  read -r span max_gap < <(awk -F'\t' '
    NR == 1 { first = $1 }
    { if (NR > 1 && $1 - prev > gap) gap = $1 - prev; prev = $1; last = $1 }
    END { printf "%d %d\n", last - first, gap + 0 }' "$manifest")
  log "frame stream: $count frames over $((span / 1000))s, largest gap ${max_gap}ms"
  if [[ "${max_gap:-0}" -gt 2000 ]]; then
    log "ERROR: the frame stream has a ${max_gap}ms gap, so the recording is not continuous"
    return 1
  fi
  awk -F'\t' -v dir="$dir" -v q="'" '
    { ts[NR] = $1; name[NR] = $2; n = NR }
    END {
      for (i = 1; i <= n; i++) {
        duration = (i < n ? ts[i + 1] - ts[i] : 250) / 1000
        if (duration <= 0) duration = 0.25
        printf "file %s%s/%s%s\nduration %.3f\n", q, dir, name[i], q, duration
      }
    }' "$manifest" >"$list"
  if ! ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" -fps_mode vfr \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p -movflags +faststart \
    "$evidence/screen.mov" >>"$evidence/recording.log" 2>&1; then
    log 'ERROR: could not assemble screen.mov from the frame stream'
    return 1
  fi
  duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$evidence/screen.mov" 2>/dev/null)"
  size="$(stat -f %z "$evidence/screen.mov" 2>/dev/null || printf 0)"
  log "recording: ${duration}s, $((span / 1000))s of captured wall clock, $size bytes"
  if ! awk -v d="${duration:-0}" -v s="$span" 'BEGIN { exit !(d + 1.5 >= s / 1000) }'; then
    log 'ERROR: the assembled video is shorter than the captured frame stream'
    return 1
  fi
  if ! awk -v d="${duration:-0}" -v min="$minimum_duration" 'BEGIN { exit !(d >= min) }'; then
    log "ERROR: the recording is shorter than ${minimum_duration}s, so it cannot cover the case"
    return 1
  fi
  printf '%s\t%s\t%s\t%s\n' "$duration" "$count" "$size" "$max_gap" >"$evidence/recording.tsv"
  # Deterministic analysis runs on every recording, at the recorder's full frame
  # rate, before the frames are dropped. Its FAIL lines join journey.log, so a
  # transient launch surface, a capture gap or a frozen screen fails the run.
  if ! command -v python3 >/dev/null; then
    log 'ERROR: python3 is required for the deterministic recording analysis'
    return 1
  fi
  local fail_before fail_after analysis_status
  fail_before="$(grep -c '^FAIL ' "$evidence/journey.log" 2>/dev/null || true)"
  python3 "$scripts/vm/analyse-recording.py" "$evidence" >>"$evidence/journey.log" 2>&1
  analysis_status=$?
  fail_after="$(grep -c '^FAIL ' "$evidence/journey.log" 2>/dev/null || true)"
  if [[ "$analysis_status" -ne 0 && "${fail_after:-0}" -le "${fail_before:-0}" ]]; then
    printf 'FAIL [recording-analysis] the analyser exited %s without recording a failed assertion\n' \
      "$analysis_status" >>"$evidence/journey.log"
    log "ERROR: the deterministic analysis exited $analysis_status with no assertion line"
    return 1
  fi
  if [[ "$analysis_status" -eq 0 ]] && ! grep -q '^PASS \[recording-analysis\] ' "$evidence/journey.log"; then
    printf 'FAIL [recording-analysis] the analyser exited 0 without recording an assertion\n' >>"$evidence/journey.log"
    log 'ERROR: the deterministic analysis produced no assertion line'
    return 1
  fi
  rm -rf "$dir" "$list"
  return 0
}
recording_ok=1
assemble_recording || { recording_ok=0; guest_status=1; }

# --- acceptance verdict ------------------------------------------------------
# Only assertion outcomes decide here. A declared known defect excuses exactly one
# assertion id on exactly one artifact checksum, it is printed as a defect rather
# than a pass, and a run whose declared assertion passes is rejected so the stale
# declaration cannot survive the fix.
fail_total="$(grep -c '^FAIL ' "$evidence/journey.log" 2>/dev/null)"
fail_total="${fail_total:-0}"
declared_failures=0
if [[ "$declared_defect" -eq 1 ]]; then
  declared_failures="$(grep -c "^FAIL \[$known_defect_id\] " "$evidence/journey.log" 2>/dev/null)"
  declared_failures="${declared_failures:-0}"
fi
other_failures=$((fail_total - declared_failures))

verdict='accepted'
if [[ "$recording_ok" -ne 1 ]]; then
  verdict='rejected'
  log 'ERROR: the evidence recording failed its continuity or length checks'
elif [[ "$other_failures" -gt 0 ]]; then
  verdict='rejected'
  log "ERROR: $other_failures assertion(s) failed outside any declared known defect"
elif [[ "$declared_defect" -eq 1 ]]; then
  if [[ "$declared_failures" -ge 1 ]]; then
    verdict='accepted-with-declared-defect'
  else
    verdict='rejected'
    log 'ERROR: the declared known defect did not reproduce; remove the stale expectation'
  fi
elif [[ "$fail_total" -eq 0 ]]; then
  verdict='accepted'
else
  verdict='rejected'
fi
if [[ "$verdict" != 'rejected' && "$guest_status" -ne 0 && "$declared_failures" -eq 0 ]]; then
  verdict='rejected'
  log 'ERROR: the guest exited non-zero without a matching failed assertion (rig setup error)'
fi

{
  printf 'artifact: %s\n' "$artifact"
  printf 'artifact_sha256: %s\n' "${artifact_sha:-locally built bundle}"
  printf 'assertions_failed: %s\n' "$fail_total"
  printf 'assertions_failed_outside_declared_defect: %s\n' "$other_failures"
  printf 'verdict: %s\n' "$verdict"
  if [[ "$declared_defect" -eq 1 ]]; then
    printf 'declared_known_defect: %s\n' "$known_defect_id"
    printf 'declared_known_defect_state: %s\n' \
      "$([[ "$declared_failures" -ge 1 ]] && printf 'reproduced' || printf 'did-not-reproduce')"
    printf 'declared_known_defect_reference: %s\n' "$known_defect_reference"
    printf 'known_defect_assertion_source: %s\n' "$(grep -m1 "^FAIL \[$known_defect_id\] \|^PASS \[$known_defect_id\] " "$evidence/journey.log")"
  fi
} >"$evidence/acceptance.txt"

if [[ "$declared_defect" -eq 1 ]]; then
  {
    printf '\n## Declared known defect - this is not a product pass\n\n'
    printf -- '- Assertion: `%s`\n' "$known_defect_id"
    printf -- '- Artifact: `%s` (this checksum only)\n' "$artifact_sha"
    printf -- '- State: %s\n' "$([[ "$declared_failures" -ge 1 ]] && printf 'reproduced' || printf 'did not reproduce')"
    printf -- '- Reference: %s\n' "$known_defect_reference"
    printf -- '- Acceptance of the next signed DMG (1.1, built from a commit that contains that fix)\n'
    printf '  runs with no declaration and must pass this assertion.\n'
  } >>"$evidence/notes.md"
fi

# --- six-lens design review --------------------------------------------------
# The recorded acceptance ends with the six-lens review inside this bundle. The panel
# is a stage of the run, not a separate command: its lens results are part of the
# sign-off, and a run whose panel did not run is declared and blocked, never silently
# passed.
panel_command="bash $(printf '%q' "$scripts/design-panel.sh") $(printf '%q' "$evidence")"
panel_status=0
bash "$scripts/design-panel.sh" "$evidence" >>"$evidence/panel.log" 2>&1 || panel_status=$?
required_lenses='rams norman spiekermann kare matas vignelli'
panel_summary="$(python3 "$scripts/vm/panel-lib.py" status "$evidence" --require $required_lenses 2>/dev/null)"
analysis_line="$(sed -n 's/^analysis=//p' <<<"$panel_summary")"
analysis_line="${analysis_line:-not recorded: the panel produced no status}"
panel_total="$(sed -n 's/^lenses_total=//p' <<<"$panel_summary")"
panel_complete="$(sed -n 's/^lenses_complete=//p' <<<"$panel_summary")"
panel_missing="$(sed -n 's/^lenses_required_missing=//p' <<<"$panel_summary")"
panel_total="${panel_total:-0}"
panel_complete="${panel_complete:-0}"
panel_reason="$(sed -n 's/^reason=//p' <<<"$panel_summary")"
panel_state='complete'
if [[ "$panel_status" -ne 0 ]]; then
  panel_state='not run'
  panel_reason="design-panel.sh exited $panel_status; see panel/panel.log"
elif [[ "$panel_total" -ne 6 || -n "${panel_missing:-}" ]]; then
  panel_state='not run'
  panel_reason="${panel_reason:-the six-lens review is incomplete: $panel_total lens(es) recorded, $panel_complete complete, missing: ${panel_missing:-none}}"
fi
{
  printf 'analysis: %s\n' "$analysis_line"
  printf 'panel: %s\n' "$panel_state"
  printf 'panel_lenses_complete: %s/%s\n' "$panel_complete" "$panel_total"
  printf 'panel_lenses_required: %s\n' "$required_lenses"
  printf 'panel_command: %s\n' "$panel_command"
  while IFS=$'\t' read -r lens_name lens_state lens_verdict lens_findings _lens_error; do
    [[ -n "${lens_name:-}" ]] || continue
    printf 'panel_lens: %s\t%s\t%s\t%s\n' "$lens_name" "$lens_state" "$lens_verdict" "$lens_findings"
  done < <(sed -n 's/^lens=//p' <<<"$panel_summary")
  [[ "$panel_state" == 'complete' ]] || printf 'panel_not_run: %s\n' "$panel_reason"
} >>"$evidence/acceptance.txt"
if [[ "$panel_state" != 'complete' ]]; then
  {
    printf '\n## Six-lens review incomplete - this bundle cannot sign off\n\n'
    printf -- '- Reason: %s\n' "$panel_reason"
    printf -- '- Lenses complete: %s of %s\n' "$panel_complete" "$panel_total"
    printf -- '- Re-run for this bundle: `%s`\n' "$panel_command"
  } >>"$evidence/notes.md"
fi

sign_off='accepted'
if [[ "$verdict" == 'rejected' ]]; then
  sign_off='not accepted - an assertion or the recording failed'
elif [[ "$panel_state" != 'complete' ]]; then
  sign_off="blocked - the six-lens review did not run ($panel_reason)"
elif [[ "$verdict" == 'accepted-with-declared-defect' ]]; then
  sign_off='not accepted - the declared known defect reproduced on this artifact'
fi
printf 'sign_off: %s\n' "$sign_off" >>"$evidence/acceptance.txt"
cat "$evidence/acceptance.txt"

log "verdict: $verdict; assertions failed: $fail_total (declared: $declared_failures, other: $other_failures); analysis: $analysis_line; panel: $panel_state ($panel_complete/$panel_total lenses); sign-off: $sign_off"
if [[ "$verdict" == 'rejected' ]]; then
  exit 1
fi
if [[ "$panel_state" != 'complete' ]]; then
  log 'ERROR: the six-lens review did not complete, so this bundle cannot sign off'
  exit 79
fi
if [[ "$verdict" == 'accepted-with-declared-defect' ]]; then
  log 'ERROR: this artifact is accepted only with a declared known defect; it is not a clean pass'
  exit 78
fi
exit 0
