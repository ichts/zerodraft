import test from 'node:test';
import assert from 'node:assert/strict';
import { fresh, advance, append, clock, wordCount } from './session.mjs';
import { LINES, TIMELINE, buildTimeline } from './demo-timeline.mjs';

test('rest has no running deadline', () => {
  assert.deepEqual(advance(fresh(), 999999), fresh());
});

test('five-second warning, recovery, eight-second wipe', () => {
  let state = append(fresh(), 'Hello', 1000);
  assert.equal(advance(state, 5999).phase, 'typing');
  state = advance(state, 6000);
  assert.equal(state.phase, 'warn');
  state = append(state, ' world', 7500);
  assert.equal(state.phase, 'typing');
  assert.equal(state.started, 1000);
  assert.equal(state.text, 'Hello world');
  assert.equal(advance(state, 15499).phase, 'warn');
  const wiped = advance(state, 15500);
  assert.equal(wiped.phase, 'wipe');
  assert.equal(wiped.text, '');
  assert.equal(wiped.unused, 46);
  state = append(wiped, 'New', 16000);
  assert.equal(state.started, 16000);
  assert.equal(state.text, 'New');
});

test('real deadline keeps only after sixty seconds', () => {
  let state = append(fresh(), 'Start', 0);
  for (let t = 6000; t <= 54000; t += 6000) state = append(state, ' words', t);
  assert.equal(advance(state, 59999).phase, 'warn');
  state = advance(state, 60000);
  assert.equal(state.phase, 'kept');
  assert.equal(append(state, ' no', 60001).text, state.text);
});

test('delayed ticks honor earlier absolute deadline and wipe wins a tie', () => {
  const running = { ...fresh(), phase: 'typing', started: 0, text: 'Draft' };
  assert.equal(advance({ ...running, lastInput: 54000 }, 100000).phase, 'kept');
  assert.equal(advance({ ...running, lastInput: 52000 }, 100000).phase, 'wipe');
  assert.equal(advance({ ...running, lastInput: 51000 }, 100000).phase, 'wipe');
});

test('late input cannot rescue an expired draft', () => {
  const state = append(append(fresh(), 'Old', 0), 'New', 8000);
  assert.equal(state.text, 'New');
  assert.equal(state.started, 8000);
});

test('whitespace does not produce a kept draft', () => {
  const state = { ...fresh(), phase: 'typing', started: 0, lastInput: 59000, text: ' \n ' };
  assert.equal(advance(state, 60000).phase, 'wipe');
});

test('demo timeline is deterministic and paced like a person', () => {
  assert.deepEqual(buildTimeline(), TIMELINE);
  const { events, typeEnd } = TIMELINE;
  // The preview keeps a human rhythm and a short loop: typing ends in
  // roughly thirteen seconds.
  assert.ok(typeEnd > 12000, `typing ends at ${typeEnd}, expected over 12000`);
  assert.ok(typeEnd < 17000, `typing ends at ${typeEnd}, expected under 17000`);
  const gaps = events.slice(1).map((event, i) => event.t - events[i].t);
  const min = Math.min(...gaps), max = Math.max(...gaps);
  assert.ok(max > min * 5, `gap spread ${min}-${max}ms must not read as a metronome`);
  assert.ok(gaps.some(gap => gap >= 350), 'word and punctuation pauses exist');
  assert.equal(events.filter(event => event.kind === 'line').length, LINES.length - 1);
});

test('demo is forward-only: the false start stays, Backspace is tried once and blocked', () => {
  const { events } = TIMELINE;
  assert.equal(events.filter(event => event.kind === 'back').length, 0, 'the demo never deletes');
  for (let i = 1; i < events.length; i++) {
    const [before, after] = [events[i - 1], events[i]];
    if (after.dn === before.dn) assert.ok(after.cur.startsWith(before.cur), `${before.cur} -> ${after.cur} only appends`);
  }
  const denies = events.filter(event => event.kind === 'deny');
  assert.equal(denies.length, 1, 'one blocked Backspace');
  const [deny] = denies;
  const before = events[events.indexOf(deny) - 1], after = events[events.indexOf(deny) + 1];
  assert.equal(deny.cur, before.cur, 'the blocked Backspace changes nothing');
  assert.ok(deny.t - before.t >= 350, 'a beat to notice the false start');
  assert.ok(after.t - deny.t >= 900, 'the blocked keycap holds before typing goes on');
  assert.equal(LINES[2], deny.cur + ' pretending.', 'the false start stays in the draft');
});

test('clock and word labels', () => {
  assert.equal(clock(60), '1:00');
  assert.equal(clock(0), '0:00');
  assert.equal(clock(37), '0:37');
  assert.equal(wordCount('  two\nwords '), 2);
  assert.equal(wordCount(''), 0);
});

test('Unicode words, individual Han characters, and non-word input', () => {
  const cases = [
    ['', 0], [' \n\t', 0], ['中文测试', 4], ['hello world 中文测试', 6],
    ['你好，world！', 3], ['café cafe\u0301', 2], ['مرحبا بالعالم', 2],
    ['こんにちは世界', 3], ['👨‍👩‍👧‍👦 👍🏽 🇨🇳', 0], ['...，！？', 0],
    ['𠀀中文', 3], ['你好👩🏽‍💻world', 3]
  ];
  for (const [text, expected] of cases) assert.equal(wordCount(text), expected, text);
});
