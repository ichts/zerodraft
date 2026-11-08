import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { rootAdapter } from './root-adapter.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const repo = path.resolve(option('--repo', path.resolve(here, '../../..')));
const surface = option('--surface', 'all');
const only = option('--rule', null);
if (!['root', 'web', 'all'].includes(surface)) throw new Error('Use --surface root, web or all.');
const origin = 100000;
const duration = 60000;
const silence = 8000;
const failures = new Map();
let checks = 0;
function check(rule, ok, detail) {
  if (only && rule !== only) return;
  checks++;
  if (ok) return;
  const previous = failures.get(rule);
  failures.set(rule, { count: (previous?.count ?? 0) + 1, first: previous?.first ?? detail });
}
function decision(last, time) {
  const finish = origin + duration;
  const wipe = last + silence;
  if (time >= Math.min(finish, wipe)) return wipe <= finish ? 'wipe' : 'kept';
  return time - last >= 5000 ? 'warn' : 'typing';
}
function times(last) {
  const values = new Set();
  // All integral seconds from the latest input through 68 s, plus millisecond boundaries.
  for (let t = last; t <= origin + 68000; t += 1000) values.add(t);
  for (const boundary of [last + 5000, last + silence, origin + duration]) {
    for (const delta of [-1, 0, 1]) if (boundary + delta >= last) values.add(boundary + delta);
  }
  return [...values].sort((a, b) => a - b);
}

if (surface === 'root' || surface === 'all') {
  const root = rootAdapter(fs.readFileSync(path.join(repo, 'index.html'), 'utf8'));
  for (let second = 0; second < 60; second++) {
    const last = origin + second * 1000;
    root.reset();
    root.input('old', origin);
    // These prefixes are genuinely reachable without ever crossing the silence deadline.
    for (let t = origin + 4000; t < last; t += 4000) root.input(root.state.text + 'x', t);
    if (last !== origin) root.input(root.state.text + 'x', last);
    const before = root.snapshot();
    for (const time of times(last)) {
      const expected = decision(last, time);
      const detail = { lastSecond: second, eventMs: time - origin, expected };
      root.restore(before);
      root.tick(time);
      const actual = root.state.failed ? 'wipe' : root.state.complete ? 'kept' : root.state.dangerActive ? 'warn' : 'typing';
      check('root.tick.earliestDeadline', actual === expected, { ...detail, actual });
      if (expected === 'wipe') {
        const unused = Math.max(0, Math.ceil((origin + duration - last - silence) / 1000));
        const report = `Draft wiped - ${Math.floor(unused / 60)}:${String(unused % 60).padStart(2, '0')} unused.`;
        check('root.receipt.deadlineNotCallback', root.state.wipeReport === report, { ...detail, expectedReport: report, actual: root.state.wipeReport });
      }
      root.restore(before);
      root.input(before.text + ' new', time);
      if (expected === 'wipe') check('root.input.noLateRescue', !root.state.text.includes('old'), { ...detail, actualText: root.state.text });
      if (expected === 'kept') check('root.input.deadlineBeforeAppend', root.state.complete && root.state.resultText === before.text, { ...detail, actualText: root.state.text, complete: root.state.complete });
      if (expected === 'typing' || expected === 'warn') check('root.input.liveAppend', root.state.text === before.text + ' new' && !root.state.failed && !root.state.complete, detail);
    }
  }
}

if (surface === 'web' || surface === 'all') {
  const { fresh, advance, append } = await import(pathToFileURL(path.join(repo, 'writeitdown/session.mjs')));
  for (let second = 0; second < 60; second++) {
    const last = origin + second * 1000;
    let before = append(fresh(), 'old', origin);
    for (let t = origin + 4000; t < last; t += 4000) before = append(before, 'x', t);
    if (last !== origin) before = append(before, 'x', last);
    for (const time of times(last)) {
      const expected = decision(last, time);
      const detail = { lastSecond: second, eventMs: time - origin, expected };
      const result = advance(before, time);
      check('web.tick.earliestDeadline', result.phase === expected, { ...detail, actual: result.phase });
      if (expected === 'wipe') {
        check('web.tick.clearsDraft', result.text === '', detail);
        check('web.receipt.deadlineNotCallback', result.unused === Math.max(0, Math.ceil((origin + duration - last - silence) / 1000)), detail);
      }
      const input = append(before, 'new', time);
      if (expected === 'wipe') check('web.input.noLateRescue', input.text === 'new', { ...detail, actualText: input.text });
      else if (expected === 'kept') check('web.input.deadlineBeforeAppend', input.phase === 'kept' && input.text === before.text, { ...detail, actual: input.phase });
      else check('web.input.liveAppend', input.text === before.text + 'new' && input.phase === 'typing', detail);
    }
  }
}
console.log(JSON.stringify({ tool: 'actual-source finite boundary exploration', surface, only, checks, failedRules: failures.size, failures: Object.fromEntries(failures) }, null, 2));
if (checks === 0) throw new Error('No matching checks ran.');
process.exitCode = failures.size ? 1 : 0;
