# Nightly Swift tests

`scripts/nightly-swift-tests.sh` runs the whole macOS Swift suite (`swift test`) every night on the Mac mini and leaves a record. Before it existed the suite ran in no automated job: the GitHub workflows cover only the web surface, and a bare `swift test` can exit 0 without running or reporting a test (`scripts/swift-test-gate.py` header).

## What one run does

1. Waits for the machine-wide `swift` heavy lock (`~/.fm-heavy-locks/fmlock`, one Swift build, test or simulator at a time) and records the wait. It holds the lock until cleanup.
2. Shallow-clones `WID_NIGHTLY_REF` (default `main`) of `WID_NIGHTLY_SOURCE` (default the GitHub repository) into a temporary directory. No working checkout is ever touched.
3. Builds once: `swift build --build-tests`.
4. Runs `swift test --skip-build` through `scripts/swift-test-gate.py --json`. The gate refuses an empty run, a run with no summary line, lost, failed or skipped tests, and a hang. The counts in the record are the gate's own.
5. Cleans up: kills every process whose command line names the temporary directory, shuts down any simulator that was not booted when the run started, deletes the clone, and fails the run if a process outlived the cleanup or the tests left the clone dirty.
6. Releases the lock and writes the record.

Exit codes: 0 pass; 1 a test failed or the gate refused; 2 the run could not happen (lock, clone, build).

## Where the record goes

`WID_NIGHTLY_OUT` (default `~/.local/state/wid-swift-nightly`):

| File | Content |
|---|---|
| `runs/<UTC id>/record.json` | verdict, commit, start time, machine, duration, lock wait, counts (`executed`, `passed`, `failed`, `skipped`, `known_issues`, `suites`), failed test names, gate problems, cleanup result |
| `runs/<UTC id>/summary.txt` | the same in five lines |
| `runs/<UTC id>/{build,swift-test,clone}.log`, `gate.json` | raw evidence |
| `latest.json` | copy of the newest `record.json` |
| `history.jsonl` | one compact record per run |
| `launchd.out`, `launchd.err` | the agent's own stdout and stderr |

A scorecard reads `latest.json` (`verdict`, `counts`, `started_at`).

## The launchd agent (machine state, not committed)

The agent file hardcodes this Mac's paths, so the repository carries only `docs/nightly-swift-tests.plist.template`. Install it on the Mac mini:

```sh
OUT="$HOME/firstmate-homes/wid/data/swift-nightly"
RUNNER="$OUT/bin/nightly-swift-tests.sh"
mkdir -p "$OUT/bin"
cp apps/macos/FirstLine/scripts/nightly-swift-tests.sh "$RUNNER"
sed -e "s|@RUNNER@|$RUNNER|" -e "s|@OUT@|$OUT|g" -e "s|@HOME@|$HOME|" -e "s|@HOUR@|4|" -e "s|@MINUTE@|30|" \
  apps/macos/FirstLine/docs/nightly-swift-tests.plist.template > ~/Library/LaunchAgents/com.ichts.wid-swift-nightly.plist
plutil -lint ~/Library/LaunchAgents/com.ichts.wid-swift-nightly.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.ichts.wid-swift-nightly.plist
launchctl print "gui/$(id -u)/com.ichts.wid-swift-nightly"
```

Run it now instead of waiting for the schedule: `launchctl kickstart "gui/$(id -u)/com.ichts.wid-swift-nightly"`. Remove it with `launchctl bootout "gui/$(id -u)/com.ichts.wid-swift-nightly"`.

The agent runs an installed copy of the runner. Copy the script again whenever it changes; `record.json` field `runner_script_differs_from_commit` says when the tested commit carries a different one.

### Why 04:30

`com.ichts.nightly-retro` runs at 03:00 and `com.ichts.sites-daily-check` at 07:15. 04:30 keeps the Mac mini's load clear of both. It also leaves four hours before an 08:30 scorecard for the lock wait (up to four hours) and the build and test run itself. The default lock wait is 14400 s (`WID_NIGHTLY_LOCK_WAIT`).

## Negative control

`WID_NIGHTLY_TEST_ARGS="--filter nomatch" bash scripts/nightly-swift-tests.sh` must exit 1 with `the run reported no test result at all` in `record.json`. A job that stays green on that input is broken.

## Windows on the Mac mini's screen

The suite is `swift test`, not a GUI journey, but some tests create real `NSWindow`s and call `makeKeyAndOrderFront` (`RoomTests`, `EditingCommandTests`), and the Pinyin test uses the real input context. They run in the xctest process, not in a built app. The nightly agent runs in the user's login session, so those windows can appear on the Mac mini's screen for the length of the test. Real-window acceptance, the shipped DMG and the recorded journeys still run only in the Tart VM (`scripts/vm-journey.sh`).

## What the nightly does not cover

Anything that needs a signed or notarised build, the real DMG, Sparkle updates against the live appcast, the packaged `.app`, a real license or Stripe checkout, a real GUI session with real HID input, a physical Mac other than this one, or macOS versions other than the Mac mini's. It tests the `main` commit as it stands at the start time; it does not test a branch unless `WID_NIGHTLY_REF` says so.
