import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const out = path.resolve(process.argv[2] ?? path.join(os.tmpdir(), 'verify-writing-deadlines-mutation'));
fs.mkdirSync(out, { recursive: true });
const scratch = path.join(out, 'scratch-repo');
fs.mkdirSync(scratch, { recursive: true });
const original = fs.readFileSync(path.join(repo, 'index.html'), 'utf8');
const needle = 'return silenceDeadline <= completionDeadline ? "wipe" : "keep";';
if (original.split(needle).length !== 2) throw new Error('Tie guard moved; review the mutation.');
const target = path.join(scratch, 'index.html');
function run(name, expectedExit) {
  const result = spawnSync(process.execPath, [path.join(here, 'verify.mjs'), '--repo', scratch, '--surface', 'root', '--rule', 'root.tick.earliestDeadline'], { encoding: 'utf8' });
  fs.writeFileSync(path.join(out, `${name}.log`), `exit=${result.status}\n${result.stdout}${result.stderr}`);
  if (result.status !== expectedExit) throw new Error(`${name}: expected exit ${expectedExit}, got ${result.status}`);
  console.log(`${name}: exit=${result.status}`);
}
fs.writeFileSync(target, original);
run('before-pass', 0);
try {
  fs.writeFileSync(target, original.replace(needle, 'return silenceDeadline < completionDeadline ? "wipe" : "keep";'));
  fs.writeFileSync(path.join(out, 'scratch-break.patch'), '- return silenceDeadline <= completionDeadline ? "wipe" : "keep";\n+ return silenceDeadline < completionDeadline ? "wipe" : "keep";\n');
  run('broken-fail', 1);
} finally {
  fs.writeFileSync(target, original);
}
run('restored-pass', 0);
console.log('Only the scratch copy changed. The unfiltered run on the tracked file must still pass.');
