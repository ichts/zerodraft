// D-076: the room's history fades per logical line, and the first refused delete of a session says why.
//
// Fade: every row of one sentence shares one measured opacity (the ink layer's span, read from the computed
// style and from the pixels), the ladder is D-069's and every step clears 7:1 on the Wheat sheet in both
// themes, and the aperture is a hard clip, so a partial line is cut at its edge and never given an alpha.
// Refusal: the 200 ms shake stays on every refusal; the first refused delete of a session also names the
// rule in the footer's status slot for two seconds, and nothing else moves.
import { test, expect } from '@playwright/test';

const TONES = { light: '#e9e2ce', dark: '#342e24' };
const QUIET = { light: '#464746', dark: '#c2bfb7' };
const REFUSAL = 'FORWARD ONLY. DELETING IS BLOCKED.';

const rgb = value => String(value).match(/[\d.]+/g).slice(0, 3).map(Number);
const lum = ([r, g, b]) => [r, g, b].map(v => { const c = v / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; })
  .reduce((sum, c, i) => sum + c * [0.2126, 0.7152, 0.0722][i], 0);
const contrast = (a, b) => { const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x); return (hi + 0.05) / (lo + 0.05); };
const hex = value => [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16));
const over = (ink, alpha, paper) => ink.map((v, i) => v * alpha + paper[i] * (1 - alpha));

async function enter(page) {
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await expect(page.locator('#editor')).toBeFocused();
}

const theme = page => page.evaluate(() => document.documentElement.dataset.theme || 'light');

/** One span per logical line: its rung, its computed opacity and the rows it occupies, top to bottom. */
const inkLines = page => page.evaluate(() => {
  const ink = document.querySelector('#editor-ink');
  const pitch = parseFloat(getComputedStyle(ink).lineHeight);
  const top = ink.getBoundingClientRect().top;
  return [...ink.querySelectorAll('[data-rung]')].map(span => {
    const range = document.createRange();
    range.selectNodeContents(span);
    const rows = [...new Set([...range.getClientRects()].filter(rect => rect.width > 1).map(rect => Math.round((rect.top - top) / pitch * 100) / 100))];
    return { text: span.textContent, rung: span.dataset.rung, opacity: Number(getComputedStyle(span).opacity), rows };
  });
});

/** How deep the ink reads in a horizontal band of the sheet, off the pixels: the mean of the 200 pixels
 *  furthest from the paper's own tone, so the glyph cores are compared and how much text a row holds does
 *  not move the number. */
async function inkDepth(page, band) {
  const png = (await page.screenshot({ clip: band })).toString('base64');
  return page.evaluate(async ([data, paperTone]) => {
    const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${data}`)).blob());
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    context.drawImage(bitmap, 0, 0);
    const pixels = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
    const paper = (0.2126 * paperTone[0] + 0.7152 * paperTone[1] + 0.0722 * paperTone[2]);
    const gaps = [];
    for (let i = 0; i < pixels.length; i += 4) gaps.push(Math.abs(0.2126 * pixels[i] + 0.7152 * pixels[i + 1] + 0.0722 * pixels[i + 2] - paper));
    gaps.sort((a, b) => b - a);
    const take = Math.min(200, gaps.length);
    return gaps.slice(0, take).reduce((sum, gap) => sum + gap, 0) / take;
  }, [png, band.tone]);
}

const rowBand = async (page, row, tone) => {
  const box = await page.locator('.editor-stack').boundingBox();
  const pitch = await page.locator('#editor-ink').evaluate(e => parseFloat(getComputedStyle(e).lineHeight));
  const inset = pitch * 0.12;
  return { x: box.x, y: box.y + row * pitch + inset, width: box.width, height: pitch - 2 * inset, tone };
};

test('every row of one logical line carries one opacity, measured in the DOM and in the pixels', async ({ page }) => {
  await enter(page);
  const mode = await theme(page);
  const tone = hex(TONES[mode]);
  const words = Array.from({ length: 40 }, () => 'mmmm').join(' ');
  await page.keyboard.insertText(`${words}.\nmmmm mmmm`);
  await page.waitForTimeout(450);

  const lines = await inkLines(page);
  const long = lines[0];
  expect(long.rung, 'the line above the live one is rung 1').toBe('1');
  expect(long.rows.length, `the long line wraps to several rows: ${JSON.stringify(long.rows)}`).toBeGreaterThanOrEqual(2);
  const token = await page.evaluate(() => Number(getComputedStyle(document.querySelector('#editor-ink')).getPropertyValue('--paper-history-1')));
  expect(long.opacity, 'one measured opacity for every row of the sentence').toBeCloseTo(token, 3);
  expect(lines.at(-1).opacity).toBe(1);

  // The two rows that sit in the aperture above the live row read the same in the pixels, and lighter than it.
  const last = lines.length - 1;
  const live = lines[last].rows[0];
  const upper = [live - 2, live - 1];
  const depths = [];
  for (const row of upper) depths.push(await inkDepth(page, await rowBand(page, row, tone)));
  const liveDepth = await inkDepth(page, await rowBand(page, live, tone));
  expect(Math.abs(depths[0] - depths[1]), `rows of one line: ${depths.map(d => d.toFixed(1))}`).toBeLessThan(6);
  expect(liveDepth - depths[0], `live ${liveDepth.toFixed(1)} against history ${depths[0].toFixed(1)}`).toBeGreaterThan(10);
});

test('the ladder is D-069 per theme, each step clears 7:1, and older lines are gone', async ({ page }) => {
  await enter(page);
  const mode = await theme(page);
  await page.keyboard.insertText('Oldest line.\nThree back.\nTwo back.\nOne back.\nLive');
  await page.waitForTimeout(450);
  const lines = await inkLines(page);
  expect(lines.map(line => line.rung)).toEqual(['3', '3', '2', '1', '0']);
  const tokens = await page.evaluate(() => {
    const style = getComputedStyle(document.querySelector('#editor-ink'));
    return [1, 2].map(n => Number(style.getPropertyValue(`--paper-history-${n}`)));
  });
  expect(tokens).toEqual(mode === 'dark' ? [0.902, 0.772] : [0.847, 0.769]);
  const byRung = Object.fromEntries(lines.map(line => [line.rung, line.opacity]));
  expect(byRung['0']).toBe(1);
  expect(byRung['1']).toBeCloseTo(tokens[0], 3);
  expect(byRung['2']).toBeCloseTo(tokens[1], 3);
  expect(byRung['3']).toBe(0);
  const ink = rgb(await page.evaluate(() => getComputedStyle(document.querySelector('#editor-ink')).color));
  const paper = hex(TONES[mode]);
  for (const alpha of [1, ...tokens]) {
    const ratio = contrast(over(ink, alpha, paper), paper);
    expect(ratio, `alpha ${alpha}: ${ratio.toFixed(2)}:1`).toBeGreaterThanOrEqual(7);
  }
});

test('a sentence that ends mid-row keeps one rung on each side, and each is cut at the sentence', async ({ page }) => {
  await enter(page);
  await page.keyboard.insertText('One short sentence. And another one follows it. Third');
  await page.waitForTimeout(450);
  const lines = await inkLines(page);
  expect(lines.map(line => line.text.trim())).toEqual(['One short sentence.', 'And another one follows it.', 'Third']);
  expect(lines.map(line => line.rung)).toEqual(['2', '1', '0']);
});

test('the aperture clips a partial line at its edge and never fades it', async ({ page }) => {
  await enter(page);
  const mode = await theme(page);
  const tone = hex(TONES[mode]);
  await page.keyboard.insertText('Above.\nLive line here');
  await page.waitForTimeout(450);
  const geometry = await page.evaluate(() => {
    const stack = document.querySelector('.editor-stack');
    const ink = document.querySelector('#editor-ink');
    const style = getComputedStyle(stack);
    return { pitch: parseFloat(getComputedStyle(ink).lineHeight), mask: style.maskImage || style.webkitMaskImage };
  });
  expect(geometry.mask, 'a hard cut: both stops at the same pitch, no gradient between them').toMatch(/rgb\(0, 0, 0\) ([\d.]+)px, rgba\(0, 0, 0, 0\) \1px/);
  // Push the live row half a pitch under the aperture's lower edge, the way the one-pitch shift does mid-animation.
  await page.evaluate(() => { const ink = document.querySelector('#editor-ink'); ink.scrollTop -= parseFloat(getComputedStyle(ink).lineHeight) / 2; });
  const box = await page.locator('.editor-stack').boundingBox();
  const blank = await inkDepth(page, { x: box.x, y: box.y + box.height + geometry.pitch, width: box.width, height: 0.9 * geometry.pitch, tone });
  const inside = await inkDepth(page, { x: box.x, y: box.y + 2.55 * geometry.pitch, width: box.width, height: 0.4 * geometry.pitch, tone });
  const below = await inkDepth(page, { x: box.x, y: box.y + 3.05 * geometry.pitch, width: box.width, height: 0.9 * geometry.pitch, tone });
  expect(inside - blank, 'the visible half of the partial line carries ink').toBeGreaterThan(40);
  expect(below - blank, `nothing is drawn under the edge: ${below.toFixed(1)} against bare paper ${blank.toFixed(1)}`).toBeLessThan(8);
  const rung = await page.evaluate(() => getComputedStyle(document.querySelector('#editor-ink [data-rung="0"]')).opacity);
  expect(Number(rung), 'the partial line keeps its own rung, not an edge alpha').toBe(1);
});

// --- Refusal --------------------------------------------------------------------------------------------

const frames = page => page.evaluate(() => Object.fromEntries(['#exit', '#room-count', '#room-clock', '.room-paper', '.editor-stack', '#editor-ink']
  .map(selector => { const r = document.querySelector(selector).getBoundingClientRect(); return [selector, [r.x, r.y, r.width, r.height].map(v => Math.round(v * 100) / 100)]; })));
const slotText = page => page.locator('#exit-hint').textContent();
// The paper's shake and its red hairline are both animations under the paper; Reduce Motion keeps the hairline alone.
const shakes = page => page.evaluate(() => document.querySelector('.room-paper').getAnimations({ subtree: true }).length);

test('the first refused delete names the rule for two seconds; later refusals only shake; a new session resets it', async ({ page }, info) => {
  await enter(page);
  const mode = await theme(page);
  await page.keyboard.insertText('Some words');
  expect(await slotText(page), 'the slot is empty before any refusal').toBe('');
  const before = await frames(page);

  await page.keyboard.press('Backspace');
  const shownAt = Date.now();
  await expect(page.locator('#exit-hint')).toHaveText(REFUSAL);
  expect(await shakes(page), 'the 200 ms shake still runs on the first refusal').toBeGreaterThan(0);
  await page.waitForTimeout(300);
  await page.screenshot({ path: info.outputPath('refusal-first.png') });
  const during = await frames(page);
  expect(during, 'nothing else moves while the notice shows').toEqual(before);

  // The status text is the quiet role: 4.5:1 on the sheet at the least, 7:1 in fact.
  const colour = await page.locator('#exit-hint').evaluate(e => getComputedStyle(e).color);
  expect(rgb(colour)).toEqual(hex(QUIET[mode]));
  expect(contrast(rgb(colour), hex(TONES[mode]))).toBeGreaterThanOrEqual(4.5);

  // A second refusal inside the window restarts nothing and says nothing new.
  await page.keyboard.press('Delete');
  expect(await slotText(page)).toBe(REFUSAL);

  await page.waitForTimeout(Math.max(0, 1800 - (Date.now() - shownAt)));
  expect(await slotText(page), 'still showing just before two seconds').toBe(REFUSAL);
  await expect(page.locator('#exit-hint')).toHaveText('', { timeout: 1200 });
  const elapsed = Date.now() - shownAt;
  expect(elapsed, `the notice lasted ${elapsed} ms`).toBeGreaterThanOrEqual(1950);
  expect(elapsed).toBeLessThan(2600);
  expect(await frames(page), 'the slot returns with no layout shift').toEqual(before);

  // Later refusals in the same session shake only.
  await page.keyboard.press('Backspace');
  expect(await shakes(page), 'a later refusal still shakes').toBeGreaterThan(0);
  expect(await slotText(page), 'a later refusal says nothing in the slot').toBe('');
  await page.keyboard.insertText(' more');

  // A session that ends starts the next one clean: stop typing until the draft is wiped, then refuse again.
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe', { timeout: 9000 });
  await page.keyboard.insertText('Fresh');
  await page.keyboard.press('Backspace');
  await expect(page.locator('#exit-hint')).toHaveText(REFUSAL);
});

test('only a delete earns the notice, and an armed exit confirmation keeps the slot', async ({ page }) => {
  await enter(page);
  await page.keyboard.insertText('Words');
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('Control+z');
  expect(await slotText(page), 'caret moves and undo only shake').toBe('');
  const hint = await page.locator('#exit-hint').getAttribute('data-hint');
  await page.keyboard.press('Escape');
  await expect(page.locator('#exit-hint')).toHaveText(hint);
  await page.keyboard.press('Backspace');
  expect(await slotText(page), 'the pending confirmation is not displaced').toBe(hint);
  expect(await shakes(page), 'the refusal still shakes').toBeGreaterThan(0);
  await page.keyboard.insertText(' typed');
  await expect(page.locator('#exit-hint')).toHaveText('');
  await page.keyboard.press('Backspace');
  await expect(page.locator('#exit-hint'), 'the notice was not spent while the confirmation held the slot').toHaveText(REFUSAL);
});

test('a composition is drawn by the ink layer with its underline, and commits into the history', async ({ page }) => {
  await enter(page);
  await page.keyboard.insertText('Before. ');
  const session = await page.context().newCDPSession(page);
  await session.send('Input.imeSetComposition', { text: 'ni', selectionStart: 2, selectionEnd: 2 });
  const composing = await page.evaluate(() => {
    const span = document.querySelector('#editor-ink .composing');
    return span && { text: span.textContent, underline: getComputedStyle(span).textDecorationLine, rung: span.dataset.rung };
  });
  expect(composing, 'the composing text is on the ink layer').toEqual({ text: 'ni', underline: 'underline', rung: '0' });
  await session.send('Input.insertText', { text: '你' });
  await page.waitForTimeout(100);
  expect(await page.locator('#editor').inputValue()).toContain('你');
  expect(await page.locator('#editor-ink .composing').count(), 'a commit leaves nothing underlined').toBe(0);
});
