import { doorSettled } from './door.mjs';
// The sheet on the writeitdown site (D-124, values D-130): one flat warm-white tone in light and one flat charcoal tone in dark, with
// their ink, quiet chrome, grey wash and one red, measured on the rendered pixels as well as the computed styles.
//
// Fails on the grained charcoal sheet that dark shipped before D-124: the dark tone, the grey wash and the
// flatness of the rendered pixels are pinned to the black sheet.
import { test, expect } from '@playwright/test';

const TONES = { light: '#fcfcfa', dark: '#1c1c1a' };
const INK = { light: '#45433d', dark: '#dcdad3' };
const QUIET = { light: '#4b4943', dark: '#bdbbb3' };
const RED = { light: '#9a5255', dark: '#d08a8c' };
const WASH = { light: '#f4f3f0', dark: '#232321' };
const WASH_DEEP = { light: '#eae9e5', dark: '#2a2a27' };
const HISTORY = { light: [0.26, 0.084], dark: [0.172, 0.061] };

const parseColour = value => {
  const match = String(value).match(/rgba?\(([^)]+)\)/);
  if (!match) return null;
  const parts = match[1].split(/[,\s/]+/).filter(Boolean).map(Number);
  return { r: parts[0], g: parts[1], b: parts[2], a: parts.length > 3 ? parts[3] : 1 };
};

const luminance = ({ r, g, b }) => {
  const channel = value => {
    const c = value / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
};

const contrast = (a, b) => {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
};

const over = (colour, backdrop) => ({
  r: colour.r * colour.a + backdrop.r * (1 - colour.a),
  g: colour.g * colour.a + backdrop.g * (1 - colour.a),
  b: colour.b * colour.a + backdrop.b * (1 - colour.a),
  a: 1
});

const toHex = ({ r, g, b }) =>
  '#' + [r, g, b].map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');

const hexColour = hex => parseColour(`rgb(${[1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)).join(',')})`);

const theme = page => page.evaluate(() => document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light');
const style = (page, selector, property) =>
  page.evaluate(([sel, prop]) => getComputedStyle(document.querySelector(sel))[prop], [selector, property]);

/** The pixels the screen shows on a text-free strip of a sheet: a real screenshot, decoded in the page. */
async function strip(page, selector, where) {
  const box = await page.locator(selector).boundingBox();
  const clip = { x: Math.round(box.x + box.width * 0.3), y: Math.round(box.y + box.height * where), width: Math.round(box.width * 0.4), height: 12 };
  const png = (await page.screenshot({ clip, animations: 'disabled' })).toString('base64');
  return page.evaluate(async data => {
    const image = new Image();
    image.src = `data:image/png;base64,${data}`;
    await image.decode();
    const canvas = document.createElement('canvas');
    [canvas.width, canvas.height] = [image.width, image.height];
    const ctx = canvas.getContext('2d');
    ctx.drawImage(image, 0, 0);
    const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    const seen = new Set();
    for (let i = 0; i < pixels.length; i += 4) seen.add('#' + [0, 1, 2].map(c => pixels[i + c].toString(16).padStart(2, '0')).join(''));
    return [...seen];
  }, png);
}

/** A sheet is flat: the strip is one colour, the tone, and no texture canvas sits behind its words. */
async function expectFlat(page, selector, mode, label, where = 0.85) {
  expect(await page.locator(`${selector} canvas`).count(), `${label} carries no texture canvas`).toBe(0);
  expect(await strip(page, selector, where), `${label} is the flat ${mode} tone on screen`).toEqual([TONES[mode]]);
}

async function enterRoom(page) {
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await doorSettled(page);
  await expect(page.locator('#room')).toBeVisible();
}

test.describe('the sheet', () => {
  test.describe('on screen', () => {
    // The demo stands still under reduced motion, so its sheet is read without the scripted wash crossing it.
    test.use({ reducedMotion: 'reduce' });

    test('the demo sheet and the room are one flat tone with the locked ink', async ({ page }) => {
      await page.goto('./');
      const mode = await theme(page);
      expect(toHex(parseColour(await style(page, '#paper', 'backgroundColor')))).toBe(TONES[mode]);
      expect(toHex(parseColour(await style(page, '#paper .script', 'color')))).toBe(INK[mode]);
      await expectFlat(page, '#paper', mode, 'the demo sheet');

      await enterRoom(page);
      expect(toHex(parseColour(await style(page, '.room-paper', 'backgroundColor')))).toBe(TONES[mode]);
      expect(toHex(parseColour(await style(page, '#editor-ink', 'color')))).toBe(INK[mode]);
      await expectFlat(page, '.room-paper', mode, 'the room sheet', 0.7);
    });

    test('the sheet follows the theme on screen: white, black, white, after a reload and a resize', async ({ page }) => {
      await page.goto('./');
      const start = await theme(page);
      const other = start === 'light' ? 'dark' : 'light';
      const toggle = page.locator('#landing .home-nav [data-theme-toggle]');
      await expectFlat(page, '#paper', start, 'the demo sheet at load');
      await toggle.click();
      await expectFlat(page, '#paper', other, 'the demo sheet after one toggle');
      await toggle.click();
      await expectFlat(page, '#paper', start, 'the demo sheet after two toggles');
      await toggle.click();
      await page.reload();
      expect(await theme(page)).toBe(other);
      await expectFlat(page, '#paper', other, 'the demo sheet after a reload');
      await page.setViewportSize({ width: 1180, height: 760 });
      await expectFlat(page, '#paper', other, 'the demo sheet after a resize');
      await enterRoom(page);
      await expectFlat(page, '.room-paper', other, 'the room sheet after a resize', 0.7);
    });
  });

  test('every word on the sheet clears 7:1, except the dimmed history lines (D-092)', async ({ page }) => {
    await enterRoom(page);
    const mode = await theme(page);
    const paper = hexColour(TONES[mode]);
    const ink = parseColour(await style(page, '#editor-ink', 'color'));

    expect(toHex(ink)).toBe(INK[mode]);
    expect(contrast(ink, paper), 'the writing ink').toBeGreaterThanOrEqual(7);

    // The history (D-092): one back about 1.57:1 and two back about 1.15:1 on either sheet, so no 7:1 floor applies.
    const alphas = await page.evaluate(() => {
      const value = getComputedStyle(document.querySelector('#editor'));
      return [Number(value.getPropertyValue('--paper-history-1')), Number(value.getPropertyValue('--paper-history-2'))];
    });
    expect(alphas).toEqual(HISTORY[mode]);
    const ladder = alphas.map(alpha => contrast(over({ ...ink, a: alpha }, paper), paper));
    expect(ladder[0], `history step one: ${ladder[0].toFixed(2)}:1`).toBeGreaterThan(1.5);
    expect(ladder[0]).toBeLessThan(1.65);
    expect(ladder[1], `history step two: ${ladder[1].toFixed(2)}:1`).toBeGreaterThan(1.1);
    expect(ladder[1]).toBeLessThan(1.2);

    expect(toHex(parseColour(await style(page, '#room-count', 'color')))).toBe(QUIET[mode]);
    expect(contrast(parseColour(await style(page, '#room-count', 'color')), paper)).toBeGreaterThanOrEqual(7);
    expect(contrast(parseColour(await style(page, '#exit', 'color')), paper)).toBeGreaterThanOrEqual(7);
    // The exit confirmation is ink, not red (D-124).
    expect(toHex(parseColour(await style(page, '#exit-hint', 'color'))), 'the exit confirmation is ink').toBe(INK[mode]);
    expect(contrast(parseColour(await style(page, '#exit-hint', 'color')), paper)).toBeGreaterThanOrEqual(7);
    expect(toHex(parseColour(await style(page, '#failure-note', 'color')))).toBe(QUIET[mode]);
    expect(contrast(parseColour(await style(page, '#failure-note', 'color')), paper)).toBeGreaterThanOrEqual(7);
  });

  test('the warn wash greys the sheet one step, deeper at the cut, and the numeral is the one red (D-124)', async ({ page }) => {
    await enterRoom(page);
    const mode = await theme(page);
    const wash = await style(page, '.room-paper-wash', 'backgroundColor');
    expect(toHex(parseColour(wash)), 'the warn wash').toBe(WASH[mode]);

    // The attribute and the read happen in one evaluation: the room's own frame loop owns `data-cut`.
    const cut = await page.evaluate(() => {
      const room = document.querySelector('#room');
      room.dataset.cut = 'true';
      return getComputedStyle(document.querySelector('.room-paper-wash')).backgroundColor;
    });
    const deep = parseColour(cut);
    expect(toHex(deep), 'the wash at the cut').toBe(WASH_DEEP[mode]);
    const numeral = parseColour(await style(page, '.danger .numeral', 'color'));
    expect(toHex(numeral), 'the numeral is the one red').toBe(RED[mode]);
    // The numeral is large text (D-124), so its floor on the deepest wash is 3:1; the caption is ink at 7:1.
    expect(contrast(numeral, deep), 'the numeral on the deepest wash').toBeGreaterThanOrEqual(3);
    expect(contrast(parseColour(await style(page, '.danger .caption', 'color')), deep), 'the caption on the deepest wash').toBeGreaterThanOrEqual(7);
    expect(contrast(parseColour(await style(page, '#room-count', 'color')), deep), 'the quiet chrome on the deepest wash').toBeGreaterThanOrEqual(7);
    const paper = hexColour(TONES[mode]);
    const step = contrast(parseColour(wash), paper);
    expect(step, 'the wash is visible on the paper').toBeGreaterThan(1.05);
    expect(contrast(deep, paper), 'the cut is one step past the ramp').toBeGreaterThan(step);
  });

  test('the kept screen stays on the same paper', async ({ page }) => {
    // The real kept path: type through the whole minute on the fake clock, then read the paper.
    await page.clock.install({ time: new Date('2026-10-26T12:00:00Z') });
    await enterRoom(page);
    await page.locator('#editor').type('kept words on the paper ', { delay: 20 });
    for (let second = 0; second < 57; second += 3) {
      await page.clock.fastForward(3000);
      await page.locator('#editor').type('keep going ');
    }
    await page.clock.fastForward(3000);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
    const mode = await theme(page);
    const paper = parseColour(await style(page, '.room-paper', 'backgroundColor'));
    expect(toHex(paper), 'the kept sheet').toBe(TONES[mode]);
    expect(await page.locator('.room-paper canvas').count(), 'the kept sheet carries no texture canvas').toBe(0);
    expect(contrast(parseColour(await style(page, '#kept-text', 'color')), paper),
      'the kept draft on the paper').toBeGreaterThanOrEqual(7);
    expect(contrast(parseColour(await style(page, '#receipt', 'color')), paper),
      'the kept receipt on the paper').toBeGreaterThanOrEqual(7);
    // The not-saved caption is a text role on the sheet, so it answers to the same floor (D-061).
    expect(contrast(parseColour(await style(page, '#kept-note', 'color')), paper),
      'the kept not-saved caption on the paper').toBeGreaterThanOrEqual(7);
  });
});
