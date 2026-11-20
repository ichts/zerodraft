import { doorSettled } from './door.mjs';
// The sheet in each paper mode (D-119): Lamp, Paper and Slate are one engine on three materials. The tokens are
// pinned per mode, and the 7:1 floor is measured in the rendered pixels, under the lamp's multiply, at the
// centre and the corners of the room, on the plain sheet, the wash and the deep wash.
//
// Fails on the canvas paper this replaced (D-069/D-093): there is no `.sheet-paper` canvas and no
// `WriteItDownPaper` renderer any more; the material is CSS, painted once by the browser.
import { test, expect } from '@playwright/test';

const SHEET = {
  lamp: { tone: '#e9e2ce', ink: '#1f1812', quiet: '#221a14', danger: '#380904', wash: '#e8cfbb', deep: '#e6bca7', history: [0.22, 0.07] },
  paper: { tone: '#fdfdfb', ink: '#1c1917', quiet: '#3f3b36', danger: '#63140b', wash: '#fae7e2', deep: '#f6d0c9', history: [0.22, 0.07] },
  slate: { tone: '#363b3d', ink: '#f7eedb', quiet: '#f4efe6', danger: '#ffe8de', wash: '#493e3d', deep: '#5a403d', history: [0.16, 0.05] },
};

const rgb = value => {
  const hex = String(value).match(/^#([0-9a-f]{6})$/i);
  if (hex) return [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16));
  return String(value).match(/[\d.]+/g).slice(0, 3).map(Number);
};
const toHex = c => '#' + rgb(c).map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
const lum = c => {
  const ch = v => { const x = v / 255; return x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4; };
  const [r, g, b] = rgb(c);
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
};
const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };

const mode = page => page.evaluate(() => document.documentElement.dataset.theme);
const style = (page, selector, property) =>
  page.evaluate(([s, p]) => getComputedStyle(document.querySelector(s))[p], [selector, property]);
const token = (page, selector, name) =>
  page.evaluate(([s, n]) => getComputedStyle(document.querySelector(s)).getPropertyValue(n).trim(), [selector, name]);

async function enterRoom(page) {
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', r => r.fulfill({ contentType: 'text/javascript', body: '' }));
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await doorSettled(page);
  await expect(page.locator('#room')).toBeVisible();
}

/** The rendered pixels of one patch: mean colour, the 2nd and 98th luminance percentiles, row and column means. */
async function pixels(page, clip) {
  const png = (await page.screenshot({ clip, animations: 'disabled', caret: 'hide' })).toString('base64');
  return page.evaluate(async data => {
    const bitmap = await createImageBitmap(await (await fetch('data:image/png;base64,' + data)).blob());
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(bitmap, 0, 0);
    const { data: px, width, height } = ctx.getImageData(0, 0, bitmap.width, bitmap.height);
    const l = [], mean = [0, 0, 0], rows = new Array(height).fill(0), cols = new Array(width).fill(0);
    let hash = 7;
    for (let y = 0; y < height; y += 1) for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const v = 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
      l.push([v, i]); rows[y] += v / width; cols[x] += v / height;
      for (let c = 0; c < 3; c += 1) mean[c] += px[i + c] / (width * height);
      hash = (hash * 31 + px[i] * 65536 + px[i + 1] * 256 + px[i + 2]) | 0;
    }
    l.sort((a, b) => a[0] - b[0]);
    const at = q => { const i = l[Math.floor(q * (l.length - 1))][1]; return [px[i], px[i + 1], px[i + 2]]; };
    const spread = a => { const m = a.reduce((s, v) => s + v, 0) / a.length; return Math.sqrt(a.reduce((s, v) => s + (v - m) ** 2, 0) / a.length); };
    return { mean, dark: at(0.02), light: at(0.98), rowSpread: spread(rows), colSpread: spread(cols), hash };
  }, png);
}

/** A text role as the reader sees it: its ink multiplied by the same light that shades the patch beneath it. */
const lit = (ink, patch, tone) => rgb(ink).map((v, i) => v * Math.min(1, patch.mean[i] / rgb(tone)[i]));

/** The text-free patches of the room: the centre under the writing line and the four corners inside the chrome. */
async function roomPatches(page) {
  const box = await page.locator('.room-paper').boundingBox();
  const s = 40;
  return {
    centre: { x: box.x + box.width / 2 - s / 2, y: box.y + box.height * 0.62, width: s, height: s },
    topLeft: { x: box.x + 8, y: box.y + 10, width: s, height: s },
    topRight: { x: box.x + box.width - 8 - s, y: box.y + 50, width: s, height: s },
    bottomLeft: { x: box.x + 8, y: box.y + box.height - 56 - s, width: s, height: s },
    bottomRight: { x: box.x + box.width - 8 - s, y: box.y + box.height - 56 - s, width: s, height: s },
  };
}

test.describe('the sheet', () => {
  test('each mode paints its locked sheet on the demo and in the room', async ({ page }) => {
    await page.goto('./');
    const m = await mode(page);
    const want = SHEET[m];
    for (const sel of ['#paper', '.room-paper', '.mo', '.vis-sheet', '.mac-card']) {
      expect(toHex(await token(page, sel, '--paper-tone')), `${sel} tone`).toBe(want.tone);
      expect(toHex(await style(page, sel, 'backgroundColor')), `${sel} paints the tone`).toBe(want.tone);
    }
    expect(toHex(await style(page, '#paper .script', 'color')), 'the demo writes in the sheet ink').toBe(want.ink);
    expect(toHex(await token(page, '#paper', '--paper-wash')), 'the wash').toBe(want.wash);
    expect(toHex(await token(page, '#paper', '--paper-wash-deep')), 'the deep wash').toBe(want.deep);
    await enterRoom(page);
    expect(toHex(await style(page, '#editor-ink', 'color')), 'the room writes in the sheet ink').toBe(want.ink);
    expect(toHex(await style(page, '#room-count', 'color')), 'the quiet role').toBe(want.quiet);
    expect(toHex(await style(page, '.danger .numeral', 'color')), 'the numeral').toBe(want.danger);
    const history = await page.evaluate(() => ['--paper-history-1', '--paper-history-2']
      .map(n => Number(getComputedStyle(document.querySelector('#editor')).getPropertyValue(n))));
    expect(history, 'the dimmed history steps (D-092)').toEqual(want.history);
    // There is no canvas paper and no renderer any more: the material is CSS.
    expect(await page.locator('.sheet-paper').count()).toBe(0);
    expect(await page.evaluate(() => 'WriteItDownPaper' in window)).toBe(false);
  });

  test('Paper is plain white: no grain, no cloud, no lamp', async ({ page }) => {
    await page.goto('./');
    test.skip((await mode(page)) !== 'paper', 'the plain sheet is the Paper mode');
    for (const sel of ['#paper', '.room-paper']) {
      expect(await style(page, sel, 'backgroundImage')).toMatch(/^none(, none)*$/);
      expect(await page.evaluate(s => getComputedStyle(document.querySelector(s), '::after').backgroundImage, sel)).toMatch(/^none(, none)*$/);
    }
  });

  test('every word in the room clears 7:1 in the rendered pixels, under the lamp, on the sheet and both washes', async ({ page }) => {
    await enterRoom(page);
    const want = SHEET[await mode(page)];
    const roles = {
      ink: await style(page, '#editor-ink', 'color'),
      quiet: await style(page, '#room-count', 'color'),
      danger: await style(page, '.danger .numeral', 'color'),
    };
    const fix = await page.addStyleTag({ content: '.room-paper-wash{opacity:1!important;transition:none!important}' });
    for (const wash of ['sheet', 'wash', 'deep']) {
      await page.evaluate(w => {
        const room = document.querySelector('#room');
        document.querySelector('.room-paper-wash').style.visibility = w === 'sheet' ? 'hidden' : 'visible';
        if (w === 'deep') room.dataset.cut = 'true'; else delete room.dataset.cut;
      }, wash);
      for (const [where, clip] of Object.entries(await roomPatches(page))) {
        const patch = await pixels(page, clip);
        for (const [role, ink] of Object.entries(roles)) {
          const seen = lit(ink, patch, want.tone);
          // The worst pixel for this ink: the darkest grain under dark ink, the brightest under light ink.
          const ground = lum(seen) < lum(patch.mean) ? patch.dark : patch.light;
          const ratio = contrast(seen, ground);
          expect.soft(ratio, `${role} on the ${wash} at the ${where}: ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(7);
        }
      }
    }
    await fix.evaluate(node => node.remove());
  });

  test('the demo words clear 7:1 under the demo lamp, on the sheet and the deep wash', async ({ page }) => {
    await page.route('https://static.cloudflareinsights.com/beacon.min.js', r => r.fulfill({ contentType: 'text/javascript', body: '' }));
    await page.clock.install({ time: new Date('2026-09-16T12:00:00Z') });
    await page.goto('./');
    const want = SHEET[await mode(page)];
    // Freeze the demo where it is: a fixed instant can already be in the past when a loaded host takes over a second
    // to load the page, and the measurement reads the ground at the column's edges, which no demo instant moves.
    await page.clock.pauseAt(await page.evaluate(() => Date.now() + 50));
    const box = await page.locator('#paper').boundingBox();
    const column = await page.locator('#paper .anchor-wrap').boundingBox();
    const s = 24;
    // The ground at both ends of the text column, on the writing line and down where the numeral and its caption
    // stand: the longest line reaches the column's edge, and the lamp is darkest away from its centre.
    const clips = {};
    for (const [name, fy] of [['line', 0.35], ['numeral', 0.6], ['caption', 0.85]]) {
      clips[`${name}Left`] = { x: column.x, y: box.y + box.height * fy - s / 2, width: s, height: s };
      clips[`${name}Right`] = { x: column.x + column.width - s, y: box.y + box.height * fy - s / 2, width: s, height: s };
    }
    const ink = await style(page, '#paper .script', 'color');
    const quiet = await token(page, '#paper', '--paper-quiet');
    const danger = await token(page, '#paper', '--paper-danger');
    await page.addStyleTag({ content: '#paper > *:not(#wash-paper){visibility:hidden!important}' });
    for (const wash of ['none', 'var(--paper-wash-deep)']) {
      await page.evaluate(w => { document.querySelector('#wash-paper').style.setProperty('background', w, 'important'); }, wash);
      for (const [where, clip] of Object.entries(clips)) {
        const patch = await pixels(page, clip);
        for (const [role, c] of Object.entries({ ink, quiet, danger })) {
          const seen = lit(c, patch, want.tone);
          const ground = lum(seen) < lum(patch.mean) ? patch.dark : patch.light;
          const ratio = contrast(seen, ground);
          expect.soft(ratio, `demo ${role} at ${where} on ${wash}: ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(7);
        }
      }
    }
  });

  test('the grain never moves while the writer types', async ({ page }) => {
    await enterRoom(page);
    const { topLeft } = await roomPatches(page);
    const before = await pixels(page, topLeft);
    await page.locator('#editor').pressSequentially('the rain is on the window and the room is quiet', { delay: 20 });
    const after = await pixels(page, topLeft);
    expect(after.hash, 'the sheet was repainted under the writer').toBe(before.hash);
  });

  test('the sheet texture keeps its own aspect on every sheet: no streak on a tall phone sheet (round 006)', async ({ page }) => {
    await enterRoom(page);
    test.skip((await mode(page)) === 'paper', 'the Paper sheet has no texture');
    // A streak is the cloud stretched along one axis. The grain tiles at its own 240 px, and the cloud scales by
    // one factor in both axes (cover), so neither can stretch whatever shape the sheet takes. Measured in pixels
    // the cloud is too slow to read, so the geometry is the assertion.
    const sizes = await page.evaluate(() => ['.room-paper', '#paper'].map(s => getComputedStyle(document.querySelector(s)).backgroundSize));
    expect(sizes[0]).toBe('240px 240px, cover');
    expect(sizes[1].split(',')[0].trim()).toBe('240px 240px');
  });

  test('the kept screen stays on the same paper, and its words clear 7:1 on it', async ({ page }) => {
    await page.clock.install({ time: new Date('2026-10-26T12:00:00Z') });
    await enterRoom(page);
    const want = SHEET[await mode(page)];
    await page.locator('#editor').pressSequentially('kept words on the paper ', { delay: 20 });
    for (let second = 0; second < 57; second += 3) {
      await page.clock.fastForward(3000);
      await page.locator('#editor').pressSequentially('keep going ');
    }
    await page.clock.fastForward(3000);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
    expect(toHex(await style(page, '.room-paper', 'backgroundColor'))).toBe(want.tone);
    for (const sel of ['#kept-text', '#receipt', '#kept-note'])
      expect(contrast(await style(page, sel, 'color'), want.tone), `${sel} on the paper`).toBeGreaterThanOrEqual(7);
  });
});
