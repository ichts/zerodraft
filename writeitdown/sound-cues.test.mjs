// The landing demo's sound cues, walked across a whole loop on the demo's own 50 ms tick.
import test from 'node:test';
import assert from 'node:assert/strict';
import { TIMELINE } from './demo-timeline.mjs';
import { cuesBetween, FRESH_MS } from './sound-cues.mjs';

const SILENT_END = TIMELINE.typeEnd + 5000, WARN_END = SILENT_END + 3000, LOOP = WARN_END + 200 + 2000;
const walk = (from, to, step) => {
  const cues = [];
  for (let t = from; t < to; t += step) cues.push(...cuesBetween(t, Math.min(t + step, to), TIMELINE.events, SILENT_END, WARN_END));
  return cues;
};

test('one loop owes every key once, the 3-2-1 once each, and the wipe once', () => {
  const cues = walk(0, LOOP, 50);
  const typed = TIMELINE.events.filter(e => e.kind === 'type' || e.kind === 'line').length;
  assert.equal(cues.filter(c => c.role === 'key').length, typed);
  assert.deepEqual(cues.filter(c => c.role === 'warn').map(c => c.step), [0, 1, 2]);
  assert.equal(cues.filter(c => c.role === 'wipe').length, 1);
});

test('the blocked Backspace is silent (D-046)', () => {
  const deny = TIMELINE.events.find(e => e.kind === 'deny');
  assert.deepEqual(cuesBetween(deny.t - 1, deny.t + 1, [deny], SILENT_END, WARN_END), []);
});

test('the count and the wipe land on the warning and the cut, not before', () => {
  assert.deepEqual(cuesBetween(SILENT_END - 50, SILENT_END, [], SILENT_END, WARN_END), [{ role: 'warn', step: 0 }]);
  assert.deepEqual(cuesBetween(SILENT_END - 51, SILENT_END - 1, [], SILENT_END, WARN_END), []);
  assert.deepEqual(cuesBetween(WARN_END - 50, WARN_END, [], SILENT_END, WARN_END), [{ role: 'wipe' }]);
});

test('a resumed tab owes nothing: a window longer than FRESH_MS is not a burst of sound', () => {
  assert.deepEqual(cuesBetween(0, 8000, TIMELINE.events, SILENT_END, WARN_END), []);   // eight seconds in one step, full of keys
  assert.equal(cuesBetween(1000, 1000 + FRESH_MS, TIMELINE.events, SILENT_END, WARN_END).length > 0, true);   // the edge itself still plays
  assert.deepEqual(cuesBetween(1000, 900, TIMELINE.events, SILENT_END, WARN_END), []);
});
