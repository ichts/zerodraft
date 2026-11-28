import { test, expect } from '@playwright/test';

// D-103, D-124: the door is instant on a 2x screen. The sheet is one flat tone, so the click has nothing to paint:
// the room's first frame already shows the sheet in its tone, the editor is focused, and the first letter lands.
//
// Budget: the target is a room that takes the first letter within 100 ms of the click. The suite runs on shared,
// loaded hosts where a wall clock counts the seconds the OS spent running someone else, so the gates count the
// page's own main-thread CPU time (CDP `ThreadTime`): the editor is focused within 120 ms of CPU after the click
// and the click through the first letter costs under 250 ms of CPU.
test.use({ deviceScaleFactor: 2 });

const FOCUS_BUDGET_MS = 120;
const FIRST_LETTER_BUDGET_MS = 250;

test.beforeEach(async ({ page }) => {
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
});

test('the room shows its sheet on the first frame and takes the first letter within the budget', async ({ page }) => {
  // Record the room sheet's colour on the first animation frame after the room is shown.
  await page.evaluate(() => {
    const room = document.getElementById('room');
    new MutationObserver((_, observer) => {
      if (room.hidden) return;
      observer.disconnect();
      requestAnimationFrame(() => {
        const sheet = document.querySelector('.room-paper');
        window.__firstFrame = { colour: getComputedStyle(sheet).backgroundColor, tone: getComputedStyle(sheet).getPropertyValue('--paper-tone').trim(), canvases: sheet.querySelectorAll('canvas').length };
      });
    }).observe(room, { attributes: true, attributeFilter: ['hidden'] });
  });

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
  const first = await page.evaluate(() => window.__firstFrame);
  expect(first, 'the first frame was recorded').toBeTruthy();
  expect(first.canvases, 'nothing is painted on the sheet').toBe(0);
  const probe = await page.evaluate(tone => { const i = document.createElement('i'); i.style.color = tone; document.body.append(i); const c = getComputedStyle(i).color; i.remove(); return c; }, first.tone);
  expect(first.colour, 'the first frame shows the sheet in its tone').toBe(probe);
});
