// Write It Down release journey gate. Deterministic, no model clicking.
// Usage: npm run journey -- --base <url> [--out <dir>] [--expect-sha <hex>]
//        [--scenarios full-session,silence-wipe]
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
import { validateWaivers, waivedOffers, assertNoWaivedOffers, assertLiveSalesAllowed } from './waivers.mjs';

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i < 0 ? d : process.argv[i + 1]; };
const base = (arg('base') || '').replace(/\/+$/, '');
if (!/^https?:\/\//.test(base)) { console.error('usage: npm run journey -- --base <url> [--out <dir>] [--expect-sha <hex>]'); process.exit(2); }
const out = path.resolve(arg('out', `journey-results/${Date.now()}`));
const expectSha = arg('expect-sha', null);
const scenarios = arg('scenarios', null)?.split(',');
if (scenarios && scenarios.some(name => !['full-session', 'silence-wipe', 'mac-purchase'].includes(name))) {
  console.error('--scenarios accepts full-session,silence-wipe,mac-purchase'); process.exit(2);
}
const DMG_URL = 'https://writeitdown.app/download/Write-It-Down-1.0.dmg';
const sizes = [{ name: 'phone', width: 390, height: 844, engine: 'webkit' }, { name: 'desktop', width: 1440, height: 900, engine: 'chromium' }];
const results = [];
let waivers;
try {
  waivers = validateWaivers(JSON.parse(fs.readFileSync(new URL('./waivers.json', import.meta.url), 'utf8')));
  if (process.argv.includes('--live-sales')) assertLiveSalesAllowed(waivers);
} catch (error) {
  console.error(`FAIL release waivers: ${error.message}`); process.exit(1);
}
console.log('\nWAIVED (absent feature or pending maintainer acceptance)');
for (const waiver of waivers) {
  results.push({ ...waiver, tag: 'release', status: 'WAIVED', name: waiver.step });
  console.log(`  ${waiver.step}: ${waiver.reason} Approved by ${waiver.approved_by}; unwaive when ${waiver.unwaive_when}.`);
}
const NOISE = /cloudflareinsights|favicon|Access-Control-Allow-Origin|access control checks/i; // third-party beacon / local-server noise
// The unpaid-licence fixture answers 404 on purpose. That console entry is the harness's own
// probe, not a missing site resource, so exactly that URL and status is expected; every other
// console error still fails the gate.
const LICENSE_SERVICE = 'https://licenses.writeitdown.app/api/v1';
const PENDING_SESSION = 'cs_test_pending_fixture';
const EXPECTED_404_URL = `${LICENSE_SERVICE}/license?session_id=${PENDING_SESSION}`;
const isExpected404 = m => m.type() === 'error'
  && /^Failed to load resource: the server responded with a status of 404/.test(m.text())
  && m.location().url === EXPECTED_404_URL;
const ok = (c, m) => { if (!c) throw new Error(m); };

async function run(size, browser) {
  const tag = size.name;
  console.log(`engine [${tag}]: ${size.engine}${size.engine === 'webkit' ? ' (iPhone 14 profile: touch, DPR, UA)' : ''}`);
  const dir = path.join(out, tag);
  const ctx = await browser.newContext({
    ...(size.engine === 'webkit' ? devices['iPhone 14'] : {}),
    viewport: { width: size.width, height: size.height }, colorScheme: 'light',
    permissions: size.engine === 'webkit' ? ['clipboard-read'] : ['clipboard-read', 'clipboard-write'],
    recordVideo: { dir, size: { width: size.width, height: size.height } },
  });
  const page = await ctx.newPage();
  page.setDefaultTimeout(5000);
  const errors = [];
  page.on('console', m => { if (m.type() === 'error' && !isExpected404(m) && !NOISE.test(m.text() + (m.location().url || ''))) errors.push(`${m.text()} @ ${m.location().url}`); });
  page.on('pageerror', e => { if (!NOISE.test(String(e))) errors.push(String(e)); });
  const url = p => `${base}${p}`;
  const log = (status, name, msg = '') => { results.push({ tag, status, name, msg }); console.log(`${status.padEnd(4)} [${tag}] ${name}${msg ? ' - ' + msg : ''}`); };
  let current = '';
  const step = async (name, fn) => {
    try {
      const m = await fn();
      await assertNoWaivedOffers(page);
      log('PASS', `${current}: ${name}`, typeof m === 'string' ? m : '');
    }
    catch (e) { log('FAIL', `${current}: ${name}`, String(e.message).split('\n')[0]); }
    await page.waitForTimeout(2000);
  };
  const block = async (name, fn) => {
    if (scenarios && !scenarios.includes(name)) return;
    current = name; await fn();
  };
  const show = sel => page.locator(sel).first().evaluate(e => e.scrollIntoView({ block: 'start' }));
  // The room stage repeats the landing header inside the hidden #room section, so the landing
  // nav and entrance locators are anchored to the visible #landing stage.
  const landingNav = page.locator('#landing nav[aria-label=Main]');
  const landingDoor = page.locator('#landing > .cta a[href="#trial"]');
  let sha = null;
  const ldGraph = async () => (JSON.parse(await page.locator('script[type="application/ld+json"]').first().textContent()))['@graph'];

  await block('landing/hero', async () => {
    await step('page loads', async () => { const r = await page.goto(url('/')); ok(r.ok(), `status ${r.status()}`); });
    await step('H1 "We force you to" + "write it down", no final period', async () => {
      const h1 = page.locator('h1.h1');
      ok(await h1.count() === 1, `${await h1.count()} h1 elements`);
      const t = (await h1.innerText()).replace(/\s+/g, ' ').trim();
      ok(t.toLowerCase() === 'we force you to write it down', `H1 is "${t}"`);
    });
    await step('second line is the red handwritten one', async () => {
      const h = page.locator('h1.h1 .hand');
      const [f, c] = await h.evaluate(e => [getComputedStyle(e).fontFamily, getComputedStyle(e).color]);
      ok(/reenie/i.test(f), `font ${f}`);
      const [r, g, b] = c.match(/\d+/g).map(Number);
      ok(r > 150 && g < 100 && b < 100, `colour ${c} is not red`);
    });
    await step('top bar: one Download for Mac pill routed to /download/', async () => {
      const pill = landingNav.locator('a', { hasText: /^download for mac$/i });
      ok(await pill.count() === 1, `${await pill.count()} pills in the visible landing nav`);
      ok(await pill.getAttribute('href') === 'download/', `pill href is ${await pill.getAttribute('href')}`);
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
    await step('the only entrance under the demo is the 60-second door', async () => {
      const cta = page.locator('#landing > .cta'), demo = page.locator('#demo');
      ok(await cta.count() === 1, `${await cta.count()} entrance bands under the demo`);
      const c = await cta.boundingBox(), d = await demo.boundingBox();
      ok(c.y >= d.y + d.height - 2, 'the entrance band is not below the demo');
      ok(await cta.locator('a').count() === 1, `${await cta.locator('a').count()} links in the entrance band`);
      ok((await landingDoor.innerText()).trim().toLowerCase() === 'give it 60 seconds', 'CTA missing');
      ok(await landingDoor.getAttribute('href') === '#trial', 'the door does not open the trial');
      ok(/8 seconds/.test(await page.locator('#landing').innerText()), 'the page no longer states the eight-second rule');
    });
    await step('no waived sign-in feature offered', async () => {
      const bad = await waivedOffers(page); ok(bad.length === 0, `found ${JSON.stringify(bad)}`);
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
    await step('lockup and favicon SVGs use the image content type', async () => {
      for (const asset of ['/logo/write-it-down-lockup.svg', '/favicon.svg', '/favicon-dark.svg']) {
        const r = await ctx.request.get(url(asset));
        const type = (r.headers()['content-type'] || '').split(';')[0].trim();
        ok(r.status() === 200 && type === 'image/svg+xml', `${asset} ${r.status()} ${r.headers()['content-type']}`);
      }
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
    await step('USD 4.99 / 2 Macs / 14 days / macOS 14 and free updates', async () => {
      await show('#mac'); const t = await page.locator('#mac').innerText();
      ok(/3 sessions/i.test(t) && /\$4\.99/.test(t) && /2 Macs/.test(t) && /14 days/.test(t) && /macOS 14/.test(t), 'facts missing'); ok(/free updates/i.test(t), 'free updates missing');
    });
    await step('Download free trial link reaches /download/ (200, real page)', async () => {
      const h = await page.locator('#mac a', { hasText: /^download free trial$/i }).getAttribute('href'); ok(h === 'download/', `href ${h}`);
      const r = await ctx.request.get(url('/download/')); ok(r.status() === 200 && /<h1>Write It Down for Mac<\/h1>/.test(await r.text()), 'download page is not the real page');
    });
    await step('Buy link points at mac.html#buy', async () => {
      ok(await page.locator('#mac a[href="mac.html#buy"]').count() === 1, 'Buy link missing');
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
      for (const n of ['support.html', 'privacy.html', 'terms.html', 'download/', 'mailto:contact@trefoilstudio.com', '#trial', 'mac.html#buy']) ok(hrefs.includes(n), `footer link ${n} missing`);
      for (const h of hrefs.filter(h => !/^(mailto:|#)/.test(h))) { const r = await ctx.request.get(url('/' + h.split('#')[0])); ok(r.status() === 200, `${h} -> ${r.status()}`); }
    });
  });
  await block('download', async () => {
    await step('top-bar pill goes to /download/', async () => {
      await page.goto(url('/'));
      await landingNav.locator('a', { hasText: /^download for mac$/i }).click();
      await page.waitForURL(/\/download\/?$/);
      const h1 = page.locator('main h1');
      ok(await h1.count() === 1, `${await h1.count()} h1 elements on the download page`);
      ok((await h1.innerText()).trim() === 'Write It Down for Mac', 'download page H1 missing (host may serve the landing as fallback)');
    });
    await step('trial terms: 3 sessions, USD 4.99 one-time, 2 Macs, 14-day refund', async () => {
      const t = (await page.locator('#trial-terms').innerText()).toUpperCase();
      ok(/3 SESSIONS/.test(t) && /USD 4\.99 ONE-TIME/.test(t) && /2 MACS/.test(t) && /14-DAY REFUND/.test(t), `terms read "${t}"`);
    });
    await step('no waived sign-in feature offered on download page', async () => { const bad = await waivedOffers(page, 'main'); ok(bad.length === 0, `found ${JSON.stringify(bad)}`); });
    await step('DMG link is the canonical URL', async () => {
      const link = page.locator('main a[data-launch="dmg"]');
      ok(await link.count() === 1, `${await link.count()} DMG links on the download page`);
      const h = await link.getAttribute('href'); ok(h === DMG_URL, `href is ${h}`);
    });
    await step('published SHA-256 present; terms, button, DMG link, sha all on screen', async () => {
      await page.evaluate(() => { const t = document.querySelector('#trial-terms').getBoundingClientRect(); window.scrollBy(0, t.top - 90); });
      const checksum = page.locator('#sha256 code');
      ok(await checksum.count() === 1, `${await checksum.count()} published checksums`);
      sha = (await checksum.innerText({ timeout: 2000 })).trim().toLowerCase();
      ok(/^[0-9a-f]{64}$/.test(sha), 'no published 64-hex SHA-256 (page still says pending)');
      if (expectSha) ok(sha === expectSha.toLowerCase(), `published ${sha} != expected ${expectSha}`);
      for (const sel of ['#trial-terms', 'main a[data-launch="dmg"]', '#sha256']) {
        ok(await page.locator(sel).count() === 1, `${sel} matches ${await page.locator(sel).count()} elements`);
        const bx = await page.locator(sel).boundingBox(); ok(bx && bx.y >= 0 && bx.y + bx.height <= size.height, `${sel} is not fully on screen`);
      }
    });
    await step('download page: canonical + og tags + title', async () => {
      const m = await page.evaluate(() => ({ c: document.querySelector('link[rel=canonical]')?.href, t: document.querySelector('meta[property="og:title"]')?.content, d: document.querySelector('meta[name=description]')?.content, u: document.querySelector('meta[property="og:url"]')?.content }));
      ok(m.c === 'https://writeitdown.app/download/' && m.u === 'https://writeitdown.app/download/' && m.t && m.d, `meta ${JSON.stringify(m)}`);
    });
    await step('download page: Install / Activate / Refunds sections', async () => {
      const t = await page.locator('.steps3 .card > h2').allInnerTexts();
      ok(t.join('|') === 'Install|Activate|Refunds', `sections ${JSON.stringify(t)}`);
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
  await block('full-session', async () => {
    await step('finished draft and real clipboard equal typed text', async () => {
      await page.goto(url('/'));
      await landingDoor.click();
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
      ok(/^1 MINUTE\. \d+ WORDS?\.$/.test(await page.locator('#receipt').innerText()), 'kept receipt missing');
      ok((await page.locator('#room-report').textContent()).trim() === '', 'deletion report present after completion');
      ok(await page.getByRole('button', { name: 'COPY TEXT', exact: true }).isVisible(), 'COPY TEXT missing');
      await page.evaluate(() => navigator.clipboard.writeText('journey clipboard sentinel'));
      await page.locator('#copy').click();
      await page.getByRole('button', { name: 'COPIED', exact: true }).waitFor({ state: 'visible' });
      const copied = await page.evaluate(() => navigator.clipboard.readText());
      ok(copied === typed, 'clipboard differs from the finished draft');
      await page.locator('#exit').click();
      ok((await page.locator('#exit-hint').innerText()).trim() === 'Press Esc again to leave and delete the draft.', 'exit confirmation missing');
      ok(await page.locator('#room').isVisible(), 'one exit act left the room');
      await page.locator('#exit').click();
      await page.locator('#room').waitFor({ state: 'hidden' });
      ok(await page.locator('#landing').isVisible(), 'the second exit act did not return to the landing');
    });
  });
  await block('silence-wipe', async () => {
    await step('draft is deleted after eight seconds of silence', async () => {
      await page.goto(url('/'));
      await landingDoor.click();
      await page.locator('#room').waitFor({ state: 'visible' });
      ok(await page.locator('#editor').inputValue() === '', 'restart retained text');
      await page.locator('#editor').click();
      const text = 'The rain has stopped and I can hear the birds outside.';
      await page.keyboard.type(text, { delay: 90 });
      ok(await page.locator('#editor').inputValue() === text, 'fresh session did not accept the sentence');
      await page.waitForTimeout(8100);
      ok(await page.locator('#editor').inputValue() === '', 'silent draft was not deleted');
      ok(/^DRAFT DELETED AT \d:\d\d\. TYPE TO START AGAIN\.$/.test(await page.locator('#room-report').innerText()), 'deletion receipt missing');
      ok(!await page.locator('#kept').isVisible(), 'silent session incorrectly kept');
      ok((await page.locator('#failed h1').innerText()).trim() === 'You stopped.', 'failure headline missing');
      ok(await page.getByRole('button', { name: 'Begin again', exact: true }).isVisible(), 'Begin again missing');
      ok((await page.locator('#room-count').innerText()).trim() === '0 words', 'wiped count is not 0 words');
    });
  });
  await block('legal', async () => {
    for (const p of ['support', 'privacy', 'terms']) await step(`${p} reachable`, async () => {
      await page.goto(url(`/${p}.html`));
      const h1 = page.locator('main h1');
      ok(await h1.count() === 1, `${await h1.count()} h1 elements on ${p}.html`);
      const h = (await h1.innerText()).trim(); ok(h.toLowerCase() === p, `H1 is "${h}"`);
    });
  });
  await block('mac-purchase', async () => {
    const service = LICENSE_SERVICE;
    const hosted = 'https://checkout.stripe.com/c/pay/cs_test_journey_fixture';
    const licenseKey = 'WID-JOURNEY-FIXTURE-NOT-A-LICENSE';
    let posts = 0;
    await ctx.route('https://licenses.writeitdown.app/**', route => route.abort());
    await ctx.route('https://checkout.stripe.com/**', route => route.fulfill({ contentType: 'text/html', body: '<h1>Hosted checkout fixture</h1>' }));
    await ctx.route(`${service}/checkout`, route => {
      ok(route.request().method() === 'POST', 'checkout must POST');
      posts++;
      return route.fulfill({ json: { url: hosted } });
    });
    await step('Buy follows harness checkout and Back permits another checkout', async () => {
      await page.goto(url('/mac.html#buy'));
      const buy = page.getByRole('button', { name: 'BUY - $4.99', exact: true });
      await buy.click();
      await page.waitForURL(hosted);
      ok(posts === 1, 'expected one checkout POST');
      await page.goBack();
      ok(await buy.isEnabled(), 'Buy remains disabled after Back');
      ok(await page.locator('#checkout-status').textContent() === '', 'stale checkout status');
      await buy.click();
      await page.waitForURL(hosted);
      ok(posts === 2, 'Back did not permit retry');
    });
    await ctx.route(`${service}/license?session_id=cs_test_paid_fixture`, route => route.fulfill({ json: { licenseKey } }));
    await step('paid fixture delivers key, copy control and activation sentence, cleans URL', async () => {
      await page.goto(url('/mac.html?session_id=cs_test_paid_fixture'));
      await page.locator('#license-result').waitFor({ state: 'visible' });
      ok(await page.locator('#license-key').textContent() === licenseKey, 'fixture key missing');
      ok(await page.getByRole('button', { name: 'COPY LICENSE KEY', exact: true }).isVisible(), 'copy control missing');
      ok((await page.locator('#license-result').innerText()).includes("Paste this key into the app's activation field."), 'activation sentence missing');
      ok(!new URL(page.url()).searchParams.has('session_id'), 'credential retained after delivery');
    });
    await ctx.route(EXPECTED_404_URL, route => route.fulfill({ status: 404, json: { error: 'not_found' } }));
    await step('unpaid fixture shows neutral notice, no key, and retains retry URL', async () => {
      await page.goto(url(`/mac.html?session_id=${PENDING_SESSION}`));
      await page.getByText('Your licence is not ready yet. Reload in a moment.', { exact: true }).waitFor();
      ok(!await page.locator('#license-key').isVisible(), 'unpaid key visible');
      ok(!await page.locator('#copy-license').isVisible(), 'unpaid copy visible');
      ok(new URL(page.url()).searchParams.get('session_id') === PENDING_SESSION, 'retry credential lost');
    });
  });
  await block('console', async () => { await step('no unexpected console errors across the journey', async () => ok(errors.length === 0, errors.slice(0, 3).join(' | '))); });

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
fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({ base, scenarios: scenarios ?? null, results }, null, 1));
console.log(`\nSUMMARY base=${base}: ${results.filter(r => r.status === 'PASS').length} pass, ${fails.length} fail; ${waivers.length} WAIVED (absent feature or pending maintainer acceptance)`);
process.exit(fails.length ? 1 : 0);
