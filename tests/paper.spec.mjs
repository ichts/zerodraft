// The sheet on the landing and in the trial: the locked Note paper and ink (D-056), measured rather than
// eyeballed. Every assertion here fails on the pre-change page, where the paper was #ffffff, the ink was
// #17150f, the sheet had no grain at all, and the quiet chrome sat at 1.8:1 on the paper.
//
// What is measured:
//   1. the two locked colours, per surface, as the browser resolves them;
//   2. the contrast floor of every text role on the paper - the words, the quiet chrome, the pen red -
//      including the numeral against the wash it actually sits on;
//   3. the grain: present (a real spread), tone-true (the mean stays on the paper), stable (byte-identical
//      while the writer types), device-exact (no resampling at 1x) and not tiled;
//   4. the texture exists before the demo sheet's first paint.
import { test, expect } from '@playwright/test';

const PAPER = '#dbe6ec';
const INK = '#1c1917';
const QUIET = '#464746';
const DANGER = '#63140b';

const parseColour = value => {
  const match = value.match(/rgba?\(([^)]+)\)/);
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

async function computed(page, selector, property = 'color') {
  return page.evaluate(([sel, prop]) => getComputedStyle(document.querySelector(sel))[prop], [selector, property]);
}

/** A text-free patch of a sheet, read straight off its canvas: mean colour and spread. */
async function patch(page, selector, offsetY = 0.6) {
  return page.evaluate(([sel, where]) => {
    const canvas = document.querySelector(sel + ' .sheet-paper');
    if (!canvas) return null;
    const ctx = canvas.getContext('2d');
    const width = Math.max(8, Math.min(220, Math.round(canvas.width * 0.18)));
    const height = Math.max(8, Math.min(160, Math.round(canvas.height * 0.12)));
    const x = Math.round((canvas.width - width) / 2);
    const y = Math.round(canvas.height * where - height / 2);
    const data = ctx.getImageData(x, y, width, height).data;
    let alpha = 0;
    let sum = 0;
    let sumSquares = 0;
    let count = 0;
    const colours = [];
    for (let i = 0; i < data.length; i += 4) {
      alpha += data[i + 3];
      const lum = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
      sum += lum;
      sumSquares += lum * lum;
      count += 1;
      colours.push(data.slice(i, i + 4).join(','));
    }
    const mean = sum / count;
    const spread = Math.sqrt(Math.max(0, sumSquares / count - mean * mean));
    return {
      meanAlpha: alpha / count,
      spread,
      distinct: new Set(colours).size,
      hash: colours.reduce((acc, value) => {
        for (let i = 0; i < value.length; i += 1) acc = (acc * 31 + value.charCodeAt(i)) | 0;
        return acc;
      }, 7)
    };
  }, [selector, offsetY]);
}

test.describe('the demo sheet at rest', () => {
  test('carries the Note tone, the ink and the grain before its first paint', async ({ page }) => {
    // Every animation frame from the first one records whether the sheet is on screen and whether it
    // is already textured. A frame that sees the sheet plain is the flash this test exists to forbid.
    await page.addInitScript(() => {
      window.__paperFrames = [];
      let remaining = 240;
      const sample = () => {
        const sheet = document.querySelector('.demo-paper');
        if (sheet) {
          const info = window.FirstLinePaper ? window.FirstLinePaper.paintInfo(sheet) : null;
          window.__paperFrames.push(info !== null && info.width > 2);
        }
        if (remaining-- > 0) requestAnimationFrame(sample);
      };
      requestAnimationFrame(sample);
    });
    await page.goto('/index.html');

    // 1. the locked colours
    expect(toHex(parseColour(await computed(page, '.demo-paper', 'backgroundColor')))).toBe(PAPER);
    expect(toHex(parseColour(await computed(page, '.demo-text')))).toBe(INK);

    // 2. the contrast floor of every role that sits on the paper
    const paper = parseColour(await computed(page, '.demo-paper', 'backgroundColor'));
    for (const [selector, role] of [['.demo-text', 'words'], ['.rules', 'the rules line'],
      ['.demo-clock', 'the clock'], ['.danger-caption', 'the warn caption']]) {
      const colour = parseColour(await computed(page, selector));
      expect(contrast(over(colour, paper), paper), `${role} on the paper`).toBeGreaterThanOrEqual(7);
    }
    expect(toHex(parseColour(await computed(page, '.demo-clock')))).toBe(QUIET);
    expect(toHex(parseColour(await computed(page, '.numeral')))).toBe(DANGER);

    // 3. the grain is real and it is on the sheet's own tone
    const sample = await patch(page, '.demo-paper');
    expect(sample.spread, 'grain spread on the demo sheet').toBeGreaterThan(2);
    expect(sample.distinct, 'distinct grain values').toBeGreaterThan(40);
    expect(sample.meanAlpha, 'the texture covers the sheet').toBeGreaterThan(20);

    // 4. the texture is device-exact: never resampled, so it cannot shimmer at 1x
    const canvas = await page.evaluate(() => {
      const element = document.querySelector('.demo-paper .sheet-paper');
      const sheet = document.querySelector('.demo-paper');
      return { width: element.width, height: element.height,
        css: [sheet.clientWidth, sheet.clientHeight], dpr: window.devicePixelRatio };
    });
    expect(canvas.width).toBe(Math.round(canvas.css[0] * canvas.dpr));
    expect(canvas.height).toBe(Math.round(canvas.css[1] * canvas.dpr));

    // 5. no rendered frame ever saw the sheet without its texture
    const frames = await page.evaluate(() => window.__paperFrames);
    expect(frames.length, 'frames that showed the demo sheet').toBeGreaterThan(0);
    expect(frames.filter(painted => !painted).length, 'frames that showed a plain sheet').toBe(0);
  });

  test('does not tile the grain', async ({ page }) => {
    await page.goto('/index.html');
    const comparison = await page.evaluate(() => {
      const canvas = document.querySelector('.demo-paper .sheet-paper');
      const ctx = canvas.getContext('2d');
      const side = 96;
      const x = Math.round(canvas.width * 0.2);
      const y = Math.round(canvas.height * 0.5);
      const left = Array.from(ctx.getImageData(x, y, side, side).data);
      const right = Array.from(ctx.getImageData(x + 128, y, side, side).data);
      let same = 0;
      for (let i = 0; i < left.length; i += 1) if (left[i] === right[i]) same += 1;
      return same / left.length;
    });
    // A repeating tile would agree almost everywhere; the field is generated for the sheet's own size.
    expect(comparison, 'the grain repeats along the sheet').toBeLessThan(0.5);
  });
});

test.describe('the trial sheet', () => {
  test('keeps the paper while the writer types, and the grain never moves', async ({ page }) => {
    await page.goto('/index.html');
    await page.click('a.door');
    const editor = page.locator('.trial-editor');
    await expect(editor).toBeFocused();

    const paperBefore = await computed(page, '.trial-writing-surface', 'backgroundColor');
    expect(toHex(parseColour(paperBefore))).toBe(PAPER);
    const grainBefore = await patch(page, '.trial-writing-surface', 0.7);
    expect(grainBefore.spread).toBeGreaterThan(2);

    await page.keyboard.type('one two three four five six seven', { delay: 25 });

    const paperAfter = await computed(page, '.trial-writing-surface', 'backgroundColor');
    expect(toHex(parseColour(paperAfter))).toBe(PAPER);
    const grainAfter = await patch(page, '.trial-writing-surface', 0.7);
    expect(grainAfter.hash, 'the grain moved under the writer').toBe(grainBefore.hash);
    expect(grainAfter.spread).toBe(grainBefore.spread);

    // the writing ink is the locked ink, at full strength
    const ink = parseColour(await computed(page, '.trial-editor'));
    expect(toHex(ink)).toBe(INK);
    expect(contrast(ink, parseColour(paperAfter))).toBeGreaterThanOrEqual(13);

    // the quiet chrome on the paper (the hint, the rules, the exit, the count) is on the floor too
    for (const selector of ['.trial-hint', '.chrome-bl .trial-exit', '.chrome-tl .label', '.chrome-br .label']) {
      const colour = parseColour(await computed(page, selector));
      expect(contrast(over(colour, parseColour(paperAfter)), parseColour(paperAfter)), selector)
        .toBeGreaterThanOrEqual(7);
    }
  });

  test('the wipe and the kept screen keep their own paper, and the wall stays untouched', async ({ page }) => {
    await page.goto('/index.html');
    await page.click('a.door');
    await page.keyboard.type('a draft that will be kept', { delay: 20 });

    // The kept sheet is a paper on the bone wall: same tone, same grain.
    await page.evaluate(() => {
      document.body.dispatchEvent(new CustomEvent('flcomplete', {
        detail: { resultText: 'a draft that will be kept', resultWordCount: 6 }
      }));
    });
    await expect(page.locator('.trial-kept')).toBeVisible();
    // The kept sheet is mounted at 0x0 while it is hidden; the ResizeObserver textures it in the same
    // rendering step that gives it a size, so no painted frame ever shows it plain.
    await page.waitForFunction(() => {
      const info = window.FirstLinePaper.paintInfo(document.querySelector('.kept-paper'));
      return info !== null && info.width > 2;
    });
    expect(toHex(parseColour(await computed(page, '.kept-paper', 'backgroundColor')))).toBe(PAPER);
    const keptGrain = await patch(page, '.kept-paper', 0.6);
    expect(keptGrain.spread, 'the kept sheet carries the grain').toBeGreaterThan(2);

    // The wall around the sheet is untouched: bone, not paper.
    const wall = parseColour(await computed(page, 'body', 'backgroundColor'));
    const bodyClasses = await page.evaluate(() => document.body.className);
    expect(bodyClasses).toContain('complete');
    expect(toHex(wall)).toBe('#f1f0eb');

    // The room's own texture leaves with the room on the same 120 ms snap the wall returns on.
    await expect.poll(async () => Number(await page.evaluate(() => getComputedStyle(
      document.querySelector('.trial-writing-surface > .sheet-paper')).opacity)),
    { timeout: 2000 }).toBe(0);
  });
});

test.describe('the wash', () => {
  test('the pen red clears 7:1 on the wash the numeral sits on', async ({ page }) => {
    await page.goto('/index.html');
    await page.click('a.door');
    await page.keyboard.type('the number lands on a washed sheet', { delay: 20 });
    await expect(page.locator('.trial-danger .numeral')).toBeVisible({ timeout: 8000 });

    const measured = await page.evaluate(() => {
      const probe = document.createElement('div');
      document.body.appendChild(probe);
      const read = css => { probe.style.background = css; const value = getComputedStyle(probe).backgroundColor; return value; };
      const deep = read('color-mix(in oklab, var(--paper) 76%, var(--danger))');
      probe.remove();
      return { deep, numeral: getComputedStyle(document.querySelector('.trial-danger .numeral')).color };
    });
    // color-mix resolves in oklab; convert through the browser's own compositor before measuring.
    const resolvedDeep = await page.evaluate(css => {
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 1;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = css;
      ctx.fillRect(0, 0, 1, 1);
      const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
      return `rgb(${r}, ${g}, ${b})`;
    }, measured.deep);
    const numeral = parseColour(measured.numeral);
    const backdrop = parseColour(resolvedDeep);
    expect(contrast(numeral, backdrop), 'the numeral on the deepest wash').toBeGreaterThanOrEqual(7);
  });
});
