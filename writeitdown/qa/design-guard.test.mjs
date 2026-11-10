// Proves each design-guard rule fires on a known-broken fixture and stays quiet on a clean one.
// Protects the token discipline (colours only in tokens.css, no inline colour, no unknown class): a guard
// that cannot fail would let the next hardcoded colour in unnoticed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { check } from './design-guard.mjs';

function site(files) {
  const root = mkdtempSync(join(tmpdir(), 'design-guard-'));
  const base = { 'tokens.css': ':root{--ink:#111111}', 'site.css': '.card{color:var(--ink)}', 'index.html': '<p class="card">x</p>' };
  for (const [name, text] of Object.entries({ ...base, ...files })) writeFileSync(join(root, name), text);
  return root;
}
const rules = root => check(root).map(v => v.rule);

test('a clean site passes', () => assert.deepEqual(check(site({})), []));

test('hex: a 6-digit colour in site.css fails, an #id selector does not', () => {
  assert.deepEqual(rules(site({ 'site.css': '.card{color:#ff0000}' })), ['hex']);
  assert.deepEqual(rules(site({ 'site.css': '.card{color:var(--ink)}\n#add{margin:0}' })), []);
});

test('hex: a 3-digit colour fails, tokens.css and generated fonts*.css are exempt', () => {
  assert.deepEqual(rules(site({ 'site.css': '.card{background:#000}' })), ['hex']);
  assert.deepEqual(rules(site({ 'fonts.css': '/* generated */ .card{color:#abcdef}' })), []);
});

test('inline: a colour literal in a style attribute fails, a layout value does not', () => {
  assert.deepEqual(rules(site({ 'index.html': '<p class="card" style="color:#fff">x</p>' })), ['inline']);
  assert.deepEqual(rules(site({ 'index.html': '<p class="card" style="background:rgb(0 0 0)">x</p>' })), ['inline']);
  assert.deepEqual(rules(site({ 'index.html': '<p class="card" style="margin:0">x</p>' })), []);
});

test('class: a class declared nowhere fails; one a script names does not', () => {
  assert.deepEqual(rules(site({ 'index.html': '<p class="card ghost">x</p>' })), ['class']);
  assert.deepEqual(rules(site({ 'index.html': '<p class="card ghost">x</p>', 'app.js': "el.classList.add('ghost')" })), []);
});
