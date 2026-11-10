// The design boards must stay in step with their source and with the system. Protects the reader of a board:
//   - a board on disk that no longer matches docs/design/canvas.json is stale,
//   - a board that names a colour literal instead of a token has stopped being the system's view,
//   - a region token that is not in tokens.css (via docs/design-system/tokens.json) is a dead reference,
//   - a canvas entry without a board file, or a board file without a canvas entry, is an orphan.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CANVAS, DIR, files } from '../../scripts/build-boards.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');
const tokens = new Set(JSON.parse(readFileSync(join(root, 'docs/design-system/tokens.json'), 'utf8')).map(t => t.name));
const HEX = /#[0-9a-fA-F]{3,8}\b/;

export const problems = (canvas, onDisk, tokenNames) => {
  const built = files(canvas);
  return [
    ...Object.keys(built).filter(f => onDisk[f] !== built[f]).map(f => `${f} is missing or stale`),
    ...Object.keys(onDisk).filter(f => !(f in built)).map(f => `${f} has no canvas entry`),
    ...canvas.boards.flatMap(b => b.regions.filter(r => !tokenNames.has(r.token)).map(r => `${b.file}: ${r.token} is not a token`)),
    ...Object.entries(onDisk).filter(([, html]) => HEX.test(html.replace(/<svg[\s\S]*?<\/svg>/g, ''))).map(([f]) => `${f} names a colour literal`),
  ];
};

const read = () => Object.fromEntries(readdirSync(DIR).filter(f => f.endsWith('.dc.html')).map(f => [f, readFileSync(join(DIR, f), 'utf8')]));

test('every board matches canvas.json, names only tokens, and no board is orphaned', () => {
  assert.ok(CANVAS.boards.length >= 10);
  assert.deepEqual(problems(CANVAS, read(), tokens), []);
});

test('known-broken: a stale board, an orphan, a dead token and a hex literal are each caught', () => {
  const disk = read();
  const first = Object.keys(disk)[0];
  assert.deepEqual(problems(CANVAS, { ...disk, [first]: disk[first].replace('Regions', 'Areas') }, tokens), [`${first} is missing or stale`]);
  assert.deepEqual(problems(CANVAS, { ...disk, 'Ghost-Rest.dc.html': '<p>x</p>' }, tokens), ['Ghost-Rest.dc.html has no canvas entry']);
  assert.deepEqual(problems(CANVAS, disk, new Set([...tokens].filter(t => t !== '--ink'))).every(p => p.endsWith('is not a token')), true);
  assert.deepEqual(problems(CANVAS, { ...disk, [first]: `${disk[first]}<p style="color:#fff">` }, tokens).sort(), [`${first} is missing or stale`, `${first} names a colour literal`].sort());
});
