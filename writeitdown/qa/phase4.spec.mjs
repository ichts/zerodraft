import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { LINES, TIMELINE } from '../demo-timeline.mjs';
import { wordCount } from '../session.mjs';

const capture = (page, info, state) => page.screenshot({ path: info.outputPath(`${state}.png`) });
const editor = page => page.locator('#editor');
const browserEvidence = new WeakMap();
const demoGeometry = new WeakMap();
const EXIT_HINT = 'Press Esc again to leave and delete the draft.';
const SILENT_END = TIMELINE.typeEnd + 5000;
const WARN_END = SILENT_END + 3000;
const CUT_END = WARN_END + 200;

// Font ink metrics measured in the page itself: the tests never import room.js or
// demo.js, so a wrong ink formula on the page cannot hide behind the same formula
// here. `run` returns a text run's ink top (page coordinates) and ink height.
const INK = () => {
  window.__ink = (text, font, lineHeight) => {
    const context = window.__inkContext ??= document.createElement('canvas').getContext('2d');
    context.font = font;
    const m = context.measureText(text || '0');
    const ascent = m.fontBoundingBoxAscent;
    const descent = m.fontBoundingBoxDescent;
    return {
      ascent, descent,
      inkAscent: m.actualBoundingBoxAscent,
      inkHeight: m.actualBoundingBoxAscent + m.actualBoundingBoxDescent,
    };
  };
  // 'line' measures the element's own line box (a single-line block keeps one);
  // 'text' measures the text run, for labels inside a control whose box is taller
  // than its line box.
  window.__run = (element, mode = 'line') => {
    const style = getComputedStyle(element);
    const font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const lineHeight = parseFloat(style.lineHeight);
    const ink = window.__ink(element.textContent, font, lineHeight);
    const range = document.createRange();
    range.selectNodeContents(element);
    const box = mode === 'text' ? (range.getClientRects()[0] || element.getBoundingClientRect()) : element.getBoundingClientRect();
    // 'line': the box IS the line box, so the baseline carries half-leading.
    // 'text': the range rect is the inline box, so the baseline is its top + ascent.
    const baseline = mode === 'text' ? box.top + ink.ascent : box.top + (lineHeight - (ink.ascent + ink.descent)) / 2 + ink.ascent;
    return {
      inkTop: baseline - ink.inkAscent,
      baseline,
      inkHeight: ink.inkHeight,
      width: box.width,
      rect: { top: box.top, bottom: box.bottom, left: box.left, right: box.right, height: box.height },
    };
  };
  // The active line of the textarea: the middle band of the five-line aperture,
  // measured from the editor's own box and the writing pitch (CSS geometry, not room.js).
  window.__writingLine = () => {
    const element = document.querySelector('#editor');
    const style = getComputedStyle(element);
    const lineHeight = parseFloat(style.lineHeight);
    const ink = window.__ink('Hxg', `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`, lineHeight);
    const box = element.getBoundingClientRect();
    const top = box.top + 2 * lineHeight;
    const baseline = top + (lineHeight - (ink.ascent + ink.descent)) / 2 + ink.ascent;
    return { top, baseline, lineHeight, centre: top + lineHeight / 2,
      paperTop: element.closest('.room-paper').getBoundingClientRect().top,
      paperHeight: element.closest('.room-paper').getBoundingClientRect().height };
  };
};

async function enter(page) {
  await page.locator('#landing .cta a[href="#trial"]').click();
  await expect(editor(page)).toBeFocused();
}

// The line-shift animation runs on rAF, which a paused fake clock freezes: settle it
// explicitly before measuring the settled geometry.
async function settle(page, ms = 400) {
  await page.clock.fastForward(ms);
}

async function assertRoom(page) {
  const geometry = await editor(page).evaluate(e => {
    const style = getComputedStyle(e);
    const line = parseFloat(style.lineHeight);
    const rect = e.getBoundingClientRect();
    const paper = e.closest('.room-paper').getBoundingClientRect();
    const write = window.__writingLine();
    return {
      height: e.clientHeight, line, overflow: style.overflowY, scrollbar: style.scrollbarWidth,
      mask: style.maskImage || style.webkitMaskImage,
      activeCentre: write.centre, ratio: (write.centre - paper.top) / paper.height,
      paperHeight: paper.height, paperTop: paper.top,
      fallback: 44 + 2.5 * line,
      apertureTop: write.top, chromeBottom: e.closest('.room-paper').querySelector('.chrome-row').getBoundingClientRect().bottom,
      pageHeight: document.documentElement.scrollHeight, viewportHeight: innerHeight,
      pageWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth,
      bars: [...document.querySelectorAll('#room .bar, #room .meter, #room .session-bar')].map(bar => {
        const box = bar.getBoundingClientRect();
        return { cls: bar.className, top: box.top, height: box.height, width: box.width, paperTop: paper.top };
      }),
    };
  });
  expect(Math.abs(geometry.height - geometry.line * 5), 'five-line aperture').toBeLessThan(1);
  // The active line sits at 35% of the sheet (D-025 parity with the Mac); on a sheet
  // too short to fit the aperture under the clock it sits at the CSS fallback.
  const short = geometry.paperHeight * 0.35 < geometry.fallback;
  expect(Math.abs(geometry.activeCentre - geometry.paperTop - (short ? geometry.fallback : 0.35 * geometry.paperHeight))).toBeLessThan(1);
  expect(Math.abs(geometry.ratio - (short ? geometry.fallback / geometry.paperHeight : 0.35)), `anchor ${geometry.ratio}`).toBeLessThan(0.005);
  expect(geometry.apertureTop).toBeGreaterThan(geometry.chromeBottom);
  expect(geometry.overflow).toBe('hidden');
  expect(geometry.scrollbar).toBe('none');
  // One 2 pt bar pinned to the paper top; the 3 pt silence meter is gone (D-014).
  expect(geometry.bars).toHaveLength(1);
  expect(geometry.bars[0].height).toBe(2);
  expect(Math.abs(geometry.bars[0].top - geometry.bars[0].paperTop)).toBeLessThan(1);
  // Stepped per-line history, not a continuous gradient: 7% / 22% / 100% / gone,
  // each band exactly one line pitch tall (D-027 parity).
  const bands = maskBands(geometry.mask);
  expect(bands.length, geometry.mask).toBe(4);
  expect(bands.map(band => band.alpha)).toEqual([0.07, 0.22, 1, 0]);
  bands.slice(0, 3).forEach((band, index) => {
    expect(Math.abs(band.end - band.start - geometry.line), `band ${index} of ${geometry.mask}`).toBeLessThan(1.1);
    expect(Math.abs(band.start - index * geometry.line)).toBeLessThan(1.1);
  });
  expect(bands[3].start, 'nothing below the active line: the mask stops at the third band').toBeCloseTo(3 * geometry.line, 0);

  expect(geometry.pageHeight).toBe(geometry.viewportHeight);
  expect(geometry.pageWidth).toBe(geometry.viewportWidth);
  return geometry;
}

// Parse the computed stepped mask into {alpha,start,end} bands, in px.
function maskBands(maskImage) {
  const stops = [...maskImage.matchAll(/(rgba?\([^)]*\)|#\w+)\s+([\d.]+)px/g)]
    .map(match => ({ alpha: /^rgb\(/.test(match[1]) ? 1 : parseFloat(match[1].split(',')[3]), px: parseFloat(match[2]) }));
  const bands = [];
  for (let index = 0; index < stops.length; index += 2) {
    const end = stops[index + 1] ? stops[index + 1].px : null;
    bands.push({ alpha: stops[index].alpha, start: stops[index].px, end: end ?? stops[index].px });
  }
  return bands;
}

test.beforeEach(async ({ page }) => {
  const evidence = { errors: [], consoleErrors: [], requests: [], failedAssets: [], failedRequests: [] };
  browserEvidence.set(page, evidence);
  page.on('pageerror', error => evidence.errors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error') evidence.consoleErrors.push(message.text());
  });
  page.on('requestfailed', request => evidence.failedRequests.push(request.url()));
  await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));
  // Hermetic: the only allowed third-party script is the Cloudflare beacon; stub it so no network call leaves the test.
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ contentType: 'text/javascript', body: '' }));
  page.on('request', request => evidence.requests.push({ method: request.method(), url: request.url() }));
  page.on('response', response => {
    if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) evidence.failedAssets.push(response.url());
  });
  await page.addInitScript(INK);
  await page.clock.install({ time: new Date('2026-09-16T12:00:00Z') });
  await page.clock.pauseAt(new Date('2026-09-16T12:00:01Z'));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  demoGeometry.set(page, await page.locator('.script').evaluate(e => {
    const rect = e.getBoundingClientRect();
    const paper = e.closest('.paper').getBoundingClientRect();
    const write = window.__run(e);
    return { line: parseFloat(getComputedStyle(e).lineHeight), fontSize: getComputedStyle(e).fontSize,
      paperHeight: paper.height, baseline: write.baseline,
      ratio: (rect.top + rect.height / 2 - paper.top) / paper.height };
  }));
});

test.afterEach(async ({ page }, info) => {
  const evidence = browserEvidence.get(page);
  await info.attach('browser-evidence', { body: JSON.stringify(evidence), contentType: 'application/json' });
  expect(evidence.errors).toEqual([]);
  expect(evidence.consoleErrors).toEqual([]);
  expect(evidence.failedRequests).toEqual([]);
  expect(evidence.failedAssets).toEqual([]);
  expect(evidence.requests.every(request => request.method === 'GET')).toBe(true);
});

test('landing demo types into #cur after a hard load', async ({ page }, info) => {
  await page.reload();
  await page.evaluate(() => document.fonts.ready);
  if (info.project.use.reducedMotion === 'reduce') {
    await expect(page.locator('#cur')).toHaveText(LINES.at(-1));
  } else {
    await page.clock.fastForward(TIMELINE.events[0].t + 100);
    await expect(page.locator('#cur')).toHaveText(/^i/);
  }
  await capture(page, info, 'demo-hard-load');
});

test('demo and trial active-line placement: 35% of the sheet on both surfaces', async ({ page }, info) => {
  if (info.project.use.reducedMotion !== 'reduce') await page.clock.fastForward(TIMELINE.typeEnd + 250);
  const demo = demoGeometry.get(page);
  await capture(page, info, 'placement-demo');
  await enter(page);
  const states = {};
  for (const [state, text] of Object.entries({ empty: '', short: 'A fresh line.', cjk: '中文继续写。'.repeat(120) })) {
    if (text) await page.keyboard.insertText(text);
    await settle(page);
    states[state] = await assertRoom(page);
    await capture(page, info, `placement-${state}`);
  }
  // Journey: the demo's writing line sits where the room's does (within 1% of the sheet), at the same size.
  for (const state of Object.values(states)) expect(Math.abs(demo.ratio - state.ratio)).toBeLessThanOrEqual(0.01);
  expect(Math.abs(demo.ratio - 0.35)).toBeLessThan(0.005);
  expect(demo.fontSize).toBe(await editor(page).evaluate(e => getComputedStyle(e).fontSize));
  expect(demo.line).toBeCloseTo(states.empty.line, 1);
  await info.attach('placement', { body: JSON.stringify({ demo, states }), contentType: 'application/json' });
  console.log(info.project.name, JSON.stringify({ demo, ratios: Object.fromEntries(Object.entries(states).map(([k, v]) => [k, v.ratio])) }));
});

test('empty room shows only the caret and the count prompt; after a wipe the receipt carries it', async ({ page }, info) => {
  await enter(page);
  await settle(page);
  await expect(page.locator('#room-count')).toHaveText('Type to start');
  // No hint on the line: the empty writing line holds only the caret (D-021/D-028).
  expect(await editor(page).evaluate(e => e.hasAttribute('placeholder'))).toBe(false);
  const caret = await editor(page).evaluate(e => {
    const style = getComputedStyle(e);
    const box = e.getBoundingClientRect();
    const paper = e.closest('.room-paper').getBoundingClientRect();
    return { caretColor: style.caretColor, placeholderColor: style.placeholderColor,
      editorCentre: box.left + box.width / 2, paperCentre: paper.left + paper.width / 2 };
  });
  expect(caret.caretColor).not.toBe('rgba(0, 0, 0, 0)');
  expect(Math.abs(caret.editorCentre - caret.paperCentre)).toBeLessThan(1);
  await capture(page, info, 'empty-focused');
  await page.keyboard.insertText('i');
  await expect(page.locator('#room-count')).toHaveText('1 word');
  await capture(page, info, 'first-char');
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(page.locator('#room-count')).toHaveText('0 words');
  await expect(page.locator('#failed h1')).toHaveText('You stopped.');
  await expect(page.locator('#begin-again')).toBeVisible();
  await expect(page.locator('#room-report')).toHaveText(/^DRAFT DELETED AT \d:\d\d\. TYPE TO START AGAIN\.$/);
  // The wiped room keeps the caret on the line, exactly as the empty room does.
  await expect(editor(page)).toBeFocused();
  await capture(page, info, 'wipe-report');
});

test('history is stepped per line and a new line shifts it exactly one pitch', async ({ page }, info) => {
  const reduced = info.project.use.reducedMotion === 'reduce';
  await enter(page);
  await page.keyboard.insertText('First line');
  await settle(page);
  const topology = await editor(page).evaluate(e => ({ line: parseFloat(getComputedStyle(e).lineHeight), scroll: e.scrollTop }));
  await page.keyboard.insertText(' typed on the same line');
  await settle(page);
  expect(await editor(page).evaluate(e => e.scrollTop), 'same-line typing moves nothing').toBe(topology.scroll);
  for (const line of [2, 3, 4]) {
    const start = topology.scroll + (line - 2) * topology.line;
    await page.keyboard.insertText('\n');
    await page.keyboard.insertText(`Line ${line}`);
    if (reduced) {
      expect(await editor(page).evaluate(e => e.scrollTop), `line ${line} snaps under Reduce Motion`).toBeCloseTo(start + topology.line, 0);
    } else {
      await page.clock.runFor(90);
      const mid = await editor(page).evaluate(e => e.scrollTop);
      expect(mid, `line ${line} is shifting, not snapping`).toBeGreaterThan(start + 0.5);
      expect(mid, `line ${line} is shifting, not snapping`).toBeLessThan(start + topology.line - 0.5);
    }
    await settle(page);
    expect(await editor(page).evaluate(e => e.scrollTop), `line ${line} shifted the history one pitch`)
      .toBeCloseTo(start + topology.line, 0);
  }
  // One fixed pitch for every script: a Chinese line advances exactly one line box too.
  const cjkStart = topology.scroll + 3 * topology.line;
  await page.keyboard.insertText('\n中文继续写。');
  if (reduced) {
    expect(await editor(page).evaluate(e => e.scrollTop), 'a CJK line snaps under Reduce Motion').toBeCloseTo(cjkStart + topology.line, 0);
  } else {
    await page.clock.runFor(90);
    const cjkMid = await editor(page).evaluate(e => e.scrollTop);
    expect(cjkMid, 'a CJK line is shifting, not snapping').toBeGreaterThan(cjkStart + 0.5);
    expect(cjkMid, 'a CJK line is shifting, not snapping').toBeLessThan(cjkStart + topology.line - 0.5);
  }
  await settle(page);
  expect(await editor(page).evaluate(e => e.scrollTop), 'a CJK line keeps the same pitch').toBeCloseTo(topology.scroll + 4 * topology.line, 0);
  await expect(page.locator('#room-count')).toHaveText(`${wordCount('First line typed on the same line\nLine 2\nLine 3\nLine 4\n中文继续写。')} words`);
});

test('warning numeral, caption and wipe receipt are placed by ink under the writing line', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('Keep typing until the warning lands.');
  await settle(page);
  await page.clock.fastForward(5500);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'warn');
  const warning = await page.evaluate(() => {
    const write = window.__writingLine();
    return { numeral: window.__run(document.querySelector('#room-numeral')),
      caption: window.__run(document.querySelector('#room-warning')),
      baseline: write.baseline, numeralText: document.querySelector('#room-numeral').textContent,
      captionText: document.querySelector('#room-warning').textContent };
  });
  expect(warning.numeralText).toMatch(/^[123]$/);
  expect(warning.captionText).toBe('KEEP TYPING OR THE DRAFT IS DELETED.');
  expect(warning.numeral.inkTop - warning.baseline, 'numeral ink top under the writing baseline').toBeGreaterThan(40);
  expect(warning.numeral.inkTop - warning.baseline).toBeLessThan(48);
  expect(warning.caption.inkTop - (warning.numeral.inkTop + warning.numeral.inkHeight), 'caption under the numeral ink').toBeGreaterThan(16);
  expect(warning.caption.inkTop - (warning.numeral.inkTop + warning.numeral.inkHeight)).toBeLessThan(24);
  await capture(page, info, 'warn');
  await page.clock.fastForward(2850);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  const receipt = await page.evaluate(() => {
    const write = window.__writingLine();
    return { receipt: window.__run(document.querySelector('#room-report')), baseline: write.baseline };
  });
  expect(receipt.receipt.inkTop - receipt.baseline, 'receipt ink top under the writing baseline').toBeGreaterThan(40);
  expect(receipt.receipt.inkTop - receipt.baseline).toBeLessThan(48);
  await capture(page, info, 'deleted');
});

test('mobile dynamic viewport keeps EXIT and word count visible with expanded toolbars', async ({ page }, info) => {
  test.skip(info.project.use.viewport.width !== 390, 'Mobile toolbar geometry');
  await page.addStyleTag({ content: '.home { min-height: 844px; }' });
  for (const [state, height] of [['collapsed', 844], ['expanded', 664], ['collapsed-again', 844]]) {
    await page.setViewportSize({ width: 390, height });
    const demo = await page.locator('.script').evaluate(e => {
      const line = e.getBoundingClientRect();
      const sheet = e.closest('.paper').getBoundingClientRect();
      return { height: sheet.height, viewport: innerHeight, ratio: (line.top + line.height / 2 - sheet.top) / sheet.height };
    });
    expect(demo.height / demo.viewport).toBeGreaterThanOrEqual(0.6);
    expect(Math.abs(demo.height - (demo.viewport * 0.61 + 2))).toBeLessThan(1);
    await enter(page);
    await page.keyboard.insertText('Keep writing.');
    await settle(page);
    await expect(page.locator('#room-count')).toHaveText('2 words');
    const room = await assertRoom(page);
    expect(Math.abs(demo.ratio - room.ratio)).toBeLessThanOrEqual(0.01);
    expect(Math.abs(room.ratio - 0.35)).toBeLessThan(0.005);
    for (const selector of ['#exit', '#room-count']) {
      const bounds = await page.locator(selector).evaluate(e => {
        const rect = e.getBoundingClientRect();
        return { top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right, width: rect.width,
          height: rect.height, viewportWidth: innerWidth, viewportHeight: innerHeight };
      });
      expect(bounds.width).toBeGreaterThan(0);
      expect(bounds.height).toBeGreaterThan(0);
      expect(bounds.top).toBeGreaterThanOrEqual(0);
      expect(bounds.left).toBeGreaterThanOrEqual(0);
      expect(bounds.bottom).toBeLessThanOrEqual(bounds.viewportHeight);
      expect(bounds.right).toBeLessThanOrEqual(bounds.viewportWidth);
    }
    await capture(page, info, `trial-toolbar-${state}`);
    await page.locator('#exit').click();
    await page.locator('#exit').click();
    await expect(page.locator('#landing .cta a')).toBeFocused();
    await expect(page.locator('#room')).toBeHidden();
  }
});

test('the short trial sheet keeps its dynamic viewport minimum', async ({ page }, info) => {
  test.skip(info.project.use.viewport.width !== 390, 'Mobile trial geometry');
  await page.setViewportSize({ width: 390, height: 560 });
  await enter(page);
  const room = await page.evaluate(() => {
    const room = document.querySelector('#room');
    const paper = room.querySelector('.room-paper');
    const sheet = paper.getBoundingClientRect();
    const nav = room.querySelector('.home-nav').getBoundingClientRect();
    const foot = room.querySelector('.paper-foot').getBoundingClientRect();
    return { viewport: innerHeight, nav: nav.height, gutter: parseFloat(getComputedStyle(room).paddingBottom),
      roomMin: parseFloat(getComputedStyle(room).minHeight), paperMin: parseFloat(getComputedStyle(paper).minHeight),
      paperBottom: sheet.bottom, footBottom: foot.bottom };
  });
  expect(room.roomMin, 'the room clears the landing min-height').toBe(0);
  expect(room.paperMin, 'the trial sheet subtracts the header and bottom gutter from the dynamic viewport')
    .toBeCloseTo(room.viewport - room.nav - room.gutter, 0);
  expect(room.paperBottom).toBeLessThanOrEqual(room.viewport);
  expect(room.footBottom).toBeLessThanOrEqual(room.viewport);
});

test('short sheets keep the warning and result slots inside the paper', async ({ page }, info) => {
  for (const size of [{ width: 844, height: 390 }, { width: 1440, height: 350 }]) {
    await page.setViewportSize(size);
    await enter(page);
    await page.keyboard.insertText('A');
    await page.clock.fastForward(8350);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
    const failure = await page.evaluate(() => {
      const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom }; };
      return { paper: box('.room-paper'), footer: box('.room-paper .paper-foot'), block: box('#failed'), receipt: box('#room-report') };
    });
    expect(failure.block.top).toBeGreaterThanOrEqual(failure.paper.top);
    expect(failure.block.bottom).toBeLessThanOrEqual(failure.receipt.top);
    expect(failure.receipt.top).toBeGreaterThanOrEqual(failure.paper.top);
    expect(failure.receipt.bottom).toBeLessThanOrEqual(failure.footer.top);
    await capture(page, info, `short-failure-${size.width}x${size.height}`);
    await page.keyboard.press('Enter');
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'rest');
    await page.keyboard.insertText('A');
    await page.clock.fastForward(5200);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'warn');
    const warning = await page.evaluate(() => {
      const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom }; };
      const line = document.querySelector('#editor');
      const lineHeight = parseFloat(getComputedStyle(line).lineHeight);
      const lineTop = line.getBoundingClientRect().top + 2 * lineHeight;
      return { paper: box('.room-paper'), footer: box('.room-paper .paper-foot'), danger: box('#room-danger'), caption: box('#room-warning'), lineTop, lineBottom: lineTop + lineHeight };
    });
    expect(warning.danger.top).toBeGreaterThanOrEqual(warning.paper.top);
    expect(warning.caption.bottom).toBeLessThanOrEqual(warning.lineTop);
    expect(warning.danger.bottom).toBeLessThanOrEqual(warning.footer.top);
    await capture(page, info, `short-warn-${size.width}x${size.height}`);
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    await expect(page.locator('#landing')).toBeVisible();
  }
});

test('kept screens keep the controls and draft clear of the paper foot', async ({ page }, info) => {
  test.skip(info.project.name !== '1440-light-no-preference', 'layout check, one project is enough');
  const sizes = [
    { width: 1440, height: 350 },
    { width: 844, height: 390 },
    { width: 667, height: 375 },
    { width: 390, height: 844 },
    { width: 1440, height: 620 },
  ];
  const compactSizes = new Set(['1440x350', '844x390']);
  for (const size of sizes) {
    const compact = compactSizes.has(`${size.width}x${size.height}`);
    await page.setViewportSize(size);
    await enter(page);
    await page.keyboard.insertText('This draft survives on a short sheet.\n');
    for (let second = 0; second < 57; second += 3) {
      await page.clock.fastForward(3000);
      await page.keyboard.insertText('Keep going. ');
    }
    await page.clock.fastForward(3000);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
    const kept = await page.evaluate(() => {
      const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, height: r.height }; };
      const probe = document.createElement('i');
      probe.style.fontSize = 'var(--t-kept)';
      document.querySelector('.room-paper').append(probe);
      const token = getComputedStyle(probe).fontSize;
      probe.remove();
      return { paper: box('.room-paper'), footer: box('.room-paper .paper-foot'), actions: box('.kept-actions'),
        scroll: box('.kept-scroll'), heading: box('#kept h1'), receipt: box('#receipt'),
        top: box('#kept').top - box('.room-paper').top, title: getComputedStyle(document.querySelector('#kept h1')).fontSize,
        token, line: parseFloat(getComputedStyle(document.querySelector('.kept-text')).lineHeight) };
    });
    expect(kept.actions.bottom).toBeLessThanOrEqual(kept.footer.top);
    expect(kept.scroll.height).toBeGreaterThanOrEqual(kept.line - 0.5);
    expect(kept.heading.top).toBeGreaterThanOrEqual(kept.paper.top);
    expect(kept.receipt.bottom).toBeLessThanOrEqual(kept.actions.top);
    expect(kept.actions.bottom).toBeLessThanOrEqual(kept.scroll.top);
    if (compact) {
      expect(kept.top, 'the compact kept layout starts at 8 px').toBe(8);
      expect(kept.title, 'the compact kept title uses the compact token').toBe('34px');
    } else {
      expect(kept.top, 'the tall kept layout keeps the Mac 72 px offset').toBe(72);
      expect(kept.title, 'the tall kept title uses the Mac token').toBe(kept.token);
    }
    await capture(page, info, `kept-${size.width}x${size.height}`);
    await page.keyboard.press('Escape');
    await expect(page.locator('#exit-hint')).toHaveText(EXIT_HINT);
    const hinted = await page.evaluate(() => {
      const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom }; };
      return { footer: box('.room-paper .paper-foot'), scroll: box('.kept-scroll'),
        top: box('#kept').top - box('.room-paper').top };
    });
    if (hinted.top === 8) expect(hinted.scroll.bottom).toBeLessThanOrEqual(hinted.footer.top);
    else {
      expect(hinted.top, 'the tall kept layout keeps the Mac offset when the hint is armed').toBe(72);
      expect(hinted.scroll.bottom - hinted.footer.top, 'the tall kept bottom keeps its 24 px footer allowance').toBeCloseTo(24, 0);
    }
    await page.keyboard.press('Escape');
    await expect(page.locator('#landing')).toBeVisible();
  }
});

test('short rooms keep the writing aperture below the clock', async ({ page }, info) => {
  await page.setViewportSize({ width: info.project.use.viewport.width, height: 350 });
  await enter(page);
  await settle(page);
  const empty = await assertRoom(page);
  expect(empty.activeCentre).toBeGreaterThan(350 * 0.35);
  await page.keyboard.insertText('One\nTwo\nThree\nFour');
  await settle(page);
  const grown = await assertRoom(page);
  expect(Math.abs(grown.activeCentre - empty.activeCentre)).toBeLessThan(1);
});

test('the session bar is one continuous linear animation, never a stepped tick', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('A');
  const bar = await page.evaluate(() => {
    const bar = document.querySelector('#room-bar');
    return bar.getAnimations().map(animation => ({ timing: animation.effect.getTiming(),
      frames: animation.effect.getKeyframes().map(frame => frame.transform) }));
  });
  if (info.project.use.reducedMotion === 'reduce') {
    // Reduce Motion steps the remaining bar at a 0.5 s cadence instead of animating it.
    expect(bar).toHaveLength(0);
    const first = await page.locator('#room-bar').evaluate(bar => bar.style.transform);
    await page.clock.fastForward(600);
    const stepped = await page.locator('#room-bar').evaluate(bar => bar.style.transform);
    expect(stepped).not.toBe(first);
    await page.clock.fastForward(500);
    expect(await page.locator('#room-bar').evaluate(bar => bar.style.transform)).not.toBe(stepped);
    return;
  }
  expect(bar).toHaveLength(1);
  expect(bar[0].timing.easing).toBe('linear');
  expect(bar[0].frames).toHaveLength(2);
  const startScale = Number(/scaleX\(([^)]+)\)/.exec(bar[0].frames[0])?.[1]);
  expect(startScale).toBeGreaterThan(0.99);
  expect(startScale).toBeLessThanOrEqual(1);
  expect(bar[0].frames[1]).toBe('scaleX(0)');
  expect(bar[0].timing.duration).toBeGreaterThan(59000);
  expect(bar[0].timing.duration).toBeLessThanOrEqual(60000);
  const before = await page.locator('#room-bar').evaluate(bar => bar.style.transform);
  await page.clock.fastForward(1000);
  expect(await page.locator('#room-bar').evaluate(bar => bar.style.transform), 'a tick never writes the bar').toBe(before);
});

test('native zen input, deny, IME paths, warning, recovery and wipe', async ({ page }, info) => {
  await enter(page);
  await capture(page, info, 'empty');
  const emptyLine = await assertRoom(page);
  await page.keyboard.insertText('First line');
  await settle(page);
  await assertRoom(page);
  await capture(page, info, 'one-line');
  for (let line = 2; line <= 4; line++) {
    await page.keyboard.press('Enter');
    await page.keyboard.insertText(`Line ${line}`);
  }
  await settle(page);
  const grownLine = await assertRoom(page);
  expect(Math.abs(grownLine.activeCentre - emptyLine.activeCentre)).toBeLessThan(1);
  await capture(page, info, 'four-lines');
  await page.locator('#exit').click();
  await page.locator('#exit').click();
  await enter(page);
  for (const file of ['input-regression.js', 'zen-regression.js']) {
    const source = await readFile(new URL(file, import.meta.url), 'utf8');
    const results = await page.evaluate(`(${source})()`);
    expect(results.every(result => result.pass)).toBe(true);
  }
  await page.locator('#restart').evaluate(button => button.click());
  const text = 'A private messy draft keeps moving. 中文继续写。👨‍👩‍👧‍👦\n'.repeat(60) + 'The active line';
  await page.keyboard.insertText(text);
  await settle(page);
  await assertRoom(page);
  await capture(page, info, 'long-typing');
  const position = await editor(page).evaluate(e => e.scrollTop);
  await editor(page).hover();
  await page.mouse.wheel(0, -600);
  expect(await editor(page).evaluate(e => e.scrollTop)).toBe(position);
  // Playwright's clock controls session timers, not WAAPI's document timeline.
  // Freeze the refusal in the native key event, before runner latency can consume it.
  await page.evaluate(() => {
    document.addEventListener('keydown', () => {
      document.getAnimations().forEach(animation => { animation.pause(); animation.currentTime = 60; });
    }, { once: true });
  });
  await page.keyboard.press('Backspace');
  await expect(editor(page)).toHaveValue(text);
  const feedback = await page.evaluate(() => {
    const paper = document.querySelector('.room-paper');
    const hairline = document.querySelector('#room-hairline');
    return {
      shake: paper.getAnimations().map(animation => ({ duration: animation.effect.getTiming().duration,
        frames: animation.effect.getKeyframes() })),
      flash: hairline.getAnimations().map(animation => ({ duration: animation.effect.getTiming().duration,
        frames: animation.effect.getKeyframes() })),
    };
  });
  expect(feedback.shake.length + feedback.flash.length).toBeGreaterThan(0);
  expect(feedback.flash, 'the red hairline flash').toHaveLength(1);
  expect(feedback.flash[0].duration).toBe(220);
  const shake = feedback.shake[0];
  if (info.project.use.reducedMotion === 'reduce') expect(shake, 'Reduce Motion keeps only the flash').toBeUndefined();
  else {
    expect(shake.duration).toBe(200);
    expect(shake.frames.some(frame => frame.transform && frame.transform.includes('-3px'))).toBe(true);
    expect(shake.frames.every(frame => !frame.opacity)).toBe(true);
    expect(feedback.flash[0].frames.every(frame => !frame.transform), 'the flash is opacity-only').toBe(true);
  }
  // A repeated blocked key restarts the refusal instead of being dropped. Reduce Motion
  // has only the hairline flash to restart.
  const restarted = await page.evaluate(reduced => {
    const target = reduced ? document.querySelector('#room-hairline') : document.querySelector('.room-paper');
    const first = target.getAnimations()[0];
    document.querySelector('#editor').dispatchEvent(new KeyboardEvent('keydown', { key: 'Backspace', bubbles: true, cancelable: true }));
    const second = target.getAnimations()[0];
    return { same: first === second, count: target.getAnimations().length };
  }, info.project.use.reducedMotion === 'reduce');
  expect(restarted.count, 'one refusal animation, restarted').toBe(1);
  expect(restarted.same, 'the refusal restarts instead of being dropped').toBe(false);
  await capture(page, info, 'deny');
  for (const key of ['Delete', 'ControlOrMeta+x', 'ArrowUp', 'PageUp']) {
    await page.keyboard.press(key);
    await expect(editor(page)).toHaveValue(text);
  }
  await page.clock.fastForward(5500);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'warn');
  await assertRoom(page);
  await capture(page, info, 'warn-recovery-start');
  await page.keyboard.insertText(' Keep writing.');
  await expect(editor(page)).toHaveValue(text + ' Keep writing.');
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'typing');
  await settle(page);
  await capture(page, info, 'recovery');
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(editor(page)).toHaveValue('');
  await assertRoom(page);
  await capture(page, info, 'wipe-report');
  await page.locator('#exit').click();
  await expect(page.locator('#exit-hint')).toHaveText(EXIT_HINT);
  await expect(page.locator('#room')).toBeVisible();
  await page.locator('#exit').click();
  await expect(page.locator('#landing .cta a[href="#trial"]')).toBeFocused();
  await capture(page, info, 'exit');
});

test('exit needs two acts, inks the inline confirmation on the footer row, and typing cancels it', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('A draft worth keeping.');
  await settle(page);
  await page.keyboard.press('Escape');
  await expect(page.locator('#exit-hint')).toHaveText(EXIT_HINT);
  await expect(page.locator('#status')).toHaveText('');
  await expect(page.locator('#room')).toBeVisible();
  const row = await page.evaluate(() => ({
    exit: window.__run(document.querySelector('#exit'), 'text'),
    hint: window.__run(document.querySelector('#exit-hint'), 'text'),
    count: window.__run(document.querySelector('#room-count'), 'text'),
    tracking: getComputedStyle(document.querySelector('#exit-hint')).letterSpacing,
    exitTracking: getComputedStyle(document.querySelector('#exit')).letterSpacing,
  }));
  const narrow = page.viewportSize().width <= 767;
  if (narrow) {
    // A phone cannot truncate a destructive confirmation: the hint takes its own line.
    expect(row.hint.rect.bottom).toBeLessThanOrEqual(row.exit.rect.top + 1);
    const hintBox = await page.locator('#exit-hint').evaluate(e => ({ width: e.clientWidth, scrollWidth: e.scrollWidth }));
    expect(hintBox.scrollWidth, 'the confirmation is fully rendered').toBeLessThanOrEqual(hintBox.width + 1);
  } else {
    expect(Math.abs(row.hint.baseline - row.exit.baseline), 'one baseline on the exit row').toBeLessThan(1);
    expect(Math.abs(row.hint.baseline - row.count.baseline), 'one baseline on the exit row').toBeLessThan(1);
  }
  expect(row.tracking).toBe('normal');
  expect(parseFloat(row.exitTracking)).toBeGreaterThan(0);
  await capture(page, info, 'exit-hint');
  // Typing cancels the armed exit.
  await page.keyboard.insertText('!');
  await expect(page.locator('#exit-hint')).toHaveText('');
  await expect(page.locator('#room')).toBeVisible();
  // The window expires: after 2 s a single request only re-arms it.
  await page.locator('#exit').click();
  await expect(page.locator('#exit-hint')).toHaveText(EXIT_HINT);
  await page.clock.fastForward(2100);
  await expect(page.locator('#exit-hint')).toHaveText('');
  await expect(page.locator('#room')).toBeVisible();
  await page.locator('#exit').click();
  await expect(page.locator('#room')).toBeVisible();
  await page.locator('#exit').click();
  await expect(page.locator('#room')).toBeHidden();
});

test('kept screen: headline, quiet receipt, action row above a scrollable draft', async ({ page, context }, info) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await enter(page);
  await page.keyboard.insertText('This draft survives. 中文继续写。\n');
  for (let second = 0; second < 57; second += 3) {
    await page.clock.fastForward(3000);
    await page.keyboard.insertText('Keep going. ');
  }
  await page.clock.fastForward(3000);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
  await expect(page.locator('#kept h1')).toHaveText('You wrote it down.');
  const words = wordCount(await page.locator('#kept-text').textContent());
  await expect(page.locator('#receipt')).toHaveText(`1 MINUTE. ${words} WORDS.`);
  const kept = await page.evaluate(() => {
    const copy = document.querySelector('#copy');
    const restart = document.querySelector('#restart');
    const draft = document.querySelector('#kept-text');
    const heading = document.querySelector('#kept h1');
    const paper = document.querySelector('.room-paper').getBoundingClientRect();
    const style = getComputedStyle(copy);
    return {
      copy: window.__run(copy, 'text'), restart: window.__run(restart, 'text'),
      copyBox: copy.getBoundingClientRect().toJSON(), restartBox: restart.getBoundingClientRect().toJSON(),
      draftTop: draft.getBoundingClientRect().top, headingBottom: heading.getBoundingClientRect().bottom,
      paperCentre: paper.left + paper.width / 2,
      pill: { background: style.backgroundColor, radius: style.borderRadius, outlineOffset: style.outlineOffset,
        outlineWidth: style.outlineWidth, outlineColor: style.outlineColor, focused: copy.matches(':focus') },
      restartStyle: { height: getComputedStyle(restart).height, border: getComputedStyle(restart).borderWidth,
        background: getComputedStyle(restart).backgroundColor },
    };
  });
  // The actions sit in the fixed top block, above the draft, so a long draft never hides them.
  expect(kept.copyBox.bottom).toBeLessThan(kept.draftTop);
  expect(kept.headingBottom).toBeLessThan(kept.copyBox.top);
  // The pill hugs its label (24 px each side) and both controls share one 48 px row.
  expect(kept.copyBox.width - kept.copy.width).toBeGreaterThan(46);
  expect(kept.copyBox.width - kept.copy.width).toBeLessThan(50);
  expect(kept.copyBox.height).toBe(48);
  expect(kept.restartBox.height).toBe(48);
  // The draft can never push the actions: it scrolls in its own area under them.
  expect(await page.locator('.kept-scroll').evaluate(e => getComputedStyle(e).overflowY)).toBe('auto');
  const stacked = Math.abs(kept.copyBox.top - kept.restartBox.top) > 1;
  if (stacked) expect(kept.restartBox.top).toBeGreaterThanOrEqual(kept.copyBox.bottom); // a phone wraps the row
  else expect(Math.abs(kept.copyBox.top - kept.restartBox.top)).toBeLessThan(1);
  // One light ring on the pill edge: no dark margin outside an inset outline.
  expect(kept.pill.focused).toBe(true);
  expect(parseFloat(kept.pill.outlineOffset)).toBeLessThanOrEqual(-2);
  expect(kept.pill.outlineWidth).toBe('2px');
  expect(kept.restartStyle.background).not.toBe(kept.pill.background);
  await capture(page, info, 'kept');
  await page.locator('#copy').click();
  await expect(page.locator('#copy')).toHaveText('COPIED');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(await page.locator('#kept-text').textContent());
  const copied = await page.evaluate(() => ({
    copyBox: document.querySelector('#copy').getBoundingClientRect().toJSON(),
    restartBox: document.querySelector('#restart').getBoundingClientRect().toJSON(),
    paper: document.querySelector('.room-paper').getBoundingClientRect().toJSON(),
  }));
  expect(copied.copyBox.width, 'COPIED is narrower than COPY TEXT').toBeLessThan(kept.copyBox.width);
  // The narrower pill re-centres the row (on a phone the two controls wrap instead).
  if (!stacked) {
    expect(Math.abs((copied.copyBox.left + copied.restartBox.right) / 2 - (copied.paper.left + copied.paper.width / 2))).toBeLessThan(1);
  }
  await capture(page, info, 'copied');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await expect(page.locator('#room')).toBeHidden();
  await expect(page.locator('#landing .cta a[href="#trial"]')).toBeFocused();
  await capture(page, info, 'escape');
});

test('the failure screen restarts from the button and from Return', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('This one gets deleted.');
  await settle(page);
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(page.locator('#failed h1')).toHaveText('You stopped.');
  await expect(page.locator('#room-count')).toHaveText('0 words');
  expect(await page.locator('#failed').evaluate(el => el.getBoundingClientRect().top - el.closest('.room-paper').getBoundingClientRect().top), 'the failure block keeps the Mac offset on a tall sheet').toBe(72);
  const row = await page.evaluate(() => {
    const button = document.querySelector('#begin-again');
    const box = button.getBoundingClientRect();
    return { height: box.height, text: button.textContent, border: getComputedStyle(button).borderWidth,
      background: getComputedStyle(button).backgroundColor };
  });
  expect(row.text).toBe('Begin again');
  expect(row.height).toBe(48);
  expect(row.border).toBe('1px');
  await capture(page, info, 'stopped');
  const heading = await page.locator('#failed h1').boundingBox();
  await page.mouse.click(heading.x + heading.width / 2, heading.y + heading.height / 2);
  await expect(editor(page)).toBeFocused();
  const report = await page.locator('#room-report').boundingBox();
  await page.mouse.click(report.x + report.width / 2, report.y + report.height / 2);
  await expect(editor(page)).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'rest');
  await expect(editor(page)).toHaveValue('');
  await expect(editor(page)).toBeFocused();
  await expect(page.locator('#room-count')).toHaveText('Type to start');
  await page.keyboard.insertText('Another one.');
  await settle(page);
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await page.locator('#begin-again').click();
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'rest');
  await expect(editor(page)).toBeFocused();
});

test('demo is forward-only: every event appends, Backspace is tried once and blocked', async ({ page }, info) => {
  const events = TIMELINE.events;
  expect(events.some(event => event.kind === 'back')).toBe(false);
  for (let i = 1; i < events.length; i++) {
    const [before, after] = [events[i - 1], events[i]];
    if (after.dn === before.dn) expect(after.cur.startsWith(before.cur), `${before.cur} -> ${after.cur}`).toBe(true);
    else expect(after.dn).toBe(before.dn + 1);
  }
  const denies = events.filter(event => event.kind === 'deny');
  expect(denies).toHaveLength(1);
  const deny = denies[0];
  expect(deny.cur).toBe("i'm just prete");
  expect(TIMELINE.typeEnd).toBeLessThan(15000);
  test.skip(info.project.use.reducedMotion === 'reduce', 'reduced motion renders the static draft');
  expect(await page.locator('#deny-key').count(), 'the demo carries no keycap affordance').toBe(0);
  const typed = count => `${count} ${count === 1 ? 'word' : 'words'}`;
  await expect(page.locator('#count')).toHaveText('Type to start');
  let at = 0;
  const seek = async ms => { await page.clock.fastForward(ms - at); at = ms; };
  await seek(deny.t - 100);
  // A visitor's own Backspace never edits the demo either.
  await page.locator('body').click({ position: { x: 5, y: 5 } });
  await page.keyboard.press('Backspace');
  await expect(page.locator('#cur')).toHaveText(deny.cur);
  await seek(deny.t + 55);
  await expect(page.locator('#cur')).toHaveText(deny.cur);
  // The refusal is the room's refusal: a 200 ms transform-only shake and a 220 ms
  // opacity-only red hairline, with no keycap theatre.
  const refusal = await page.evaluate(() => ({
    shake: document.querySelector('#paper').getAnimations().map(a => ({ duration: a.effect.getTiming().duration,
      frames: a.effect.getKeyframes() })),
    flash: document.querySelector('#demo-hairline').getAnimations().map(a => ({ duration: a.effect.getTiming().duration })),
  }));
  expect(refusal.shake).toHaveLength(1);
  expect(refusal.shake[0].duration).toBe(200);
  expect(refusal.shake[0].frames.some(frame => frame.transform && frame.transform.includes('-3px'))).toBe(true);
  expect(refusal.flash).toHaveLength(1);
  expect(refusal.flash[0].duration).toBe(220);
  // The counter is the true count of everything typed so far (lines that scrolled up included), like the room.
  await expect(page.locator('#count')).toHaveText(typed(wordCount(LINES.slice(0, deny.dn).concat(deny.cur).join(' '))));
  await capture(page, info, 'demo-deny');
  await seek(deny.t + 700);
  await expect(page.locator('#cur')).toHaveText(deny.cur);
  await seek(TIMELINE.typeEnd + 100);
  await expect(page.locator('#prev-0')).toHaveText("i'm just prete pretending.");
  await expect(page.locator('#prev-1')).toHaveText(LINES[1]);
  await expect(page.locator('#count')).toHaveText(typed(wordCount(LINES.join(' '))));
});

test('demo loop: warning group, cut, and the failure screen in the status slot', async ({ page }, info) => {
  await expect(page.locator('#demo-key')).toHaveCount(0);
  const typeEnd = TIMELINE.typeEnd;
  let at = 0;
  const seek = async ms => { await page.clock.fastForward(ms - at); at = ms; };
  if (info.project.use.reducedMotion !== 'reduce') await seek(typeEnd + 250);
  await expect(page.locator('#prev-0')).toHaveText(LINES[2]);
  await expect(page.locator('#cur')).toHaveText(LINES[3]);
  // The history ladder is the room's ladder: 22% one line up, 7% two lines up.
  const ladder = await page.evaluate(() => [...document.querySelectorAll('.prev-line')].map(e => getComputedStyle(e).opacity));
  expect(ladder).toEqual(['0.22', '0.07']);
  // No second bar: the 3 pt silence meter is gone.
  await expect(page.locator('#meter')).toHaveCount(0);
  const bars = await page.evaluate(() => [...document.querySelectorAll('#demo .bar, #demo .meter')].map(e => e.getBoundingClientRect().height));
  expect(bars).toEqual([2]);
  await capture(page, info, 'demo-typing');
  await expect(page.locator('#warn')).toBeHidden();
  await expect(page.locator('#demo-stopped')).toBeHidden();
  if (info.project.use.reducedMotion === 'reduce') {
    await page.clock.fastForward(30000);
    await expect(page.locator('#clock')).toHaveText('1:00');
    await expect(page.locator('#cur')).toHaveText(LINES[3]);
    return;
  }
  for (const [offset, numeral] of [[150, '3'], [1150, '2'], [2150, '1']]) {
    await seek(SILENT_END + offset);
    await expect(page.locator('#paper')).toHaveClass(/warn/);
    await expect(page.locator('#numeral')).toHaveText(numeral);
    await expect(page.locator('#warn-caption')).toHaveText('KEEP TYPING OR THE DRAFT IS DELETED.');
  }
  const warning = await page.evaluate(() => {
    const script = window.__run(document.querySelector('.script'));
    return { numeral: window.__run(document.querySelector('#numeral')),
      caption: window.__run(document.querySelector('#warn-caption')), baseline: script.baseline };
  });
  expect(warning.numeral.inkTop - warning.baseline, 'demo numeral ink under the writing baseline').toBeGreaterThan(40);
  expect(warning.numeral.inkTop - warning.baseline).toBeLessThan(48);
  expect(warning.caption.inkTop - (warning.numeral.inkTop + warning.numeral.inkHeight)).toBeGreaterThan(16);
  expect(warning.caption.inkTop - (warning.numeral.inkTop + warning.numeral.inkHeight)).toBeLessThan(26);
  await capture(page, info, 'demo-warn');
  await seek(WARN_END + 100);
  await expect(page.locator('#paper')).toHaveClass(/cut/);
  await expect(page.locator('#warn')).toBeHidden();
  await expect(page.locator('#demo-stopped')).toBeHidden();
  await expect(page.locator('#count')).toHaveText('0 words');
  await capture(page, info, 'demo-cut');
  await seek(CUT_END + 300);
  await expect(page.locator('#demo-stopped')).toBeVisible();
  await expect(page.locator('#warn')).toBeHidden();
  await expect(page.locator('#demo-stopped .stopped')).toHaveText('You stopped.');
  expect(await page.locator('#demo-stopped').evaluate(el => el.getBoundingClientRect().top - el.closest('.paper').getBoundingClientRect().top), 'the demo failure block keeps the Mac offset on a tall sheet').toBe(72);
  const reportLook = await page.evaluate(() => {
    const probe = name => {
      const i = document.createElement('i');
      i.style.color = getComputedStyle(document.querySelector('#demo')).getPropertyValue(name);
      document.querySelector('#demo').append(i);
      const color = getComputedStyle(i).color; i.remove(); return color;
    };
    return {
      title: getComputedStyle(document.querySelector('#demo-stopped .stopped')).color,
      ink: probe('--ink'),
      tracking: getComputedStyle(document.querySelector('#clock')).letterSpacing,
    };
  });
  expect(reportLook.title).toBe(reportLook.ink);
  expect(reportLook.tracking).toBe('normal');
  await expect(page.locator('#report')).toContainText(`DRAFT DELETED AT 0:${60 - Math.round(CUT_END / 1000)}. TYPE TO START AGAIN`);
  await expect(page.locator('#count')).toHaveText('0 words');
  const receipt = await page.evaluate(() => {
    const script = window.__run(document.querySelector('.script'));
    return { report: window.__run(document.querySelector('#report')), baseline: script.baseline };
  });
  expect(receipt.report.inkTop - receipt.baseline, 'the receipt takes the status slot under the line').toBeGreaterThan(40);
  expect(receipt.report.inkTop - receipt.baseline).toBeLessThan(48);
  await capture(page, info, 'demo-report');
  await seek(CUT_END + 2700);
  await expect(page.locator('#cur')).not.toHaveText('');
});

test('the demo danger group clears when a new loop reaches typing', async ({ page }, info) => {
  test.skip(info.project.use.reducedMotion === 'reduce', 'the static demo never loops');
  await page.clock.fastForward(SILENT_END + 150);
  await expect(page.locator('#warn')).toBeVisible();
  await expect(page.locator('#warn-caption')).toHaveText('KEEP TYPING OR THE DRAFT IS DELETED.');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await expect(page.locator('#room')).toBeVisible();
  await page.clock.fastForward(CUT_END + 2000 - (SILENT_END + 150) + 1000);
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await expect(page.locator('#landing')).toBeVisible();
  await page.clock.runFor(100);
  await expect(page.locator('#warn')).toBeHidden();
  await expect(page.locator('#warn-caption')).toHaveText('');
  await expect(page.locator('#demo-stopped')).toBeHidden();
});

test('short demo sheets keep the status slot inside the paper', async ({ page }, info) => {
  test.skip(info.project.use.reducedMotion === 'reduce', 'the static demo has no warning or report');
  await page.setViewportSize({ width: 844, height: 390 });
  await page.reload();
  await page.evaluate(() => document.fonts.ready);
  await page.clock.fastForward(SILENT_END + 150);
  await expect(page.locator('#warn')).toBeVisible();
  const warning = await page.evaluate(() => {
    const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom }; };
    const line = document.querySelector('.script');
    const lineTop = line.getBoundingClientRect().top;
    return { paper: box('#paper'), footer: box('#paper .paper-foot'), danger: box('#warn'), caption: box('#warn-caption'),
      lineTop, lineBottom: lineTop + parseFloat(getComputedStyle(line).lineHeight) };
  });
  expect(warning.danger.top).toBeGreaterThanOrEqual(warning.paper.top);
  expect(warning.danger.bottom <= warning.lineTop || warning.danger.top >= warning.lineBottom, 'the warning group does not cover the active line').toBe(true);
  expect(warning.danger.bottom).toBeLessThanOrEqual(warning.footer.top);
  await page.clock.fastForward(CUT_END - (SILENT_END + 150) + 300);
  await expect(page.locator('#demo-stopped')).toBeVisible();
  const report = await page.evaluate(() => {
    const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom }; };
    return { paper: box('#paper'), footer: box('#paper .paper-foot'), block: box('#demo-stopped'), receipt: box('#report') };
  });
  expect(report.block.top).toBeGreaterThanOrEqual(report.paper.top);
  expect(report.block.bottom).toBeLessThanOrEqual(report.receipt.top);
  expect(report.receipt.top).toBeGreaterThanOrEqual(report.paper.top);
  expect(report.receipt.bottom).toBeLessThanOrEqual(report.footer.top);
  await capture(page, info, 'short-demo-report');
});

test('the room wears the landing design system', async ({ page }) => {
  await enter(page);
  const look = await page.evaluate(() => {
    const css = s => getComputedStyle(document.querySelector(s));
    const probe = name => {
      const i = document.createElement('i');
      i.style.color = getComputedStyle(document.querySelector('#room')).getPropertyValue(name);
      document.querySelector('#room').append(i);
      const c = getComputedStyle(i).color; i.remove(); return c;
    };
    return {
      page: css('#room').backgroundColor, pageToken: probe('--page'),
      sheet: css('.room-paper').backgroundColor, sheetToken: probe('--sheet'),
      sheetShadow: css('.room-paper').boxShadow, roomShadow: css('#room').boxShadow,
      writing: css('#editor').fontFamily, tool: ['#room-clock', '#room-count', '#exit'].map(s => css(s).fontFamily),
      washes: document.querySelectorAll('#room .wash').length,
    };
  });
  expect(look.page).toBe(look.pageToken);
  expect(look.sheet).toBe(look.sheetToken);
  expect(look.sheetShadow).not.toBe('none');
  expect(look.roomShadow).toBe('none');
  expect(look.writing).toMatch(/^"?Newsreader/);
  for (const family of look.tool) expect(family).toMatch(/system-ui/);
  expect(look.washes, 'the warning wash lives on the sheet only').toBe(1);
  await expect(page.locator('#room .home-nav [data-theme-toggle]')).toBeVisible();
  await page.locator('#room [data-theme-toggle]').click();
  await expect(editor(page), 'switching theme hands focus back to the writing').toBeFocused();
});
