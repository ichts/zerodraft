import { test, expect } from '@playwright/test';

// D-103: the door is instant on a 2x screen too. The room's sheet is textured by a worker while the visitor
// reads the landing, so the click finds it painted: no 4 MP canvas is generated in the click's own task (that
// froze the page for about 1.2 s on a Retina Mac while the room was already visible, and the first letter waited).
//
// Budget: the target is a room that takes the first letter within 100 ms of the click. The suite runs on shared,
// loaded hosts where a wall clock counts the seconds the OS spent running someone else, so the gates count the
// page's own main-thread CPU time (CDP `ThreadTime`): the editor is focused within 120 ms of CPU after the click
// and the click through the first letter costs under 250 ms of CPU. The frozen build holds the main thread for
// about 1200 ms on a 2x screen. A click before the texture is ready waits for it without blocking (not asserted
// here; the visitor needs a moment to read the page).
test.use({ deviceScaleFactor: 2 });

const FOCUS_BUDGET_MS = 120;
const FIRST_LETTER_BUDGET_MS = 250;

test.beforeEach(async ({ page }) => {
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
});

const roomSheet = page => page.evaluate(() => {
  const info = window.WriteItDownPaper.paintInfo(document.querySelector('.room-paper'));
  return info && { width: info.width, height: info.height, at: info.at };
});

// Give the visitor the moment they need to read the page. A build that never textures the hidden room just times
// out here and fails on the click's own budgets below, which is the measurement that matters.
const textureReady = page => page.waitForFunction(() => window.WriteItDownPaper?.paintInfo(document.querySelector('.room-paper'))?.width > 2, null, { timeout: 8000 }).catch(() => {});

test('the room takes the first letter within the budget, and the click paints nothing', async ({ page }) => {
  await textureReady(page);
  const warmed = await roomSheet(page);

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

  const r = await page.evaluate(() => ({
    value: document.getElementById('editor').value,
    canvas: (c => ({ width: c.width, height: c.height }))(document.querySelector('.room-paper .sheet-paper')),
    css: (s => [s.clientWidth, s.clientHeight])(document.querySelector('.room-paper')), dpr: devicePixelRatio,
  }));
  expect(r.value, 'the letter reached the editor').toBe('a');
  expect(focused - start, `main-thread CPU from click to editor focused (ms), budget ${FOCUS_BUDGET_MS}`).toBeLessThan(FOCUS_BUDGET_MS);
  expect(typed - start, `main-thread CPU from click to the first letter (ms), budget ${FIRST_LETTER_BUDGET_MS}`).toBeLessThan(FIRST_LETTER_BUDGET_MS);

  // The sheet that was warmed is the sheet on screen: same pixels, same size, not painted again by the click.
  const after = await roomSheet(page);
  expect(warmed, 'the room sheet was textured before the click').not.toBeNull();
  expect(after.at, 'the click repainted the sheet').toBe(warmed.at);
  expect(r.canvas.width).toBe(Math.round(r.css[0] * r.dpr));
  expect(r.canvas.height).toBe(Math.round(r.css[1] * r.dpr));
});

test('warming a hidden room moves nothing the visitor can see, and follows a resize', async ({ page }) => {
  await textureReady(page);
  await page.evaluate(() => scrollTo(0, 240));
  const first = await roomSheet(page);
  expect(first, 'the room sheet was textured before the click').not.toBeNull();
  const before = await page.evaluate(() => ({ y: scrollY, landing: document.getElementById('landing').hidden, room: document.getElementById('room').hidden }));
  expect(before.y, 'the landing scrolls').toBeGreaterThan(0);

  await page.setViewportSize({ width: 1180, height: 760 });
  await page.waitForFunction(w => window.WriteItDownPaper.paintInfo(document.querySelector('.room-paper')).width !== w, first.width, { timeout: 15000 });
  const after = await page.evaluate(() => ({ y: scrollY, landing: document.getElementById('landing').hidden, room: document.getElementById('room').hidden, inTrial: document.documentElement.classList.contains('in-trial') }));
  expect(after).toEqual({ ...before, inTrial: false });

  // The resized, still hidden room was warmed for its new size, so the click finds it painted.
  const warmed = await roomSheet(page);
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.waitForTimeout(500);
  expect((await roomSheet(page)).at, 'the click after a resize repainted the sheet').toBe(warmed.at);
});
