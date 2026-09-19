import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { TIMELINE } from '../demo-timeline.mjs';

const capture = (page, info, state) => page.screenshot({ path: info.outputPath(`${state}.png`) });
const editor = page => page.locator('#editor');
const browserEvidence = new WeakMap();
const demoGeometry = new WeakMap();

async function enter(page) {
  await page.locator('#landing .door').click();
  await expect(editor(page)).toBeFocused();
}

async function assertZen(page) {
  const geometry = await editor(page).evaluate(e => {
    const style = getComputedStyle(e);
    const line = parseFloat(style.lineHeight);
    const rect = e.getBoundingClientRect();
    const paper = e.closest('.room-paper').getBoundingClientRect();
    const activeCenter = rect.top + e.scrollHeight - e.scrollTop - parseFloat(style.paddingBottom) - line / 2;
    return {
      height: e.clientHeight, line, overflow: style.overflowY, scrollbar: style.scrollbarWidth,
      mask: style.maskImage, bottomGap: e.scrollHeight - e.clientHeight - e.scrollTop,
      centerOffset: activeCenter - (rect.top + rect.height / 2),
      activeCenter, paperTop: paper.top, paperHeight: paper.height,
      ratio: (activeCenter - paper.top) / paper.height,
      apertureTop: rect.top,
      chromeBottom: e.closest('.room-paper').querySelector('.chrome-row').getBoundingClientRect().bottom,
      visibleTextLines: [0, 1, 2, 3].filter(previous => activeCenter - previous * line > rect.top).length,
      pageHeight: document.documentElement.scrollHeight, viewportHeight: innerHeight,
      pageWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth,
    };
  });
  expect(Math.abs(geometry.height - geometry.line * 5)).toBeLessThan(1);
  expect(geometry.visibleTextLines).toBe(3);
  expect(Math.abs(geometry.centerOffset)).toBeLessThan(1);
  const demo = demoGeometry.get(page);
  // Compare line-box centers in their own papers, allowing only a quarter
  // demo line of proportional drift, not a loose viewport midpoint bound.
  expect(Math.abs(geometry.ratio - demo.ratio)).toBeLessThan(demo.line / (4 * demo.paperHeight));
  expect(geometry.activeCenter).toBeLessThan(geometry.viewportHeight / 2);
  expect(geometry.apertureTop).toBeGreaterThan(geometry.chromeBottom);
  expect(geometry.bottomGap).toBeLessThan(2);
  expect(geometry.overflow).toBe('hidden');
  expect(geometry.scrollbar).toBe('none');
  // The current line occupies 40%-60% of the aperture: alpha 1 throughout.
  expect(geometry.mask).toContain('rgb(0, 0, 0) 40%');
  expect(geometry.mask).toContain('rgb(0, 0, 0) 60%');
  expect(geometry.mask).toContain('rgba(0, 0, 0, 0.07) 10%');
  expect(geometry.mask).toContain('rgba(0, 0, 0, 0.22) 30%');
  // iA Writer Focus: the falloff above the clear band mirrors the falloff
  // below it - same stop positions, same alpha ladder - at every width.
  const stops = maskStops(geometry.mask);
  expect(stops).toHaveLength(8);
  for (const stop of stops) {
    const mirror = stops.find(other => Math.abs(other.pos - (100 - stop.pos)) < 0.5);
    expect(mirror, `no mirror stop for ${JSON.stringify(stop)} in ${geometry.mask}`).toBeTruthy();
    expect(Math.abs(mirror.alpha - stop.alpha)).toBeLessThan(0.011);
  }
  const bandLines = geometry.height * 0.2 / geometry.line;
  expect(bandLines).toBeGreaterThanOrEqual(1);
  expect(bandLines).toBeLessThanOrEqual(2);
  expect(geometry.pageHeight).toBe(geometry.viewportHeight);
  expect(geometry.pageWidth).toBe(geometry.viewportWidth);
  return geometry;
}

// Parse a computed linear-gradient into {pos, alpha} pairs; unpositioned
// first/last stops are 0%/100%. Computed colors look like rgb(0, 0, 0),
// rgba(0, 0, 0, 0.07).
function maskStops(maskImage) {
  const body = maskImage.slice(maskImage.indexOf('(') + 1, maskImage.lastIndexOf(')'));
  const tokens = [];
  let depth = 0, token = '';
  for (const ch of body) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) { tokens.push(token.trim()); token = ''; }
    else token += ch;
  }
  tokens.push(token.trim());
  return tokens.map((stop, index) => {
    const match = stop.match(/^(.*?)(?:\s+([\d.]+%))?$/);
    const alpha = match[1].match(/,\s*([\d.]+)\)$/);
    return {
      pos: match[2] ? parseFloat(match[2]) : index === 0 ? 0 : 100,
      alpha: /^rgb\(/.test(match[1]) ? 1 : alpha ? parseFloat(alpha[1]) : NaN,
    };
  });
}

test.beforeEach(async ({ page }) => {
  const evidence = { errors: [], consoleErrors: [], requests: [], failedAssets: [], failedRequests: [] };
  browserEvidence.set(page, evidence);
  page.on('pageerror', error => evidence.errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error') evidence.consoleErrors.push(message.text());
  });
  page.on('requestfailed', request => evidence.failedRequests.push(request.url()));
  await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));
  page.on('request', request => evidence.requests.push({ method: request.method(), url: request.url() }));
  page.on('response', response => {
    if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) evidence.failedAssets.push(response.url());
  });
  await page.clock.install({ time: new Date('2026-09-16T12:00:00Z') });
  await page.clock.pauseAt(new Date('2026-09-16T12:00:01Z'));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  demoGeometry.set(page, await page.locator('.script').evaluate(e => {
    const rect = e.getBoundingClientRect();
    const paper = e.closest('.paper').getBoundingClientRect();
    return { line: parseFloat(getComputedStyle(e).lineHeight), paperHeight: paper.height,
      ratio: (rect.top + rect.height / 2 - paper.top) / paper.height };
  }));
});

test.afterEach(async ({ page }, info) => {
  const evidence = browserEvidence.get(page);
  await info.attach('browser-evidence', { body: JSON.stringify(evidence), contentType: 'application/json' });
  expect(evidence.errors).toEqual([]);
  expect(evidence.consoleErrors).toEqual([]);
  expect(evidence.failedRequests).toEqual([]);
  expect(evidence.failedAssets).toEqual([]);
  expect(evidence.requests.every(request => request.method === 'GET')).toBe(true);
});

test('demo and trial active-line placement', async ({ page }, info) => {
  if (info.project.use.reducedMotion !== 'reduce') await page.clock.fastForward(TIMELINE.typeEnd + 250);
  const demo = demoGeometry.get(page);
  await capture(page, info, 'placement-demo');
  await enter(page);
  const states = {};
  for (const [state, text] of Object.entries({ empty: '', short: 'A fresh line.', cjk: '中文继续写。'.repeat(120) })) {
    if (text) await page.keyboard.insertText(text);
    states[state] = await assertZen(page);
    await capture(page, info, `placement-${state}`);
  }
  await info.attach('placement', { body: JSON.stringify({ demo, states }), contentType: 'application/json' });
  console.log(info.project.name, JSON.stringify({ demo, states }));
});

test('native zen input, deny, IME paths, warning, recovery and wipe', async ({ page }, info) => {
  await capture(page, info, 'landing');
  await enter(page);
  await capture(page, info, 'empty-focused');
  for (const file of ['input-regression.js', 'zen-regression.js']) {
    const source = await readFile(new URL(file, import.meta.url), 'utf8');
    const results = await page.evaluate(`(${source})()`);
    expect(results.every(result => result.pass)).toBe(true);
  }
  await page.locator('#restart').evaluate(button => button.click());
  const text = 'A private messy draft keeps moving. 中文继续写。👨‍👩‍👧‍👦\n'.repeat(60) + 'The active line';
  await page.keyboard.insertText(text);
  await assertZen(page);
  await capture(page, info, 'long-typing');
  const position = await editor(page).evaluate(e => e.scrollTop);
  await editor(page).hover();
  await page.mouse.wheel(0, -600);
  expect(await editor(page).evaluate(e => e.scrollTop)).toBe(position);
  // Playwright's clock controls session timers, not WAAPI's document timeline.
  // Freeze feedback in the native key event, before runner latency can consume it.
  await page.locator('.room-paper').evaluate(paper => {
    paper.getAnimations().forEach(a => a.finish());
    document.addEventListener('keydown', () => {
      paper.getAnimations().forEach(a => { a.pause(); a.currentTime = 230; });
    }, { once: true });
  });
  await page.keyboard.press('Backspace');
  await expect(editor(page)).toHaveValue(text);
  const feedback = await page.locator('.room-paper').evaluate(paper => paper.getAnimations().map(a => ({
    duration: a.effect.getTiming().duration, frames: a.effect.getKeyframes(),
  })));
  expect(feedback.length).toBeGreaterThan(0);
  expect(feedback.every(a => a.duration === 600)).toBe(true);
  const shake = feedback.find(a => a.frames.some(frame => frame.transform));
  if (info.project.use.reducedMotion === 'reduce') expect(shake).toBeUndefined();
  else {
    expect(shake.frames.some(frame => frame.transform === 'translateX(-4px)')).toBe(true);
    expect(shake.frames.at(-2).offset).toBe(.7);
    expect(shake.frames.at(-2).transform).toBe(shake.frames.at(-1).transform);
  }
  await page.locator('.room-paper').evaluate(paper => paper.getAnimations().forEach(a => { a.pause(); a.currentTime = 230; }));
  await capture(page, info, 'deny');
  for (const key of ['Delete', 'ControlOrMeta+x', 'ArrowUp', 'PageUp']) {
    await page.keyboard.press(key);
    await expect(editor(page)).toHaveValue(text);
  }
  await page.locator('.room-paper').evaluate(paper => paper.getAnimations().forEach(a => a.finish()));
  await page.clock.fastForward(5500);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'warn');
  await assertZen(page);
  await capture(page, info, 'warn');
  await page.keyboard.insertText(' Keep writing.');
  await expect(editor(page)).toHaveValue(text + ' Keep writing.');
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'typing');
  await assertZen(page);
  await capture(page, info, 'recovery');
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(editor(page)).toHaveValue('');
  await assertZen(page);
  await capture(page, info, 'wipe-report');
  await page.locator('#exit').click();
  await expect(page.locator('#landing .door')).toBeFocused();
  await capture(page, info, 'exit');
});

test('mocked sixty-second kept, copy and Escape', async ({ page, context }, info) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await enter(page);
  await page.keyboard.insertText('This draft survives. 中文继续写。\n');
  for (let second = 0; second < 57; second += 3) {
    await page.clock.fastForward(3000);
    await page.keyboard.insertText('Keep going. ');
  }
  await page.clock.fastForward(3000);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
  await capture(page, info, 'kept');
  await page.locator('#copy').click();
  await expect(page.locator('#copy')).toHaveText('COPIED');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(await page.locator('#kept-text').textContent());
  await capture(page, info, 'copied');
  await page.keyboard.press('Escape');
  await expect(page.locator('#room')).toBeHidden();
  await expect(page.locator('#landing .door')).toBeFocused();
  await capture(page, info, 'escape');
});

test('demo correction beat: visible rhythmic deletion, then retype', async ({ page }, info) => {
  test.skip(info.project.use.reducedMotion === 'reduce', 'reduced motion renders the static draft');
  expect(TIMELINE.typeEnd).toBeGreaterThan(16500); // the retired uniform pace ended at 15000
  const events = TIMELINE.events;
  const typo = events.find(event => event.kind === 'type' && event.cur.endsWith('promotoin'));
  const backs = events.filter(event => event.kind === 'back');
  const fixed = events.find(event => event.kind === 'type' && event.cur === 'i dont want the promotion');
  expect(backs).toHaveLength(3);
  let at = 0;
  const seek = async ms => { await page.clock.fastForward(ms - at); at = ms; };
  await seek(typo.t + 55); // a 50ms tick lands past the event, before the next one
  await expect(page.locator('#cur')).toHaveText('i dont want the promotoin');
  await capture(page, info, 'correction-typo');
  await seek(backs[1].t + 55);
  await expect(page.locator('#cur')).toHaveText(backs[1].cur);
  expect(backs[1].cur.length).toBe(typo.cur.length - 2);
  await capture(page, info, 'correction-deleting');
  await seek(fixed.t + 55);
  await expect(page.locator('#cur')).toHaveText('i dont want the promotion');
  await capture(page, info, 'correction-fixed');
});

test('historical demo sample without subtitles, centered report', async ({ page }, info) => {
  await expect(page.locator('#demo-key')).toHaveCount(0);
  const typeEnd = TIMELINE.typeEnd, SILENT = typeEnd + 5000, WARN = SILENT + 3000, CUT = WARN + 200;
  let at = 0;
  const seek = async ms => { await page.clock.fastForward(ms - at); at = ms; };
  if (info.project.use.reducedMotion !== 'reduce') await seek(typeEnd + 250);
  await expect(page.locator('#prev-1')).toHaveText('cant say this out loud but');
  // The demo corrects its typo on screen now, so the kept line shows the fix.
  await expect(page.locator('#prev-0')).toHaveText('i dont want the promotion');
  await expect(page.locator('#cur')).toHaveText('promotion. i want time off');
  await capture(page, info, 'demo-typing');
  if (info.project.use.reducedMotion === 'reduce') {
    await page.clock.fastForward(30000);
    await expect(page.locator('#clock')).toHaveText('1:00');
    await expect(page.locator('#cur')).toHaveText('promotion. i want time off');
    return;
  }
  await seek(SILENT + 150);
  await expect(page.locator('#paper')).toHaveClass('paper warn');
  await capture(page, info, 'demo-warn');
  await seek(WARN + 100);
  await expect(page.locator('#paper')).toHaveClass('paper cut');
  await capture(page, info, 'demo-cut');
  await seek(CUT + 300);
  await expect(page.locator('#report')).toContainText(`DRAFT WIPED - 0:${60 - Math.round(CUT / 1000)} UNUSED`);
  const centers = await page.evaluate(() => {
    const p = document.querySelector('#paper').getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(document.querySelector('#report'));
    const r = range.getBoundingClientRect();
    return { x: r.x + r.width / 2 - p.x - p.width / 2, y: r.y + r.height / 2 - p.y - p.height / 2 };
  });
  expect(Math.abs(centers.x)).toBeLessThan(2);
  expect(Math.abs(centers.y)).toBeLessThan(4);
  await capture(page, info, 'demo-report');
});
