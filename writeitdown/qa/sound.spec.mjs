import { test, expect } from '@playwright/test';

// The landing demo's sound (Nib set): off until a click, quiet by default, silent in reduced motion, silent in the room.
// Web Audio is observed from outside by wrapping the browser's own start() and setTargetAtTime() before the page loads.
test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' });   // every project runs the same checks; the reduced-motion case sets its own
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.addInitScript(() => {
    window.__audio = { contexts: 0, starts: [], targets: [] };
    const Native = window.AudioContext;
    window.AudioContext = class extends Native { constructor(...a) { super(...a); window.__audio.contexts++; } };
    const start = AudioBufferSourceNode.prototype.start;
    AudioBufferSourceNode.prototype.start = function (...a) { window.__audio.starts.push(Math.round(this.buffer.duration * 1000)); return start.apply(this, a); };
    const target = AudioParam.prototype.setTargetAtTime;
    AudioParam.prototype.setTargetAtTime = function (v, ...a) { window.__audio.targets.push(v); return target.call(this, v, ...a); };
  });
});

const toggle = page => page.locator('[data-sound-toggle]');
const volume = page => page.locator('[data-sound-volume]');
const heard = page => page.evaluate(() => window.__audio.starts.slice());

async function soundOn(page) {
  await toggle(page).click();
  await expect(toggle(page)).toHaveAttribute('aria-pressed', 'true');
  await page.waitForFunction(() => window.__audio.targets.length > 0);
  await page.evaluate(() => { window.__audio.starts.length = 0; });
}

test('sound is off at load: no audio context, no slider, a labelled button', async ({ page }) => {
  await page.goto('./');
  await page.waitForTimeout(1500);
  expect(await page.evaluate(() => window.__audio.contexts)).toBe(0);
  await expect(toggle(page)).toHaveAttribute('aria-pressed', 'false');
  await expect(toggle(page)).toHaveAttribute('aria-label', 'Turn sound on');
  await expect(volume(page)).toBeHidden();
  expect(await heard(page)).toEqual([]);
});

test('a click turns sound on at the auditioned level, and the demo loop is heard: keys, 3-2-1, wipe', async ({ page }) => {
  await page.clock.install();
  await page.goto('./');
  await soundOn(page);
  await expect(toggle(page)).toHaveAttribute('aria-label', 'Turn sound off');
  expect(await page.evaluate(() => window.__audio.contexts)).toBe(1);
  await expect(volume(page)).toBeVisible();
  await expect(volume(page)).toHaveValue('40');
  expect((await page.evaluate(() => window.__audio.targets)).at(-1)).toBeCloseTo(0.16, 5);   // slider 40 = gain 0.16 = -15.9 dB
  await page.clock.runFor(24000);                                                             // one demo loop is 23.0 s
  const starts = await heard(page);
  expect(starts.filter(ms => ms === 1000)).toHaveLength(1);                                   // the wipe
  expect(starts.filter(ms => ms === 90)).toHaveLength(3);                                     // 3, 2, 1
  expect(starts.filter(ms => ms === 150).length).toBeGreaterThan(100);                        // the 115 typed keys
});

test('the volume slider sets the gain by the quadratic law, and Off silences the demo', async ({ page }) => {
  await page.clock.install();
  await page.goto('./');
  await soundOn(page);
  await volume(page).fill('100');
  expect((await page.evaluate(() => window.__audio.targets)).at(-1)).toBeCloseTo(1, 5);
  await volume(page).fill('0');
  expect((await page.evaluate(() => window.__audio.targets)).at(-1)).toBe(0);
  await toggle(page).click();
  await expect(toggle(page)).toHaveAttribute('aria-pressed', 'false');
  await expect(volume(page)).toBeHidden();
  await page.evaluate(() => { window.__audio.starts.length = 0; });
  await page.clock.runFor(24000);
  expect(await heard(page)).toEqual([]);
});

test('the button works from the keyboard', async ({ page }) => {
  await page.goto('./');
  await toggle(page).focus();
  await page.keyboard.press('Enter');
  await expect(toggle(page)).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Space');
  await expect(toggle(page)).toHaveAttribute('aria-pressed', 'false');
});

test('reduced motion: the demo is still and makes no sound even with sound on', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.clock.install();
  await page.goto('./');
  await soundOn(page);
  await page.clock.runFor(24000);
  expect(await heard(page)).toEqual([]);
});

test('the room is silent: typing in the trial plays nothing', async ({ page }) => {
  await page.clock.install();
  await page.goto('./');
  await soundOn(page);
  await page.locator('a[href="#trial"]').first().click();
  const editor = page.locator('#editor');
  await editor.waitFor({ state: 'visible' });
  await page.evaluate(() => { window.__audio.starts.length = 0; });
  await editor.focus();
  await page.keyboard.type('quiet room', { delay: 20 });
  await page.clock.runFor(10000);
  expect(await heard(page)).toEqual([]);
});

test('a hidden tab that resumes owes no burst of sound', async ({ page }) => {
  await page.clock.install();
  await page.goto('./');
  await soundOn(page);
  const before = (await heard(page)).length;   // on a loaded host real time passes first, so count only what the jump adds
  await page.clock.fastForward(8000);          // one long gap in a single step: the cue window is far past FRESH_MS
  expect((await heard(page)).length - before).toBeLessThan(3);
});

test('the sound is part of the landing only: no other shipped page loads it', async ({ request }) => {
  for (const file of ['room.js', 'feedback.js', 'session.mjs', 'status-slot.js', 'paper.js']) {
    const body = await (await request.get(file)).text();
    expect(body, file).not.toMatch(/sound(-cues)?\.m?js|landingSound|AudioContext/);
  }
});
