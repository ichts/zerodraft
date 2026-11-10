// Exports writeitdown/tokens.css as docs/design-system/tokens.json: one entry per custom property
// declaration, so design boards and tools read the system without parsing CSS (Godwit's single token source).
//
//   node scripts/export-tokens.mjs           write docs/design-system/tokens.json
//   node scripts/export-tokens.mjs --check   exit 1 when the committed JSON disagrees with tokens.css
//
// Entry: { name, value, layer, scope }
//   layer  "primitive" when the value is a literal (a colour, length, duration, family or number) and
//          "semantic" when it is composed from other tokens (var(), calc() or color-mix() over them).
//   scope  the selector (and at-rule condition) the declaration sits under, because one name takes
//          different values per theme and viewport. The same name is listed once per scope, in file order.
// The CSS stays the only source of truth; this file is derived and never edited by hand.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
export const CSS_PATH = join(root, 'writeitdown/tokens.css');
export const JSON_PATH = join(root, 'docs/design-system/tokens.json');

const stripComments = css => css.replace(/\/\*[\s\S]*?\*\//g, '');
const clean = text => text.replace(/\s+/g, ' ').trim();

// Splits `a:b;c:d(e;f)` on semicolons that sit outside parentheses and quotes.
function declarations(body) {
  const out = [];
  let depth = 0, quote = '', start = 0;
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (quote) { if (ch === quote) quote = ''; continue; }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '(') depth++;
    else if (ch === ')') depth--;
    else if (ch === ';' && depth === 0) { out.push(body.slice(start, i)); start = i + 1; }
  }
  out.push(body.slice(start));
  return out.map(clean).filter(Boolean);
}

// Walks `selector{...}` blocks, carrying the enclosing at-rule condition into the scope.
function* blocks(css, atRule = '') {
  let i = 0;
  while (i < css.length) {
    const open = css.indexOf('{', i);
    if (open === -1) return;
    let depth = 1, j = open + 1;
    while (j < css.length && depth) depth += css[j] === '{' ? 1 : css[j] === '}' ? -1 : 0, j++;
    const head = clean(css.slice(i, open));
    const body = css.slice(open + 1, j - 1);
    if (head.startsWith('@')) yield* blocks(body, head);
    else yield { scope: atRule ? `${atRule} { ${head} }` : head, body };
    i = j;
  }
}

export function exportTokens(css) {
  const tokens = [];
  for (const { scope, body } of blocks(stripComments(css))) {
    for (const decl of declarations(body)) {
      const colon = decl.indexOf(':');
      const name = decl.slice(0, colon).trim();
      if (!name.startsWith('--')) continue;
      const value = clean(decl.slice(colon + 1));
      tokens.push({ name, value, layer: /\b(?:var|calc|color-mix)\(/.test(value) ? 'semantic' : 'primitive', scope });
    }
  }
  return tokens;
}

export const render = css => `${JSON.stringify(exportTokens(css), null, 2)}\n`;

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const next = render(readFileSync(CSS_PATH, 'utf8'));
  if (process.argv.includes('--check')) {
    let current = '';
    try { current = readFileSync(JSON_PATH, 'utf8'); } catch {}
    if (current !== next) { console.error('docs/design-system/tokens.json is out of date: run node scripts/export-tokens.mjs'); process.exit(1); }
    console.log('tokens.json: in step with tokens.css');
  } else {
    mkdirSync(dirname(JSON_PATH), { recursive: true });
    writeFileSync(JSON_PATH, next);
    console.log(`wrote ${JSON_PATH}`);
  }
}
