// Keeps docs/design-system/tokens.json in step with tokens.css. Protects the design boards and any tool that
// reads the committed JSON: a token changed in the CSS without re-running the export fails here, so the
// export cannot rot. The parser cases prove the layer and scope rules on a known snippet.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CSS_PATH, JSON_PATH, exportTokens, render } from '../../scripts/export-tokens.mjs';

const css = readFileSync(CSS_PATH, 'utf8');

test('the committed tokens.json equals what tokens.css exports', () => {
  assert.equal(readFileSync(JSON_PATH, 'utf8'), render(css), 'run: node scripts/export-tokens.mjs');
});

test('a token edited in the CSS makes the committed JSON stale', () => {
  assert.notEqual(readFileSync(JSON_PATH, 'utf8'), render(`${css}\n:root{--added-without-export:1px}`));
});

test('literals are primitive, composed values are semantic, and the scope carries theme and media', () => {
  const tokens = exportTokens(`/* c */ :root{--a:#fff;--b:var(--a)}
    @media (max-width:820px){.home{--gut:20px;--c:calc(var(--gut) * 2)}}
    :root[data-theme="dark"]{--a:#000}`);
  assert.deepEqual(tokens, [
    { name: '--a', value: '#fff', layer: 'primitive', scope: ':root' },
    { name: '--b', value: 'var(--a)', layer: 'semantic', scope: ':root' },
    { name: '--gut', value: '20px', layer: 'primitive', scope: '@media (max-width:820px) { .home }' },
    { name: '--c', value: 'calc(var(--gut) * 2)', layer: 'semantic', scope: '@media (max-width:820px) { .home }' },
    { name: '--a', value: '#000', layer: 'primitive', scope: ':root[data-theme="dark"]' },
  ]);
});
