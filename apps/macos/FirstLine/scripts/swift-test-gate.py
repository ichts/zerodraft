"""[INPUT] `swift test` arguments after the gate's own options (`--stall-seconds`, `--build-seconds`).
[OUTPUT] The suite's own output, then one verdict line; exit 0 only when the run printed its own summary,
         every test it started reported, and nothing failed. Exit 1 when the run reported nothing, ended
         without a summary, lost tests it had started, failed a test, skipped a test, or went silent past
         the watchdog. With `--json PATH` it also writes the same counts and verdict as a JSON object
         (scripts/nightly-swift-tests.sh reads that file instead of parsing the printed text a second time).
[POS] apps/macos/FirstLine/scripts/swift-test-gate.py - the only command a hand-off may cite as the Mac
      suite's evidence. `swift test` exits 0 without running or reporting anything on this host (measured
      2026-11-09: `--filter "RoomTests|PinyinInputTests|EditingCommandTests"` exited 0 after 61 s with
      `Executed 0 tests` at the XCTest layer and no result line at all; `--filter RoomTests` exited after
      48 tests started and 11 reported, with no terminating line; a full run passed 397 tests and then sat
      at 100% CPU for 312 s with no output). A bare exit code is therefore not evidence, and the gate is.
[PROTOCOL] The child writes to a pty, so its progress arrives line by line instead of in one block at exit;
           the watchdog is a silence budget, not a total budget, so a slow-but-progressing build is never
           killed. The build phase (before the first test line) has its own, longer silence budget.
"""
import argparse
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

# swift-testing prints `━` instead of `✔` on a passing test or run that recorded a known issue
# (withKnownIssue); the verdict word, not the mark, says whether it passed.
ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
SUMMARY = re.compile(r'^(?P<mark>[✔✘━]) Test run with (?P<tests>\d+) tests? in (?P<suites>\d+) suites? '
                     r'(?P<verdict>passed|failed) after')
RESULT = re.compile(r'^(?P<mark>[✔✘━]) Test (?P<name>\S.*?) (?P<verdict>passed|failed) after ')
STARTED = re.compile(r'^◇ Test (?P<name>\S.*?) started\.$')
SKIPPED = re.compile(r'^\u279c Test (?P<name>\S.*?) skipped')
KNOWN_ISSUE = re.compile(r'^━ Test (?P<name>\S.*?) recorded a known issue')
BUILD_SILENCE = 900
STALL_SILENCE = 180


def main(argv):
    gate = argparse.ArgumentParser(add_help=True, description='Run swift test and refuse to call it green '
                                  'unless it printed its own result.')
    gate.add_argument('--stall-seconds', type=int, default=STALL_SILENCE,
                      help='silence after the first test line that counts as a hang (default 180)')
    gate.add_argument('--build-seconds', type=int, default=BUILD_SILENCE,
                      help='silence before the first test line that counts as a stuck build (default 900)')
    gate.add_argument('--json', metavar='PATH', help='also write the counts and verdict to PATH as JSON')
    options, passthrough = gate.parse_known_args(argv)
    command = ['swift', 'test'] + [arg for arg in passthrough if arg != '--']

    master, slave = pty.openpty()
    started_at = time.monotonic()
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave,
                             start_new_session=True)
    os.close(slave)

    started = {}
    results = {}
    known_issues = {}
    skipped = {}
    summary = None
    last_output = time.monotonic()
    killed_for_silence = None
    buffer = b''

    def consume(line):
        nonlocal summary, last_output
        line = ANSI.sub('', line.rstrip('\r\n'))
        if not line:
            return
        print(line, flush=True)
        last_output = time.monotonic()
        if line.startswith('◇ Test case ') or line.startswith('◇ Test run '):
            return
        match = SUMMARY.match(line)
        if match:
            summary = {'mark': match['mark'], 'tests': int(match['tests']),
                       'suites': int(match['suites']), 'verdict': match['verdict']}
            return
        match = STARTED.match(line)
        if match:
            started[match['name']] = None
            return
        match = RESULT.match(line)
        if match and not match['name'].startswith('run with '):
            results[match['name']] = match['verdict']
            return
        match = SKIPPED.match(line)
        if match:
            skipped[match['name']] = None
            return
        match = KNOWN_ISSUE.match(line)
        if match:
            known_issues[match['name']] = None

    try:
        while True:
            ready, _, _ = select.select([master], [], [], 1.0)
            if ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    chunk = b''
                if not chunk:
                    break
                buffer += chunk
                while b'\n' in buffer:
                    raw, buffer = buffer.split(b'\n', 1)
                    consume(raw.decode('utf-8', 'replace'))
                continue
            silence = time.monotonic() - last_output
            limit = options.build_seconds if not started and not results else options.stall_seconds
            if silence > limit:
                killed_for_silence = silence
                os.killpg(os.getpgid(child.pid), signal.SIGKILL)
                break
    finally:
        if buffer:
            consume(buffer.decode('utf-8', 'replace'))
        try:
            code = child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(child.pid), signal.SIGKILL)
            code = child.wait()
        os.close(master)

    elapsed = time.monotonic() - started_at
    failed = sorted(name for name, verdict in results.items() if verdict == 'failed')
    problems = []
    if killed_for_silence is not None:
        problems.append(f'the run went {killed_for_silence:.0f} s without a line and was killed')
    if code != 0:
        problems.append(f'swift test exited {code}')
    if not results:
        problems.append('the run reported no test result at all')
    if skipped:
        problems.append(f'{len(skipped)} test(s) were skipped: {", ".join(sorted(skipped))}')
    if failed:
        problems.append(f'{len(failed)} test(s) failed: {", ".join(failed)}')
    if summary is None:
        problems.append(f'the run ended without its own summary line ({len(started)} started, '
                        f'{len(results)} reported)')
    else:
        if summary['verdict'] != 'passed' or summary['mark'] == '✘':
            problems.append(f'the run summary says {summary["verdict"]}')
        if summary['tests'] == 0:
            problems.append('the run summary counts zero tests')
        if summary['tests'] < len(started):
            problems.append(f'{len(started) - summary["tests"]} of the {len(started)} tests that started '
                            f'never reported')
        if summary['tests'] != len(results) + len(skipped):
            problems.append(f'the run summary counts {summary["tests"]} tests but {len(results)} result '
                            f'lines and {len(skipped)} skips were printed')

    if options.json:
        record = {'verdict': 'fail' if problems else 'pass', 'exit_code': code, 'problems': problems,
                  'executed': len(results), 'passed': len(results) - len(failed), 'failed': len(failed),
                  'failed_names': failed, 'skipped': len(skipped), 'skipped_names': sorted(skipped),
                  'known_issues': len(known_issues), 'summary_tests': summary['tests'] if summary else None,
                  'suites': summary['suites'] if summary else None, 'seconds': round(elapsed, 1)}
        with open(options.json, 'w', encoding='utf-8') as handle:
            json.dump(record, handle, indent=2)
            handle.write('\n')

    if problems:
        print('\nGATE FAIL - ' + '; '.join(problems), flush=True)
        return 1
    print(f'\nGATE PASS - {summary["tests"]} tests in {summary["suites"]} suites, 0 failed, '
          f'{len(results)} reported, {len(known_issues)} with a known issue, {elapsed:.0f} s', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
