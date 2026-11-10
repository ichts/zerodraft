// What a person reads: one line per task and platform saying whether this build is faster, slower, or unchanged,
// and how many fewer steps the buyer takes. These tests pin the wording and the noise rule of that line, so a
// night loop's scorecard cannot quietly report a 40 ms wobble as an improvement.
import test from 'node:test';
import assert from 'node:assert/strict';
import { experienceLines, formatTable, runsToMetrics, fmtMs, median } from './metrics.mjs';

const metrics = (t1ms, t3ms = 900) => ({
  'web-desktop': {
    T1: { steps: 2, ms: t1ms },
    T3: { steps: 2, ms: t3ms }
  }
});

test('a change inside 5% is reported as noise, not as an improvement', () => {
  assert.equal(experienceLines(metrics(200), metrics(210))[0], 'Begin to writing (web-desktop): 200 ms to 210 ms (within noise), 0 fewer steps');
  assert.equal(experienceLines(metrics(200), metrics(251))[0], 'Begin to writing (web-desktop): 200 ms to 251 ms, 0 fewer steps');
});

test('a change under 50 ms is noise even when it is most of the value', () => {
  assert.match(experienceLines(metrics(100), metrics(149))[0], /\(within noise\)/);
  assert.doesNotMatch(experienceLines(metrics(100), metrics(151))[0], /\(within noise\)/);
});

test('steps are reported as fewer, more, or none', () => {
  const fewer = experienceLines(metrics(200), { 'web-desktop': { T1: { steps: 1, ms: 200 } } })[0];
  assert.match(fewer, /1 fewer steps/);
  const more = experienceLines(metrics(200), { 'web-desktop': { T1: { steps: 3, ms: 200 } } })[0];
  assert.match(more, /1 more steps/);
  assert.match(experienceLines(metrics(200), metrics(200))[0], /0 fewer steps/);
});

test('seconds read as seconds, and an unmeasured task says so instead of inventing a number', () => {
  assert.equal(fmtMs(1333), '1.33 s');
  assert.equal(fmtMs(212), '212 ms');
  const line = experienceLines(metrics(200), { 'web-desktop': { T1: { steps: 2, ms: null } } })[0];
  assert.match(line, /time unmeasured, 0 fewer steps/);
});

test('with nothing measurable the scorecard says exactly that', () => {
  assert.equal(experienceLines(metrics(200), metrics(200.5))[0], 'Begin to writing (web-desktop): 200 ms to 201 ms (within noise), 0 fewer steps');
  assert.equal(experienceLines({}, metrics(200)), 'No measurable change in the three core tasks.');
  assert.equal(experienceLines(metrics(200), { 'web-phone': { T1: { steps: 2, ms: 200 } } }), 'No measurable change in the three core tasks.');
});

test('a foreign metrics document still prints a table with no invented values', () => {
  const foreign = { 'web-desktop': { T1: { steps: 2, ms: 1333 }, T3: { steps: 2, ms: 698, n: 3 } } };
  const table = formatTable(foreign);
  assert.match(table, /T1 Begin to writing +\| web-desktop/);
  assert.doesNotMatch(table, /undefined|NaN/);
  assert.doesNotMatch(table, /first screen/);
});

test('the table takes the median of the runs and the sum of the product latencies it measured', () => {
  // The lower median of an even run count, so a two-run night reports a value it actually measured.
  assert.equal(median([100, 300, 200]), 200);
  assert.equal(median([100, 300]), 100);
  const m = runsToMetrics([
    { viewport: 'desktop', loadavg: 12, t1: { ms: { nav_to_fonts_ready: 100, click_to_editor_focus: 20, key_to_glyph_painted: 30 } } },
    { viewport: 'desktop', loadavg: 14, t1: { ms: { nav_to_fonts_ready: 300, click_to_editor_focus: 40, key_to_glyph_painted: 10 } } },
    { viewport: 'phone', loadavg: 14, t1: { ms: { nav_to_fonts_ready: 50, click_to_editor_focus: 10, key_to_glyph_painted: 20 } } }
  ], { at: 'now', head: 'abc123' });
  assert.equal(m['web-desktop'].T1.steps, 2);
  assert.equal(m['web-desktop'].T1.ms, 130); // 100 (nav, lower median) + 20 (focus) + 10 (glyph)
  assert.equal(m['web-desktop'].T1.n, 2);
  assert.equal(m['web-phone'].T1.ms, 80);
  assert.deepEqual(m.meta.head, 'abc123');
});
