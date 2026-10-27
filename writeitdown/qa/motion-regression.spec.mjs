import { test, expect } from '@playwright/test';
import { TIMELINE } from '../demo-timeline.mjs';

const loop = TIMELINE.typeEnd + 5000 + 3000 + 200 + 2000;

async function barAnchor(page, selector, clockSelector) {
  return page.locator(selector).evaluate((bar, clockSelector) => {
    const animation = bar.getAnimations()[0];
    const clock = document.querySelector(clockSelector).textContent.split(':').map(Number);
    return {
      fraction: Number(animation.effect.getKeyframes()[0].transform.match(/scaleX\(([^)]+)\)/)[1]),
      duration: animation.effect.getTiming().duration,
      seconds: clock[0] * 60 + clock[1],
    };
  }, clockSelector);
}

function expectAligned(anchor) {
  expect(anchor.fraction).toBeGreaterThan(0);
  expect(anchor.fraction).toBeLessThan(0.98);
  expect(Math.abs(anchor.fraction * 60 - anchor.seconds)).toBeLessThanOrEqual(1);
  expect(Math.abs(anchor.duration - anchor.fraction * 60000)).toBeLessThan(1);
}

test.beforeEach(async ({ page }) => {
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.clock.install({ time: new Date('2026-10-25T12:00:00Z') });
  await page.clock.pauseAt(new Date('2026-10-25T12:00:01Z'));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
});

test('demo moves each completed line one pitch without replacing existing history', async ({ page }, info) => {
  if (info.project.use.reducedMotion === 'reduce') {
    const history = await page.locator('.prev-stack').textContent();
    await page.clock.runFor(500);
    expect(await page.locator('.prev-stack').evaluate(stack => new DOMMatrixReadOnly(getComputedStyle(stack).transform).m42)).toBe(0);
    await expect(page.locator('.prev-stack')).toHaveText(history);
    await expect(page.locator('#clock')).toHaveText('1:00');
    return;
  }
  let at = 0;
  for (const event of TIMELINE.events.filter(event => event.kind === 'line')) {
    const target = Math.ceil(event.t / 50) * 50 + 32;
    await page.clock.runFor(target - at);
    const moving = await page.locator('.prev-stack').evaluate(stack => ({
      offset: new DOMMatrixReadOnly(getComputedStyle(stack).transform).m42,
      pitch: parseFloat(getComputedStyle(document.querySelector('.script')).lineHeight),
      text: stack.firstElementChild.textContent,
      retained: !window.previousLine || window.previousLine === stack.children[1],
    }));
    expect(moving.text).toBe(TIMELINE.events.filter(e => e.t < event.t).at(-1).cur);
    expect(moving.retained).toBe(true);
    expect(moving.offset).toBeGreaterThan(0);
    expect(moving.offset).toBeLessThan(moving.pitch);
    await page.clock.runFor(200);
    expect(await page.locator('.prev-stack').evaluate(stack => new DOMMatrixReadOnly(getComputedStyle(stack).transform).m42)).toBe(0);
    await page.evaluate(() => { window.previousLine = document.querySelector('#prev-0'); });
    at = target + 200;
  }
});

test('room bar reanchors to the deadline after motion preference changes', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.clock.runFor(50);
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.keyboard.insertText('Start');
  for (let i = 0; i < 10; i++) {
    await page.clock.fastForward(3000);
    await page.keyboard.insertText(' writing');
  }
  // Reduce Motion steps the bar on a 500 ms cadence, so the last tick's step is still pending
  // at the 30 s mark: let it land before the preference change, not after it.
  await page.clock.runFor(500);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.clock.runFor(50);
  await expect.poll(() => page.locator('#room-bar').evaluate(bar => bar.getAnimations().length)).toBe(0);
  const stepped = await page.locator('#room-bar').evaluate(bar => new DOMMatrixReadOnly(getComputedStyle(bar).transform).m11);
  expect(stepped).toBeCloseTo(0.5, 1);
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.clock.runFor(50);
  await expect.poll(() => page.locator('#room-bar').evaluate(bar => bar.getAnimations().length)).toBe(1);
  expectAligned(await barAnchor(page, '#room-bar', '#room-clock'));
});

test('room bar starts a fresh session full under Reduce Motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.clock.runFor(50);
  await page.locator('#landing .cta a[href="#trial"]').click();
  await expect(page.locator('#room')).toBeVisible();
  await expect(page.locator('#editor')).toBeFocused();
  await page.keyboard.insertText('Start');
  for (const ms of [500, 4900, 2000, 500, 100]) await page.clock.fastForward(ms);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  const scale = () => page.locator('#room-bar').evaluate(bar => Number(bar.style.transform.match(/scaleX\(([^)]+)\)/)[1]));
  expect(await scale()).toBe(0);
  await page.keyboard.insertText('A');
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'typing');
  expect(await scale()).toBeGreaterThan(0.99);
});

test('demo bar reanchors after hidden loops and motion preference changes', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.clock.runFor(50);
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.clock.fastForward(loop * 3 + 5000);
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await page.clock.runFor(50);
  expectAligned(await barAnchor(page, '#bar', '#clock'));
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.clock.runFor(50);
  await expect.poll(() => page.locator('#bar').evaluate(bar => bar.getAnimations().length)).toBe(0);
  await expect(page.locator('#clock')).toHaveText('1:00');
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.clock.runFor(50);
  await expect.poll(() => page.locator('#bar').evaluate(bar => bar.getAnimations().length)).toBe(1);
  expectAligned(await barAnchor(page, '#bar', '#clock'));
});

test('repeated refusals continue from the presented shake and hairline', async ({ page }, info) => {
  const reduced = info.project.use.reducedMotion === 'reduce';
  for (const [paper, hairline] of [['#paper', '#demo-hairline'], ['.room-paper', '#room-hairline']]) {
    if (paper === '.room-paper') await page.locator('#landing .cta a[href="#trial"]').click();
    const result = await page.evaluate(async ({ paper, hairline }) => {
      const { denyFeedback } = await import('./feedback.js');
      const sheet = document.querySelector(paper);
      const line = document.querySelector(hairline);
      denyFeedback(sheet, line);
      for (const target of [sheet, line]) {
        for (const animation of target.getAnimations()) { animation.pause(); animation.currentTime = 35; }
      }
      const before = { x: new DOMMatrixReadOnly(getComputedStyle(sheet).transform).m41,
        opacity: Number(getComputedStyle(line).opacity) };
      denyFeedback(sheet, line);
      const shake = sheet.getAnimations()[0];
      const flash = line.getAnimations()[0];
      if (shake) { shake.pause(); shake.currentTime = 0; }
      flash.pause(); flash.currentTime = 0;
      return { before, after: { x: new DOMMatrixReadOnly(getComputedStyle(sheet).transform).m41,
        opacity: Number(getComputedStyle(line).opacity) }, shakes: sheet.getAnimations().length,
        flashes: line.getAnimations().length };
    }, { paper, hairline });
    expect(result.before.opacity).toBeGreaterThan(0.5);
    expect(result.after.opacity).toBeCloseTo(result.before.opacity, 4);
    expect(result.flashes).toBe(1);
    expect(result.shakes).toBe(reduced ? 0 : 1);
    if (!reduced) expect(Math.abs(result.before.x)).toBeGreaterThan(0.1);
    expect(result.after.x).toBeCloseTo(result.before.x, 4);
  }
});
