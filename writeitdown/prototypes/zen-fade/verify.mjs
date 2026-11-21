// Numeric checks for the zen fade prototype (run from writeitdown/: node prototypes/zen-fade/verify.mjs [base-url]).
// Each line prints PASS or FAIL with the measured number; exits 1 on any FAIL. Not part of `npm test`.
import { chromium } from '@playwright/test';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || 'http://127.0.0.1:8441/writeitdown/prototypes/zen-fade/';
const browser = await chromium.launch({ channel: 'chrome' });
const page = await (await browser.newContext({ viewport: { width: 1920, height: 1080 } })).newPage();
await page.goto(`${base}?paused`);
let failed = 0;
const check = (name, ok, detail) => { if (!ok) failed += 1; console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail ?? ''}`); };
const near = (a, b, tol = 0.6) => Math.abs(a - b) <= tol;

const type = text => page.evaluate(t => { for (const ch of t) window.zenFade.panels.forEach(p => p.append(ch)); }, text);
const settle = ms => page.waitForTimeout(ms);
const rungs = id => page.evaluate(id => {
  const p = window.zenFade.panels.find(x => x.id === id);
  return p.spans().map(s => ({ rung: s.dataset.rung, opacity: Number(getComputedStyle(s).opacity) }));
}, id);
const live = id => page.evaluate(id => {
  const p = window.zenFade.panels.find(x => x.id === id);
  return { live: parseFloat(p.stack.style.getPropertyValue('--live')), lh: parseFloat(getComputedStyle(p.scroller).lineHeight) };
}, id);

// Keep is the original mask: the same stops and alphas as the last stylesheet that carried it.
const original = execFileSync('git', ['show', '13f214e:writeitdown/site.css'], { encoding: 'utf8', cwd: new URL('../..', import.meta.url).pathname })
  .match(/mask-image:(linear-gradient\(transparent,[^;}]*\))/)[1];
const kept = await page.evaluate(() => getComputedStyle(document.querySelector('[data-v="old"] .stack')).maskImage);
check('Keep: mask carries the original alphas 0.07 / 0.22 and stops 10 / 30 / 40 / 60 / 70 %',
  /0\.07/.test(kept) && /0\.22/.test(kept) && ['10%', '30%', '40%', '60%', '70%'].every(s => kept.includes(s)) && /\.07/.test(original) && /\.22/.test(original), kept.slice(0, 140));

await type('First line.\nSecond line.\nThird line.\n');
await settle(500);
for (const id of ['b', 'c', 'now']) {
  const r = await rungs(id);
  const want = { b: [0, 0.07, 0.22], c: [0.25, 0.25, 0.25], now: [0, 0.769, 0.847] }[id];
  const got = r.map(x => x.opacity);
  check(`${id}: three Return lines wear the ladder (three up, two up, one up) and the live line is full`, want.every((w, i) => near(got[i], w, 0.002)) && near(got[3], 1, 0.002), JSON.stringify(got));
}
check('b: one span per Return line plus the live line', (await rungs('b')).length === 4);
let a = await live('a');
check('a: after Return the live line starts on the middle band (2 pitches)', near(a.live, 2 * a.lh), `${a.live} vs ${2 * a.lh}`);
await type('A live line long enough to wrap onto a second row because the sheet is only so wide, and then a third row after that one too, to be sure of it.');
await settle(400);
a = await live('a');
check('a: a wrapped live line keeps the boundary on its own first row (rises whole pitches)', [1, 2].some(rows => near(a.live, 2 * a.lh - rows * a.lh, 0.8)), `live=${a.live} lh=${a.lh}`);
const dissolve = await page.evaluate(() => getComputedStyle(window.zenFade.panels.find(x => x.id === 'b').scroller.querySelector('.l')).transitionDuration);
check('b: the dissolve takes 0.32 s', dissolve === '0.32s', dissolve);
const drop = await page.evaluate(() => getComputedStyle(window.zenFade.panels.find(x => x.id === 'c').scroller.querySelector('.l')).transitionDuration);
check("c: the drop takes 0.12 s, the apps' own speed", drop === '0.12s', drop);
await browser.close();
process.exit(failed ? 1 : 0);
