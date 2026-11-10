// The component gallery (kit/) must never reach writeitdown.app. Protects the live site from a dev-only page:
// install.sh copies an explicit file list, so the gallery stays out only while that list names no kit file,
// copies no directory wholesale, and no shipped page, sitemap or crawler file points at it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const installer = readFileSync(join(root, 'install.sh'), 'utf8');

export const shippedFiles = script => script.match(/^FILES='([^']*)'/m)?.[1].split(/\s+/).filter(Boolean) ?? [];
export const leaks = (script, pages) => [
  ...shippedFiles(script).filter(f => f === 'kit' || f.startsWith('kit/')).map(f => `FILES lists ${f}`),
  ...(/\bcp\s+-[a-zA-Z]*[rR]|\brsync\b|install\s+-[a-zA-Z]*d[^\n]*\bkit\b|\bkit\//.test(script.replace(/^FILES='[^']*'/m, '')) ? ['install.sh copies or names a directory wholesale'] : []),
  ...Object.entries(pages).filter(([, text]) => /(?:href|src)="[^"]*\bkit\/|\/kit\//.test(text)).map(([name]) => `${name} links the gallery`),
];

const shippedPages = () => {
  const names = shippedFiles(installer).filter(f => /\.(html|xml|txt)$/.test(f));
  return Object.fromEntries(names.map(f => [f, readFileSync(join(root, f), 'utf8')]));
};

test('the installer ships a non-empty explicit list and none of it is the gallery', () => {
  assert.ok(shippedFiles(installer).length > 40, 'the FILES list was not read');
  assert.deepEqual(leaks(installer, shippedPages()), []);
  assert.ok(readdirSync(join(root, 'kit')).includes('index.html'), 'the gallery exists, so this guard has something to exclude');
});

test('known-broken: a list that names a kit file, or links to the gallery, is caught', () => {
  assert.deepEqual(leaks(installer.replace("FILES='", "FILES='kit/index.html "), {}), ['FILES lists kit/index.html']);
  assert.deepEqual(leaks(installer, { 'index.html': '<a href="kit/">kit</a>' }), ['index.html links the gallery']);
  assert.deepEqual(leaks(`${installer}\ncp -R "$SOURCE/kit" "$TARGET"\n`, {}), ['install.sh copies or names a directory wholesale']);
});
