// Write It Down release journey gate. Deterministic, no model clicking.
// Usage: npm run journey -- --base <url> [--out <dir>] [--expect-sha <hex>]
// Fresh visitor (new context, light, video on): phone = WebKit + iPhone 14 profile
// at 390x844 (every iOS browser incl. WeChat is WebKit), desktop = Chromium 1440x900.
// ONE context + page per viewport, one continuous human-paced video.
// Exit 0 = every step passed; 1 = any failed step; 2 = bad usage.
// Structure: one `block(name, steps)` per page section; extend by adding a block
// (or steps inside one) - each step is `step(label, async () => ...)`.
import { chromium, webkit, devices } from '@playwright/test';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i < 0 ? d : process.argv[i + 1]; };
const base = (arg('base') || '').replace(/\/+$/, '');
if (!/^https?:\/\//.test(base)) { console.error('usage: npm run journey -- --base <url> [--out <dir>] [--expect-sha <hex>]'); process.exit(2); }
const out = path.resolve(arg('out', `journey-results/${Date.now()}`));
const expectSha = arg('expect-sha', null);
const DMG_URL = 'https://writeitdown.app/download/Write-It-Down-1.0.dmg';
const human = process.env.WID_JOURNEY_PACE !== 'fast'; // 2 s pause per step, 90 ms keystrokes
const sizes = [{ name: 'phone', width: 390, height: 844, engine: 'webkit' }, { name: 'desktop', width: 1440, height: 900, engine: 'chromium' }];
const results = [];
const NOISE = /cloudflareinsights|favicon|Access-Control-Allow-Origin|access control checks/i; // third-party beacon / local-server noise
const ok = (c, m) => { if (!c) throw new Error(m); };

async function run(size, browser) {
  const tag = size.name;
  console.log(`engine [${tag}]: ${size.engine}${size.engine === 'webkit' ? ' (iPhone 14 profile: touch, DPR, UA)' : ''}`);
  const dir = path.join(out, tag);
  const ctx = await browser.newContext({
    ...(size.engine === 'webkit' ? devices['iPhone 14'] : {}),
    viewport: { width: size.width, height: size.height }, colorScheme: 'light',
    recordVideo: { dir, size: { width: size.width, height: size.height } },
  });
  const page = await ctx.newPage();
  page.setDefaultTimeout(5000);
  const errors = [];
  page.on('console', m => { if (m.type() === 'error' && !NOISE.test(m.text() + (m.location().url || ''))) errors.push(m.text()); });
  page.on('pageerror', e => { if (!NOISE.test(String(e))) errors.push(String(e)); });
  const url = p => `${base}${p}`;
  const log = (status, name, msg = '') => { results.push({ tag, status, name, msg }); console.log(`${status.padEnd(4)} [${tag}] ${name}${msg ? ' - ' + msg : ''}`); };
  let current = '';
  const step = async (name, fn) => {
    try { const m = await fn(); log('PASS', `${current}: ${name}`, typeof m === 'string' ? m : ''); }
    catch (e) { log('FAIL', `${current}: ${name}`, String(e.message).split('\n')[0]); }
    if (human) await page.waitForTimeout(2000);
  };
  const block = async (name, fn) => { current = name; await fn(); };
  const show = sel => page.locator(sel).first().evaluate(e => e.scrollIntoView({ block: 'start' }));
  const offers = (scope) => page.locator(`${scope} a, ${scope} button`).evaluateAll(els => els.filter(e => /^\s*(buy|checkout|purchase|sign in|log in)\b/i.test(e.textContent) || /checkout|stripe|waffo|\/login|\/signin/i.test(e.getAttribute('href') || '')).map(e => e.textContent.trim()));
  let sha = null;

  await block('landing/hero', async () => {
    await step('page loads', async () => { const r = await page.goto(url('/')); ok(r.ok(), `status ${r.status()}`); });
    await step('H1 "We force you to" + "write it down", no final period', async () => {
      const t = (await page.locator('h1.h1').first().innerText()).replace(/\s+/g, ' ').trim();
      ok(t.toLowerCase() === 'we force you to write it down', `H1 is "${t}"`);
    });
    await step('second line is the red handwritten one', async () => {
      const h = page.locator('h1.h1 .hand');
      const [f, c] = await h.evaluate(e => [getComputedStyle(e).fontFamily, getComputedStyle(e).color]);
      ok(/reenie/i.test(f), `font ${f}`);
      const [r, g, b] = c.match(/\d+/g).map(Number);
      ok(r > 150 && g < 100 && b < 100, `colour ${c} is not red`);
    });
    await step('top bar: Download for Mac pill present', async () => {
      ok(await page.locator('nav[aria-label=Main] a', { hasText: /^download for mac$/i }).count() === 1, 'pill missing');
    });
  });
  await block('landing/demo', async () => {
    await step('demo sheet fills >=60% of the first viewport', async () => {
      const b = await page.locator('#demo .paper').boundingBox();
      const vis = Math.max(0, Math.min(b.y + b.height, size.height) - Math.max(b.y, 0));
      const r = vis / size.height; ok(r >= 0.6, `demo sheet covers ${(r * 100).toFixed(0)}% of the viewport`); return `${(r * 100).toFixed(0)}%`;
    });
    await step('demo is the scripted preview with a 60-second clock', async () => {
      ok(/^\d:\d\d$/.test((await page.locator('#clock').innerText()).trim()), 'clock');
      ok(await page.locator('#demo .paper').isVisible(), 'sheet hidden');
    });
    await step('deck line sits under the demo; CTA "Give it 60 seconds" present', async () => {
      const d = await page.locator('.deck').boundingBox(), p = await page.locator('#demo').boundingBox();
      ok(d.y >= p.y + p.height - 2, 'deck is not below the demo');
      ok(/8 seconds/.test(await page.locator('.deck').innerText()), 'deck text');
      ok(await page.getByRole('link', { name: 'Give it 60 seconds' }).count() === 1, 'CTA missing');
    });
    await step('no price/buy/sign-in button offered (checkout does not exist yet)', async () => {
      const bad = await offers('body'); ok(bad.length === 0, `found ${JSON.stringify(bad)}`);
    });
  });
  await block('landing/how-it-works', async () => {
    await step('3 cards: no way back, eight seconds, reach zero', async () => {
      await show('#how');
      const t = await page.locator('.cards .card h3').allInnerTexts();
      ok(t.length === 3 && /no way back/i.test(t[0]) && /eight seconds/i.test(t[1]) && /reach zero/i.test(t[2]), `cards ${JSON.stringify(t)}`);
    });
  });
  await block('landing/stop-states', async () => {
    await step('writing / warning / deleted strip', async () => {
      await show('#moment');
      ok(await page.locator('.moments .mo').count() === 3, 'need 3 states');
      ok(/DRAFT DELETED/.test(await page.locator('.mo.m3').innerText()), 'deleted state text');
    });
  });
  await block('landing/mac-block', async () => {
    await step('USD 4.99 / 2 Macs / 14 days and honest "buying opens soon"', async () => {
      await show('#mac');
      const t = await page.locator('#mac').innerText();
      ok(/3 sessions/i.test(t) && /\$4\.99/.test(t) && /2 Macs/.test(t) && /14 days/.test(t), 'facts missing');
      ok(/buying opens soon/i.test(t), 'honest "buying opens soon" missing');
    });
  });
  await block('landing/footer', async () => {
    await step('Trefoil Studio + Support/Privacy/Terms links', async () => {
      await show('footer');
      ok(/Trefoil Studio/.test(await page.locator('footer').innerText()), 'Trefoil Studio missing');
      for (const n of ['Support', 'Privacy', 'Terms']) ok(await page.locator('footer a', { hasText: n }).count() === 1, `${n} link missing`);
    });
  });
  await block('download', async () => {
    await step('top-bar pill goes to /download/', async () => {
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.locator('nav[aria-label=Main] a', { hasText: /^download for mac$/i }).click();
      await page.waitForURL(/\/download\/?$/);
      ok((await page.locator('h1').first().innerText()).trim() === 'Write It Down for Mac', 'download page H1 missing (host may serve the landing as fallback)');
    });
    await step('trial terms: 3 sessions, USD 4.99 one-time, buying opens soon', async () => {
      const t = (await page.locator('#trial-terms').innerText()).toUpperCase();
      ok(/3 SESSIONS/.test(t) && /USD 4\.99 ONE-TIME/.test(t) && /BUYING OPENS SOON/.test(t), `terms read "${t}"`);
    });
    await step('no buy/checkout offered', async () => { const bad = await offers('main'); ok(bad.length === 0, `found ${JSON.stringify(bad)}`); });
    await step('DMG link is the canonical URL', async () => {
      const h = await page.locator('a[data-launch="dmg"]').getAttribute('href'); ok(h === DMG_URL, `href is ${h}`);
    });
    await step('published SHA-256 present; terms, button, DMG link, sha all on screen', async () => {
      await page.evaluate(() => { const t = document.querySelector('#trial-terms').getBoundingClientRect(); window.scrollBy(0, t.top - 90); });
      sha = (await page.locator('#sha256 code').first().innerText({ timeout: 2000 })).trim().toLowerCase();
      ok(/^[0-9a-f]{64}$/.test(sha), 'no published 64-hex SHA-256 (page still says pending)');
      if (expectSha) ok(sha === expectSha.toLowerCase(), `published ${sha} != expected ${expectSha}`);
      for (const sel of ['#trial-terms', 'a[data-launch="dmg"]', '#sha256']) {
        const bx = await page.locator(sel).boundingBox(); ok(bx && bx.y >= 0 && bx.y + bx.height <= size.height, `${sel} is not fully on screen`);
      }
    });
    await step('DMG: 200, diskimage type, size >=1 MB, not HTML, sha equals published', async () => {
      const r = await ctx.request.get(url(new URL(DMG_URL).pathname));
      ok(r.status() === 200, `status ${r.status()}`);
      const ct = r.headers()['content-type'] || ''; ok(/diskimage|octet-stream/.test(ct), `content-type ${ct}`);
      const body = await r.body(); ok(body.length >= 1_000_000, `size ${body.length} bytes is implausible for a DMG`);
      ok(!/^<!doctype html|^<html/i.test(body.subarray(0, 64).toString()), 'body is an HTML page');
      ok(sha, 'no published sha to compare');
      const got = crypto.createHash('sha256').update(body).digest('hex'); ok(got === sha, `sha256 of file ${got} != published ${sha}`);
      return `${body.length} bytes, sha ok`;
    });
  });
  await block('room', async () => {
    await step('back to landing, "Give it 60 seconds" starts the real room, typing works', async () => {
      await page.goBack(); await page.waitForURL(/\/(index\.html)?$/);
      await page.getByRole('link', { name: 'Give it 60 seconds' }).click();
      await page.locator('#room').waitFor({ state: 'visible' });
      await page.locator('#editor').click();
      const d = human ? 90 : 30;
      await page.keyboard.type('hello from a new visitor. I am writing forward and I will not stop. ', { delay: d });
      await page.keyboard.type('Nothing here is saved, so the only way out is through the next sentence.', { delay: d });
      ok((await page.locator('#editor').inputValue()).includes('through the next sentence'), 'editor text');
      ok(/^[1-9]/.test((await page.locator('#room-count').innerText()).trim()), 'word count');
      ok(/^[01]:[0-5]\d$/.test((await page.locator('#room-clock').innerText()).trim()), 'clock');
    });
  });
  await block('legal', async () => {
    for (const p of ['support', 'privacy', 'terms']) await step(`${p} reachable`, async () => {
      await page.goto(url(`/${p}.html`)); const h = (await page.locator('h1').first().innerText()).trim(); ok(h.toLowerCase() === p, `H1 is "${h}"`);
    });
  });
  await block('waitlist', async () => {
    await step('waitlist form reachable', async () => {
      await page.goto(url('/mac.html#waitlist')); await page.locator('#waitlist-form').waitFor({ state: 'visible' });
      for (const s of ['#waitlist-email', 'input[name=consent]']) ok(await page.locator(s).count() === 1, `${s} missing`);
    });
  });
  await block('later', async () => {
    log('SKIP', 'sign-in / checkout / test payment / output after payment', 'not built yet; asserted above that none is offered. Add real steps when they ship.');
  });
  await block('console', async () => { await step('no console errors across the journey', async () => ok(errors.length === 0, errors.slice(0, 3).join(' | '))); });

  const vid = page.video(); await ctx.close();
  if (vid) { const dest = path.join(dir, `journey-${tag}.webm`); fs.renameSync(await vid.path(), dest); console.log(`video [${tag}]: ${dest}`); }
}

fs.mkdirSync(out, { recursive: true });
let chrome; try { chrome = await chromium.launch({ channel: 'chrome' }); } catch { chrome = await chromium.launch(); }
const wk = await webkit.launch();
console.log(`journey base=${base} out=${out}`);
for (const s of sizes) await run(s, s.engine === 'webkit' ? wk : chrome);
await wk.close(); await chrome.close();
const fails = results.filter(r => r.status === 'FAIL');
fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({ base, results }, null, 1));
console.log(`\nSUMMARY base=${base}: ${results.filter(r => r.status === 'PASS').length} pass, ${fails.length} fail, ${results.filter(r => r.status === 'SKIP').length} skip`);
process.exit(fails.length ? 1 : 0);
