import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fresh, advance, append, clock, wordCount, countLabel, historyLines, nextDeadline, GONE } from './session.mjs';
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

// The room arms a timer for the instant the session changes by itself, so that instant is a number here and is
// computed once: the earlier of the 60-second finish and the 8-second silence wipe. A sample can arrive up to a
// couple of ticks late; the timer cannot, which is why the number has to exist outside the sampler (D-111).
test('the next automatic transition is the earlier of the finish and the wipe', () => {
  assert.equal(nextDeadline(fresh()), null, 'rest has nothing to arm');
  const once = append(fresh(), 'Hello', 0);
  assert.equal(nextDeadline(once), 8000, 'one keystroke then silence: the wipe comes first');
  const writing = { ...once, lastInput: 54000 };
  assert.equal(nextDeadline(writing), 60000, 'still typing: the finish comes first');
  const warned = { ...once, phase: 'warn', lastInput: 2000 };
  assert.equal(nextDeadline(warned), 10000, 'the warning still ends at the wipe');
  const tie = { ...once, lastInput: 52000 };
  assert.equal(nextDeadline(tie), 60000, 'a tie resolves to the one instant, and the wipe wins it');
  assert.equal(nextDeadline(advance(writing, 60000)), null, 'a finished session arms nothing');
  assert.equal(nextDeadline(advance(tie, 60000)), null, 'a wiped session arms nothing');
});

test('the armed instant is exactly where advance changes phase, never one tick early or late', () => {
  const states = [
    append(fresh(), 'Hello', 1000),
    { ...append(fresh(), 'Hello', 1000), lastInput: 53000 },
    { ...append(fresh(), 'Hello', 1000), phase: 'warn', lastInput: 3000 },
    { ...append(fresh(), ' ', 1000) },
    { ...append(fresh(), 'Hi', 0), phase: 'warn', lastInput: 52000 }
  ];
  const running = ['typing', 'warn'];
  for (const state of states) {
    const at = nextDeadline(state);
    assert.ok(running.includes(advance(state, at - 0.5).phase), `${at}: still running a millisecond before`);
    assert.ok(!running.includes(advance(state, at).phase), `${at}: the session ends at the instant itself`);
  }
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
  assert.ok(after.t - deny.t >= 900, 'the refusal holds before typing goes on');
  assert.equal(LINES[2], deny.cur + ' pretending.', 'the false start stays in the draft');
});

test('clock and word labels', () => {
  assert.equal(clock(60), '1:00');
  assert.equal(clock(0), '0:00');
  assert.equal(clock(37), '0:37');
  assert.equal(wordCount('  two\nwords '), 2);
  assert.equal(wordCount(''), 0);
});

// One fixture for the web rooms, the Mac room and the Windows room: same text, same number, same label (D-099).
const fixture = JSON.parse(readFileSync(new URL('../tests/fixtures/word-count.json', import.meta.url), 'utf8'));

test('each CJK character is one word and punctuation and emoji are none (shared fixture)', () => {
  for (const { name, text, words } of fixture.counts) assert.equal(wordCount(text), words, name);
});

test('the unit is always word or words, in every language (D-099)', () => {
  for (const { text, label } of fixture.labels) assert.equal(countLabel(text), label, text.slice(0, 20));
  assert.equal(countLabel('', 0), '0 words');
  assert.equal(countLabel('', 1), '1 word');
  assert.equal(countLabel('', 2), '2 words');
});

test('the history ladder counts lines ended by Return, never sentences (D-088)', () => {
  const text = 'First is long. Second is long.\nThird is long. Fourth is long.\nLive. Still live';
  const rungs = historyLines(text).map(line => [text.slice(line.start, line.end).trim(), line.rung]);
  assert.deepEqual(rungs, [['First is long. Second is long.', 2], ['Third is long. Fourth is long.', 1], ['Live. Still live', 0]]);
  assert.deepEqual(historyLines('One. Two. Three.').map(line => line.rung), [0], 'full stops never end a line');
  assert.deepEqual(historyLines('only one').map(line => line.rung), [0]);
  assert.deepEqual(historyLines('').map(line => line.rung), []);
});

test('a hard line break puts the writer on a fresh live line, and CJK stops do not split a line', () => {
  assert.deepEqual(historyLines('one\ntwo\n').map(line => line.rung), [2, 1]);
  assert.deepEqual(historyLines('one\ntwo').map(line => line.rung), [1, 0]);
  assert.deepEqual(historyLines('今天下雨。我在写字。').map(line => line.rung), [0]);
  assert.deepEqual(historyLines('今天下雨。\n我在写字。').map(line => line.rung), [1, 0]);
  assert.deepEqual(historyLines('a\n\nb').map(line => line.rung), [2, 1, 0], 'a blank line is a line');
  assert.deepEqual(historyLines('a\r\nb\rc').map(line => line.rung), [2, 1, 0], 'CRLF is one break');
  const covered = historyLines('a. b.\nc');
  assert.equal(covered[0].start, 0);
  assert.equal(covered.at(-1).end, 7);
});
