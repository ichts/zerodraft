#!/usr/bin/env node
/* Core-task meter for the writeitdown web surface.
   [INPUT] the repository (it serves `writeitdown/` itself over loopback), the installed Chrome, and an optional
           baseline metrics file to compare against. Never a live host, never a real payment.
   [OUTPUT] one JSON file of raw runs, one metrics document in the shape `data/wid-core-tasks-baseline` uses, the
           table, and - with `--compare` - the experience line the captain reads.
   [POS] the night loop's instrument: it answers "did the three tasks get cheaper" with numbers from the real page,
         so a fix can be argued with evidence instead of opinion. Measurement only; it changes no product code.
   [PROTOCOL] T1 navigation -> first glyph painted, T2 first glyph -> clipboard, T3 landing -> Stripe hand-off
              (POST stubbed, navigation aborted). Every browser starts from a fresh context. Timestamps are taken in
              the page with `performance.timeOrigin + performance.now()`, so one wall clock spans both documents.
              A value that cannot be measured is null; nothing is estimated and human think time is never counted.

   node scripts/core-tasks/measure-web.mjs [--runs 2] [--tasks 1,2,3] [--viewports desktop,mobile]
                                           [--out <dir>] [--compare docs/core-tasks-baseline.json]

   Wall clock is dominated by T2 by design: the web trial is a 60-second session, so each T2 run really types for
   a minute. `--tasks 1,3` is the fast shape while working on the buy path or the door. */
import { createRequire } from 'node:module';
import { spawn, execFileSync } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { loadavg } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { experienceLines, formatTable, runsToMetrics } from './metrics.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true]);
  return acc;
}, []));
const runs = Number(args.runs ?? 2);
const tasks = String(args.tasks ?? '1,2,3').split(',').map(Number);
const viewportNames = String(args.viewports ?? 'desktop,mobile').split(',');
const out = path.resolve(args.out ?? path.join(here, 'out', new Date().toISOString().replace(/[:.]/g, '-')));
mkdirSync(path.join(out, 'shots'), { recursive: true });

const { chromium } = createRequire(path.join(repo, 'package.json'))('@playwright/test');
const VIEWPORTS = {
  desktop: { viewport: { width: 1440, height: 900 }, hasTouch: false, isMobile: false },
  mobile: { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, hasTouch: true, isMobile: true }
};
const FAKE_KEY = 'FAKE-KEY-NOT-REAL';
const FAKE_STRIPE = 'https://checkout.stripe.com/c/pay/cs_test_FAKE';
const TYPING_MS_PER_CHAR = 170; // ~350 keystrokes a minute, the pace the baseline report measured
const WORDS = 'i keep writing forward because the clock is running and the words have to come out before it reaches zero so i do not stop to think about the shape of the sentence '.split(' ');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const freePort = () => new Promise(resolve => {
  const s = createServer();
  s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); });
});

/* In-page recorder: one wall clock, every moment the three tasks are made of. */
const recorder = () => {
  const epoch = () => performance.timeOrigin + performance.now();
  const m = (window.__m = { marks: [], mark(name, extra) { this.marks.push({ name, at: epoch(), ...extra }); } });
  m.marks.push({ name: 'origin', at: performance.timeOrigin });
  const afterPaint = name => requestAnimationFrame(() => requestAnimationFrame(() => m.mark(name)));
  new PerformanceObserver(list => list.getEntries().forEach(e => e.name === 'first-contentful-paint'
    && m.marks.push({ name: 'fcp', at: performance.timeOrigin + e.startTime }))).observe({ type: 'paint', buffered: true });
  document.addEventListener('pointerdown', e => m.mark('pointerdown'), true);
  document.addEventListener('keydown', e => m.mark('keydown', { key: e.key }), true);
  document.addEventListener('DOMContentLoaded', () => {
    const room = document.getElementById('room');
    const editor = document.getElementById('editor');
    if (!room) return;
    let lastHidden = room.hidden, lastPhase = room.dataset.phase;
    new MutationObserver(() => {
      if (lastHidden !== room.hidden) { lastHidden = room.hidden; m.mark(room.hidden ? 'room-hidden' : 'room-visible'); }
      // Two marks per phase: the synchronous flip (the room decided) and the frame that shows it. The gap between
      // them is the room's own render cost, and the gap from the deadline to the flip is detection (D-111).
      if (lastPhase !== room.dataset.phase) { lastPhase = room.dataset.phase; m.mark(`phase:${room.dataset.phase}`); afterPaint(`phase-painted:${room.dataset.phase}`); }
    }).observe(room, { attributes: true, attributeFilter: ['hidden', 'data-phase'] });
    editor?.addEventListener('focus', () => m.mark('editor-focus'));
    editor?.addEventListener('input', () => { m.mark('input'); afterPaint('input-painted'); });
    const label = document.getElementById('copy-label');
    if (label) new MutationObserver(() => m.mark(`copy-label:${label.textContent}`)).observe(label, { childList: true, characterData: true, subtree: true });
  });
  // The door is the landing's named 'door' animation (D-097); it is settled on the frame after the last one ends.
  document.addEventListener('click', () => {
    let waited = 0;
    const poll = () => {
      const room = document.getElementById('room');
      if (!room || room.hidden) { if (waited++ < 120) return requestAnimationFrame(poll); return m.mark('door-settled'); }
      if (document.getAnimations().some(a => a.id === 'door')) return requestAnimationFrame(poll);
      m.mark('door-settled');
    };
    requestAnimationFrame(poll);
  }, true);
  window.addEventListener('load', () => m.mark('load'));
  document.addEventListener('DOMContentLoaded', () => document.fonts.ready.then(() => m.mark('fonts-ready')));
};

const at = (marks, name) => marks.find(x => x.name === name)?.at ?? null;
const since = (a, b) => (a == null || b == null ? null : Math.round((b - a) * 10) / 10);
const openPage = async (browser, vpName, base) => {
  const context = await browser.newContext({ ...VIEWPORTS[vpName], colorScheme: 'light', reducedMotion: 'no-preference', permissions: ['clipboard-read', 'clipboard-write'] });
  await context.addInitScript(recorder);
  const page = await context.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => window.__m.marks.some(x => x.name === 'fonts-ready'));
  return { context, page };
};
const openRoom = async (page, vpName) => {
  const door = page.locator('#landing a[href="#trial"]').first();
  if (vpName === 'mobile') await door.tap(); else await door.click();
  await page.waitForFunction(() => window.__m.marks.some(x => x.name === 'door-settled') && document.activeElement?.id === 'editor');
  await sleep(120);
};

/* T1 - open the product and start writing. Two steps: the door, then one character. */
async function taskOne(browser, vpName, base) {
  const { context, page } = await openPage(browser, vpName, base);
  const cold = await page.evaluate(() => ({ storageKeys: localStorage.length, cookies: document.cookie }));
  await page.screenshot({ path: path.join(out, 'shots', `${vpName}-t1-landing.png`) });
  const before = await page.evaluate(() => window.__m.marks);
  const door = page.locator('#landing a[href="#trial"]').first();
  if (vpName === 'mobile') await door.tap(); else await door.click();
  await page.waitForFunction(() => window.__m.marks.some(x => x.name === 'door-settled') && document.activeElement?.id === 'editor');
  await sleep(120);
  await page.screenshot({ path: path.join(out, 'shots', `${vpName}-t1-room-empty.png`) });
  await page.keyboard.press('i');
  await page.waitForFunction(() => window.__m.marks.some(x => x.name === 'input-painted'));
  await page.screenshot({ path: path.join(out, 'shots', `${vpName}-t1-first-char.png`) });
  const marks = await page.evaluate(() => window.__m.marks);
  const click = at(marks, 'pointerdown');
  const key = at(marks, 'keydown');
  const text = await page.locator('#editor').inputValue();
  await context.close();
  return {
    cold,
    ms: {
      nav_to_fcp: since(at(marks, 'origin'), at(marks, 'fcp')),
      nav_to_fonts_ready: since(at(before, 'origin'), at(before, 'fonts-ready')),
      click_to_editor_focus: since(click, at(marks, 'editor-focus')),
      click_to_door_settled: since(click, at(marks, 'door-settled')),
      key_to_glyph_painted: since(key, at(marks, 'input-painted'))
    },
    steps: { clicks: 1, keypresses: 1, decisions: 1 },
    typedOk: text === 'i'
  };
}

/* T2 - write to 0:00 uninterrupted and take the text. Two steps: the write, then Copy text. */
async function taskTwo(browser, vpName, base) {
  const { context, page } = await openPage(browser, vpName, base);
  await openRoom(page, vpName);
  const typed = [];
  const started = Date.now();
  let i = 0;
  while (Date.now() - started < 56_000) {
    const word = WORDS[i++ % WORDS.length];
    await page.keyboard.type(`${word} `, { delay: TYPING_MS_PER_CHAR });
    typed.push(`${word} `);
  }
  const deadlineOverrun = await (async () => {
    await page.waitForFunction(() => window.__m.marks.some(x => x.name === 'phase-painted:kept'), null, { timeout: 20_000 });
    const marks = await page.evaluate(() => window.__m.marks);
    // The session clock starts on the first input event (the same instant the room records), and the kept screen
    // counts once it is painted, so this is the late-arriving milliseconds a writer actually waits.
    const sessionStart = marks.find(x => x.name === 'input')?.at;
    const firstPainted = marks.find(x => x.name === 'input-painted')?.at;
    const flip = marks.find(x => x.name === 'phase:kept')?.at;
    const kept = marks.find(x => x.name === 'phase-painted:kept')?.at;
    return { overrun: since(sessionStart + 60_000, kept), firstChar: firstPainted, kept,
      detection: since(sessionStart + 60_000, flip), paint: since(flip, kept) };
  })();
  const focusAtKept = await page.evaluate(() => document.activeElement?.id ?? null);
  const keptText = await page.locator('#kept-text').innerText();
  const receipt = await page.locator('#receipt').innerText();
  await page.screenshot({ path: path.join(out, 'shots', `${vpName}-t2-kept.png`) });
  const pointerAt = await page.evaluate(() => performance.timeOrigin + performance.now());
  if (vpName === 'mobile') await page.locator('#copy').tap(); else await page.locator('#copy').click();
  await page.waitForFunction(() => document.getElementById('copy-label')?.textContent === 'Copied', null, { timeout: 5000 });
  const afterCopy = await page.evaluate(() => window.__m.marks);
  const copiedAt = afterCopy.find(x => /^copy-label:Copied/.test(x.name))?.at;
  const clipboard = await page.evaluate(() => navigator.clipboard.readText()).catch(() => null);
  await page.screenshot({ path: path.join(out, 'shots', `${vpName}-t2-copied.png`) });
  await context.close();
  const typedText = typed.join('');
  return {
    ms: {
      first_char_to_kept_painted: since(deadlineOverrun.firstChar, deadlineOverrun.kept),
      kept_painted_to_copy_pointer: since(deadlineOverrun.kept, pointerAt),
      copy_pointer_to_copied_label: since(pointerAt, copiedAt),
      deadline_overrun_vs_60000: deadlineOverrun.overrun,
      deadline_detection_ms: deadlineOverrun.detection,
      kept_paint_ms: deadlineOverrun.paint
    },
    steps: { typingKeystrokes: typedText.length, nonTypingActions: 1, nonTypingActionsNote: 'one click on Copy text (focus is already on it)' },
    focusAtKept,
    receipt,
    // The kept text is compared without its line breaks: the ink layer renders logical lines, the draft is one run.
    keptTextMatchesTyped: keptText.replace(/\s+/g, ' ').trim() === typedText.replace(/\s+/g, ' ').trim(),
    clipboardMatchesKept: clipboard != null && clipboard.replace(/\s+/g, ' ').trim() === keptText.replace(/\s+/g, ' ').trim()
  };
}

/* T3 - buy the full version. Stubbed: the checkout POST is answered locally and the Stripe navigation is aborted,
   so no money can move and no session is created. */
async function taskThree(browser, vpName, base) {
  const { context, page } = await openPage(browser, vpName, base);
  // One handler: the POST is answered locally (the licence service is never contacted) and the Stripe navigation is
  // aborted before it leaves the browser, so this task cannot create a session and cannot spend anything.
  let postedAt = null, stripeRequested = null;
  await context.route('**/api/v1/checkout', route => {
    postedAt ??= Date.now();
    return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'content-type': 'application/json' }, body: JSON.stringify({ url: FAKE_STRIPE }) });
  });
  await context.route('https://checkout.stripe.com/**', route => { stripeRequested = Date.now(); route.abort(); });
  const reach = await page.evaluate(() => {
    const a = [...document.querySelectorAll('#landing a')].find(x => /Buy for \$4\.99/.test(x.textContent));
    if (!a) return { screensDown: null, inFirstScreen: false };
    const r = a.getBoundingClientRect();
    return { screensDown: Math.round(((r.top + scrollY) / innerHeight) * 100) / 100, inFirstScreen: r.top < innerHeight };
  });
  await page.screenshot({ path: path.join(out, 'shots', `${vpName}-t3-landing-first-screen.png`) });
  const scrollBefore = await page.evaluate(() => scrollY);
  await page.locator('#landing a:has-text("Buy for $4.99")').first().scrollIntoViewIfNeeded();
  const scrolls = Math.round((await page.evaluate(() => scrollY) - scrollBefore) / await page.evaluate(() => innerHeight) * 100) / 100;
  const clickAt = await page.evaluate(() => performance.timeOrigin + performance.now());
  await page.locator('#landing a:has-text("Buy for $4.99")').first().click();
  await page.waitForURL(/mac\.html/, { timeout: 15_000 });
  await page.waitForSelector('#buy-form button', { state: 'visible' });
  const loadedAt = await page.evaluate(() => performance.timeOrigin + performance.now());
  await page.screenshot({ path: path.join(out, 'shots', `${vpName}-t3-purchase-page.png`) });
  await page.locator('#buy-form button').click();
  await page.waitForURL(/checkout\.stripe\.com/, { timeout: 15_000 }).catch(() => {});
  const handoffAt = Date.now();
  await context.close();
  return {
    reach,
    ms: {
      landing_click_to_purchase_page_loaded: since(clickAt, loadedAt),
      buy_click_to_checkout_post: postedAt == null ? null : postedAt - clickAt,
      buy_click_to_stripe_handoff: stripeRequested == null ? null : stripeRequested - postedAt
    },
    steps: { clicks: 2, scrollsOnLanding: scrolls, decisions: 0 }
  };
}

/* T3b - the header path: three clicks, no scrolling. It exists so the shorter route a buyer can already take is in
   the same document as the landing link's reach, and a fix cannot trade one for the other unnoticed. */
async function taskThreeB(browser, vpName, base) {
  const { context, page } = await openPage(browser, vpName, base);
  await context.route('**/api/v1/checkout', route => route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'content-type': 'application/json' }, body: JSON.stringify({ url: FAKE_STRIPE }) }));
  await context.route('https://checkout.stripe.com/**', route => route.abort());
  const t0 = Date.now();
  await page.locator('.home-nav a:has-text("Download for Mac")').first().click();
  await page.waitForSelector('a:has-text("Buy for $4.99")', { timeout: 15_000 });
  await page.locator('a:has-text("Buy for $4.99")').first().click();
  await page.waitForURL(/mac\.html/, { timeout: 15_000 });
  await page.waitForSelector('#buy-form button', { state: 'visible' });
  await page.locator('#buy-form button').click();
  await page.waitForURL(/checkout\.stripe\.com/, { timeout: 15_000 }).catch(() => {});
  const t1 = Date.now();
  await context.close();
  return { ms: { total_machine: since(t0, t1) }, steps: { clicks: 3, scrolls: 0 } };
}

// --- the run ---------------------------------------------------------------------------------------------------
let server;
try {
  const port = await freePort();
  server = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '-d', repo], { stdio: 'ignore' });
  await sleep(600);
  const base = `http://127.0.0.1:${port}/writeitdown/`;
  const browser = await chromium.launch({ channel: 'chrome' });
  const raw = { meta: { base, repo, runs, tasks, viewports: viewportNames, at: new Date().toISOString(), browser: browser.version(), loadavgStart: loadavg().map(x => Math.round(x * 10) / 10) }, runs: [] };
  for (let n = 1; n <= runs; n++) {
    for (const vpName of viewportNames) {
      const rec = { viewport: vpName, run: n, loadavg: loadavg()[0] };
      if (tasks.includes(1)) rec.t1 = await taskOne(browser, vpName, base);
      if (tasks.includes(2)) rec.t2 = await taskTwo(browser, vpName, base);
      if (tasks.includes(3)) { rec.t3 = await taskThree(browser, vpName, base); rec.t3b = await taskThreeB(browser, vpName, base); }
      raw.runs.push(rec);
      console.error(`[core-tasks] ${vpName} run ${n} done (load ${rec.loadavg.toFixed(1)})`);
    }
  }
  raw.meta.loadavgEnd = loadavg().map(x => Math.round(x * 10) / 10);
  await browser.close();
  const head = (() => { try { return execFileSync('git', ['-C', repo, 'rev-parse', '--short', 'HEAD']).toString().trim(); } catch { return null; } })();
  const metrics = runsToMetrics(raw.runs, { ...raw.meta, head });
  writeFileSync(path.join(out, 'web.json'), JSON.stringify(raw, null, 1));
  writeFileSync(path.join(out, 'metrics.json'), JSON.stringify(metrics, null, 1));
  console.log(`\n${formatTable(metrics)}`);
  const unmeasured = Object.entries(metrics).filter(([k]) => !k.startsWith('_') && k !== 'meta')
    .flatMap(([k, m]) => ['T1', 'T2', 'T3'].filter(t => !m[t]).map(t => `${t} on ${k}: unmeasured`));
  if (unmeasured.length) console.log(`\nunmeasured: ${unmeasured.join(', ')}`);
  if (args.compare) {
    const baseline = JSON.parse(readFileSync(path.resolve(args.compare), 'utf8'));
    const lines = experienceLines(baseline, metrics);
    console.log(`\n${Array.isArray(lines) ? lines.join('\n') : lines}`);
  }
  console.log(`\nraw: ${path.join(out, 'web.json')}  metrics: ${path.join(out, 'metrics.json')}  shots: ${path.join(out, 'shots')}`);
  console.log(`load average ${raw.meta.loadavgStart[0]} -> ${raw.meta.loadavgEnd[0]}; every number is a product latency plus whatever the host took, so compare a run with a run on a similar host.`);
} finally {
  server?.kill();
}
