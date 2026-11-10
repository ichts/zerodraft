#!/bin/bash
# [INPUT] Environment only (all optional): WID_NIGHTLY_SOURCE (git URL or path, default the GitHub repo),
#         WID_NIGHTLY_REF (branch or tag, default main), WID_NIGHTLY_OUT (record directory, default
#         ~/.local/state/wid-swift-nightly), WID_NIGHTLY_LOCK (fmlock path), WID_NIGHTLY_LOCK_WAIT
#         (seconds to wait for the machine-wide swift lock, default 14400), WID_NIGHTLY_TEST_ARGS (extra
#         `swift test` arguments, for the negative control only).
# [OUTPUT] <out>/runs/<UTC id>/{record.json,summary.txt,build.log,swift-test.log,gate.json}, <out>/latest.json
#          (copy of the newest record) and one JSON line per run appended to <out>/history.jsonl. Exit 0 only
#          when the whole Swift suite passed through swift-test-gate.py; 1 when a test failed or the gate
#          refused; 2 when the run could not happen (lock, clone, build).
# [POS] apps/macos/FirstLine/scripts/nightly-swift-tests.sh - the nightly Mac suite runner. It tests a
#       fresh shallow clone, never a working checkout, and ships nothing: no signing, no packaging, no
#       appcast. The launchd agent that calls it is machine state; its template and install steps are
#       docs/NIGHTLY_TESTS.md.
# [PROTOCOL] Holds the machine-wide `swift` heavy lock (~/.fm-heavy-locks) from before the clone until
#            cleanup and records how long it waited. Every process the run started is found by the clone's
#            path and killed, any simulator it did not find booted is shut down, and a leftover process
#            or a dirty clone fails the run: a nightly job that leaves things behind is a defect. The counts
#            come from swift-test-gate.py --json, never from a second parse of the log, so a zero-test or
#            summary-less run cannot be recorded as a pass.
set -u
set -o pipefail

PATH=${PATH:+$PATH:}/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

SOURCE=${WID_NIGHTLY_SOURCE:-https://github.com/ichts/zerodraft.git}
REF=${WID_NIGHTLY_REF:-main}
OUT=${WID_NIGHTLY_OUT:-$HOME/.local/state/wid-swift-nightly}
FMLOCK=${WID_NIGHTLY_LOCK:-$HOME/.fm-heavy-locks/fmlock}
LOCK_WAIT=${WID_NIGHTLY_LOCK_WAIT:-14400}
# Word-split on purpose: a flat argument list such as `--filter nomatch`.
# shellcheck disable=SC2206
TEST_ARGS=(${WID_NIGHTLY_TEST_ARGS:-})
GATE_SCRIPT=scripts/swift-test-gate.py

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR=$OUT/runs/$RUN_ID
mkdir -p "$RUN_DIR" || { echo "cannot create $RUN_DIR" >&2; exit 2; }
START_EPOCH=$(date +%s)
START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

STAGE="lock"
FAILURE=""
COMMIT=""
LOCK_PATH=""
LOCK_WAITED=0
WORK=""
CHILD=""
BASELINE_SIMS=""
LEAKED=""
SIMS_SHUT=""
TREE_DIRTY=""
RUNNER_STALE=""
EXIT=0

log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" >&2; }

booted_sims() {
  command -v xcrun >/dev/null 2>&1 || return 0
  xcrun simctl list devices booted 2>/dev/null | grep -Eo '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | sort -u
}

# Runs "$@" with output to the log named by $1's caller; waits on it so a signal reaches the trap at once.
run_logged() {  # <logfile> <command...>
  local logfile=$1; shift
  "$@" >"$logfile" 2>&1 &
  CHILD=$!
  wait "$CHILD"
  local status=$?
  CHILD=""
  return $status
}

fail_with() {  # <exit code> <message>
  EXIT=$1
  FAILURE=$2
  log "FAIL ($STAGE): $FAILURE"
}

cleanup() {
  trap - EXIT INT TERM
  [ -n "$CHILD" ] && kill -TERM "$CHILD" 2>/dev/null
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then
    if [ -d "$WORK/repo/.git" ]; then
      TREE_DIRTY=$(git -C "$WORK/repo" status --porcelain 2>/dev/null | head -20)
    fi
    # The unique directory name, not its path: /var and /private/var both occur in child command lines.
    local mark
    mark=$(basename "$WORK")
    pkill -TERM -f "$mark" 2>/dev/null
    sleep 2
    pkill -KILL -f "$mark" 2>/dev/null
    sleep 1
    LEAKED=$(pgrep -fl "$mark" 2>/dev/null | head -10)
    local sim
    for sim in $(booted_sims); do
      case " $BASELINE_SIMS " in
        *" $sim "*) ;;
        *) xcrun simctl shutdown "$sim" >/dev/null 2>&1; SIMS_SHUT="$SIMS_SHUT $sim" ;;
      esac
    done
    rm -rf "$WORK"
  fi
  if [ -n "$TREE_DIRTY" ] && [ "$EXIT" -eq 0 ]; then
    EXIT=1
    FAILURE="the test run left the clone dirty: $(printf '%s' "$TREE_DIRTY" | tr '\n' ';')"
  fi
  if [ -n "$LEAKED" ] && [ "$EXIT" -eq 0 ]; then
    EXIT=1
    FAILURE="processes of the run were still alive after cleanup: $(printf '%s' "$LEAKED" | tr '\n' ';')"
  fi
  [ -n "$LOCK_PATH" ] && "$FMLOCK" release "$LOCK_PATH" >/dev/null 2>&1
  write_record
  exit "$EXIT"
}
trap cleanup EXIT
trap 'FAILURE=${FAILURE:-"interrupted by a signal"}; [ "$EXIT" -eq 0 ] && EXIT=2; exit "$EXIT"' INT TERM

write_record() {
  RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR OUT=$OUT START_ISO=$START_ISO START_EPOCH=$START_EPOCH STAGE=$STAGE \
  FAILURE=$FAILURE COMMIT=$COMMIT SOURCE=$SOURCE REF=$REF LOCK_WAITED=$LOCK_WAITED EXIT=$EXIT \
  LEAKED=$LEAKED SIMS_SHUT=$SIMS_SHUT TREE_DIRTY=$TREE_DIRTY RUNNER_STALE=$RUNNER_STALE TEST_ARGS="${TEST_ARGS[*]:-}" \
  python3 - <<'PY'
import json, os, platform, shutil, socket, subprocess, time

e = os.environ
run_dir = e['RUN_DIR']

def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ''

try:
    with open(os.path.join(run_dir, 'gate.json'), encoding='utf-8') as handle:
        gate = json.load(handle)
except (OSError, ValueError):
    gate = None

passed = e['EXIT'] == '0' and gate is not None and gate['verdict'] == 'pass'
record = {
    'run_id': e['RUN_ID'],
    'verdict': 'pass' if passed else 'fail',
    'exit_code': int(e['EXIT']),
    'stage_reached': e['STAGE'],
    'failure': e['FAILURE'] or None,
    'started_at': e['START_ISO'],
    'duration_seconds': int(time.time()) - int(e['START_EPOCH']),
    'lock_wait_seconds': int(e['LOCK_WAITED']),
    'commit': e['COMMIT'] or None,
    'source': e['SOURCE'],
    'ref': e['REF'],
    'extra_test_args': e['TEST_ARGS'] or None,
    'machine': {'host': socket.gethostname().split('.')[0], 'macos': platform.mac_ver()[0],
                'arch': platform.machine(), 'swift': (sh('swift', '--version').splitlines() or [''])[0],
                'load_average': [round(v, 1) for v in os.getloadavg()]},
    'counts': None if gate is None else {k: gate[k] for k in
              ('executed', 'passed', 'failed', 'skipped', 'known_issues', 'suites')},
    'failed_tests': [] if gate is None else gate['failed_names'],
    'gate_problems': [] if gate is None else gate['problems'],
    'runner_script_differs_from_commit': {'yes': True, 'no': False}.get(e['RUNNER_STALE']),
    'cleanup': {'leaked_processes': e['LEAKED'] or None, 'simulators_shut_down': e['SIMS_SHUT'].split(),
                'dirty_clone': e['TREE_DIRTY'] or None},
    'files': {'directory': run_dir, 'build_log': 'build.log', 'test_log': 'swift-test.log',
              'gate': 'gate.json'},
}
with open(os.path.join(run_dir, 'record.json'), 'w', encoding='utf-8') as handle:
    json.dump(record, handle, indent=2)
    handle.write('\n')

c = record['counts']
lines = [f"WID Swift nightly {record['run_id']}: {record['verdict'].upper()}",
         f"commit {record['commit'] or 'none'} ({record['ref']}) on {record['machine']['host']}, "
         f"{record['duration_seconds']} s, waited {record['lock_wait_seconds']} s for the swift lock"]
if c:
    lines.append(f"executed {c['executed']}, passed {c['passed']}, failed {c['failed']}, skipped {c['skipped']}, "
                 f"known issues {c['known_issues']}, suites {c['suites']}")
else:
    lines.append(f"no test counts: the run stopped at stage '{record['stage_reached']}'")
for name in record['failed_tests']:
    lines.append(f'failed: {name}')
for problem in record['gate_problems']:
    lines.append(f'gate: {problem}')
if record['failure']:
    lines.append(f"failure: {record['failure']}")
lines.append(f"record: {os.path.join(run_dir, 'record.json')}")
text = '\n'.join(lines) + '\n'
with open(os.path.join(run_dir, 'summary.txt'), 'w', encoding='utf-8') as handle:
    handle.write(text)
shutil.copyfile(os.path.join(run_dir, 'record.json'), os.path.join(e['OUT'], 'latest.json'))
with open(os.path.join(e['OUT'], 'history.jsonl'), 'a', encoding='utf-8') as handle:
    handle.write(json.dumps(record, separators=(',', ':')) + '\n')
print(text, end='')
PY
}

acquire_lock() {
  [ -x "$FMLOCK" ] || { fail_with 2 "no fmlock at $FMLOCK"; return 1; }
  local waited_from out
  waited_from=$(date +%s)
  log "waiting for the swift lock (up to $LOCK_WAIT s)"
  if ! out=$("$FMLOCK" acquire swift wid-swift-nightly "$LOCK_WAIT"); then
    LOCK_WAITED=$(( $(date +%s) - waited_from ))
    fail_with 2 "no swift lock after $LOCK_WAITED s"
    return 1
  fi
  LOCK_WAITED=$(( $(date +%s) - waited_from ))
  LOCK_PATH=$out
  # fmlock records its own short-lived PID; record this script's so a live holder is never reclaimed.
  printf 'wid-swift-nightly\t%s\n' "$$" > "$LOCK_PATH/owner"
  log "holding $LOCK_PATH after waiting $LOCK_WAITED s"
}

main() {
  acquire_lock || return
  BASELINE_SIMS=$(booted_sims | tr '\n' ' ')
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/wid-swift-nightly.XXXXXX") || { fail_with 2 "no temp directory"; return; }

  STAGE="clone"
  run_logged "$RUN_DIR/clone.log" git clone --quiet --depth 1 --branch "$REF" "$SOURCE" "$WORK/repo" \
    || { fail_with 2 "git clone of $REF from $SOURCE failed (clone.log)"; return; }
  COMMIT=$(git -C "$WORK/repo" rev-parse HEAD)
  local module=$WORK/repo/apps/macos/FirstLine
  [ -f "$module/$GATE_SCRIPT" ] || { fail_with 2 "$REF has no $GATE_SCRIPT"; return; }
  grep -q -- '--json' "$module/$GATE_SCRIPT" \
    || { fail_with 2 "$REF carries a swift-test-gate.py without --json; this runner needs the version that has it"; return; }
  # The agent runs an installed copy of this driver; say so when the tested commit carries a newer one.
  if cmp -s "$0" "$module/scripts/nightly-swift-tests.sh"; then RUNNER_STALE=no; else RUNNER_STALE=yes; fi

  STAGE="build"
  log "building once at $COMMIT"
  ( cd "$module" && exec swift build --build-tests ) >"$RUN_DIR/build.log" 2>&1 &
  CHILD=$!
  wait "$CHILD"; local build_status=$?; CHILD=""
  [ "$build_status" -eq 0 ] || { fail_with 2 "swift build --build-tests exited $build_status (build.log)"; return; }

  STAGE="test"
  log "running the suite through the gate"
  ( cd "$module" && exec python3 "$GATE_SCRIPT" --json "$RUN_DIR/gate.json" -- --skip-build ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} ) \
    >"$RUN_DIR/swift-test.log" 2>&1 &
  CHILD=$!
  wait "$CHILD"; local gate_status=$?; CHILD=""
  tail -3 "$RUN_DIR/swift-test.log" >&2
  [ "$gate_status" -eq 0 ] || { fail_with 1 "swift-test-gate.py exited $gate_status (swift-test.log)"; return; }
  STAGE="done"
}

main
