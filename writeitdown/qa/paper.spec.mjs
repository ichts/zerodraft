// The Note paper on the writeitdown site (D-056): tone, grain and ink, measured rather than eyeballed,
// on the landing demo sheet and in the room, light and dark.
//
// Fails before the change: the sheet was #ffffff, the ink #1c1917 on a surface with no texture at all, the
// quiet chrome sat at 4.5:1, the pen red at 5.2:1, and the faded history lines at 1.2:1.
import { test, expect } from '@playwright/test';

const TONES = { light: '#dbe6ec', dark: '#21272a' };
const INK = { light: '#1c1917', dark: '#ece7d9' };
const QUIET = { light: '#464746', dark: '#b8b5ac' };
const DANGER = { light: '#63140b', dark: '#ffb4a2' };
const WASH = { light: '#ddd3d5', dark: '#352c2c' };
const WASH_DEEP = { light: '#ddc0be', dark: '#49302e' };

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

/** How warm a colour reads: red ahead of green. The Note sheet is slightly cool, so this is what "the
 *  paper turns red" means on a paper that is not white. */
const warmth = ({ r, g }) => (r - g) / 255;

const theme = page => page.evaluate(() => document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light');
const style = (page, selector, property) =>
  page.evaluate(([sel, prop]) => getComputedStyle(document.querySelector(sel))[prop], [selector, property]);

/** A text-free patch of a sheet, read straight off its canvas: spread (grain), distinct values, and a hash. */
async function patch(page, selector, where = 0.6) {
  return page.evaluate(([sel, position]) => {
    const canvas = document.querySelector(sel + ' .sheet-paper');
    if (!canvas) return null;
    const ctx = canvas.getContext('2d');
    const width = Math.max(8, Math.min(200, Math.round(canvas.width * 0.18)));
    const height = Math.max(8, Math.min(120, Math.round(canvas.height * 0.12)));
    const x = Math.round((canvas.width - width) / 2);
    const y = Math.round(canvas.height * position - height / 2);
    const data = ctx.getImageData(x, y, width, height).data;
    let sum = 0;
    let sumSquares = 0;
    let count = 0;
    let alpha = 0;
    const values = [];
    for (let i = 0; i < data.length; i += 4) {
      alpha += data[i + 3];
      const lum = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
      sum += lum;
      sumSquares += lum * lum;
      count += 1;
      values.push(data.slice(i, i + 4).join(','));
    }
    const mean = sum / count;
    return {
      spread: Math.sqrt(Math.max(0, sumSquares / count - mean * mean)),
      meanAlpha: alpha / count,
      distinct: new Set(values).size,
      hash: values.reduce((acc, value) => {
        for (let i = 0; i < value.length; i += 1) acc = (acc * 31 + value.charCodeAt(i)) | 0;
        return acc;
      }, 7)
    };
  }, [selector, where]);
}

async function enterRoom(page) {
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await expect(page.locator('#room')).toBeVisible();
  await waitForPaper(page, '.room-paper');
}

/** The sheet exists and carries its texture: the room is hidden at 0x0 until the reveal, and the
 *  ResizeObserver textures it in the same rendering step that gives it its size. */
async function waitForPaper(page, selector) {
  await page.waitForFunction(sel => {
    const element = document.querySelector(sel);
    const info = element && window.WriteItDownPaper.paintInfo(element);
    if (!info || !(info.width > 2)) return false;
    const canvas = element.querySelector('.sheet-paper');
    const data = canvas.getContext('2d').getImageData(1, 1, 4, 4).data;
    return data.some(value => value !== 0);
  }, selector);
}

test.describe('the sheet', () => {
  test('the demo sheet and the room carry the locked tone, ink and grain', async ({ page }) => {
    await page.goto('./');
    const mode = await theme(page);
    const paper = parseColour(await style(page, '#paper', 'backgroundColor'));
    expect(toHex(paper)).toBe(TONES[mode]);

    // The words on the demo sheet are the locked ink.
    expect(toHex(parseColour(await style(page, '#paper .script', 'color')))).toBe(INK[mode]);

    await waitForPaper(page, '#paper');
    const demoGrain = await patch(page, '#paper', 0.75);
    expect(demoGrain.spread, 'the demo sheet carries grain').toBeGreaterThan(2);
    expect(demoGrain.distinct).toBeGreaterThan(40);

    await enterRoom(page);
    expect(toHex(parseColour(await style(page, '.room-paper', 'backgroundColor')))).toBe(TONES[mode]);
    expect(toHex(parseColour(await style(page, '#editor', 'color')))).toBe(INK[mode]);

    // The texture is device-exact: one canvas pixel per device pixel, so it cannot shimmer.
    const exact = await page.evaluate(() => {
      const canvas = document.querySelector('.room-paper .sheet-paper');
      const sheet = document.querySelector('.room-paper');
      return { width: canvas.width, height: canvas.height,
        css: [sheet.clientWidth, sheet.clientHeight], dpr: window.devicePixelRatio };
    });
    expect(exact.width).toBe(Math.round(exact.css[0] * exact.dpr));
    expect(exact.height).toBe(Math.round(exact.css[1] * exact.dpr));
  });

  test('every word on the sheet clears 7:1, including the faded history lines', async ({ page }) => {
    await enterRoom(page);
    const mode = await theme(page);
    const paper = parseColour(await style(page, '.room-paper', 'backgroundColor'));
    const ink = parseColour(await style(page, '#editor', 'color'));

    expect(toHex(ink)).toBe(INK[mode]);
    expect(contrast(ink, paper), 'the writing ink').toBeGreaterThanOrEqual(7);

    // The history ladder: the alphas the mask applies, composited over the paper.
    const alphas = await page.evaluate(() => {
      const editor = document.querySelector('#editor');
      const value = getComputedStyle(editor);
      return [
        Number(value.getPropertyValue('--paper-history-1')),
        Number(value.getPropertyValue('--paper-history-2'))
      ];
    });
    expect(alphas[0]).toBeGreaterThan(0);
    expect(alphas[1]).toBeGreaterThan(0);
    const ladder = alphas.map(alpha => contrast(over({ ...ink, a: alpha }, paper), paper));
    expect(ladder[0], `history step one: ${ladder[0].toFixed(2)}:1`).toBeGreaterThanOrEqual(9);
    expect(ladder[1], `history step two: ${ladder[1].toFixed(2)}:1`).toBeGreaterThanOrEqual(7);

    // The quiet chrome and the pen red on the sheet.
    expect(toHex(parseColour(await style(page, '#room-count', 'color')))).toBe(QUIET[mode]);
    expect(contrast(parseColour(await style(page, '#room-count', 'color')), paper)).toBeGreaterThanOrEqual(7);
    expect(contrast(parseColour(await style(page, '#exit', 'color')), paper)).toBeGreaterThanOrEqual(7);
    expect(toHex(parseColour(await style(page, '#room-report', 'color')))).toBe(DANGER[mode]);
    expect(contrast(parseColour(await style(page, '#room-report', 'color')), paper)).toBeGreaterThanOrEqual(7);
  });

  test('the grain never moves while the writer types', async ({ page }) => {
    await enterRoom(page);
    const before = await patch(page, '.room-paper', 0.75);
    expect(before.spread).toBeGreaterThan(2);
    await page.locator('#editor').type('the rain is on the window and the room is quiet', { delay: 20 });
    const after = await patch(page, '.room-paper', 0.75);
    expect(after.hash, 'the grain was regenerated under the writer').toBe(before.hash);
    expect(after.spread).toBe(before.spread);
  });

  test('the warn wash is the sheet own mix, not a pale tint meant for white', async ({ page }) => {
    await enterRoom(page);
    const mode = await theme(page);
    const wash = await style(page, '.room-paper-wash', 'backgroundColor');
    expect(toHex(parseColour(wash)), 'the warn wash').toBe(WASH[mode]);

    // The cut steps one step deeper, and the numeral sitting on it still clears 7:1. The attribute and
    // the read happen in one evaluation: the room's own frame loop owns `data-cut`.
    const cut = await page.evaluate(() => {
      const room = document.querySelector('#room');
      room.dataset.cut = 'true';
      return getComputedStyle(document.querySelector('.room-paper-wash')).backgroundColor;
    });
    const deep = parseColour(cut);
    expect(toHex(deep), 'the wash at the cut').toBe(WASH_DEEP[mode]);
    const numeral = parseColour(await style(page, '.danger .numeral', 'color'));
    expect(contrast(numeral, deep), 'the numeral on the deepest wash').toBeGreaterThanOrEqual(7);
    // The wash is a tint of the sheet: warmer than the paper and warmer still at the cut.
    const paper = parseColour(await style(page, '.room-paper', 'backgroundColor'));
    expect(warmth(parseColour(wash)) - warmth(paper), 'the wash does not warm the paper').toBeGreaterThan(0.05);
    expect(warmth(deep), 'the cut is not deeper than the ramp').toBeGreaterThan(warmth(parseColour(wash)));
  });

  test('the kept screen stays on the same paper', async ({ page }) => {
    // The real kept path: type through the whole minute on the fake clock, then read the paper.
    await page.clock.install({ time: new Date('2026-10-26T12:00:00Z') });
    await enterRoom(page);
    await page.locator('#editor').type('kept words on the note paper ', { delay: 20 });
    for (let second = 0; second < 57; second += 3) {
      await page.clock.fastForward(3000);
      await page.locator('#editor').type('keep going ');
    }
    await page.clock.fastForward(3000);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
    const paper = parseColour(await style(page, '.room-paper', 'backgroundColor'));
    expect(toHex(paper)).toBe(TONES[await theme(page)]);
    const grain = await patch(page, '.room-paper', 0.5);
    expect(grain.spread, 'the kept sheet carries the grain').toBeGreaterThan(2);
    expect(contrast(parseColour(await style(page, '#kept-text', 'color')), paper),
      'the kept draft on the paper').toBeGreaterThanOrEqual(7);
    expect(contrast(parseColour(await style(page, '#receipt', 'color')), paper),
      'the kept receipt on the paper').toBeGreaterThanOrEqual(7);
    // The not-saved caption is a text role on the sheet, so it answers to the same floor (D-061).
    expect(contrast(parseColour(await style(page, '#kept-note', 'color')), paper),
      'the kept not-saved caption on the paper').toBeGreaterThanOrEqual(7);
  });
});
