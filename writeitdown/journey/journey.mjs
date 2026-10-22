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
  const ldGraph = async () => (JSON.parse(await page.locator('script[type="application/ld+json"]').first().textContent()))['@graph'];

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
      ok(await page.getByRole('link', { name: 'Give it 60 seconds' }).count() >= 1, 'CTA missing');
    });
    await step('no price/buy/sign-in button offered (checkout does not exist yet)', async () => {
      const bad = await offers('body'); ok(bad.length === 0, `found ${JSON.stringify(bad)}`);
    });
  });
  await block('landing/seo', async () => {
    await step('canonical, meta description, og:*, twitter:card present and correct', async () => {
      const m = await page.evaluate(() => {
        const g = (sel, at) => document.querySelector(sel)?.getAttribute(at) || '';
        return { canonical: g('link[rel=canonical]', 'href'), desc: g('meta[name=description]', 'content'), ogt: g('meta[property="og:title"]', 'content'), ogd: g('meta[property="og:description"]', 'content'), ogi: g('meta[property="og:image"]', 'content'), ogu: g('meta[property="og:url"]', 'content'), tw: g('meta[name="twitter:card"]', 'content'), title: document.title };
      });
      ok(m.canonical === 'https://writeitdown.app/', `canonical ${m.canonical}`);
      ok(m.desc.length > 40 && m.ogd.length > 40 && m.ogt.length > 5, 'description/og text missing');
      ok(/^https:\/\/writeitdown\.app\/og\.png$/.test(m.ogi) && m.ogu === 'https://writeitdown.app/' && m.tw, `og image/url/twitter ${m.ogi} ${m.ogu} ${m.tw}`);
      ok(/write it down/i.test(m.title), `title ${m.title}`);
    });
    await step('og.png is served as an image', async () => {
      const r = await ctx.request.get(url('/og.png')); ok(r.status() === 200 && /image\/png/.test(r.headers()['content-type'] || ''), `og.png ${r.status()} ${r.headers()['content-type']}`);
    });
    await step('SoftwareApplication JSON-LD parses: 4.99 USD, PreOrder, macOS 14+', async () => {
      const g = await ldGraph(); const a = g.find(x => x['@type'] === 'SoftwareApplication'); ok(a, 'no SoftwareApplication');
      ok(a.offers.price === '4.99' && a.offers.priceCurrency === 'USD', `offer ${JSON.stringify(a.offers)}`);
      ok(/PreOrder$/.test(a.offers.availability), `availability ${a.offers.availability}`);
      ok(/macOS 14/.test(a.operatingSystem), `os ${a.operatingSystem}`);
    });
    await step('heading tree: one h1, h2 order per SEO.md, 3 h3 under how, 8 h3 under FAQ', async () => {
      const tree = (await page.locator('#landing h1, #landing h2, #landing h3').evaluateAll(els => els.map(e => e.tagName.toLowerCase() + ' ' + e.textContent.replace(/\s+/g, ' ').trim()))).join('\n');
      const h = tree.split('\n'); ok(h.filter(x => x.startsWith('h1 ')).length === 1, 'need exactly one h1 in the landing');
      const order = [/^h1 We force you to write it down$/, /^h2 What it feels like when you stop/, /^h2 Sixty seconds\. Forward only\. Nothing kept\./, /^h3 No way back/, /^h3 Eight seconds of silence/, /^h3 Reach zero, keep it/, /^h2 Real rules, real numbers/, /^h2 Write It Down for Mac/, /^h2 Questions, answered/];
      order.forEach((re, i) => ok(re.test(h[i] || ''), `heading ${i}: "${h[i]}" does not match ${re}`));
      ok(h.slice(9, 17).every(x => x.startsWith('h3 ')) && h.length === 18 && /^h2 We force you to write it down$/.test(h[17]), `FAQ/callback headings: ${JSON.stringify(h.slice(9))}`);
    });
  });
  await block('landing/core-rule', async () => {
    await step('three moments: writing, warning 3, deleted', async () => {
      await show('#core'); ok(await page.locator('#core .mo').count() === 3, 'need 3 states'); ok(/DRAFT DELETED/.test(await page.locator('.mo.m3').innerText()), 'deleted state text');
    });
  });
  await block('landing/how-it-works', async () => {
    await step('3 cards: no way back, eight seconds, reach zero', async () => {
      await show('#how'); const t = await page.locator('#how .cards .card h3').allInnerTexts();
      ok(t.length === 3 && /no way back/i.test(t[0]) && /eight seconds/i.test(t[1]) && /reach zero/i.test(t[2]), `cards ${JSON.stringify(t)}`);
    });
  });
  await block('landing/facts', async () => {
    await step('ledger: six rows incl. blocked, pressure, privacy, length, price, maker', async () => {
      await show('#facts'); const t = (await page.locator('#facts .ledger b').allInnerTexts()).map(x => x.toLowerCase());
      ok(['blocked', 'pressure', 'privacy', 'length', 'price', 'maker'].every((k, i) => t[i] === k), `rows ${JSON.stringify(t)}`);
      ok(/\$4\.99/.test(await page.locator('#facts').innerText()), 'price row');
    });
  });
  await block('landing/mac-block', async () => {
    await step('USD 4.99 / 2 Macs / 14 days / macOS 14 and honest "buying opens soon"', async () => {
      await show('#mac'); const t = await page.locator('#mac').innerText();
      ok(/3 sessions/i.test(t) && /\$4\.99/.test(t) && /2 Macs/.test(t) && /14 days/.test(t) && /macOS 14/.test(t), 'facts missing'); ok(/buying opens soon/i.test(t), '"buying opens soon" missing');
    });
    await step('Download free trial link reaches /download/ (200, real page)', async () => {
      const h = await page.locator('#mac a', { hasText: /^download free trial$/i }).getAttribute('href'); ok(h === 'download/', `href ${h}`);
      const r = await ctx.request.get(url('/download/')); ok(r.status() === 200 && /<h1>Write It Down for Mac<\/h1>/.test(await r.text()), 'download page is not the real page');
    });
    await step('waitlist link points at mac.html#waitlist', async () => {
      ok(await page.locator('#mac a[href="mac.html#waitlist"]').count() === 1, 'waitlist link missing');
    });
  });
  await block('landing/faq', async () => {
    await step('FAQ: 8 details, first open; open/close toggles by click and keyboard', async () => {
      await show('#faq'); const d = page.locator('#faq details'); ok(await d.count() === 8, `${await d.count()} items`);
      ok(await d.nth(0).evaluate(e => e.open), 'first item should start open');
      const sum = d.nth(1).locator('summary'); await sum.click(); ok(await d.nth(1).evaluate(e => e.open), 'did not open on click');
      ok(await d.nth(1).locator('p').isVisible(), 'answer not visible when open');
      await sum.click(); ok(!(await d.nth(1).evaluate(e => e.open)), 'did not close on click');
      await sum.focus(); await page.keyboard.press('Enter'); ok(await d.nth(1).evaluate(e => e.open), 'did not open on Enter');
      await page.keyboard.press('Enter'); ok(!(await d.nth(1).evaluate(e => e.open)), 'did not close on Enter');
    });
    await step('FAQ text equals the FAQPage JSON-LD (same 8 questions and answers)', async () => {
      const q = (await ldGraph()).find(x => x['@type'] === 'FAQPage'); ok(q && q.mainEntity.length === 8, 'FAQPage needs 8 questions');
      const vis = await page.locator('#faq details').evaluateAll(els => els.map(e => [e.querySelector('summary h3').textContent.replace(/\s+/g, ' ').trim(), e.querySelector('p').textContent.replace(/\s+/g, ' ').trim()]));
      q.mainEntity.forEach((m, i) => { ok(vis[i][0] === m.name, `Q${i + 1} "${vis[i][0]}" != JSON-LD "${m.name}"`); ok(vis[i][1] === m.acceptedAnswer.text.replace(/\s+/g, ' ').trim(), `A${i + 1} differs from JSON-LD`); });
    });
  });
  await block('landing/callback', async () => {
    await step('call-back band repeats the line and the 60-second door', async () => {
      await show('.callback'); const t = (await page.locator('.callback').innerText()).replace(/\s+/g, ' ');
      ok(/we force you to write it down/i.test(t) && /8 seconds/.test(t), 'band text'); ok(await page.locator('.callback a[href="#trial"]').count() === 1, 'door missing');
    });
  });
  await block('landing/footer', async () => {
    await step('Trefoil Studio, Product/Help/Legal links all resolve', async () => {
      await show('footer'); const t = await page.locator('footer').innerText(); ok(/Trefoil Studio/.test(t), 'Trefoil Studio missing');
      const hrefs = await page.locator('footer a').evaluateAll(els => els.map(e => e.getAttribute('href')));
      for (const n of ['support.html', 'privacy.html', 'terms.html', 'download/', 'mailto:contact@trefoilstudio.com', '#trial', 'mac.html#waitlist']) ok(hrefs.includes(n), `footer link ${n} missing`);
      for (const h of hrefs.filter(h => !/^(mailto:|#)/.test(h))) { const r = await ctx.request.get(url('/' + h.split('#')[0])); ok(r.status() === 200, `${h} -> ${r.status()}`); }
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
    await step('download page: canonical + og tags + title', async () => {
      const m = await page.evaluate(() => ({ c: document.querySelector('link[rel=canonical]')?.href, t: document.querySelector('meta[property="og:title"]')?.content, d: document.querySelector('meta[name=description]')?.content, u: document.querySelector('meta[property="og:url"]')?.content }));
      ok(m.c === 'https://writeitdown.app/download/' && m.u === 'https://writeitdown.app/download/' && m.t && m.d, `meta ${JSON.stringify(m)}`);
    });
    await step('download page: Install / Activate / Refunds sections', async () => {
      const t = await page.locator('.steps3 h2, .steps3 h3, #install h2, #trial h2, #refunds h2').allInnerTexts(); ok(['Install', 'Activate', 'Refunds'].every(k => t.includes(k)), `sections ${JSON.stringify(t)}`);
    });
    await step('DMG: 200, diskimage type, size >=1 MB, not HTML, sha equals published', async () => {
      const r = await ctx.request.get(url(new URL(DMG_URL).pathname));
      ok(r.status() === 200, `status ${r.status()}`);
      const ct = r.headers()['content-type'] || ''; ok(ct.split(';')[0].trim() === 'application/x-apple-diskimage', `content-type ${ct}`);
      const body = await r.body(); ok(body.length >= 1_000_000, `size ${body.length} bytes is implausible for a DMG`);
      ok(!/^<!doctype html|^<html/i.test(body.subarray(0, 64).toString()), 'body is an HTML page');
      ok(sha, 'no published sha to compare');
      const got = crypto.createHash('sha256').update(body).digest('hex'); ok(got === sha, `sha256 of file ${got} != published ${sha}`);
      return `${body.length} bytes, sha ok`;
    });
    await step('missing DMG returns 404, never HTML', async () => {
      const r = await ctx.request.get(url(`/download/missing-${crypto.randomUUID()}.dmg`));
      ok(r.status() === 404, `status ${r.status()}`);
      ok(!/text\/html/i.test(r.headers()['content-type'] || ''), 'HTML content type');
      ok(!/<(?:!doctype|html)\b/i.test(await r.text()), 'HTML fallback body');
    });
  });
  await block('room', async () => {
    await step('full real-time minute keeps exactly the typed draft and allows copying', async () => {
      await page.goBack(); await page.waitForURL(/\/(index\.html)?$/);
      await page.getByRole('link', { name: 'Give it 60 seconds' }).first().click();
      await page.locator('#room').waitFor({ state: 'visible' });
      await page.locator('#editor').click();
      const prose = 'I walked to the station this morning and watched the sun rise over the roofs. The next train was late, so I had time to think about the letter I wanted to write. I am putting those thoughts on paper now, one sentence at a time. ';
      let typed = '';
      const started = Date.now();
      while (Date.now() - started < 59000) {
        ok(await page.locator('#editor').isVisible(), 'session finished before sixty seconds');
        const char = prose[typed.length % prose.length];
        await page.keyboard.type(char, { delay: 90 });
        typed += char;
        ok(await page.locator('#editor').inputValue() === typed, 'input lost or draft wiped during continuous typing');
      }
      await page.locator('#kept').waitFor({ state: 'visible', timeout: 5000 });
      ok(Date.now() - started >= 60000, 'session finished before sixty seconds');
      ok((await page.locator('#room-clock').innerText()).trim() === '0:00', 'clock did not reach zero');
      ok(await page.locator('#kept-text').textContent() === typed, 'kept draft differs from typed text');
      ok(/0:00.*WORDS? KEPT\./.test(await page.locator('#receipt').innerText()), 'kept receipt missing');
      ok((await page.locator('#room-report').textContent()).trim() === '', 'deletion report present after completion');
      ok(await page.getByRole('button', { name: 'COPY TEXT', exact: true }).isVisible(), 'COPY TEXT missing');
      await page.locator('#copy').click();
      await page.getByRole('button', { name: 'COPIED', exact: true }).waitFor({ state: 'visible' });
    });
    await step('fresh session deletes its draft after nine seconds of silence', async () => {
      await page.locator('#restart').click();
      ok(await page.locator('#editor').inputValue() === '', 'restart retained text');
      await page.locator('#editor').click();
      const text = 'The rain has stopped and I can hear the birds outside.';
      await page.keyboard.type(text, { delay: 90 });
      ok(await page.locator('#editor').inputValue() === text, 'fresh session did not accept the sentence');
      await page.waitForTimeout(9000);
      ok(await page.locator('#editor').inputValue() === '', 'silent draft was not deleted');
      ok(/^DRAFT DELETED AT \d:\d\d\. TYPE TO START AGAIN\.$/.test(await page.locator('#room-report').innerText()), 'deletion receipt missing');
      ok(!await page.locator('#kept').isVisible(), 'silent session incorrectly kept');
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
console.log(`\nSUMMARY base=${base}: ${results.filter(r => r.status === 'PASS').length} pass, ${fails.length} fail; ${results.filter(r => r.status === 'SKIP').length} EXEMPT pending captain approval: not built (sign-in / checkout / test payment / output after payment)`);
process.exit(fails.length ? 1 : 0);
