// Write It Down release journey gate. Deterministic, no model clicking.
// Usage: npm run journey -- --base <url> [--out <dir>]
// Plays a brand-new visitor (fresh context, light theme, video on) at
// phone 390x844 and desktop 1440x900. Exit 0 = every step passed; any
// failure exits 1. Steps that cannot exist yet are reported SKIP with the
// reason and an assertion that the feature is not (wrongly) offered.
import { chromium, webkit, devices } from '@playwright/test';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i < 0 ? d : process.argv[i + 1]; };
const base = (arg('base') || '').replace(/\/+$/, '');
if (!/^https?:\/\//.test(base)) { console.error('usage: npm run journey -- --base <url> [--out <dir>]'); process.exit(2); }
const out = path.resolve(arg('out', `journey-results/${Date.now()}`));
const DMG_URL = 'https://writeitdown.app/download/Write-It-Down-1.0.dmg';
// Phone = WebKit + iPhone profile (every iOS browser incl. WeChat is WebKit); desktop = Chromium.
const sizes = [{ name: 'phone', width: 390, height: 844, engine: 'webkit' }, { name: 'desktop', width: 1440, height: 900, engine: 'chromium' }];
const results = [];
// Human pace (default): deliberate pauses so a recorded video is readable. WID_JOURNEY_PACE=fast disables them.
const human = process.env.WID_JOURNEY_PACE !== 'fast';

async function run(size, browser) {
  const device = size.engine === 'webkit' ? devices['iPhone 14'] : {};
  const tag = size.name;
  console.log(`engine [${tag}]: ${size.engine}${size.engine === 'webkit' ? ' (iPhone 14 profile: touch, DPR, UA)' : ''}`);
  const log = (status, step, msg = '') => { results.push({ tag, status, step, msg }); console.log(`${status.padEnd(4)} [${tag}] ${step}${msg ? ' - ' + msg : ''}`); };
  const step = async (name, fn) => { try { const m = await fn(); if (m === 'SKIP') return; log('PASS', name, typeof m === 'string' ? m : ''); } catch (e) { log('FAIL', name, String(e.message).split('\n')[0]); } if (human) await page.waitForTimeout(2000); };
  const ok = (c, m) => { if (!c) throw new Error(m); };
  const dir = path.join(out, tag);
  const ctx = await browser.newContext({
    ...device, viewport: { width: size.width, height: size.height }, colorScheme: 'light', storageState: undefined,
    recordVideo: { dir, size: { width: size.width, height: size.height } },
  });
  const page = await ctx.newPage();
  page.setDefaultTimeout(5000);
  const errors = [];
  // Third-party analytics beacon (CORS-blocks on non-prod origins) and the favicon 404 on the local static server are not journey errors.
  page.on('console', m => { if (m.type() === 'error' && !/cloudflareinsights|favicon|Access-Control-Allow-Origin|access control checks/i.test(m.text() + (m.location().url || ''))) errors.push(m.text()); });
  page.on('pageerror', e => { if (!/cloudflareinsights|Access-Control-Allow-Origin|access control checks/i.test(String(e))) errors.push(String(e)); });
  const url = p => `${base}${p}`;

  await step('understand: landing loads', async () => { const r = await page.goto(url('/')); ok(r.ok(), `status ${r.status()}`); });
  await step('understand: H1 is "We force you to write it down" without final period', async () => {
    const t = (await page.locator('h1.h1').first().innerText()).replace(/\s+/g, ' ').trim();
    ok(t.toLowerCase() === 'we force you to write it down', `H1 is "${t}"`);
  });
  await step('understand: handwritten second line', async () => {
    const f = await page.locator('h1.h1 .hand').evaluate(e => getComputedStyle(e).fontFamily);
    ok(/reenie/i.test(f), `second line font is ${f}`);
    ok((await page.locator('h1.h1 .hand').innerText()).trim().toLowerCase() === 'write it down', 'second line text');
  });
  await step('understand: deck below the demo', async () => {
    const d = await page.locator('.deck').boundingBox(), p = await page.locator('#demo').boundingBox();
    ok(d && p && d.y >= p.y + p.height - 2, 'deck is not below the demo');
    ok(/8 seconds/.test(await page.locator('.deck').innerText()), 'deck text');
  });
  await step('try: demo takes >=60% of first viewport height', async () => {
    const b = await page.locator('#demo .paper').boundingBox();
    const vis = Math.max(0, Math.min(b.y + b.height, size.height) - Math.max(b.y, 0));
    const r = vis / size.height;
    ok(r >= 0.6, `demo paper covers ${(r * 100).toFixed(0)}% of the viewport`);
    return `${(r * 100).toFixed(0)}%`;
  });
  await step('no price/buy/checkout offered on landing (checkout does not exist yet)', async () => {
    const bad = await page.locator('a,button').evaluateAll(els => els.filter(e => /^\s*(buy|checkout|purchase|sign in|log in)\b/i.test(e.textContent) || /checkout|stripe|waffo|\/login|\/signin/i.test(e.getAttribute('href') || '')).map(e => e.textContent.trim()));
    ok(bad.length === 0, `found ${JSON.stringify(bad)}`);
  });
  await step('nav DOWNLOAD entry goes to /download/', async () => {
    await page.locator('nav a', { hasText: /^download/i }).click();
    await page.waitForURL(/\/download\/?$/, { timeout: 5000 });
    ok((await page.locator('h1').first().innerText()).trim() === 'Write It Down for Mac', 'download page H1 missing (host may be serving the landing as fallback)');
  });
  await step('download page: terms, button, DMG link and SHA-256 line on screen', async () => {
    await page.evaluate(() => { const t = document.querySelector('#trial-terms').getBoundingClientRect(); window.scrollBy(0, t.top - 90); });
    for (const sel of ['#trial-terms', 'a[data-launch="dmg"]', '#sha256']) {
      const bx = await page.locator(sel).boundingBox();
      ok(bx && bx.y >= 0 && bx.y + bx.height <= size.height, `${sel} is not fully on screen`);
    }
  });
  let sha = null;
  await step('download page shows trial terms', async () => {
    const t = (await page.locator('#trial-terms').innerText()).toUpperCase();
    ok(/3 (FREE )?SESSIONS/.test(t) && /USD 4\.99 ONE-TIME/.test(t) && /BUYING OPENS SOON/.test(t), `terms read "${t}"`);
  });
  await step('download page offers no buy/checkout (checkout does not exist yet)', async () => {
    const bad = await page.locator('main a,main button').evaluateAll(els => els.filter(e => /^\s*(buy|checkout|purchase)\b/i.test(e.textContent) || /checkout|stripe|waffo/i.test(e.getAttribute('href') || '')).map(e => e.textContent.trim()));
    ok(bad.length === 0, `found ${JSON.stringify(bad)}`);
  });
  await step('download page DMG link is the canonical URL', async () => {
    const h = await page.locator('a[data-launch="dmg"]').getAttribute('href');
    ok(h === DMG_URL, `href is ${h}`);
  });
  await step('published SHA-256 present on the page', async () => {
    sha = (await page.locator('#sha256 code').first().innerText({ timeout: 2000 })).trim().toLowerCase();
    ok(/^[0-9a-f]{64}$/.test(sha), 'no published 64-hex SHA-256 (page still says pending)');
  });
  await step('DMG answers 200, diskimage type, plausible size, sha matches published', async () => {
    const r = await ctx.request.get(url(new URL(DMG_URL).pathname));
    ok(r.status() === 200, `status ${r.status()}`);
    const ct = r.headers()['content-type'] || '';
    ok(/diskimage|octet-stream/.test(ct), `content-type ${ct}`);
    const body = await r.body();
    ok(body.length >= 1_000_000, `size ${body.length} bytes is implausible for a DMG`);
    ok(!/^<!doctype html|^<html/i.test(body.subarray(0, 64).toString()), 'body is an HTML page, not a DMG');
    ok(sha, 'no published sha to compare');
    const got = crypto.createHash('sha256').update(body).digest('hex');
    ok(got === sha, `sha256 of file ${got} != published ${sha}`);
    return `${body.length} bytes, sha ok`;
  });
  await step('back to landing, then try: "Give it 60 seconds" starts the real room and typing works', async () => {
    await page.goBack();
    await page.waitForURL(/\/(index\.html)?$/);
    await page.getByRole('link', { name: 'Give it 60 seconds' }).click();
    await page.locator('#room').waitFor({ state: 'visible', timeout: 5000 });
    await page.locator('#editor').click();
    await page.keyboard.type('hello from a new visitor. I am writing forward and I will not stop. ', { delay: human ? 90 : 30 });
    await page.keyboard.type('Nothing here is saved, so the only way out is through the next sentence.', { delay: human ? 90 : 30 });
    const v = await page.locator('#editor').inputValue();
    ok(v.includes('hello from a new visitor'), `editor holds "${v}"`);
    const c = await page.locator('#room-count').innerText();
    ok(/^[1-9]/.test(c.trim()), `word count reads "${c}"`);
    ok(/^[01]:[0-5]\d$/.test((await page.locator('#room-clock').innerText()).trim()), 'clock');
  });
  for (const p of ['support', 'privacy', 'terms']) {
    await step(`${p} reachable`, async () => {
      await page.goto(url(`/${p}.html`));
      const h = (await page.locator('h1').first().innerText()).trim();
      ok(h.toLowerCase() === p, `H1 is "${h}"`);
    });
  }
  await step('waitlist form reachable', async () => {
    await page.goto(url('/mac.html#waitlist'));
    await page.locator('#waitlist-form').waitFor({ state: 'visible', timeout: 5000 });
    for (const s of ['#waitlist-email', 'input[name=consent]']) ok(await page.locator(s).count() === 1, `${s} missing`);
  });
  log('SKIP', 'sign-in / checkout / test payment / output after payment', 'not built yet; asserted above that none is offered. Add real steps when they ship.');
  await step('no console errors across the journey', async () => { ok(errors.length === 0, errors.slice(0, 3).join(' | ')); });

  const vid = page.video();
  await ctx.close();
  if (vid) { const p = await vid.path(); const dest = path.join(dir, `journey-${tag}.webm`); fs.renameSync(p, dest); console.log(`video [${tag}]: ${dest}`); }
}

fs.mkdirSync(out, { recursive: true });
let chrome;
try { chrome = await chromium.launch({ channel: 'chrome' }); } catch { chrome = await chromium.launch(); }
const wk = await webkit.launch();
console.log(`journey base=${base} out=${out}`);
for (const s of sizes) await run(s, s.engine === 'webkit' ? wk : chrome);
await wk.close();
await chrome.close();

const fails = results.filter(r => r.status === 'FAIL');
fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({ base, results }, null, 1));
console.log(`\nSUMMARY base=${base}: ${results.filter(r => r.status === 'PASS').length} pass, ${fails.length} fail, ${results.filter(r => r.status === 'SKIP').length} skip`);
process.exit(fails.length ? 1 : 0);
