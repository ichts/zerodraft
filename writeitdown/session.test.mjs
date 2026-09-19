import test from 'node:test';
import assert from 'node:assert/strict';
import { fresh, advance, append, clock, wordCount } from './session.mjs';

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
