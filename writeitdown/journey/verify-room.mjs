import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.resolve(root, '../tmp/journey-controls', String(Date.now()));
await fs.mkdir(out, { recursive: true });
const original = await fs.readFile(path.join(root, 'room.js'), 'utf8');
const cases = [
  { name: 'no-finish', scenarios: 'full-session', from: 'state = advance(state, now);', to: "const next = advance(state, now); state = next.phase === 'kept' ? state : next;", failure: 'full-session: finished draft and real clipboard equal typed text' },
  { name: 'no-wipe', scenarios: 'silence-wipe', from: 'state = advance(state, now);', to: "const next = advance(state, now); state = next.phase === 'wipe' ? state : next;", failure: 'silence-wipe: draft is deleted after eight seconds of silence' },
  { name: 'no-copy', scenarios: 'full-session', from: 'await navigator.clipboard.writeText(text);', to: 'await Promise.resolve();', failure: 'full-session: finished draft and real clipboard equal typed text', message: 'clipboard differs from the finished draft' },
  { name: 'good', scenarios: 'full-session,silence-wipe' },
];
const report = [];

for (const control of cases) {
  const dir = path.join(out, control.name);
  const site = path.join(dir, 'site');
  await fs.mkdir(site, { recursive: true });
  for (const entry of await fs.readdir(root, { withFileTypes: true })) {
    if (entry.isFile() && /\.(html|css|js|mjs|woff2|png|txt|xml)$/.test(entry.name)) {
      await fs.copyFile(path.join(root, entry.name), path.join(site, entry.name));
    }
  }
  if (control.from) {
    assert.equal(original.split(control.from).length, 2, `mutation boundary for ${control.name}`);
    await fs.writeFile(path.join(site, 'room.js'), original.replace(control.from, control.to));
  }
  const listener = net.createServer();
  listener.listen(0, '127.0.0.1');
  await once(listener, 'listening');
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const server = spawn(process.execPath, [path.join(root, 'journey/serve-local.mjs'), '--root', site, '--port', String(port)], { stdio: ['ignore', 'pipe', 'inherit'] });
  const serverExit = once(server, 'exit');
  try {
    await Promise.race([
      once(server.stdout, 'data'),
      serverExit.then(() => { throw new Error('local server exited before listening'); }),
    ]);
    const journey = spawn(process.execPath, [path.join(root, 'journey/journey.mjs'), '--base', `http://127.0.0.1:${port}`, '--out', path.join(dir, 'evidence'), '--scenarios', control.scenarios], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] });
    let log = '';
    for (const stream of [journey.stdout, journey.stderr]) stream.on('data', chunk => { log += chunk; process.stdout.write(chunk); });
    const [code, signal] = await once(journey, 'exit');
    await fs.writeFile(path.join(dir, 'journey.log'), log);
    assert.equal(signal, null, `${control.name} terminated by signal`);
    const data = JSON.parse(await fs.readFile(path.join(dir, 'evidence/results.json'), 'utf8'));
    const failures = data.results.filter(result => result.status === 'FAIL');
    report.push({ control: control.name, code, failures });
    await fs.writeFile(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
    console.log(`CONTROL ${control.name}: exit ${code}; ${failures.map(result => `${result.tag}: ${result.name} (${result.msg})`).join('; ') || 'all named scenarios passed'}`);
    assert.equal(code, control.failure ? 1 : 0, `${control.name} exit code`);
    if (control.failure) {
      assert.equal(failures.length, 2, `${control.name} must fail on both viewports`);
      assert.deepEqual(new Set(failures.map(result => result.tag)), new Set(['phone', 'desktop']));
      for (const failure of failures) {
        assert.equal(failure.name, control.failure);
        if (control.message) assert.equal(failure.msg, control.message);
      }
    } else {
      for (const tag of ['phone', 'desktop']) {
        for (const scenario of ['full-session', 'silence-wipe']) {
          assert(data.results.some(result => result.tag === tag && result.status === 'PASS' && result.name.startsWith(`${scenario}:`)), `${tag} ${scenario} did not pass`);
        }
      }
    }
  } finally {
    server.kill();
    await serverExit;
  }
}
console.log(`PASS room negative controls and intact build; evidence: ${out}`);
