import { doorSettled } from './door.mjs';
// D-077, D-088 and D-092: the room's history fades per line ended by Return, and the first refused delete of a session says why.
//
// Fade: the unit is the line ended by Return, never a sentence (D-088). Every row of one line shares one measured opacity
// (the ink layer's span, read from the computed style and from the pixels). The steps are D-092's: live 1, one back .22,
// two back .07, older gone, per theme; the lines above dissolve to their next step over 320 ms when Return lands. The
// dimmed lines are exempt from the 7:1 floor (the captain's exception); the live line keeps the full ink. The aperture is
// a hard clip, so a partial line is cut at its edge and never given an alpha.
// Refusal: the 200 ms shake stays on every refusal; the first refused delete of a session also says the rule once,
// centred just under the line being written, for two seconds (D-100, moved out of the footer), and nothing else moves.
import { test, expect } from '@playwright/test';

const TONES = { light: '#e9e2ce', dark: '#342e24' };
const QUIET = { light: '#464746', dark: '#c2bfb7' };
const REFUSAL = 'You can only add the next word.';

const rgb = value => String(value).match(/[\d.]+/g).slice(0, 3).map(Number);
const lum = ([r, g, b]) => [r, g, b].map(v => { const c = v / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; })
  .reduce((sum, c, i) => sum + c * [0.2126, 0.7152, 0.0722][i], 0);
const contrast = (a, b) => { const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x); return (hi + 0.05) / (lo + 0.05); };
const hex = value => [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16));
const over = (ink, alpha, paper) => ink.map((v, i) => v * alpha + paper[i] * (1 - alpha));

async function enter(page) {
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await doorSettled(page);
  await expect(page.locator('#editor')).toBeFocused();
}

/** Every running dissolve has landed: the document timeline only moves with frames, so wait on the animations themselves. */
const dissolved = page => page.evaluate(async () => {
  await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  await Promise.all(document.getAnimations().filter(animation => animation instanceof CSSTransition).map(animation => animation.finished.catch(() => {})));
});

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
  await dissolved(page);

  const lines = await inkLines(page);
  const long = lines[0];
  expect(long.rung, 'the line above the live one is rung 1').toBe('1');
  expect(long.rows.length, `the long line wraps to several rows: ${JSON.stringify(long.rows)}`).toBeGreaterThanOrEqual(2);
  const token = await page.evaluate(() => Number(getComputedStyle(document.querySelector('#editor-ink')).getPropertyValue('--paper-history-1')));
  expect(long.opacity, 'one measured opacity for every row of the line').toBeCloseTo(token, 3);
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

test('each Return line gets exactly its step, 1 / .22 / .07 per theme, and older lines are gone (D-092)', async ({ page }) => {
  await enter(page);
  const mode = await theme(page);
  await page.keyboard.insertText('Oldest line.\nThree back.\nTwo back.\nOne back.\nLive');
  await dissolved(page);
  const lines = await inkLines(page);
  expect(lines.map(line => line.rung)).toEqual(['3', '3', '2', '1', '0']);
  const tokens = await page.evaluate(() => {
    const style = getComputedStyle(document.querySelector('#editor-ink'));
    return [1, 2].map(n => Number(style.getPropertyValue(`--paper-history-${n}`)));
  });
  expect(tokens).toEqual(mode === 'dark' ? [0.16, 0.05] : [0.22, 0.07]);
  const byRung = Object.fromEntries(lines.map(line => [line.rung, line.opacity]));
  expect(byRung).toEqual({ 0: 1, 1: tokens[0], 2: tokens[1], 3: 0 });
  expect(byRung['0']).toBe(1);
  const ink = rgb(await page.evaluate(() => getComputedStyle(document.querySelector('#editor-ink')).color));
  const paper = hex(TONES[mode]);
  expect(contrast(ink, paper), 'the live line keeps the full ink').toBeGreaterThanOrEqual(7);
  // The captain's contrast exception: the same 1.57:1 and 1.15:1 in both themes, not 7:1 roles.
  const ratios = tokens.map(alpha => contrast(over(ink, alpha, paper), paper));
  expect(ratios[0], `one back ${ratios[0].toFixed(2)}:1`).toBeGreaterThan(1.5);
  expect(ratios[0]).toBeLessThan(1.65);
  expect(ratios[1], `two back ${ratios[1].toFixed(2)}:1`).toBeGreaterThan(1.1);
  expect(ratios[1]).toBeLessThan(1.2);
});

test('a full stop never ends a line: one line holds every sentence typed before Return (D-088)', async ({ page }) => {
  await enter(page);
  await page.keyboard.insertText('One short sentence. And another one follows it. Third');
  await dissolved(page);
  const lines = await inkLines(page);
  expect(lines.map(line => line.text.trim())).toEqual(['One short sentence. And another one follows it. Third']);
  expect(lines.map(line => line.rung)).toEqual(['0']);
  expect(lines[0].opacity, 'typing sentences on the live line fades nothing').toBe(1);
});

test('pressing Return starts the dissolve of the line just written, and not before', async ({ page }, info) => {
  const reduced = info.project.use.reducedMotion === 'reduce';
  await enter(page);
  const token = await page.evaluate(() => Number(getComputedStyle(document.querySelector('#editor-ink')).getPropertyValue('--paper-history-1')));
  await page.keyboard.insertText('First thought. Still the first line');
  await dissolved(page);
  expect((await inkLines(page)).map(line => [line.rung, line.opacity])).toEqual([['0', 1]]);

  await page.keyboard.press('Enter');
  expect((await inkLines(page)).map(line => line.rung), 'the written line steps back in the task Return lands').toEqual(['1']);
  const dissolve = await page.evaluate(() => document.querySelector('#editor-ink [data-rung]').getAnimations()
    .filter(a => a.transitionProperty === 'opacity').map(a => a.effect.getTiming().duration));
  expect(dissolve, reduced ? 'Reduce Motion steps at once' : 'a 320 ms opacity dissolve starts with Return').toEqual(reduced ? [] : [320]);
  await dissolved(page);
  expect((await inkLines(page))[0].opacity, 'the dissolve lands on the first step').toBeCloseTo(token, 3);

  await page.keyboard.insertText('Second line. Third sentence');
  expect((await inkLines(page)).map(line => line.rung)).toEqual(['1', '0']);
  await page.keyboard.press('Enter');
  expect((await inkLines(page)).map(line => line.rung)).toEqual(['2', '1']);
  const hist2 = await page.evaluate(() => Number(getComputedStyle(document.querySelector('#editor-ink')).getPropertyValue('--paper-history-2')));
  await dissolved(page);
  expect((await inkLines(page)).map(line => line.opacity)).toEqual([hist2, token]);
  expect((await inkLines(page)).map(line => line.text.trim())).toEqual(['First thought. Still the first line', 'Second line. Third sentence']);
});

test('the aperture clips a partial line at its edge and never fades it', async ({ page }) => {
  await enter(page);
  const mode = await theme(page);
  const tone = hex(TONES[mode]);
  await page.keyboard.insertText('Above.\nLive line here');
  await dissolved(page);
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

// The footer, the count, the clock, the paper and the writing layer: none may move while the note shows (D-100).
const frames = page => page.evaluate(() => Object.fromEntries(['#exit', '#room-count', '#room-clock', '.room-paper', '.editor-stack', '#editor-ink', '#exit-hint']
  .map(selector => { const r = document.querySelector(selector).getBoundingClientRect(); return [selector, [r.x, r.y, r.width, r.height].map(v => Math.round(v * 100) / 100)]; })));
const noteShown = page => page.locator('#refusal-note').getAttribute('data-shown');
// The paper's shake and its red hairline are both animations under the paper; Reduce Motion keeps the hairline alone.
const shakes = page => page.evaluate(() => document.querySelector('.room-paper').getAnimations({ subtree: true }).length);
// Where the note sits against the writing: its box, the live line's box bottom and the footer's top, all in page pixels.
const geometry = page => page.evaluate(() => {
  const box = selector => document.querySelector(selector).getBoundingClientRect();
  const note = box('#refusal-note');
  const stack = box('.editor-stack');
  const lh = parseFloat(getComputedStyle(document.querySelector('#editor')).lineHeight);
  return { note: { x: note.x, y: note.y, width: note.width, height: note.height }, stack: { x: stack.x, width: stack.width },
    lineBottom: stack.y + 3 * lh, lh, footerTop: box('.room-paper .paper-foot').top, paper: box('.room-paper') };
});

test('the first refused delete says the rule once, centred under the line being written; later refusals only shake', async ({ page }, info) => {
  await enter(page);
  const mode = await theme(page);
  await page.keyboard.insertText('Some words');
  expect(await noteShown(page), 'nothing shows before any refusal').toBe('false');
  const before = await frames(page);
  // The note's own clock, read in the page so a slow screenshot cannot change what is measured.
  await page.evaluate(() => {
    const note = document.getElementById('refusal-note');
    window.__noteFlips = [];
    new MutationObserver(() => window.__noteFlips.push([note.dataset.shown, performance.now()])).observe(note, { attributes: true, attributeFilter: ['data-shown'] });
  });

  await page.keyboard.press('Backspace');
  await expect(page.locator('#refusal-note')).toHaveAttribute('data-shown', 'true');
  await expect(page.locator('#refusal-note')).toHaveText(REFUSAL);
  expect(REFUSAL, 'sentence case, never all capitals').not.toBe(REFUSAL.toUpperCase());
  expect(await shakes(page), 'the 200 ms shake still runs on the first refusal').toBeGreaterThan(0);
  // The paper's own shake and hairline are the refusal's animations, not the note's: let the short ones (the shake, the hairline) end, then the note must still be on screen and nothing may have moved.
  await page.waitForFunction(() => document.querySelector('.room-paper').getAnimations({ subtree: true }).every(a => a.effect.getComputedTiming().endTime > 1000));
  expect(await noteShown(page), 'the note outlives the shake').toBe('true');
  expect(await frames(page), 'the footer and the writing keep their frames while the note shows').toEqual(before);
  await expect(page.locator('#exit'), 'Esc to exit stays in the footer').toHaveText(/^(Esc to exit|Exit)$/);
  await expect(page.locator('#exit-hint'), 'the footer slot stays empty').toHaveText('');

  // Centred on the writing column, just beneath the live line, clear of the footer, and not over the caret line.
  const g = await geometry(page);
  expect(Math.abs(g.note.x + g.note.width / 2 - (g.stack.x + g.stack.width / 2)), 'centred on the writing column').toBeLessThanOrEqual(1);
  expect(g.note.y, 'beneath the live line, not over it').toBeGreaterThanOrEqual(g.lineBottom);
  expect(g.note.y - g.lineBottom, 'just beneath the line').toBeLessThan(g.lh);
  expect(g.note.y + g.note.height, 'fully visible above the footer').toBeLessThanOrEqual(g.footerTop);

  // The quiet role: 7:1 on the sheet, announced once (the visible note is hidden from assistive tech).
  const colour = await page.locator('#refusal-note').evaluate(e => getComputedStyle(e).color);
  expect(rgb(colour)).toEqual(hex(QUIET[mode]));
  expect(contrast(rgb(colour), hex(TONES[mode]))).toBeGreaterThanOrEqual(7);
  await expect(page.locator('#refusal-note')).toHaveAttribute('aria-hidden', 'true');
  expect(await page.locator('#status').textContent(), 'announced once, in the live region').toBe(REFUSAL);

  // A second refusal inside the window restarts nothing and says nothing new on screen.
  await page.keyboard.press('Delete');
  expect(await noteShown(page)).toBe('true');

  await page.screenshot({ path: info.outputPath('refusal-first.png') });
  await expect(page.locator('#refusal-note')).toHaveAttribute('data-shown', 'false', { timeout: 2600 });
  const flips = await page.evaluate(() => window.__noteFlips);
  expect(flips.map(([value]) => value), 'shown once, then hidden once; the second refusal restarted nothing').toEqual(['true', 'false']);
  const lasted = flips[1][1] - flips[0][1];
  expect(lasted, `the note lasted ${Math.round(lasted)} ms`).toBeGreaterThanOrEqual(1990);
  expect(lasted).toBeLessThan(2200);
  await expect(page.locator('#refusal-note'), 'it fades out and is gone').toHaveCSS('opacity', '0');
  expect(await frames(page), 'nothing moved after it went').toEqual(before);

  // Later refusals in the same session shake only and show nothing.
  await page.keyboard.press('Backspace');
  expect(await shakes(page), 'a later refusal still shakes').toBeGreaterThan(0);
  expect(await noteShown(page), 'a later refusal shows no text').toBe('false');
  expect(await page.locator('#status').textContent()).toBe('Blocked. Forward only.');
  await page.keyboard.insertText(' more');

  // A session that ends starts the next one clean: stop typing until the draft is wiped, then refuse again.
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe', { timeout: 9000 });
  await page.keyboard.press('Backspace');
  expect(await noteShown(page), 'the stopped screen owns the space: the note waits').toBe('false');
  await page.keyboard.insertText('Fresh');
  await page.keyboard.press('Backspace');
  await expect(page.locator('#refusal-note')).toHaveAttribute('data-shown', 'true');
});

test('the note fades out in 200 ms, and under Reduce Motion it only steps', async ({ page }) => {
  await enter(page);
  const reduce = await page.evaluate(() => matchMedia('(prefers-reduced-motion: reduce)').matches);
  await page.keyboard.insertText('Words');
  await page.keyboard.press('Backspace');
  await expect(page.locator('#refusal-note')).toHaveAttribute('data-shown', 'true');
  const timing = await page.locator('#refusal-note').evaluate(e => getComputedStyle(e).transitionDuration);
  expect(timing.split(',')[0].trim(), 'shown: no transition in, so the note is there on the refusal frame').toBe('0s');
  await expect(page.locator('#refusal-note')).toHaveAttribute('data-shown', 'false', { timeout: 2600 });
  const out = await page.locator('#refusal-note').evaluate(e => getComputedStyle(e).transitionDuration.split(',')[0].trim());
  expect(out, reduce ? 'Reduce Motion: no fade, an opacity step' : 'fades out over 200 ms').toBe(reduce ? '0s' : '0.2s');
  const moved = await page.locator('#refusal-note').evaluate(e => getComputedStyle(e).transform);
  expect(moved, 'it never moves').toBe('none');
});

test('only a delete earns the note; the warning owns the space; an armed exit confirmation does not block it', async ({ page }) => {
  await enter(page);
  await page.keyboard.insertText('Words');
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('Control+z');
  expect(await noteShown(page), 'caret moves and undo only shake').toBe('false');
  // Silence: the warning numeral takes the space under the line, so a refused delete waits unspent.
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'warn', { timeout: 6500 });
  await page.keyboard.press('Backspace');
  expect(await noteShown(page), 'no note over the warning numeral').toBe('false');
  await page.keyboard.insertText(' typed');
  await page.keyboard.press('Escape');
  const hint = await page.locator('#exit-hint').getAttribute('data-hint');
  await expect(page.locator('#exit-hint')).toHaveText(hint);
  await page.keyboard.press('Backspace');
  await expect(page.locator('#refusal-note'), 'the waiting note shows now').toHaveAttribute('data-shown', 'true');
  await expect(page.locator('#exit-hint'), 'the confirmation keeps its footer slot').toHaveText(hint);
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
