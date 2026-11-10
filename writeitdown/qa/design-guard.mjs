// Design guard: the token discipline as a failing command, not a comment.
// Godwit's kit_guard_test, translated to this static site (no templ, no Starbase): the colours live in
// tokens.css and nowhere else, pages carry no inline colour, and a page cannot use a class nothing declares.
//
//   node qa/design-guard.mjs            check the site (exit 1 and list every violation)
//   node --test qa/design-guard.test.mjs   prove each rule fires on a known-broken fixture
//
// Rules
//   hex      a 3/4/6/8-digit hex colour in any CSS file except tokens.css and the generated fonts*.css,
//            or in an inline <style> block of a page.
//   inline   a colour literal (hex, rgb, hsl, lab, lch, oklab, oklch, color(), color-mix()) in a style="" attribute.
//   class    a class used in a page's static markup that no CSS file, inline <style> or script references.
//            Scoped so it cannot cry wolf: a class counts as known when ANY stylesheet declares it OR any
//            script (.js/.mjs) names it, because a script-provided hook is not an unknown class. Classes
//            that only exist at runtime never appear in static markup, so they are out of scope by construction.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, basename, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const TOKENS = 'tokens.css';
const GENERATED_CSS = /^fonts.*\.css$/;
const SKIP_DIRS = new Set(['node_modules', 'test-results', 'qa', 'journey', 'fonts']);

const COLOUR_FN = /\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|color-mix)\(/i;
const HEX = /(?<![\w&#-])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})(?![\w-])/g;
const INLINE_HEX = new RegExp(HEX.source);

function walk(dir, root, files = []) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      if (!SKIP_DIRS.has(name) || dir !== root) walk(path, root, files);
    } else files.push(path);
  }
  return files;
}

const stripCssComments = css => css.replace(/\/\*[\s\S]*?\*\//g, match => match.replace(/[^\n]/g, ' '));
const lineOf = (text, index) => text.slice(0, index).split('\n').length;

// A hex inside a selector (`#editor`) is followed by `{` before any `;` or `}`; a declared colour is not.
function hexViolations(css, file) {
  const clean = stripCssComments(css);
  const found = [];
  for (const match of clean.matchAll(HEX)) {
    const next = clean.slice(match.index + match[0].length).search(/[;{}]/);
    const terminator = next === -1 ? '' : clean[match.index + match[0].length + next];
    if (terminator === '{') continue;
    found.push({ rule: 'hex', file, line: lineOf(clean, match.index), detail: `${match[0]} belongs in tokens.css` });
  }
  return found;
}

const classesOf = html => {
  const set = new Set();
  for (const attr of html.matchAll(/\sclass\s*=\s*"([^"]*)"/g)) {
    for (const name of attr[1].split(/\s+/)) if (name) set.add(name);
  }
  return set;
};

const declaredIn = css => new Set([...stripCssComments(css).matchAll(/\.(-?[_a-zA-Z][\w-]*)/g)].map(m => m[1]));

export function check(root) {
  const files = walk(root, root);
  const rel = file => relative(root, file);
  const violations = [];
  const known = new Set();
  const pages = [];

  for (const file of files) {
    const text = file.endsWith('.css') || /\.(html|m?js)$/.test(file) ? readFileSync(file, 'utf8') : '';
    if (file.endsWith('.css')) {
      for (const name of declaredIn(text)) known.add(name);
      if (basename(file) !== TOKENS && !GENERATED_CSS.test(basename(file))) violations.push(...hexViolations(text, rel(file)));
    } else if (/\.m?js$/.test(file)) {
      for (const name of text.matchAll(/[\w-]+/g)) known.add(name[0]);
    } else if (file.endsWith('.html')) pages.push({ file, text });
  }

  for (const { file, text } of pages) {
    const markup = text.replace(/<!--[\s\S]*?-->/g, m => m.replace(/[^\n]/g, ' '));
    for (const block of markup.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/gi)) {
      for (const name of declaredIn(block[1])) known.add(name);
      violations.push(...hexViolations(block[1], rel(file)).map(v => ({ ...v, line: lineOf(markup, block.index) + v.line - 1 })));
    }
    for (const block of markup.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)) {
      for (const name of block[1].matchAll(/[\w-]+/g)) known.add(name[0]);
    }
    for (const attr of markup.matchAll(/\sstyle\s*=\s*"([^"]*)"/g)) {
      if (INLINE_HEX.test(attr[1]) || COLOUR_FN.test(attr[1])) {
        violations.push({ rule: 'inline', file: rel(file), line: lineOf(markup, attr.index), detail: `colour literal in style="${attr[1]}"` });
      }
    }
  }

  for (const { file, text } of pages) {
    const markup = text.replace(/<!--[\s\S]*?-->/g, '').replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, '');
    for (const name of classesOf(markup)) {
      if (!known.has(name)) violations.push({ rule: 'class', file: rel(file), line: 0, detail: `class "${name}" is declared by no CSS and named by no script` });
    }
  }
  return violations;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const violations = check(root);
  for (const v of violations) console.error(`design-guard [${v.rule}] ${v.file}${v.line ? `:${v.line}` : ''} ${v.detail}`);
  if (violations.length) process.exit(1);
  console.log('design-guard: ok');
}
