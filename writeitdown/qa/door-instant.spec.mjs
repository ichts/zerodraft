import { test, expect } from '@playwright/test';

// D-103, kept under D-119: the door is instant on a 2x screen too. The sheet's material is CSS (grain, cloud and the
// lamp's multiply), so the click generates no texture and there is nothing to warm while the visitor reads: the
// room's first letter never waits on a paint the click caused.
//
// Budget: the target is a room that takes the first letter within 100 ms of the click. The suite runs on shared,
// loaded hosts, so the gates carry margin: the editor is focused within 250 ms of the click and no main-thread task
// after the click runs longer than 150 ms (a key typed into a busy page waits for it). The canvas build froze the
// main thread for about 1200 ms on a 2x screen.
test.use({ deviceScaleFactor: 2 });

const FOCUS_BUDGET_MS = 250;
const LONG_TASK_BUDGET_MS = 150;

test.beforeEach(async ({ page }) => {
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.addInitScript(() => {
    window.__long = [];
    new PerformanceObserver(list => list.getEntries().forEach(e => window.__long.push({ start: e.startTime, duration: e.duration })))
      .observe({ type: 'longtask', buffered: true });
  });
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
});

test('the room takes the first letter within the budget, and the click paints nothing', async ({ page }) => {
  await page.evaluate(() => {
    document.addEventListener('click', e => { window.__click = e.timeStamp; }, { capture: true, once: true });
    const editor = document.getElementById('editor');
    editor.addEventListener('focus', e => { window.__focus = e.timeStamp; }, { once: true });
  });
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.waitForFunction(() => document.activeElement?.id === 'editor');
  await page.keyboard.type('a');
  await page.waitForTimeout(1500);

  const r = await page.evaluate(() => ({
    click: window.__click, focus: window.__focus, value: document.getElementById('editor').value,
    long: window.__long.filter(t => t.start + t.duration > window.__click).map(t => t.duration),
  }));
  expect(r.value, 'the letter reached the editor').toBe('a');
  expect(r.focus - r.click, `click to editor focused (ms), budget ${FOCUS_BUDGET_MS}`).toBeLessThan(FOCUS_BUDGET_MS);
  expect(Math.max(0, ...r.long), `longest main-thread task after the click (ms), budget ${LONG_TASK_BUDGET_MS}`).toBeLessThan(LONG_TASK_BUDGET_MS);

  // The material is CSS: no canvas, no renderer, no texture generated for the click.
  expect(await page.locator('.sheet-paper').count()).toBe(0);
});

test('a resize while the room is hidden moves nothing the visitor can see', async ({ page }) => {
  await page.evaluate(() => scrollTo(0, 240));
  const before = await page.evaluate(() => ({ y: scrollY, landing: document.getElementById('landing').hidden, room: document.getElementById('room').hidden }));
  expect(before.y, 'the landing scrolls').toBeGreaterThan(0);
  await page.setViewportSize({ width: 1180, height: 760 });
  await page.waitForTimeout(300);
  const after = await page.evaluate(() => ({ y: scrollY, landing: document.getElementById('landing').hidden, room: document.getElementById('room').hidden, inTrial: document.documentElement.classList.contains('in-trial') }));
  expect(after).toEqual({ ...before, inTrial: false });
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.waitForFunction(() => document.activeElement?.id === 'editor');
  const box = await page.locator('.room-paper').boundingBox();
  expect(box.width, 'the room sheet fits the new width').toBeLessThanOrEqual(1180);
});
