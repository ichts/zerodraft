import { doorSettled } from './door.mjs';
import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { LINES, TIMELINE } from '../demo-timeline.mjs';
import { clock, wordCount, countLabel } from '../session.mjs';
import { barFraction } from './bar-clip.mjs';

const capture = (page, info, state) => page.screenshot({ path: info.outputPath(`${state}.png`) });
const editor = page => page.locator('#editor');
const browserEvidence = new WeakMap();
const demoGeometry = new WeakMap();
// The exit names the act the input can perform; width only decides layout (D-067).
const EXIT_HINT = {
  keyboard: 'Press Esc again to leave and delete the draft.',
  touch: 'Tap EXIT again to leave and delete the draft.',
};
const touchInput = page => page.evaluate(() => matchMedia('(hover: none), (any-pointer: coarse)').matches);
const exitHintFor = async page => ((await touchInput(page)) ? EXIT_HINT.touch : EXIT_HINT.keyboard);
const SILENT_END = TIMELINE.typeEnd + 5000;
const WARN_END = SILENT_END + 3000;
const CUT_END = WARN_END + 200;

const rgb = value => String(value).match(/[\d.]+/g).slice(0, 3).map(Number);
const luminance = colour => {
  const [r, g, b] = rgb(colour).map(v => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

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
  await doorSettled(page);
  await expect(editor(page)).toBeFocused();
}

// The line-shift animation runs on rAF, which a paused fake clock freezes: settle it
// explicitly before measuring the settled geometry.
async function settle(page, ms = 400) {
  await page.clock.fastForward(ms);
}

test('CJK counts words and kept actions use sentence case', async ({ page }, info) => {
  await page.goto('index.html');
  await enter(page);
  await page.keyboard.insertText('我们是');
  await expect(page.locator('#room-count')).toHaveText('3 words');
  await capture(page, info, 'cjk-count');
  for (let i = 0; i < 11; i++) {
    await page.clock.fastForward(5000);
    await page.keyboard.insertText('我');
  }
  await page.clock.fastForward(5000);
  await expect(page.locator('#receipt')).toHaveText('1 minute. 14 words.');
  await expect(page.locator('#restart')).toHaveText('Begin again');
  await expect(page.locator('#copy-label')).toHaveText('Copy text');
  await capture(page, info, 'cjk-kept');
  await page.locator('#copy').click();
  await expect(page.locator('#copy-label')).toHaveText('Copied');
  await capture(page, info, 'cjk-copied');
});

async function assertRoom(page) {
  const geometry = await editor(page).evaluate(e => {
    const style = getComputedStyle(e);
    const line = parseFloat(style.lineHeight);
    const rect = e.getBoundingClientRect();
    const paper = e.closest('.room-paper').getBoundingClientRect();
    const write = window.__writingLine();
    return {
      height: e.clientHeight, line, overflow: style.overflowY, scrollbar: style.scrollbarWidth,
      mask: getComputedStyle(e.closest('.editor-stack')).maskImage || getComputedStyle(e.closest('.editor-stack')).webkitMaskImage,
      activeCentre: write.centre, ratio: (write.centre - paper.top) / paper.height,
      paperHeight: paper.height, paperTop: paper.top,
      fallback: 44 + 2.5 * line,
      history: [Number(style.getPropertyValue('--paper-history-1')), Number(style.getPropertyValue('--paper-history-2'))],
      apertureTop: write.top, chromeBottom: e.closest('.room-paper').querySelector('.chrome-row').getBoundingClientRect().bottom,
      pageHeight: document.documentElement.scrollHeight, viewportHeight: innerHeight,
      pageWidth: document.documentElement.scrollWidth, viewportWidth: innerWidth,
      bars: [...document.querySelectorAll('#room .bar, #room .meter, #room .session-bar')].map(bar => {
        const box = bar.getBoundingClientRect();
        return { cls: bar.className, top: box.top, height: box.height, width: box.width, paperTop: paper.top,
          border: getComputedStyle(bar).borderTopWidth };
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
  // One 2 pt border-top bar (its box spans the corner radius) pinned to the paper top; the 3 pt silence meter is gone (D-014).
  expect(geometry.bars).toHaveLength(1);
  expect(geometry.bars[0].border).toBe('2px');
  expect(Math.abs(geometry.bars[0].top - geometry.bars[0].paperTop)).toBeLessThan(1);
  // The aperture is one hard clip at the third pitch (the live line and the two history lines above it); the
  // history steps live on the ink layer's spans per logical line (D-077, qa/history-fade.spec.mjs), so the
  // clip carries no alpha band of its own and a partial line is cut, never faded.
  expect(geometry.mask, 'the aperture clip').toMatch(/#?rgb\(0, 0, 0\) [\d.]+px, rgba\(0, 0, 0, 0\) [\d.]+px/);
  const stops = [...geometry.mask.matchAll(/([\d.]+)px/g)].map(match => parseFloat(match[1]));
  expect(stops, geometry.mask).toHaveLength(2);
  stops.forEach(stop => expect(Math.abs(stop - 3 * geometry.line), geometry.mask).toBeLessThan(1.1));

  expect(geometry.pageHeight).toBe(geometry.viewportHeight);
  expect(geometry.pageWidth).toBe(geometry.viewportWidth);
  return geometry;
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
  // Every width measured below depends on the face the device renders, so the faces must be loaded
  // first and the test asserts it instead of trusting a sleep (D-059). A face the page uses stays
  // `unloaded` only when it is a variant nothing asked for; `loading` or `error` is a real failure,
  // and the two families the page owns must each have a loaded face.
  const fonts = await page.evaluate(async () => {
    await document.fonts.ready;
    return { status: document.fonts.status,
      faces: [...document.fonts].map(face => ({ family: face.family.replace(/["']/g, ''), status: face.status })) };
  });
  expect(fonts.status, 'the declared faces are loaded before a width is measured').toBe('loaded');
  expect(fonts.faces.filter(face => face.status !== 'loaded' && face.status !== 'unloaded'), JSON.stringify(fonts.faces)).toEqual([]);
  for (const family of ['Newsreader', 'Reenie Beanie']) {
    expect(fonts.faces.some(face => face.family === family && face.status === 'loaded'), `${family} loaded`).toBe(true);
  }
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

// The insertion point as it is actually drawn: the caret's own colour and the product of every
// ancestor's opacity, so a test can tell a painted caret from one the stopped sheet hides (D-070).
const insertionPoint = page => page.evaluate(() => {
  const e = document.querySelector('#editor');
  let node = e, opacity = 1;
  while (node && node !== document.body) { opacity *= parseFloat(getComputedStyle(node).opacity); node = node.parentElement; }
  const style = getComputedStyle(e);
  const painted = (color) => {
    const match = color.match(/rgba?\(([^)]+)\)/);
    if (!match) return false;
    const parts = match[1].split(',').map(part => parseFloat(part));
    return (parts.length < 4 ? 1 : parts[3]) > 0;
  };
  return { opacity, caret: painted(style.caretColor), ink: painted(getComputedStyle(document.querySelector('#editor-ink')).color),
    focused: document.activeElement === e, collapsed: e.selectionStart === e.selectionEnd };
});

test('empty room shows only the caret and the count prompt; after a wipe the block states it', async ({ page }, info) => {
  await enter(page);
  await settle(page);
  await expect(page.locator('#room-count')).toHaveText('Type to begin');
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
  const emptyPoint = await insertionPoint(page);
  expect(emptyPoint).toEqual({ opacity: 1, caret: true, ink: true, focused: true, collapsed: true });
  await capture(page, info, 'empty-focused');
  await page.keyboard.insertText('i');
  await expect(page.locator('#room-count')).toHaveText('1 word');
  await capture(page, info, 'first-char');
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(page.locator('#room-count')).toHaveText('0 words');
  await expect(page.locator('#failed h1')).toHaveText('You stopped.');
  await expect(page.locator('#failure-note')).toHaveText('Draft deleted.');
  await expect(page.locator('#begin-again')).toBeVisible();
  // The stopped sheet keeps the editor focused, so typing restarts in place, but its writing layer
  // is transparent: no caret is drawn inside the stopped group (D-070 supersedes D-065).
  await expect(editor(page)).toBeFocused();
  const wipedPoint = await insertionPoint(page);
  expect(wipedPoint).toEqual({ ...emptyPoint, opacity: 0 });
  // Session chrome is off on the stopped sheet: the clock is not frozen as a receipt (D-070).
  const chrome = () => page.locator('#room .chrome-row').evaluate(el => getComputedStyle(el).visibility);
  expect(await chrome()).toBe('hidden');
  await capture(page, info, 'wipe-report');
  await page.keyboard.insertText('A');
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'typing');
  await expect(page.locator('#room-clock')).toHaveText('1:00');
  expect(await chrome()).toBe('visible');
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
  await expect(page.locator('#room-count')).toHaveText(countLabel('First line typed on the same line\nLine 2\nLine 3\nLine 4\n中文继续写。'));
});

test('warning numeral and caption are placed by ink under the writing line', async ({ page }, info) => {
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
  await capture(page, info, 'deleted');
});

test('mobile dynamic viewport keeps EXIT and word count visible with expanded toolbars', async ({ page }, info) => {
  test.skip(info.project.use.viewport.width !== 390, 'Mobile toolbar geometry');
  for (const [state, height] of [['collapsed', 844], ['expanded', 664], ['collapsed-again', 844]]) {
    await page.setViewportSize({ width: 390, height });
    const demo = await page.locator('.script').evaluate(e => {
      const line = e.getBoundingClientRect();
      const sheet = e.closest('.paper').getBoundingClientRect();
      const first = document.querySelector('.first-screen').getBoundingClientRect();
      return { height: sheet.height, bottom: sheet.bottom, firstBottom: first.bottom, firstHeight: first.height,
        viewport: innerHeight, ratio: (line.top + line.height / 2 - sheet.top) / sheet.height };
    });
    expect(demo.firstHeight, `${state}: the first screen fills the viewport`).toBeGreaterThanOrEqual(demo.viewport - 0.5);
    expect(demo.height, `${state}: the sheet keeps its 300 px floor`).toBeGreaterThanOrEqual(300 - 0.5);
    expect(Math.abs(demo.bottom - demo.firstBottom), `${state}: the sheet owns the space the door leaves`).toBeLessThanOrEqual(1);
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
    await expect(page.locator('#landing .cta a[href="#trial"]')).toBeFocused();
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

// 320x568 is the smallest phone the room claims to hold, and nothing measured its stopped screen: the compact kept
// layout (status-slot.js) runs there, where the title, the receipt, two pills, the note and the draft all share 470 px
// of paper. Nothing may leave the sheet, the page may not scroll, and every control has to stay on screen.
test('the stopped screen holds on the smallest phone', async ({ page }, info) => {
  test.skip(info.project.name !== '390-light-no-preference', 'One project owns the smallest-phone geometry');
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  await enter(page);
  await page.keyboard.insertText('a');
  for (let i = 0; i < 11; i++) {
    await page.clock.fastForward(5000);
    await page.keyboard.insertText(' a');
  }
  await page.clock.fastForward(5100);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
  const kept = await page.evaluate(() => {
    const box = selector => { const el = document.querySelector(selector); const r = el.getBoundingClientRect();
      return { top: r.top, bottom: r.bottom, left: r.left, right: r.right, width: r.width, height: r.height,
        viewportWidth: innerWidth, viewportHeight: innerHeight }; };
    return { paper: box('#room .room-paper'), title: box('#kept h1'), receipt: box('#receipt'), copy: box('#copy'),
      restart: box('#restart'), note: box('#kept-note'), draft: box('#kept-text'), exit: box('#exit'),
      scrollHeight: document.documentElement.scrollHeight, viewportHeight: innerHeight, scrollWidth: document.documentElement.scrollWidth };
  });
  expect(kept.scrollWidth, 'the smallest phone does not scroll sideways').toBeLessThanOrEqual(320);
  expect(kept.scrollHeight, 'the stopped screen fits the smallest phone without a page scroll').toBeLessThanOrEqual(kept.viewportHeight);
  for (const [name, part] of Object.entries({ receipt: kept.receipt, copy: kept.copy, restart: kept.restart, note: kept.note, draft: kept.draft })) {
    expect(part.width, `${name} has width`).toBeGreaterThan(0);
    expect(part.top, `${name} starts inside the sheet`).toBeGreaterThanOrEqual(kept.paper.top - 0.5);
    expect(part.bottom, `${name} ends inside the sheet`).toBeLessThanOrEqual(kept.paper.bottom + 0.5);
    expect(part.left, `${name} starts inside the sheet`).toBeGreaterThanOrEqual(kept.paper.left - 0.5);
    expect(part.right, `${name} ends inside the sheet`).toBeLessThanOrEqual(kept.paper.right + 0.5);
  }
  // The kept column reads top down on one centre line, and the receipt closes on the draft rather than the note
  // being pushed out: a squeezed compact layout must not reorder or overlap anything.
  expect(kept.title.bottom, 'the title comes before the receipt').toBeLessThanOrEqual(kept.receipt.top + 0.5);
  expect(kept.receipt.bottom, 'the receipt comes before the copy pill').toBeLessThanOrEqual(kept.copy.top + 0.5);
  expect(kept.copy.bottom, 'the copy pill comes before the restart pill').toBeLessThanOrEqual(kept.restart.top + 0.5);
  expect(kept.restart.bottom, 'the restart pill comes before the note').toBeLessThanOrEqual(kept.note.top + 0.5);
  expect(kept.note.bottom, 'the note comes before the draft').toBeLessThanOrEqual(kept.draft.top + 0.5);
  expect(kept.draft.bottom, 'the draft comes before the exit row').toBeLessThanOrEqual(kept.exit.top + 0.5);
  expect(kept.exit.bottom, 'the exit row stays on screen').toBeLessThanOrEqual(kept.viewportHeight);
  await capture(page, info, 'kept-320x568');
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
      return { paper: box('.room-paper'), footer: box('.room-paper .paper-foot'), block: box('#failed') };
    });
    expect(failure.block.top).toBeGreaterThanOrEqual(failure.paper.top);
    expect(failure.block.bottom).toBeLessThanOrEqual(failure.footer.top);
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
    { width: 320, height: 568 },
    { width: 390, height: 844 },
    { width: 767, height: 900 },
    { width: 1440, height: 620 },
  ];
  const compactSizes = new Set(['1440x350', '844x390', '667x375']);
  for (const size of sizes) {
    const compact = compactSizes.has(`${size.width}x${size.height}`);
    await page.setViewportSize(size);
    await enter(page);
    await page.keyboard.insertText('This draft survives on a short sheet.\n');
    for (let second = 0; second < 57; second += 3) {
      await page.clock.fastForward(3000);
      await page.keyboard.insertText('Keep going. '.repeat(5));
    }
    await page.clock.fastForward(3000);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
    const forced = [320, 390, 767].includes(size.width);
    if (forced) {
      await page.locator('#exit-hint').evaluate(e => {
        const width = document.querySelector('.room-paper .paper-foot').clientWidth;
        const pad = Math.max(0, (width - 150) / 2);
        e.style.paddingLeft = `${pad}px`;
        e.style.paddingRight = `${pad}px`;
      });
      await page.evaluate(() => window.dispatchEvent(new Event('resize')));
    }
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
    expect(await page.locator('.kept-scroll').evaluate(e => e.scrollHeight > e.clientHeight), 'the kept box is filled for the clearance check').toBe(true);
    if (compact) {
      expect(kept.top, 'the compact kept layout starts at 8 px').toBe(8);
      expect(kept.title, 'the compact kept title uses the compact token').toBe('34px');
    } else {
      expect(kept.top, 'the tall kept layout keeps the Mac 72 px offset').toBe(72);
      expect(kept.title, 'the tall kept title uses the Mac token').toBe(kept.token);
    }
    await capture(page, info, `kept-${size.width}x${size.height}`);
    // A fallback font can wrap the receipt onto a second line, making the fixed block
    // above the draft taller: the Linux runner reserved one extra line and left 30.4 px
    // of a 33.6 px draft line. The draft keeps a full line anyway - the kept screen's
    // own gaps give way - and the stress is undone before the confirmation checks below.
    if (size.width === 320) {
      const squeezed = await page.evaluate(() => {
        const receipt = document.querySelector('.kept-receipt');
        const lineBox = parseFloat(getComputedStyle(receipt).lineHeight);
        receipt.style.paddingTop = `${lineBox}px`;
        window.dispatchEvent(new Event('resize'));
        const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, height: r.height }; };
        const scroller = document.querySelector('.kept-scroll');
        scroller.scrollTop = 0;
        // The draft's own first rendered line, as the face on this machine draws it.
        const range = document.createRange();
        range.selectNodeContents(document.querySelector('.kept-text'));
        const first = range.getClientRects()[0];
        return { scroll: box('.kept-scroll'), lineBox, firstLine: { top: first.top, bottom: first.bottom, height: first.height },
          receipt: box('#receipt'), actions: box('.kept-actions') };
      });
      expect(squeezed.receipt.height, 'the stress adds one receipt line above the draft').toBeGreaterThanOrEqual(20.8 + squeezed.lineBox - 1);
      expect(squeezed.firstLine.height, 'the draft renders a measurable first line').toBeGreaterThan(0);
      expect(squeezed.firstLine.top, 'the first draft line starts inside the kept box').toBeGreaterThanOrEqual(squeezed.scroll.top - 0.5);
      expect(squeezed.firstLine.bottom, 'a taller fixed block still leaves one full line of the kept draft')
        .toBeLessThanOrEqual(squeezed.scroll.bottom + 0.5);
      await page.locator('.kept-receipt').evaluate(e => { e.style.paddingTop = ''; });
      await page.evaluate(() => window.dispatchEvent(new Event('resize')));
      const restored = await page.evaluate(() => document.querySelector('.kept-scroll').getBoundingClientRect().height);
      expect(restored, 'undoing the stress restores the kept geometry').toBeCloseTo(kept.scroll.height, 0);
    }
    await page.keyboard.press('Escape');
    await expect(page.locator('#exit-hint')).toHaveText(await exitHintFor(page));
    await page.evaluate(() => window.dispatchEvent(new Event('resize')));
    const hinted = await page.evaluate(() => {
      const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, height: r.height }; };
      return { footer: box('.room-paper .paper-foot'), scroll: box('.kept-scroll'), actions: box('.kept-actions'),
        heading: box('#kept h1'), receipt: box('#receipt'), hint: box('#exit-hint'),
        hintLine: parseFloat(getComputedStyle(document.querySelector('#exit-hint')).lineHeight),
        top: box('#kept').top - box('.room-paper').top,
        title: getComputedStyle(document.querySelector('#kept h1')).fontSize };
    });
    expect(hinted.top, 'the confirmation does not change the kept layout mode').toBe(kept.top);
    expect(hinted.title, 'the confirmation does not change the kept title').toBe(kept.title);
    expect(hinted.heading.top).toBeCloseTo(kept.heading.top, 0);
    expect(hinted.receipt.top).toBeCloseTo(kept.receipt.top, 0);
    expect(hinted.actions.top).toBeCloseTo(kept.actions.top, 0);
    expect(hinted.scroll.top).toBeCloseTo(kept.scroll.top, 0);
    expect(hinted.scroll.bottom, 'the confirmation does not move the kept placement').toBeCloseTo(kept.scroll.bottom, 0);
    if (forced) expect(hinted.hint.height, 'the forced confirmation is two lines').toBeGreaterThanOrEqual(hinted.hintLine * 2 - 1);
    if (compact) expect(hinted.scroll.bottom).toBeLessThanOrEqual(hinted.footer.top);
    expect(hinted.scroll.bottom, 'the confirmation never covers the kept draft').toBeLessThanOrEqual(hinted.hint.top);
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

test('the session bar drains continuously, never in steps', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('A');
  // The rendered bar, not the animation object: whatever drives it, the writer sees a bar that has moved a little
  // further every quarter second. A stepped tick stands still between ticks and then jumps, which is exactly what
  // reading the rendered value twice per half second catches - one 500 ms sample cannot tell a 500 ms step from a
  // continuous drain.
  const remaining = async () => barFraction(await page.locator('#room-bar')
    .evaluate(bar => getComputedStyle(bar).clipPath));
  if (info.project.use.reducedMotion === 'reduce') {
    // Reduce Motion is the one place a step is the intended behaviour: the bar holds still between the 0.5 s ticks
    // and moves at each one.
    const held = await remaining();
    await page.waitForTimeout(250);
    expect(await remaining(), 'the bar moved between two reduced-motion ticks').toBe(held);
    await page.clock.fastForward(500);
    const ticked = await remaining();
    expect(ticked, 'the bar did not step at the 0.5 s tick').not.toBe(held);
    await page.waitForTimeout(250);
    expect(await remaining(), 'the bar moved between two reduced-motion ticks').toBe(ticked);
    return;
  }
  let previous = await remaining();
  for (let index = 0; index < 8; index += 1) {
    for (const wait of [250, 250]) {
      await page.waitForTimeout(wait);
      const now = await remaining();
      const drop = previous - now;
      expect(drop, `the bar stood still ${index * 500 + wait} ms in: ${previous} then ${now}`).toBeGreaterThan(0.0005);
      expect(drop, `the bar jumped ${index * 500 + wait} ms in: ${previous} then ${now}`).toBeLessThan(0.03);
      previous = now;
    }
  }
});

test('the session bar is the paper\'s own rounded top edge at every fill', async ({ page }) => {
  await enter(page);
  await page.keyboard.insertText('A');
  await settle(page);
  const geometry = () => page.evaluate(() => {
    const paper = document.querySelector('#room .room-paper');
    const bar = document.querySelector('#room-bar');
    const p = paper.getBoundingClientRect();
    const b = bar.getBoundingClientRect();
    const s = getComputedStyle(bar);
    const radius = parseFloat(getComputedStyle(paper).borderTopLeftRadius);
    return { left: b.left - p.left, right: p.right - b.right, top: b.top - p.top, radius,
      border: s.borderTopWidth, barRadius: [s.borderTopLeftRadius, s.borderTopRightRadius],
      side: [s.borderLeftWidth, s.borderRightWidth], clip: s.clipPath, overflow: getComputedStyle(paper).overflow };
  });
  const full = await geometry();
  expect(full.left, 'the bar starts at the card edge').toBe(0);
  expect(full.right, 'the bar ends at the card edge').toBe(0);
  expect(full.top).toBe(0);
  expect(full.border).toBe('2px');
  expect(full.side, 'the border tapers to the card edge, never a side stroke').toEqual(['0px', '0px']);
  expect(full.radius).toBeGreaterThan(0);
  expect(full.barRadius, 'the bar follows the card corner curve').toEqual([`${full.radius}px`, `${full.radius}px`]);
  expect(barFraction(full.clip)).toBeGreaterThan(0.99);
  for (let i = 0; i < 10; i++) {
    await page.clock.fastForward(3000);
    await page.keyboard.insertText(' writing');
  }
  await page.clock.runFor(600);
  // WAAPI runs on the real timeline, not the faked page clock: seat the fill at its midpoint.
  await page.locator('#room-bar').evaluate(bar => bar.getAnimations().forEach(a => { a.pause(); a.currentTime = 30000; }));
  const half = await geometry();
  expect(half.left, 'the bar still starts at the card edge').toBe(0);
  expect(half.right, 'the revealed edge never shrinks the box').toBe(0);
  expect(barFraction(half.clip)).toBeGreaterThan(0.4);
  expect(barFraction(half.clip)).toBeLessThan(0.6);
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
  await expect(page.locator('#exit-hint')).toHaveText(await exitHintFor(page));
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
  await expect(page.locator('#exit-hint')).toHaveText(await exitHintFor(page));
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
  expect(row.exitTracking, 'the exit label tracks like the count (D-090)').toBe(row.tracking);
  await capture(page, info, 'exit-hint');
  // Typing cancels the armed exit.
  await page.keyboard.insertText('!');
  await expect(page.locator('#exit-hint')).toHaveText('');
  await expect(page.locator('#room')).toBeVisible();
  // The window expires: after 2 s a single request only re-arms it.
  await page.locator('#exit').click();
  await expect(page.locator('#exit-hint')).toHaveText(await exitHintFor(page));
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
  // The floor is measured while the room is still hidden, so a hidden descendant must not be the
  // thing being measured (it would report 0 and fall back to the em constant).
  expect(await page.locator('#copy-label').evaluate(label => getComputedStyle(label).getPropertyValue('--copy-floor').trim()),
    'the floor is measured before the room opens').toMatch(/^\d+px$/);
  await enter(page);
  await page.keyboard.insertText('This draft survives. 中文继续写。\n');
  for (let second = 0; second < 57; second += 3) {
    await page.clock.fastForward(3000);
    await page.keyboard.insertText('Keep going. ');
  }
  await page.clock.fastForward(3000);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
  // The one-pixel hover lift is deliberate; measure the row at rest, with the pointer off both controls.
  await page.mouse.move(0, 0);
  await expect(page.locator('#kept h1')).toHaveText('You wrote it down.');
  const keptDraft = await page.locator('#kept-text').textContent();
  await expect(page.locator('#receipt')).toHaveText(`1 minute. ${countLabel(keptDraft)}.`);
  const kept = await page.evaluate(() => {
    const copy = document.querySelector('#copy');
    const restart = document.querySelector('#restart');
    const draft = document.querySelector('#kept-text');
    const heading = document.querySelector('#kept h1');
    const paper = document.querySelector('.room-paper').getBoundingClientRect();
    const style = getComputedStyle(copy);
    return {
      restart: window.__run(restart, 'text'),
      copyBox: copy.getBoundingClientRect().toJSON(), restartBox: restart.getBoundingClientRect().toJSON(),
      draftTop: draft.getBoundingClientRect().top, headingBottom: heading.getBoundingClientRect().bottom,
      note: document.querySelector('#kept-note').getBoundingClientRect().toJSON(),
      noteText: document.querySelector('#kept-note').textContent,
      count: document.querySelector('#room-count').textContent,
      paperCentre: paper.left + paper.width / 2,
      pill: { background: style.backgroundColor, radius: style.borderRadius, outlineOffset: style.outlineOffset,
        outlineWidth: style.outlineWidth, outlineColor: style.outlineColor, focused: copy.matches(':focus') },
      restartStyle: { height: getComputedStyle(restart).height, border: getComputedStyle(restart).borderWidth,
        background: getComputedStyle(restart).backgroundColor, radius: getComputedStyle(restart).borderRadius },
    };
  });
  // One owner for the count: the red receipt prints the session's size, the corner stays silent,
  // and one caption states that the text exists only in this tab (D-062).
  expect(kept.count, 'the corner count is silent on the kept screen').toBe('');
  expect(kept.noteText).toBe('Nothing here is saved. Copy it before you leave.');
  expect(kept.note.top).toBeGreaterThan(kept.copyBox.bottom);
  expect(kept.note.top).toBeLessThan(kept.draftTop);
  // The actions sit in the fixed top block, above the draft, so a long draft never hides them.
  expect(kept.copyBox.bottom).toBeLessThan(kept.draftTop);
  expect(kept.headingBottom).toBeLessThan(kept.copyBox.top);
  // The pill hugs its one label node with 24 px each side, and a font-derived floor keeps that
  // box at the widest label's width without a second copy of the words (D-059).
  // Hover and press feedback ride on transitions; geometry is read once they have settled.
  const readCopy = () => page.evaluate(async () => {
    await Promise.all(document.getAnimations().filter(a => a instanceof CSSTransition).map(a => a.finished.catch(() => {})));
    const copy = document.querySelector('#copy');
    const label = document.querySelector('#copy-label');
    const restart = document.querySelector('#restart');
    const walker = document.createTreeWalker(copy, NodeFilter.SHOW_TEXT);
    const textNodes = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode()) textNodes.push(node.nodeValue.trim());
    return {
      text: label.textContent.trim(), ink: window.__run(label, 'text').width,
      domText: copy.textContent.replace(/\s+/g, ' ').trim(), textNodes,
      before: getComputedStyle(copy, '::before').content,
      copyBox: copy.getBoundingClientRect().toJSON(), labelBox: label.getBoundingClientRect().toJSON(),
      labelClient: label.clientWidth, labelScroll: label.scrollWidth,
      floor: getComputedStyle(label).getPropertyValue('--copy-floor').trim(),
      restartBox: restart.getBoundingClientRect().toJSON(), paper: document.querySelector('.room-paper').getBoundingClientRect().toJSON(),
    };
  });
  const expectOneLabel = state => {
    expect(['none', 'normal'].includes(state.before), 'no generated content carries the label').toBe(true);
    expect(state.textNodes, 'the button carries one text node').toEqual([state.text]);
    expect(state.domText, 'the button carries one copy of its label').toBe(state.text);
    expect(state.labelBox.width, 'the label box holds its own text').toBeGreaterThanOrEqual(state.ink - 0.5);
    expect(state.labelScroll, 'the label never clips its text').toBeLessThanOrEqual(state.labelClient + 0.5);
    // The floor is measured from the three labels in the rendered face, not a constant: a machine
    // with a wider system face must still carry one (D-059).
    expect(state.floor, 'the label carries a measured floor').toMatch(/^\d+px$/);
    expect(state.copyBox.width - state.labelBox.width, 'the pill keeps 24 px of label padding').toBeCloseTo(48, 1);
  };
  // The pointer rests on COPY before it presses, as a writer's does. A pointer left over RUN IT
  // AGAIN (where the entry click lands when the row stacks) would lift it by its hover and fake a move.
  await page.locator('#restart').hover();
  await page.locator('#copy').hover();
  const keptCopy = await readCopy();
  await expect(page.locator('#copy')).toHaveAccessibleName(keptCopy.text);
  expectOneLabel(keptCopy);
  // Both actions are 48 px tall. The boxes are read in float layout space, where a fractional offset leaves a
  // 1e-5 px rounding residue (CI read 47.99997 and 48.00003), so this asserts to a hundredth of a pixel.
  expect(kept.copyBox.height).toBeCloseTo(48, 2);
  expect(kept.restartBox.height).toBeCloseTo(48, 2);
  // The draft can never push the actions: it scrolls in its own area under them.
  expect(await page.locator('.kept-scroll').evaluate(e => getComputedStyle(e).overflowY)).toBe('auto');
  const stacked = Math.abs(kept.copyBox.top - kept.restartBox.top) > 1;
  if (stacked) expect(kept.restartBox.top).toBeGreaterThanOrEqual(kept.copyBox.bottom); // 320 wraps the row
  else expect(Math.abs(kept.copyBox.top - kept.restartBox.top)).toBeLessThan(1);
  // The row wraps only when the two measured controls plus the gap cannot fit its width, so a
  // wider fallback face may stack them cleanly but a row with room can never wrap.
  // The row box shrink-wraps its controls, so the width it may use is its parent's content box.
  const row = await page.locator('.kept-actions').evaluate(e => {
    const p = getComputedStyle(e.parentElement);
    const width = e.parentElement.clientWidth - parseFloat(p.paddingLeft) - parseFloat(p.paddingRight);
    return { width, gap: parseFloat(getComputedStyle(e).columnGap) || 0 };
  });
  const fits = kept.copyBox.width + row.gap + kept.restartBox.width <= row.width + 0.5;
  expect(stacked, `the row stacks only when ${kept.copyBox.width} + ${row.gap} + ${kept.restartBox.width} exceeds ${row.width}`).toBe(!fits);
  // One light ring on the pill edge: no dark margin outside an inset outline.
  expect(kept.pill.focused).toBe(true);
  expect(parseFloat(kept.pill.outlineOffset)).toBeLessThanOrEqual(-2);
  expect(kept.pill.outlineWidth).toBe('2px');
  // Focus is a ring on the pill, never a re-cut into a rounded rectangle beside a capsule (D-059).
  expect(kept.pill.radius).toBe('999px');
  expect(kept.restartStyle.radius).toBe('999px');
  expect(kept.restartStyle.background).not.toBe(kept.pill.background);
  await capture(page, info, 'kept');
  await page.locator('#copy').click();
  await expect(page.locator('#copy-label')).toHaveText('Copied');
  await expect(page.locator('#copy')).toHaveAccessibleName('Copied');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(await page.locator('#kept-text').textContent());
  const copied = await readCopy();
  // The press swaps the label and moves nothing: the pill keeps its floor, the row keeps its
  // anchor, and Begin again stays under no pointer at all (D-059).
  expect(copied.copyBox.width, 'the pill keeps one width across labels').toBeCloseTo(keptCopy.copyBox.width, 1);
  expectOneLabel(copied);
  expect(copied.copyBox.left).toBeCloseTo(keptCopy.copyBox.left, 1);
  expect(copied.restartBox.left, 'Begin again does not move').toBeCloseTo(keptCopy.restartBox.left, 1);
  expect(copied.restartBox.top).toBeCloseTo(keptCopy.restartBox.top, 1);
  expect(copied.restartBox.width).toBeCloseTo(keptCopy.restartBox.width, 1);
  if (!stacked) {
    expect(Math.abs((copied.copyBox.left + copied.restartBox.right) / 2 - (copied.paper.left + copied.paper.width / 2))).toBeLessThan(1);
  }
  await page.evaluate(() => {
    Object.defineProperty(navigator.clipboard, 'writeText', { value: () => Promise.reject(new Error('blocked')), configurable: true });
    document.execCommand = () => false;
  });
  await page.locator('#copy').click();
  await expect(page.locator('#copy-label')).toHaveText('Try copy again');
  await expect(page.locator('#copy')).toHaveAccessibleName('Try copy again');
  const failed = await readCopy();
  expect(failed.text).toBe('Try copy again');
  expect(failed.copyBox.width, 'the failed label keeps the same pill width').toBeCloseTo(keptCopy.copyBox.width, 1);
  expectOneLabel(failed);
  expect(failed.copyBox.left).toBeCloseTo(keptCopy.copyBox.left, 1);
  expect(failed.restartBox.left).toBeCloseTo(keptCopy.restartBox.left, 1);
  await capture(page, info, 'copied');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await expect(page.locator('#room')).toBeHidden();
  await expect(page.locator('#landing .cta a[href="#trial"]')).toBeFocused();
  await capture(page, info, 'escape');
});

// The kept screen is one draft in one place: the wide kept block. The writing column's ink layer
// repeats the same text, so a kept screen that leaves it painted draws the draft twice, and at
// phone width the two copies land line over line.
test('the kept screen draws the draft once', async ({ page }, info) => {
  // One logical line long enough to wrap: the room's newest rung, the one the aperture shows.
  const draft = 'The train was late so I wrote the letter anyway.';
  for (const size of [{ width: 1440, height: 900 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(size);
    await enter(page);
    await page.keyboard.insertText(draft);
    for (let second = 0; second < 57; second += 3) {
      await page.clock.fastForward(3000);
      await page.keyboard.insertText(' and kept going');
    }
    await page.clock.fastForward(3000);
    await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
    const drawn = await page.evaluate(first => {
      // A copy is painted when it has a box, no ancestor hides it with display or visibility, and the
      // opacities above it do not multiply it away.
      const painted = element => {
        if (!element) return false;
        let opacity = 1;
        for (let node = element; node; node = node.parentElement) {
          const style = getComputedStyle(node);
          if (style.display === 'none' || style.visibility === 'hidden') return false;
          opacity *= Number(style.opacity);
        }
        return opacity > 0 && [...element.getClientRects()].some(rect => rect.width > 0 && rect.height > 0);
      };
      const name = element => `${element.tagName}${element.id ? `#${element.id}` : ''}`;
      return [...document.querySelectorAll('#room *')]
        .filter(element => [...element.childNodes]
          .some(node => node.nodeType === Node.TEXT_NODE && node.nodeValue.includes(first)) && painted(element))
        .map(name);
    }, draft);
    // The writing column's textarea and the ink layer that paints it both leave the sheet, so the only
    // draft on screen is the kept block's own; one holder proves it whichever element a copy uses.
    await expect(page.locator('#editor'), `the ${size.width} kept screen hides the writing line`).toBeHidden();
    await expect(page.locator('#editor-ink'), `the ${size.width} kept screen hides the writing ink`).toBeHidden();
    expect(drawn, `the ${size.width} kept screen holds one copy of the draft`).toEqual(['DIV#kept-text']);
    if (info.project.name === '1440-light-no-preference' || info.project.name === '390-light-no-preference') {
      await capture(page, info, `kept-once-${size.width}x${size.height}`);
    }
    // The next session paints its ink again: hiding the layer must not outlive the kept screen.
    await page.locator('#restart').click();
    await page.keyboard.insertText('A new draft');
    await expect(page.locator('#editor-ink'), 'the restarted room still paints its draft').toHaveText('A new draft');
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    await expect(page.locator('#landing')).toBeVisible();
  }
});

// The payoff screen is the one moment a stranger has felt the product work, so it carries one
// quiet route to the app and never before the draft is kept. Inserting it must not move the action
// row the writer's hand is already on.
test('the kept screen offers one route to the app, and the writing screen none', async ({ page }, info) => {
  const link = '#kept a[href="download/?from=kept"]';
  await enter(page);
  await page.keyboard.insertText('A draft that earns the payoff screen.');
  await settle(page);
  expect(await page.locator(`${link}:visible`).count(), 'the writing screen carries no app link').toBe(0);
  for (let second = 0; second < 57; second += 3) {
    await page.clock.fastForward(3000);
    await page.keyboard.insertText(' Keep going.');
  }
  await page.clock.fastForward(3000);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'kept');
  await expect(page.locator(`${link}:visible`), 'the kept screen carries exactly one route').toHaveCount(1);
  const app = page.locator(link);
  await expect(app).toHaveText('Mac app');
  expect(await app.getAttribute('target'), 'the app opens beside the draft').toBe('_blank');
  expect(await app.getAttribute('rel'), 'the new tab never reaches back').toContain('noopener');
  const kept = await page.evaluate(selector => {
    const box = element => {
      const r = element.getBoundingClientRect();
      return { top: r.top, left: r.left, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
    };
    const style = getComputedStyle(document.querySelector(selector));
    return {
      link: box(document.querySelector(selector)), actions: box(document.querySelector('.kept-actions')),
      note: box(document.querySelector('.kept-note')), scroll: box(document.querySelector('.kept-scroll')),
      colour: style.color, noteColour: getComputedStyle(document.querySelector('.kept-note')).color,
      size: parseFloat(style.fontSize), decoration: style.textDecorationLine,
    };
  }, link);
  expect(kept.link.top, 'the link sits under the action row').toBeGreaterThanOrEqual(kept.actions.bottom);
  expect(kept.note.top, 'the link sits above the not-saved caption').toBeGreaterThanOrEqual(kept.link.bottom);
  expect(kept.actions.bottom, 'the caption stays above the draft').toBeLessThanOrEqual(kept.scroll.top);
  expect(kept.link.height, 'the link keeps a 44 px tap row').toBeGreaterThanOrEqual(44);
  expect(kept.size, 'the link carries the quiet role, not a second pill').toBe(13);
  expect(kept.colour, 'the link takes the quiet ink, in the caption\'s own colour').toBe(kept.noteColour);
  expect(kept.decoration, 'the link reads as a link').toContain('underline');
  // The pair must not depend on the link: taken out of flow, the action row sits exactly where it sits
  // with the link present, so the new control cost the writer no pixel of the row they are on.
  const without = await page.evaluate(selector => {
    const element = document.querySelector(selector);
    element.style.display = 'none';
    window.dispatchEvent(new Event('resize'));
    const r = document.querySelector('.kept-actions').getBoundingClientRect();
    element.style.display = '';
    window.dispatchEvent(new Event('resize'));
    return { top: r.top, left: r.left, right: r.right, bottom: r.bottom };
  }, link);
  for (const edge of ['top', 'left', 'right', 'bottom']) {
    expect(without[edge], `the action row ${edge} does not depend on the link`).toBeCloseTo(kept.actions[edge], 1);
  }
  // Keyboard reach, and the ring is the shared one on the control's own shape.
  await page.locator('#restart').focus();
  await page.keyboard.press('Tab');
  const focused = await page.evaluate(() => {
    const element = document.activeElement;
    const style = getComputedStyle(element);
    return { text: element.textContent.trim(), ring: element.matches(':focus-visible'),
      outline: `${style.outlineWidth} ${style.outlineStyle}`, radius: style.borderRadius, top: element.getBoundingClientRect().top };
  });
  expect(focused.text, 'one Tab from Begin again reaches the app').toBe('Mac app');
  expect(focused.ring, 'the ring is visible').toBe(true);
  expect(focused.outline).toBe('2px solid');
  expect(focused.radius, 'a text control keeps its shape under focus').toBe('0px');
  expect(focused.top, 'the ring is not laid over the pill row above it').toBeGreaterThan(kept.actions.bottom);
  await capture(page, info, 'kept-app-link');
  // A sheet too short for the payoff block and one line of the returned draft leaves the app row out
  // and keeps the draft line; the room's own Mac link still offers the app there.
  await page.setViewportSize({ width: 844, height: 390 });
  await page.evaluate(() => window.dispatchEvent(new Event('resize')));
  await page.clock.fastForward(100);
  expect(await page.locator(`${link}:visible`).count(), 'a 390 px sheet keeps its draft line instead').toBe(0);
  expect(await page.locator('#room a[href="download/"]:visible').count(), 'the room still offers the app').toBeGreaterThan(0);
  await page.setViewportSize(info.project.use.viewport);
  await page.evaluate(() => window.dispatchEvent(new Event('resize')));
  await page.clock.fastForward(100);
  expect(await page.locator(`${link}:visible`).count(), 'a sheet with room carries the route again').toBe(1);
  // The stopped screen is not a payoff, so it carries no route either.
  await page.locator('#restart').click();
  await page.keyboard.insertText('A draft that stops.');
  await page.clock.fastForward(9000);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  expect(await page.locator(`${link}:visible`).count(), 'the wipe screen carries no app link').toBe(0);
});

// The stopped screen is one composition, not a block pinned under the top edge (D-070).
// The captain locked it in the tuner: one group of headline, consequence line and pill,
// its midpoint at 33% of the sheet, derived per sheet height rather than scaled.
const FAILURE_ANCHOR = 0.33;
const GAP_HEADLINE_LINE = 9;
const GAP_LINE_BUTTON = 24;
const PILL_HEIGHT = 48;
const PILL_PAD_X = 20;
// The headline keeps the result screens' own role size `clamp(32px, 5vw, 48px)`, so the
// phone sheet re-derives it instead of shrinking the desktop number.
const headlineSize = width => Math.round(Math.min(Math.max(width * 0.05, 32), 48));

async function failureGeometry(page) {
  return page.locator('#failed').evaluate(element => {
    const paper = element.closest('.room-paper');
    const paperRect = paper.getBoundingClientRect();
    const css = node => getComputedStyle(node);
    const rel = node => {
      const r = node.getBoundingClientRect();
      return { top: r.top - paperRect.top, bottom: r.bottom - paperRect.top,
        left: r.left - paperRect.left, right: r.right - paperRect.left,
        width: r.width, height: r.height };
    };
    const token = name => {
      const probe = document.createElement('i');
      probe.style.color = css(element).getPropertyValue(name);
      element.append(probe);
      const color = css(probe).color;
      probe.remove();
      return color;
    };
    const headline = element.querySelector('h1');
    const line = element.querySelector('.failure-note');
    const button = element.querySelector('#begin-again');
    const group = rel(element);
    const bar = paper.querySelector('.bar');
    const chrome = paper.querySelector('.chrome-row');
    return {
      paper: { width: paperRect.width, height: paperRect.height },
      group,
      anchor: (group.top + group.height / 2) / paperRect.height,
      centreOffset: (group.left + group.width / 2) - paperRect.width / 2,
      headline: { ...rel(headline), size: parseFloat(css(headline).fontSize),
        weight: css(headline).fontWeight, lineHeight: parseFloat(css(headline).lineHeight) },
      line: { ...rel(line), size: parseFloat(css(line).fontSize),
        weight: css(line).fontWeight, ink: css(line).color },
      sheet: css(paper).backgroundColor,
      button: { ...rel(button), size: parseFloat(css(button).fontSize),
        weight: css(button).fontWeight, padX: parseFloat(css(button).paddingLeft),
        radius: parseFloat(css(button).borderRadius), tag: button.tagName },
      gapHeadlineLine: rel(line).top - rel(headline).bottom,
      gapLineButton: rel(button).top - rel(line).bottom,
      quiet: token('--paper-quiet'),
      chrome: { clock: css(chrome).visibility, bar: css(bar).visibility },
    };
  });
}

test('the stopped screen is one group anchored at 33% of the sheet', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('This one gets deleted.');
  await settle(page);
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(page.locator('#failed')).toBeVisible();
  // The door's click point can land on the block that appears eight seconds later; park
  // the pointer so the rest state is measured without a hover.
  await page.mouse.move(1, 1);
  const failure = await failureGeometry(page);
  const width = info.project.use.viewport.width;
  // Geometry first: the group's own midpoint carries the composition.
  expect(failure.paper.height, `sheet height at ${width}`).toBeGreaterThan(200);
  expect(failure.anchor, `group midpoint at ${(failure.anchor * 100).toFixed(2)}% of the ${failure.paper.height} px sheet`)
    .toBeCloseTo(FAILURE_ANCHOR, 2);
  expect(Math.abs(failure.centreOffset), 'the group is centred on the paper').toBeLessThan(1);
  // Order under the headline: the consequence line, then the pill.
  expect(failure.headline.bottom, 'the headline is above the line').toBeLessThanOrEqual(failure.line.top + 0.5);
  expect(failure.line.bottom, 'the line is above the button').toBeLessThanOrEqual(failure.button.top + 0.5);
  expect(failure.button.bottom, 'the button closes the group').toBeLessThanOrEqual(failure.group.bottom + 0.5);
  // The two gaps the captain set, measured box edge to box edge.
  expect(failure.gapHeadlineLine, 'headline to line').toBeCloseTo(GAP_HEADLINE_LINE, 0);
  expect(failure.gapLineButton, 'line to button').toBeCloseTo(GAP_LINE_BUTTON, 0);
  // Type: the headline at the result role's size for this width, Newsreader 500 at 1.1.
  expect(failure.headline.size).toBe(headlineSize(width));
  expect(failure.headline.weight).toBe('500');
  expect(failure.headline.lineHeight).toBeCloseTo(failure.headline.size * 1.1, 0);
  expect(failure.line.size).toBe(15);
  expect(failure.line.weight).toBe('400');
  expect(failure.line.ink, 'the line is the sheet\'s quiet ink').toBe(failure.quiet);
  expect(contrast(failure.line.ink, failure.sheet), 'the line clears 7:1 on the sheet').toBeGreaterThanOrEqual(7);
  // The pill: 48 tall, 15 / 600, 20 px side padding, full radius.
  expect(failure.button.tag).toBe('BUTTON');
  expect(failure.button.height).toBe(PILL_HEIGHT);
  expect(failure.button.size).toBe(15);
  expect(failure.button.weight).toBe('600');
  expect(failure.button.padX).toBe(PILL_PAD_X);
  expect(failure.button.radius).toBeGreaterThanOrEqual(PILL_HEIGHT / 2);
  // No receipt: the screen states the deletion once, and the session chrome is off.
  await expect(page.locator('#room')).not.toContainText('TYPE TO START AGAIN');
  await expect(page.locator('#room-report, #report, #room .restart-key')).toHaveCount(0);
  expect(failure.chrome.clock, 'the clock is not part of the stopped screen').toBe('hidden');
  expect(failure.chrome.bar, 'the session bar is not part of the stopped screen').toBe('hidden');
  await expect(page.locator('#room-count')).toHaveText('0 words');
  const red = await page.locator('#room').evaluate(room => {
    const probe = document.createElement('i');
    probe.style.color = 'var(--red)';
    room.append(probe);
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  });
  const runs = await page.locator('#failed').evaluate(el => [el, ...el.querySelectorAll('*')]
    .map(node => ({ tag: node.tagName, text: node.textContent.trim(), color: getComputedStyle(node).color })));
  for (const run of runs) expect(run.color, `${run.tag} "${run.text}" is red`).not.toBe(red);
  await capture(page, info, `stopped-${width}`);
  // The rest of the paused screen never moves the composition as time passes.
  const settled = await failureGeometry(page);
  await page.clock.fastForward(5000);
  const later = await failureGeometry(page);
  expect(later.group).toEqual(settled.group);
});

test('the stopped pill carries the keyboard and shows the room ink ring', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('A');
  await settle(page);
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await page.mouse.move(1, 1);
  // Keyboard entry reaches the one control on the sheet and shows the room's ink ring.
  await page.keyboard.press('Shift+Tab');
  await expect(page.locator('#begin-again')).toBeFocused();
  const focus = await page.locator('#begin-again').evaluate(button => ({
    visible: button.matches(':focus-visible'),
    outline: `${getComputedStyle(button).outlineWidth} ${getComputedStyle(button).outlineStyle}`,
    offset: getComputedStyle(button).outlineOffset,
    shortcuts: button.getAttribute('aria-keyshortcuts'),
  }));
  expect(focus.visible, 'focus stays visible on the stopped screen').toBe(true);
  expect(focus.outline, "the room's 2 px ink ring").toBe('2px solid');
  expect(parseFloat(focus.offset), 'the ring clears the pill edge').toBeGreaterThan(0);
  expect(focus.shortcuts, 'the shortcut is exposed to assistive technology').toBe('Enter');
  await capture(page, info, 'stopped-focus');
});

test('Return and the pill start a fresh session and bring the chrome back', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('This one gets deleted.');
  await settle(page);
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  await expect(page.locator('#room .chrome-row')).toBeHidden();
  await page.keyboard.press('Enter');
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'rest');
  await expect(editor(page)).toBeFocused();
  await expect(page.locator('#room-clock')).toBeVisible();
  await expect(page.locator('#room-clock')).toHaveText('1:00');
  expect(barFraction(await page.locator('#room-bar').evaluate(bar => bar.style.clipPath)), 'the bar resets with the session').toBe(1);
  await expect(page.locator('#room .bar')).toBeVisible();
  await expect(page.locator('#failed')).toBeHidden();
  await expect(page.locator('#room .chrome-row')).toBeVisible();
  await expect(page.locator('#room-count')).toHaveText('Type to begin');
  await page.keyboard.insertText('This one gets deleted too.');
  await settle(page);
  await page.clock.fastForward(8350);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'wipe');
  // The pill is the only restart control, and its own box is the whole target; the footer keeps Esc to exit.
  const target = await page.locator('#begin-again').boundingBox();
  await page.mouse.click(target.x + target.width / 2, target.y + target.height / 2);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'rest');
  await expect(editor(page)).toBeFocused();
  await expect(page.locator('#room-clock')).toHaveText('1:00');
  await expect(page.locator('#room .chrome-row')).toBeVisible();
  expect(barFraction(await page.locator('#room-bar').evaluate(bar => bar.style.clipPath))).toBe(1);
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
  // The theatre takes no input, so its count slot never carries a typing prompt; it fills in with
  // the room's own word string once the script produces a word (D-064).
  await expect(page.locator('#count')).toHaveText('');
  let at = 0;
  const seek = async ms => { await page.clock.fastForward(ms - at); at = ms; };
  await seek(deny.t - 100);
  // A visitor's own Backspace never edits the demo either.
  await page.locator('body').click({ position: { x: 5, y: 5 } });
  await page.keyboard.press('Backspace');
  await expect(page.locator('#cur')).toHaveText(deny.cur);
  // Playwright's clock controls the demo's timers, not WAAPI's document timeline, so runner latency
  // can consume a 200 ms refusal before it is read. Freeze the refusal in the native key event.
  await page.evaluate(() => {
    document.addEventListener('keydown', () => {
      for (const animation of document.getAnimations()) {
        if (['paper', 'demo-hairline'].includes(animation.effect.target?.id)) {
          animation.pause();
          animation.currentTime = 60;
        }
      }
    }, { once: true });
  });
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
  // The demo's history is the room's: the theme's first history step one line up, the second two lines up
  // (D-092: .22 and .07 light, .16 and .05 dark, exempt from 7:1).
  const ladder = await page.evaluate(() => {
    const sheet = getComputedStyle(document.querySelector('#paper'));
    return {
      stops: [sheet.getPropertyValue('--paper-history-1').trim(), sheet.getPropertyValue('--paper-history-2').trim()],
      rendered: [...document.querySelectorAll('.prev-line')].map(e => getComputedStyle(e).opacity),
    };
  });
  expect(Number(ladder.rendered[0])).toBeCloseTo(Number(ladder.stops[0]), 2);
  expect(Number(ladder.rendered[1])).toBeCloseTo(Number(ladder.stops[1]), 2);
  // No second bar: the 3 pt silence meter is gone.
  await expect(page.locator('#meter')).toHaveCount(0);
  // One bar, painted as a 2 px border-top on a box one corner radius tall (the paper's own top edge).
  const bars = await page.evaluate(() => [...document.querySelectorAll('#demo .bar, #demo .meter')].map(e => getComputedStyle(e).borderTopWidth));
  expect(bars).toEqual(['2px']);
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
  await expect(page.locator('#demo-stopped .failure-note')).toHaveText('Draft deleted.');
  const reportLook = await page.evaluate(() => {
    const probe = name => {
      const i = document.createElement('i');
      i.style.color = getComputedStyle(document.querySelector('#demo')).getPropertyValue(name);
      document.querySelector('#demo').append(i);
      const color = getComputedStyle(i).color; i.remove(); return color;
    };
    return {
      title: getComputedStyle(document.querySelector('#demo-stopped .stopped')).color,
      note: getComputedStyle(document.querySelector('#demo-stopped .failure-note')).color,
      sheet: getComputedStyle(document.querySelector('#demo-stopped').closest('[data-paper]')).backgroundColor,
      quiet: probe('--paper-quiet'),
      red: probe('--red'),
      ink: probe('--ink'),
      tracking: getComputedStyle(document.querySelector('#clock')).letterSpacing,
    };
  });
  expect(reportLook.title).toBe(reportLook.ink);
  expect(reportLook.note, 'the consequence line is the sheet\'s quiet ink, never red').toBe(reportLook.quiet);
  expect(contrast(reportLook.note, reportLook.sheet), 'the demo line clears 7:1 on the sheet').toBeGreaterThanOrEqual(7);
  expect(reportLook.note).not.toBe(reportLook.red);
  expect(reportLook.tracking).toBe('normal');
  // The demo previews the same composition: the block's midpoint at 33% of the paper and
  // the 9 px gap under the headline, with no control (the demo is watch-only, D-044).
  const demoBlock = await page.locator('#demo-stopped').evaluate(element => {
    const paper = element.closest('.paper');
    const paperRect = paper.getBoundingClientRect();
    const rel = node => {
      const r = node.getBoundingClientRect();
      return { top: r.top - paperRect.top, bottom: r.bottom - paperRect.top, height: r.height };
    };
    const group = rel(element);
    const note = element.querySelector('.failure-note');
    return {
      anchor: (group.top + group.height / 2) / paperRect.height,
      gap: rel(note).top - rel(element.querySelector('.stopped')).bottom,
      noteSize: parseFloat(getComputedStyle(note).fontSize),
      clock: getComputedStyle(paper.querySelector('.chrome-row')).visibility,
      bar: getComputedStyle(paper.querySelector('.bar')).visibility,
    };
  });
  expect(demoBlock.anchor, 'the demo block follows the room anchor').toBeCloseTo(FAILURE_ANCHOR, 2);
  expect(demoBlock.gap, 'headline to line in the demo').toBeCloseTo(GAP_HEADLINE_LINE, 0);
  expect(demoBlock.noteSize).toBe(15);
  expect(demoBlock.clock, 'the demo takes its clock off the stopped sheet').toBe('hidden');
  expect(demoBlock.bar, 'the demo takes its bar off the stopped sheet').toBe('hidden');
  await expect(page.locator('#demo-stopped button')).toHaveCount(0);
  await expect(page.locator('#report')).toHaveCount(0);
  await expect(page.locator('#count')).toHaveText('0 words');
  await capture(page, info, 'demo-report');
  await seek(CUT_END + 2700);
  await expect(page.locator('#cur')).not.toHaveText('');
  await expect(page.locator('#demo-stopped')).toBeHidden();
  expect(await page.locator('#demo .chrome-row').evaluate(el => getComputedStyle(el).visibility),
    'the rearm hands the chrome back').toBe('visible');
});

test('the demo takes its chrome off while the stopped block shows', async ({ page }, info) => {
  test.skip(info.project.use.reducedMotion === 'reduce', 'the static demo has no report phase');
  await page.clock.fastForward(CUT_END + 300);
  await expect(page.locator('#demo-stopped')).toBeVisible();
  const clockHide = await page.locator('#demo .chrome-row').evaluate(el => getComputedStyle(el).visibility);
  const barHide = await page.locator('#demo .bar').evaluate(el => getComputedStyle(el).visibility);
  expect(clockHide).toBe('hidden');
  expect(barHide).toBe('hidden');
  // The room's own rule, not a frozen receipt: the loop hands the chrome back with the new minute.
  await page.clock.fastForward(2400);
  await expect(page.locator('#demo-stopped')).toBeHidden();
  await expect(page.locator('#clock')).toHaveText('1:00');
  expect(await page.locator('#demo .chrome-row').evaluate(el => getComputedStyle(el).visibility)).toBe('visible');
});

test('the demo danger group clears when a new loop reaches typing', async ({ page }, info) => {
  test.skip(info.project.use.reducedMotion === 'reduce', 'the static demo never loops');
  await page.clock.fastForward(SILENT_END + 150);
  await expect(page.locator('#warn')).toBeVisible();
  await expect(page.locator('#warn-caption')).toHaveText('KEEP TYPING OR THE DRAFT IS DELETED.');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await doorSettled(page);
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
  // The screen can be short two ways: a wide landscape window, or a small phone whose sheet now
  // shares the first screen with the door (D-058). Both keep the group off the writing line.
  for (const size of [{ width: 844, height: 390 }, { width: 1440, height: 350 }, { width: 375, height: 667 }, { width: 320, height: 700 }, { width: 375, height: 701 }]) {
    await page.setViewportSize(size);
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
    expect(warning.danger.top, `${size.width}x${size.height}: the group starts inside the paper`).toBeGreaterThanOrEqual(warning.paper.top);
    expect(warning.danger.bottom <= warning.lineTop || warning.danger.top >= warning.lineBottom, `${size.width}x${size.height}: the warning group does not cover the active line`).toBe(true);
    expect(warning.danger.bottom, `${size.width}x${size.height}: the group stays above the footer`).toBeLessThanOrEqual(warning.footer.top);
    await page.clock.fastForward(CUT_END - (SILENT_END + 150) + 300);
    await expect(page.locator('#demo-stopped')).toBeVisible();
    const report = await page.evaluate(() => {
      const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom }; };
      return { paper: box('#paper'), footer: box('#paper .paper-foot'), block: box('#demo-stopped') };
    });
    expect(report.block.top, `${size.width}x${size.height}: the stopped group starts inside the paper`).toBeGreaterThanOrEqual(report.paper.top);
    expect(report.block.bottom, `${size.width}x${size.height}: the stopped group stays above the footer`).toBeLessThanOrEqual(report.footer.top);
    await capture(page, info, `short-demo-report-${size.width}x${size.height}`);
  }
});

test('the short-viewport numeral shrinks the landing sheet only', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 664 });
  const numeral = await page.evaluate(() => ({
    demo: parseFloat(getComputedStyle(document.querySelector('#numeral')).fontSize),
    room: parseFloat(getComputedStyle(document.querySelector('#room-numeral')).fontSize),
    demoShort: Math.min(innerHeight * 0.15, 140),
    roomMac: Math.min(innerHeight * 0.18, 170),
  }));
  expect(numeral.demo, 'the short landing sheet keeps its smaller numeral').toBeCloseTo(numeral.demoShort, 1);
  expect(numeral.room, 'the room keeps the Mac numeral on a short sheet').toBeCloseTo(numeral.roomMac, 1);
});

test('the room wears the landing design system', async ({ page }) => {
  await enter(page);
  const look = await page.evaluate(() => {
    const css = s => getComputedStyle(document.querySelector(s));
    const probeOn = (selector, name) => {
      const i = document.createElement('i');
      i.style.color = getComputedStyle(document.querySelector(selector)).getPropertyValue(name);
      document.querySelector('#room').append(i);
      const c = getComputedStyle(i).color; i.remove(); return c;
    };
    const probe = name => probeOn('#room', name);
    return {
      page: css('#room').backgroundColor, pageToken: probe('--page'),
      // The renderer owns the sheet's tone token on the sheet itself (it corrects the texture's mean, D-069),
      // so the paper is compared with the tone the renderer set for it; the rendered value is measured in
      // qa/paper.spec.mjs.
      sheet: css('.room-paper').backgroundColor, sheetToken: probeOn('.room-paper', '--paper-tone'),
      sheetShadow: css('.room-paper').boxShadow, roomShadow: css('#room').boxShadow,
      writing: css('#editor').fontFamily, tool: ['#room-clock', '#room-count', '#exit'].map(s => css(s).fontFamily),
      washes: document.querySelectorAll('#room .wash').length,
    };
  });
  expect(look.page).toBe(look.pageToken);
  // D-056/D-069: the writing sheet is the Note paper, a measured role of its own; `--sheet` stays the plain
  // surface for cards, controls and fields, so the room's paper paints the tone the renderer set for it.
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

test('focus is a ring, never a re-cut of the control it lands on', async ({ page }, info) => {
  // Walk in with the keyboard, so every focus the page makes is a :focus-visible one - the state
  // that used to re-cut the room's pill into an 8 px rectangle (D-059).
  const shape = () => page.evaluate(() => {
    const element = document.activeElement;
    const style = getComputedStyle(element);
    const box = element.getBoundingClientRect();
    return { tag: element.tagName.toLowerCase(), id: element.id, text: (element.textContent || '').trim(),
      ring: element.matches(':focus-visible'), radius: style.borderRadius,
      outline: `${style.outlineWidth} ${style.outlineStyle}`, width: box.width, height: box.height };
  });
  const door = await (async () => {
    for (let step = 0; step < 4; step += 1) await page.keyboard.press('Tab');
    return page.evaluate(() => {
      const element = document.activeElement;
      const style = getComputedStyle(element);
      return { text: (element.textContent || '').trim(), ring: element.matches(':focus-visible'),
        radius: style.borderRadius, outline: `${style.outlineWidth} ${style.outlineStyle}`,
        width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height };
    });
  })();
  expect(door.text, 'the keyboard reaches the door last').toBe('Give it 60 seconds');
  expect(door.ring).toBe(true);
  expect(door.radius, 'the door keeps its pill under focus').toBe('999px');
  expect(door.outline).toBe('2px solid');
  expect(door.height).toBe(48);
  await page.keyboard.press('Enter');
  await expect(editor(page)).toBeFocused();
  // One Tab from the writing line lands on the exit control; its own shape is a square text control.
  await page.keyboard.press('Tab');
  const exit = await shape();
  expect(exit.id).toBe('exit');
  expect(exit.ring, 'the ring is visible').toBe(true);
  expect(exit.radius, 'a square control stays square').toBe('0px');
  expect(exit.outline).toBe('2px solid');
  await capture(page, info, 'focus-exit');
});

test('nothing in the room can throw a live draft away in one act', async ({ page }, info) => {
  await enter(page);
  await page.keyboard.insertText('A draft that has to survive a stray click.');
  await settle(page);
  const text = await editor(page).inputValue();
  // The warning names the act this width can perform.
  await expect(page.locator('#exit')).toHaveText((await touchInput(page)) ? 'Exit' : 'Esc to exit');
  // Both Mac links leave this document alone, so a click on them cannot take the draft down.
  const macLinks = await page.evaluate(() => [...document.querySelectorAll('#room a[href="download/"]')]
    .map(link => ({ target: link.target, rel: link.rel })));
  expect(macLinks.length, 'the room carries the Mac link in the header or the exit row').toBeGreaterThan(0);
  for (const link of macLinks) {
    expect(link.target, 'the Mac link opens beside the room, not over it').toBe('_blank');
    expect(link.rel).toContain('noopener');
  }
  // The brand is the same act as EXIT: the first click arms the confirmation and keeps the draft.
  await page.locator('#room-brand').click();
  await expect(page.locator('#room')).toBeVisible();
  await expect(page.locator('#landing')).toBeHidden();
  await expect(page.locator('#exit-hint')).toHaveText(await exitHintFor(page));
  await expect(editor(page)).toHaveValue(text);
  await expect(page.locator('#room')).toHaveAttribute('data-phase', 'typing');
  await capture(page, info, 'brand-armed');
  // The second act is the one that leaves.
  await page.locator('#room-brand').click();
  await expect(page.locator('#room')).toBeHidden();
  await expect(page.locator('#landing')).toBeVisible();
  await expect(page.locator('#landing .cta a[href="#trial"]')).toBeFocused();
});

test.describe('a thumb on the phone', () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 390, height: 844 } });
  test('a thumb gets the same two acts as a keyboard', async ({ page }, info) => {
    const loaded = await page.goto('./');
    expect(loaded, 'the suite serves the page through its own baseURL').not.toBeNull();
    expect(loaded.status(), 'the page loads from the suite origin').toBeLessThan(400);
    expect(new URL(page.url()).protocol, 'the page has a real http(s) origin').toMatch(/^https?:$/);
    await page.locator('#landing .cta a[href="#trial"]').tap();
    await doorSettled(page);
    await expect(editor(page)).toBeFocused();
    await page.clock.runFor(50);
    await page.keyboard.insertText('Typed with a thumb.');
    await page.clock.runFor(50);
    await expect(page.locator('#exit')).toHaveText('Exit');
    const tap = async selector => {
      const box = await page.locator(selector).boundingBox();
      await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
      await page.clock.runFor(50);
    };
    // One tap on the brand arms the confirmation and keeps the draft.
    await tap('#room-brand');
    await expect(page.locator('#room')).toBeVisible();
    await expect(page.locator('#exit-hint')).toHaveText('Tap EXIT again to leave and delete the draft.');
    await expect(editor(page)).toHaveValue('Typed with a thumb.');
    await capture(page, info, 'thumb-brand-armed');
    // One tap on EXIT re-arms rather than leaving; the second tap is the act that leaves.
    await page.clock.runFor(2100);
    await expect(page.locator('#exit-hint')).toHaveText('');
    await tap('#exit');
    await expect(page.locator('#room')).toBeVisible();
    await expect(page.locator('#exit-hint')).toHaveText('Tap EXIT again to leave and delete the draft.');
    await expect(editor(page)).toHaveValue('Typed with a thumb.');
    await tap('#exit');
    await expect(page.locator('#room')).toBeHidden();
    await expect(page.locator('#landing')).toBeVisible();
  });
});

test.describe('a landscape phone', () => {
  test.use({ hasTouch: true, isMobile: true, viewport: { width: 844, height: 390 } });
  test('a wide touch screen still names the control it can press', async ({ page }) => {
    expect(await touchInput(page), 'the touch profile reports coarse input').toBe(true);
    await page.locator('#landing .cta a[href="#trial"]').tap();
    await doorSettled(page);
    await expect(editor(page)).toBeFocused();
    await expect(page.locator('#exit')).toHaveText('Exit');
    const tap = async selector => {
      const box = await page.locator(selector).boundingBox();
      await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
      await page.clock.runFor(50);
    };
    await tap('#exit');
    await expect(page.locator('#exit-hint')).toHaveText(EXIT_HINT.touch);
    await expect(page.locator('#room')).toBeVisible();
    await tap('#exit');
    await expect(page.locator('#room')).toBeHidden();
    await expect(page.locator('#landing')).toBeVisible();
  });
});

test.describe('a wide fine pointer', () => {
  test.use({ hasTouch: false, isMobile: false, viewport: { width: 844, height: 390 } });
  test('a wide fine pointer keeps the Escape wording', async ({ page }) => {
    expect(await touchInput(page), 'the desktop profile reports a fine pointer').toBe(false);
    await page.locator('#landing .cta a[href="#trial"]').click();
    await doorSettled(page);
    await expect(editor(page)).toBeFocused();
    await expect(page.locator('#exit')).toHaveText('Esc to exit');
    await page.locator('#exit').click();
    await expect(page.locator('#exit-hint')).toHaveText(EXIT_HINT.keyboard);
    await expect(page.locator('#room')).toBeVisible();
    await page.locator('#exit').click();
    await expect(page.locator('#room')).toBeHidden();
    await expect(page.locator('#landing')).toBeVisible();
  });
});

test('the door and the sheet it opens share one first screen on a short phone', async ({ page }, info) => {
  const read = () => page.evaluate(() => {
    const box = selector => { const rect = document.querySelector(selector).getBoundingClientRect(); return { top: rect.top, bottom: rect.bottom, height: rect.height }; };
    return { viewport: innerHeight, viewportWidth: innerWidth, scrollWidth: document.documentElement.scrollWidth,
      first: box('.first-screen'), door: box('#landing .cta .btn'), note: box('.hero-sub'), sheet: box('#paper') };
  });
  const expectFold = (fold, label) => {
    expect(fold.first.height, `${label}: the first screen fills the viewport`).toBeGreaterThanOrEqual(fold.viewport - 0.5);
    expect(fold.sheet.height, `${label}: the sheet keeps its 300 px lower floor`).toBeGreaterThanOrEqual(300 - 0.5);
    // The floor is `max(300px, 61vh)`, so the only shortfall a correct layout can show is the
    // browser's own sub-pixel rounding of the vh unit: hold the ratio to one rendering pixel.
    expect(fold.sheet.height, `${label}: the sheet stays at or above 61%`).toBeGreaterThanOrEqual(fold.viewport * 0.61 - 1);
    expect(Math.abs(fold.sheet.bottom - fold.first.bottom), `${label}: the sheet owns the first screen's remaining space`).toBeLessThanOrEqual(1);
    expect(fold.note.top, `${label}: the note starts on the first screen`).toBeGreaterThanOrEqual(0);
    expect(fold.note.bottom, `${label}: the note is on the first screen`).toBeLessThanOrEqual(fold.viewport);
    expect(fold.door.top, `${label}: the door starts on the first screen`).toBeGreaterThanOrEqual(0);
    expect(fold.door.bottom, `${label}: the whole door is on the first screen`).toBeLessThanOrEqual(fold.viewport);
  };
  // The hand word's write-on reveal is real time, not the fake clock: let it finish before the
  // captures, so the evidence shows the resting headline.
  await page.waitForTimeout(1500);
  for (const size of [{ width: 375, height: 667 }, { width: 320, height: 700 }, { width: 375, height: 701 }]) {
    await page.setViewportSize(size);
    await page.evaluate(() => window.scrollTo(0, 0));
    expectFold(await read(), `${size.width}x${size.height}`);
    await capture(page, info, `fold-${size.width}x${size.height}`);
  }
  // The same container plus floor at a taller phone and at 320x568: the sheet keeps 61% and the
  // first screen grows when the content and the floor need more than the viewport.
  for (const size of [{ width: 375, height: 812 }, { width: 320, height: 568 }]) {
    await page.setViewportSize(size);
    await page.evaluate(() => window.scrollTo(0, 0));
    expectFold(await read(), `${size.width}x${size.height}`);
  }
  // The two documented targets stay at or above the 61% the landing contract measured.
  for (const size of [{ width: 390, height: 844 }, { width: 1440, height: 900 }]) {
    await page.setViewportSize(size);
    const fold = await read();
    expect(fold.sheet.height, `${size.width}x${size.height}: the sheet stays at or above 61%`).toBeGreaterThanOrEqual(fold.viewport * 0.61 - 1);
  }
  // The first screen has no seam on either axis: sweep the phone band and assert the door, its
  // note and the sheet never overflow their containers.
  if (info.project.name === '390-light-no-preference') {
    for (let width = 320; width <= 430; width += 10) {
      for (let height = 640; height <= 760; height += 20) {
        await page.setViewportSize({ width, height });
        await page.evaluate(() => window.scrollTo(0, 0));
        const fold = await read();
        const label = `${width}x${height}`;
        expect(fold.scrollWidth, `${label}: no horizontal overflow`).toBeLessThanOrEqual(fold.viewportWidth);
        expect(fold.sheet.height / fold.viewport, `${label}: the sheet stays at or above 61%`).toBeGreaterThanOrEqual(0.61 - 1 / fold.viewport);
        expect(Math.abs(fold.sheet.bottom - fold.first.bottom), `${label}: the sheet stays inside the first screen`).toBeLessThanOrEqual(1);
        expect(fold.note.top, `${label}: the note starts on the first screen`).toBeGreaterThanOrEqual(0);
        expect(fold.note.bottom, `${label}: the note is on the first screen`).toBeLessThanOrEqual(fold.viewport);
        expect(fold.door.top, `${label}: the door starts on the first screen`).toBeGreaterThanOrEqual(0);
        expect(fold.door.bottom, `${label}: the door is on the first screen`).toBeLessThanOrEqual(fold.viewport);
      }
    }
  }
  // 320x568 keeps the floor: the entrance is still reachable.
  await page.setViewportSize({ width: 320, height: 568 });
  await page.evaluate(() => window.scrollTo(0, 0));
  const smallest = await read();
  expect(smallest.door.bottom, '320x568 keeps the door on the first screen').toBeLessThanOrEqual(smallest.viewport);
});
test('the watch-only demo advertises no input, and its count speaks like the room', async ({ page }, info) => {
  // The theatre draws no insertion point and no typing prompt: neither exists in a preview that
  // cannot take a keystroke (D-064).
  await expect(page.locator('#paper .caret, #paper [data-caret]')).toHaveCount(0);
  if (info.project.use.reducedMotion === 'reduce') {
    // The static draft is the finished one; its count names that draft and never an instruction.
    await expect(page.locator('#count')).toHaveText(/^\d+ words?$/);
    return;
  }
  await expect(page.locator('#count')).toHaveText('');
  const first = TIMELINE.events[0];
  await page.clock.fastForward(first.t + 10);
  // The first scripted word prints the same string the room prints for one word.
  await expect(page.locator('#count')).toHaveText(`${wordCount(first.cur)} ${wordCount(first.cur) === 1 ? 'word' : 'words'}`);
  await expect(page.locator('#count')).toHaveText('1 word');
});

test('the landing states the warning lead-in and never labels a moment with another moment', async ({ page }) => {
  const copy = await page.evaluate(() => ({
    moments: [...document.querySelectorAll('#core .mo small')].map(e => e.textContent.replace(/\s+/g, ' ').trim()),
    numeral: document.querySelector('#core .mo .n').textContent.trim(),
    stopped: [...document.querySelectorAll('#core .mo.m3 .t, #core .mo.m3 .r')].map(e => e.textContent.trim()),
    marker: [...document.querySelectorAll('#how .line8 .lab span, #how .line8 .lab b')].map(e => e.textContent.trim()),
    card: document.querySelectorAll('#how .card .txt')[1].textContent.replace(/\s+/g, ' ').trim(),
    faq: document.querySelector('#faq details p').textContent.replace(/\s+/g, ' ').trim(),
    schema: JSON.parse(document.querySelector('script[type="application/ld+json"]').textContent)['@graph'][1].mainEntity[0].acceptedAnswer.text,
  }));
  expect(copy.moments[0]).toMatch(/^0:47\b/);
  expect(copy.moments[2]).toMatch(/^8 s\b/);
  // The middle panel's label and its numeral name the same quantity: three seconds left.
  const label = copy.moments[1].match(/^(\d+) s left\b/);
  expect(label, `the warning panel is labelled with its own numeral: ${copy.moments[1]}`).not.toBeNull();
  expect(Number(label[1])).toBe(Number(copy.numeral));
  expect(Number(label[1]), 'the warning leads the deletion by three seconds').toBe(3);
  // The deleted panel shows the stopped screen's own words and names no second moment (D-070).
  expect(copy.stopped).toEqual(['You stopped.', 'Draft deleted.']);
  // One form for a silence mark everywhere.
  expect(copy.marker).toEqual(['last key', '5 s · warning', '8 s · deleted']);
  // The card says the one rule (D-101) and the marker above it shows the warning; the lead-in is stated in the answer the schema repeats word for word.
  expect(copy.card).toBe('8 seconds of silence deletes the draft.');
  expect(copy.faq).toMatch(/warning always starts three seconds before/i);
  expect(copy.faq).toBe(copy.schema);
});

test('the clock does not breathe: tabular numerals on the room and the demo', async ({ page }) => {
  const measure = () => page.evaluate(() => {
    const widths = element => ['1:00', '0:58', '0:11'].map(text => {
      const previous = element.textContent;
      element.textContent = text;
      const width = element.getBoundingClientRect().width;
      element.textContent = previous;
      return width;
    });
    return { demo: widths(document.querySelector('#clock')),
      demoNumeric: getComputedStyle(document.querySelector('#clock')).fontVariantNumeric };
  });
  const demo = await measure();
  expect(demo.demoNumeric).toBe('tabular-nums');
  expect(new Set(demo.demo.map(width => width.toFixed(2))).size, `the demo clock's width never changes: ${demo.demo}`).toBe(1);
  await enter(page);
  const room = await page.evaluate(() => {
    const element = document.querySelector('#room-clock');
    return { widths: ['1:00', '0:58', '0:11'].map(text => {
        const previous = element.textContent;
        element.textContent = text;
        const width = element.getBoundingClientRect().width;
        element.textContent = previous;
        return width;
      }),
      numeric: getComputedStyle(element).fontVariantNumeric,
      countNumeric: getComputedStyle(document.querySelector('#room-count')).fontVariantNumeric };
  });
  expect(room.numeric).toBe('tabular-nums');
  expect(new Set(room.widths.map(width => width.toFixed(2))).size, `the room clock's width never changes: ${room.widths}`).toBe(1);
  // The count on the same row was already tabular: one tool face, one numeral metric.
  expect(room.countNumeric).toBe('tabular-nums');
});
