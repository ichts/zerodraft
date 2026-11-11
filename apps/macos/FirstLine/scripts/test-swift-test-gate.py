"""[INPUT] none; runs swift-test-gate.py against a stub `swift` that prints canned swift-testing output.
[OUTPUT] exit 0 when every case below gets the verdict and the --json counts it must; assertion error otherwise.
[POS] apps/macos/FirstLine/scripts/test-swift-test-gate.py - protects the Mac suite's evidence: the gate must
      never call an empty, summary-less, failing or skipping run green, and must not call a run that recorded a
      known issue red (swift-testing prints `━`, not `✔`, for those). The nightly job's counts come from this
      gate's --json file, so a wrong count here is a wrong morning scorecard.
[PROTOCOL] No Swift toolchain needed: the stub shadows `swift` on PATH. Run from anywhere.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

GATE = Path(__file__).resolve().parent / 'swift-test-gate.py'


def run(output):
    """Run the gate against a stub that prints `output` and exits 0, like `swift test` does on this host."""
    with tempfile.TemporaryDirectory(prefix='gate-test-') as directory:
        root = Path(directory)
        (root / 'canned.txt').write_text(output, encoding='utf-8')
        stub = root / 'swift'
        stub.write_text(f'#!/bin/sh\ncat "{root}/canned.txt"\nexit 0\n')
        stub.chmod(0o755)
        record = root / 'gate.json'
        env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}')
        done = subprocess.run([sys.executable, str(GATE), '--json', str(record), '--', '--skip-build'],
                              env=env, capture_output=True, text=True, timeout=60)
        return done.returncode, json.loads(record.read_text())


def started(name):
    return f'◇ Test {name} started.\n'


PASSED = '✔ Test {} passed after 0.001 seconds.\n'
RUN_START = '◇ Test run started.\n'

# A green run: three tests, summary agrees.
code, rec = run(RUN_START + ''.join(started(n) + PASSED.format(n) for n in ('a()', 'b()', 'c()')) +
                '✔ Test run with 3 tests in 1 suite passed after 0.01 seconds.\n')
assert code == 0 and rec['verdict'] == 'pass', (code, rec)
assert (rec['executed'], rec['passed'], rec['failed'], rec['skipped'], rec['suites']) == (3, 3, 0, 0, 1), rec

# A passing run that recorded a known issue prints `━` marks; it is still a pass and counts the test.
code, rec = run(RUN_START + started('a()') + PASSED.format('a()') + started('k()') +
                '━ Test k() recorded a known issue at T.swift:4:45: Expectation failed: false\n'
                '━ Test k() passed after 0.001 seconds with 1 known issue.\n'
                '━ Test run with 2 tests in 1 suite passed after 0.01 seconds with 1 known issue.\n')
assert code == 0 and rec['verdict'] == 'pass', (code, rec)
assert (rec['executed'], rec['passed'], rec['known_issues']) == (2, 2, 1), rec

# swift exited 0 and printed a summary of zero tests: the case the gate exists for.
code, rec = run(RUN_START + '✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.\n')
assert code == 1 and rec['verdict'] == 'fail' and rec['executed'] == 0, (code, rec)

# swift exited 0 and printed nothing from the suite at all.
code, rec = run('Test Suite \'All tests\' passed\n\t Executed 0 tests, with 0 failures\n')
assert code == 1 and rec['verdict'] == 'fail', (code, rec)

# Tests started but the run ended without its summary (a hang or a crash that still exits 0).
code, rec = run(RUN_START + started('a()') + started('b()') + PASSED.format('a()'))
assert code == 1 and rec['verdict'] == 'fail', (code, rec)

# A failing test is counted and named even though the stub exits 0.
code, rec = run(RUN_START + started('a()') + started('b()') + PASSED.format('a()') +
                '✘ Test b() failed after 0.001 seconds with 1 issue.\n'
                '✘ Test run with 2 tests in 1 suite failed after 0.01 seconds with 1 issue.\n')
assert code == 1 and rec['verdict'] == 'fail', (code, rec)
assert (rec['executed'], rec['passed'], rec['failed'], rec['failed_names']) == (2, 1, 1, ['b()']), rec

# A skipped test is never green: the testing rules forbid skipping, so the gate names it and fails.
code, rec = run(RUN_START + started('a()') + PASSED.format('a()') + '➜ Test off() skipped: "because"\n'
                '✔ Test run with 2 tests in 1 suite passed after 0.01 seconds.\n')
assert code == 1 and rec['verdict'] == 'fail', (code, rec)
assert rec['skipped'] == 1 and rec['skipped_names'] == ['off()'], rec
assert any('skipped' in problem for problem in rec['problems']), rec

print('swift-test-gate.py: 7 cases behaved')
