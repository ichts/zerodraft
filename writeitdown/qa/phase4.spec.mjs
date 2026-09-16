import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';

const capture = (page, info, state) => page.screenshot({ path: info.outputPath(`${state}.png`) });
const editor = page => page.locator('#editor');
const browserEvidence = new WeakMap();

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
      centerOffset: activeCenter - (paper.top + paper.height / 2),
      visibleTextLines: [0, 1, 2, 3].filter(previous => activeCenter - previous * line > rect.top).length,
      pageHeight: document.documentElement.scrollHeight, viewportHeight: innerHeight,
      pageWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth,
    };
  });
  expect(Math.abs(geometry.height - geometry.line * 5)).toBeLessThan(1);
  expect(geometry.visibleTextLines).toBe(3);
  expect(Math.abs(geometry.centerOffset)).toBeLessThan(16);
  expect(geometry.bottomGap).toBeLessThan(2);
  expect(geometry.overflow).toBe('hidden');
  expect(geometry.scrollbar).toBe('none');
  // The current line occupies 40%-60% of the aperture: alpha 1 throughout.
  expect(geometry.mask).toContain('rgb(0, 0, 0) 40%');
  expect(geometry.mask).toContain('rgb(0, 0, 0) 60%');
  expect(geometry.mask).toContain('rgba(0, 0, 0, 0.07) 10%');
  expect(geometry.mask).toContain('rgba(0, 0, 0, 0.22) 30%');
  expect(geometry.pageHeight).toBe(geometry.viewportHeight);
  expect(geometry.pageWidth).toBe(geometry.viewportWidth);
}

test.beforeEach(async ({ page }) => {
  const evidence = { errors: [], requests: [], failedAssets: [] };
  browserEvidence.set(page, evidence);
  page.on('pageerror', error => evidence.errors.push(error.message));
  page.on('request', request => evidence.requests.push({ method: request.method(), url: request.url() }));
  page.on('response', response => {
    if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) evidence.failedAssets.push(response.url());
  });
  await page.clock.install({ time: new Date('2026-09-16T12:00:00Z') });
  await page.clock.pauseAt(new Date('2026-09-16T12:00:01Z'));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
});

test.afterEach(async ({ page }, info) => {
  const evidence = browserEvidence.get(page);
  await info.attach('browser-evidence', { body: JSON.stringify(evidence), contentType: 'application/json' });
  expect(evidence.errors).toEqual([]);
  expect(evidence.failedAssets).toEqual([]);
  expect(evidence.requests.every(request => request.method === 'GET')).toBe(true);
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
  for (const key of ['Backspace', 'Delete', 'ControlOrMeta+x', 'ArrowUp', 'PageUp']) {
    await page.keyboard.press(key);
    await expect(editor(page)).toHaveValue(text);
  }
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
  await page.clock.fastForward(5500);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'warn');
  await capture(page, info, 'warn');
  await page.keyboard.insertText(' Keep writing.');
  await expect(editor(page)).toHaveValue(text + ' Keep writing.');
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'typing');
  await assertZen(page);
  await capture(page, info, 'recovery');
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(editor(page)).toHaveValue('');
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

test('historical demo sample without subtitles, centered report', async ({ page }, info) => {
  await expect(page.locator('#demo-key')).toHaveCount(0);
  if (info.project.use.reducedMotion !== 'reduce') await page.clock.fastForward(15050);
  await expect(page.locator('#prev-1')).toHaveText('cant say this out loud but');
  await expect(page.locator('#prev-0')).toHaveText('i dont want the promotoin');
  await expect(page.locator('#cur')).toHaveText('promotion. i want time off');
  await capture(page, info, 'demo-typing');
  if (info.project.use.reducedMotion === 'reduce') {
    await page.clock.fastForward(25000);
    await expect(page.locator('#clock')).toHaveText('1:00');
    await expect(page.locator('#cur')).toHaveText('promotion. i want time off');
    return;
  }
  await page.clock.fastForward(5000);
  await expect(page.locator('#paper')).toHaveClass('paper warn');
  await capture(page, info, 'demo-warn');
  await page.clock.fastForward(3000);
  await expect(page.locator('#paper')).toHaveClass('paper cut');
  await capture(page, info, 'demo-cut');
  await page.clock.fastForward(200);
  await expect(page.locator('#report')).toContainText('DRAFT WIPED');
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
