// Builds docs/design/<Screen>-<State>.dc.html from docs/design/canvas.json: one board per screen state, each
// naming its regions by token (never a colour literal) with a live swatch drawn from the real stylesheet, so a
// board shows the system as it is today and flips with the theme button.
//
//   node scripts/build-boards.mjs           write the boards
//   node scripts/build-boards.mjs --check   exit 1 when a board on disk differs from what canvas.json builds
//
// canvas.json is the only file to edit. writeitdown/qa/boards.spec.mjs drives each real screen into the state and
// fails when a region's computed value differs from its token or a listed string is not on screen.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
export const DIR = join(root, 'docs/design');
export const CANVAS = JSON.parse(readFileSync(join(DIR, 'canvas.json'), 'utf8'));

const esc = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
const SITE = '../../writeitdown';

export function board(b) {
  const regions = b.regions.map(r => `<tr><td>${esc(r.name)}</td><td><code>${esc(r.selector)}</code></td><td><code>${esc(r.property)}</code></td><td><code>${esc(r.token)}</code></td><td><i class="swatch" style="background:var(${r.token})"></i></td></tr>`).join('\n');
  const strings = b.strings.length ? `<h2>Strings</h2>\n<ul class="strings">${b.strings.map(s => `<li>${esc(s)}</li>`).join('')}</ul>` : '';
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(b.screen)} - ${esc(b.state)}</title>
<meta name="robots" content="noindex">
<link rel="icon" href="${SITE}/favicon.svg" type="image/svg+xml">
<script src="${SITE}/theme.js"></script>
<link rel="stylesheet" href="${SITE}/site.css">
<link rel="stylesheet" href="${SITE}/tokens.css">
<link rel="stylesheet" href="${SITE}/fonts.css">
<style>
.board{padding-bottom:var(--s9)}
.board h1{margin:var(--s7) 0 var(--s2);text-align:left;font:500 var(--t-h3)/1.2 var(--serif)}
.board h2{margin:var(--s6) 0 var(--s3);text-align:left;font:500 var(--t-ui)/1.6 var(--sans);letter-spacing:.04em;color:var(--mute)}
.board table{width:100%;border-collapse:collapse;font:400 var(--t-small)/1.6 var(--sans)}
.board th,.board td{padding:var(--s2) var(--s3) var(--s2) 0;border-bottom:1px solid var(--hair);text-align:left;vertical-align:middle}
.board th{font-weight:500;color:var(--mute)}
.board code{font:inherit;overflow-wrap:anywhere}
.board td:nth-child(3) code{overflow-wrap:normal}
@media (max-width:520px){.board table{font-size:12px}.board th,.board td{padding-right:var(--s2)}.board .swatch{width:24px}}
.board .swatch{display:block;width:40px;height:20px;border:1px solid var(--hair-2);border-radius:var(--r-min)}
.board .strings{margin:0;padding:0;list-style:none;font:400 var(--t-small)/1.8 var(--sans)}
</style>
</head>
<body class="home page-a">
<nav class="wrap home-nav" aria-label="Main"><a class="brand" href="${SITE}/index.html" aria-label="Write It Down"></a><div class="nav-end"><button class="theme-btn" type="button" data-theme-toggle aria-label="Switch to dark theme"><svg class="i-moon" viewBox="0 0 20 20" width="18" height="18" aria-hidden="true" focusable="false"><path d="M16.5 12.4A7 7 0 0 1 7.6 3.5a7 7 0 1 0 8.9 8.9z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg><svg class="i-sun" viewBox="0 0 20 20" width="18" height="18" aria-hidden="true" focusable="false"><circle cx="10" cy="10" r="3.6" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M10 1.8v2.1M10 16.1v2.1M1.8 10h2.1M16.1 10h2.1M4.2 4.2l1.5 1.5M14.3 14.3l1.5 1.5M4.2 15.8l1.5-1.5M14.3 5.7l1.5-1.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg></button></div></nav>
<main class="wrap board">
<h1>${esc(b.screen)} - ${esc(b.state)}</h1>
<p><a href="${SITE}/${esc(b.url)}">${esc(b.url)}</a></p>
<h2>Regions</h2>
<table>
<tr><th>Region</th><th>Selector</th><th>Property</th><th>Token</th><th></th></tr>
${regions}
</table>
${strings}
</main>
</body>
</html>
`;
}

export const files = canvas => Object.fromEntries(canvas.boards.map(b => [`${b.file}.dc.html`, board(b)]));

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const built = files(CANVAS);
  if (process.argv.includes('--check')) {
    const onDisk = readdirSync(DIR).filter(f => f.endsWith('.dc.html')).sort();
    const stale = [...new Set([...Object.keys(built), ...onDisk])].filter(f => {
      try { return readFileSync(join(DIR, f), 'utf8') !== built[f]; } catch { return true; }
    });
    if (stale.length) { console.error(`boards out of date: ${stale.join(', ')} - run node scripts/build-boards.mjs`); process.exit(1); }
    console.log('boards: in step with canvas.json');
  } else {
    for (const [name, html] of Object.entries(built)) writeFileSync(join(DIR, name), html);
    console.log(`wrote ${Object.keys(built).length} boards`);
  }
}
