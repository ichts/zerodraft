import { test, expect } from '@playwright/test';

// D-103, kept under D-119: the door is instant on a 2x screen too. The sheet's material is CSS (grain, cloud and the
// lamp's multiply), so the click generates no texture and there is nothing to warm while the visitor reads: the
// room's first letter never waits on a paint the click caused.
//
// Budget: the target is a room that takes the first letter within 100 ms of the click. The suite runs on shared,
// loaded hosts where a wall clock counts the seconds the OS spent running someone else, so the gates count the
// page's own main-thread CPU time (CDP `ThreadTime`): the editor is focused within 120 ms of CPU after the click
// and the click through the first letter costs under 250 ms of CPU. The canvas build froze the main thread for
// about 1200 ms on a 2x screen; the clean run costs about 70 ms.
test.use({ deviceScaleFactor: 2 });

const FOCUS_BUDGET_MS = 120;
const FIRST_LETTER_BUDGET_MS = 250;

test.beforeEach(async ({ page }) => {
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
});

test('the room takes the first letter within the budget, and the click paints nothing', async ({ page }) => {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Performance.enable', { timeDomain: 'threadTicks' });
  const cpuMs = async () => 1000 * (await cdp.send('Performance.getMetrics')).metrics.find(m => m.name === 'ThreadTime').value;
  const start = await cpuMs();
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.waitForFunction(() => document.activeElement?.id === 'editor');
  const focused = await cpuMs();
  await page.keyboard.type('a');
  await page.waitForTimeout(1500);
  const typed = await cpuMs();

  expect(await page.locator('#editor').inputValue(), 'the letter reached the editor').toBe('a');
  expect(focused - start, `main-thread CPU from click to editor focused (ms), budget ${FOCUS_BUDGET_MS}`).toBeLessThan(FOCUS_BUDGET_MS);
  expect(typed - start, `main-thread CPU from click to the first letter (ms), budget ${FIRST_LETTER_BUDGET_MS}`).toBeLessThan(FIRST_LETTER_BUDGET_MS);

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
