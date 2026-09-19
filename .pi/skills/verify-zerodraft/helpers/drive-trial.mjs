#!/usr/bin/env node
// verify-zerodraft helper: drives the flagship trial wipe flow on the root
// static surface and captures evidence. Read the contract in ../SKILL.md.
//
//   node .pi/skills/verify-zerodraft/helpers/drive-trial.mjs --doctor
//   node .pi/skills/verify-zerodraft/helpers/drive-trial.mjs --url <base> --evidence <dir>
//
// Exit 0 = every assertion passed; exit 1 = first failure named on stderr.

import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const args = process.argv.slice(2);
const flag = name => {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args[i + 1];
};

const url = (flag('--url') || 'http://127.0.0.1:8000').replace(/\/$/, '');
const evidence = flag('--evidence')
  || join('tmp', 'verify-zerodraft', new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14));
const doctor = args.includes('--doctor');

function loadPlaywright() {
  const candidates = [process.env.PLAYWRIGHT_NODE_MODULES, resolve('writeitdown/node_modules')]
    .filter(Boolean);
  for (const dir of candidates) {
    try {
      return createRequire(join(dir, 'verify-zerodraft.js'))('playwright');
    } catch { /* try the next candidate */ }
  }
  return null;
}

const playwright = loadPlaywright();
if (!playwright) {
  console.error('FAIL: playwright module not found. Tried $PLAYWRIGHT_NODE_MODULES and writeitdown/node_modules.');
  console.error('Fix: cd writeitdown && npm install   (once the writeitdown harness is on your branch)');
  console.error(' Or: npm install --no-save --prefix tmp/zvd-pw playwright && PLAYWRIGHT_NODE_MODULES=tmp/zvd-pw/node_modules <this command>');
  process.exit(1);
}

async function launchBrowser() {
  try {
    return await playwright.chromium.launch();
  } catch {
    return await playwright.chromium.launch({ channel: 'chrome' });
  }
}

if (doctor) {
  try {
    const browser = await launchBrowser();
    await browser.close();
    console.log(`OK: playwright ${playwright.chromium.name()} resolves and a browser launches.`);
  } catch (error) {
    console.error(`FAIL: browser launch: ${error.message.split('\n')[0]}`);
    console.error('Fix: npx playwright install chromium   (or install Google Chrome for the channel fallback)');
    process.exit(1);
  }
  process.exit(0);
}

mkdirSync(evidence, { recursive: true });

const assertions = [];
const check = (name, ok, detail = '') => {
  assertions.push({ name, ok, detail });
  if (!ok) throw new Error(`assertion failed: ${name}${detail ? ` (${detail})` : ''}`);
};

const consoleErrors = [];
const pageErrors = [];
const failedRequests = [];

const browser = await launchBrowser();
let driveError = null;
try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  page.on('pageerror', error => pageErrors.push(error.message));
  page.on('requestfailed', request => failedRequests.push(request.url()));
  await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));

  // 1. Landing: the door is the only entrance, the demo paper is present.
  await page.goto(`${url}/index.html`);
  const door = page.locator('a.door');
  await door.waitFor();
  check('landing door visible', (await door.textContent()).includes('Give it sixty seconds.'));
  await page.locator('.demo-paper').waitFor();
  await page.screenshot({ path: join(evidence, '01-landing.png') });

  // 2. Enter the trial through the door. The overlay fades in over --snap
  //    (visibility transitions from hidden), so wait for it to be visible.
  await door.click();
  const editor = page.locator('.trial-editor[role="textbox"]');
  await page.waitForFunction(() => getComputedStyle(document.querySelector('.trial-overlay')).visibility === 'visible');
  check('trial route entered', await page.evaluate(() => location.hash === '#trial'));
  // Observation, not a gate: whether the app's own rAF focus landed on the
  // editor. When it did not, do what a real user does - click the paper.
  const editorAutofocused = await page.evaluate(() => document.activeElement?.classList.contains('trial-editor'));
  assertions.push({ name: 'editor autofocused on entry (observation)', ok: true, detail: String(editorAutofocused) });
  if (!editorAutofocused) await editor.click();
  await page.screenshot({ path: join(evidence, '02-trial-rest.png') });

  // 3. Type forward; the word count corner tracks it.
  const sentence = 'The quick brown fox writes without looking back.';
  const expectedWords = sentence.split(/\s+/).length;
  await page.keyboard.type(sentence, { delay: 40 });
  await page.waitForTimeout(300);
  const words = await page.locator('.chrome-br .label').textContent();
  check('word count tracks typing', (words || '').startsWith(`${expectedWords} word`), words);

  // 4. Forward-only: Backspace is denied and the text does not change.
  const before = await editor.textContent();
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(300);
  check('backspace denied, text unchanged', (await editor.textContent()) === before);
  await page.screenshot({ path: join(evidence, '03-typed-deny.png') });

  // 5. Silence: the wipe lands at 8 seconds with the machine report.
  await page.locator('.report-line').waitFor({ timeout: 15000 });
  const report = await page.locator('.report-line').textContent();
  check('wipe report lands', /draft wiped - \d+:\d{2} unused/i.test(report || ''), report);
  check('draft is gone', (await editor.textContent()) === '');
  await page.screenshot({ path: join(evidence, '04-wiped.png') });

  // 6. Type to restart: the editor is still armed, a fresh session begins.
  await editor.click();
  await page.keyboard.type('Again.', { delay: 60 });
  await page.waitForTimeout(300);
  check('rearm starts a fresh session', (await editor.textContent()) === 'Again.');
  check('report hidden after rearm', await page.locator('.report-line').isHidden());
  const timer = await page.locator('.chrome-tr .trial-timer').textContent();
  check('timer restarted near 1:00', /^(1:00|0:5\d)$/.test((timer || '').trim()), timer);
  await page.screenshot({ path: join(evidence, '05-rearmed.png') });

  // 7. The trial persists nothing.
  check('localStorage untouched', await page.evaluate(() => localStorage.length === 0));
} catch (error) {
  driveError = error;
  assertions.push({ name: 'drive completed without exception', ok: false, detail: String(error?.message || error).split('\n')[0] });
} finally {
  const failed = assertions.filter(a => !a.ok);
  const summary = { url, evidence, assertions, consoleErrors, pageErrors, failedRequests };
  writeFileSync(join(evidence, 'drive-trial.json'), JSON.stringify(summary, null, 2));
  await browser.close();
  if (failed.length) {
    console.error(`FAIL: ${failed[0].name} - evidence in ${evidence}/drive-trial.json`);
    process.exit(1);
  }
  console.log(`PASS: ${assertions.length} assertions, evidence in ${evidence}/`);
  if (consoleErrors.length || pageErrors.length) {
    console.log(`WARN: ${consoleErrors.length} console errors, ${pageErrors.length} page errors (see drive-trial.json)`);
  }
}
