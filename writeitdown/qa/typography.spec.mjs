import { readFileSync } from 'node:fs';
import { test, expect } from '@playwright/test';
import { fontsSettled, openPage, sweepTimeout } from './page-sweep.mjs';

// The type set (D-057, faces replaced by D-119). writeitdown.app draws text with one face: Allo for what the writer
// writes, every heading and everything the tool says, Resource Han Rounded for the same roles in Chinese, and the
// system monospace for literal machine strings (a shell command, a hash). The hand accent is gone with Reenie Beanie.
//
// A role that leaves this set fails here rather than on a captain's screen. The Mac half of the advance contract is
// apps/macos/FirstLine/Tests/FirstLineTests/TypographyParityTests.swift, which reads qa/shared-type-baseline.json.
// The Mac still draws Newsreader until its own lane follows D-119, so that baseline stays the Mac's and the web's
// advance check below is held as a recorded divergence, not deleted.
const SHARED = {
  writing: /^Allo$/,
  chinese: /^"Resource Han Rounded"$/,
  machine: /^(ui-monospace|SFMono-Regular|Menlo|monospace)$/,
};
const baseline = JSON.parse(readFileSync(new URL('./shared-type-baseline.json', import.meta.url)));
const pages = ['index.html', 'download/', 'buy.html', 'mac.html', 'support.html', 'privacy.html', 'terms.html', 'impressum.html',
  'what-is-write-it-down.html', 'is-my-writing-saved.html', 'delete-a-draft.html',
  'write-it-down-free-trial.html', 'write-it-down-mac-vs-web.html', 'write-it-down-price.html'];
const fontHosts = /fonts\.(googleapis|gstatic)\.com/;

const firstFamily = stack => stack.split(',')[0].trim().replace(/^'(.*)'$/, '"$1"');

// Walks every element that renders its own text and reports the family it resolved to, so a new
// component cannot quietly pick a face up outside the set.
const census = () => {
  const rows = [];
  for (const element of document.querySelectorAll('body *')) {
    if (!element.getClientRects().length) continue;
    const text = [...element.childNodes]
      .filter(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim())
      .map(node => node.textContent.trim()).join(' ');
    if (!text) continue;
    const style = getComputedStyle(element);
    rows.push({
      tag: element.tagName.toLowerCase(),
      // A literal machine string keeps its monospace inside the element that declares it: the hash's
      // two unbroken halves and the install command's argument are spans inside their `code` block.
      inCode: element.closest('code, pre, kbd, samp') !== null,
      id: element.id,
      classes: element.className && typeof element.className === 'string' ? element.className : '',
      family: style.fontFamily,
      size: style.fontSize,
      weight: style.fontWeight,
      letterSpacing: style.letterSpacing,
      text: text.slice(0, 40),
    });
  }
  return rows;
};

const faceOf = row => Object.entries(SHARED)
  .find(([, pattern]) => pattern.test(firstFamily(row.family)))?.[0] ?? `unknown:${firstFamily(row.family)}`;

test('every text role on every shipped page stays in the shared type set', async ({ page }) => {
  test.setTimeout(sweepTimeout(pages.length));
  const found = new Map();
  for (const path of pages) {
    await openPage(page, path);
    const rows = await page.evaluate(census);
    for (const row of rows) {
      const face = faceOf(row);
      if (!found.has(face)) found.set(face, []);
      found.get(face).push(`${path} ${row.tag}${row.id ? '#' + row.id : ''}.${row.classes.split(' ')[0]} "${row.text}"`);
    }
    const stray = rows.filter(row => !['writing', 'chinese', 'machine'].includes(faceOf(row)));
    expect(stray.map(row => `${path} ${row.tag}.${row.classes}: ${row.family}`), `${path}: a text role left the shared set`).toEqual([]);
    const machine = rows.filter(row => faceOf(row) === 'machine');
    expect(machine.every(row => row.tag === 'code' || row.inCode), `${path}: monospace is reserved for code, found ${machine.map(r => `${r.tag}${r.inCode ? ' (in code)' : ''}`).join(',')}`).toBe(true);
  }
  // The census is only a guard if it actually sees the shared faces on the pages that carry them.
  expect([...found.keys()].sort(), 'the shared faces are present and named').toEqual(['machine', 'writing']);
});

test('the site serves its own faces and never asks another host for one', async ({ page }, info) => {
  test.setTimeout(sweepTimeout(pages.length));
  // Derived from the configured baseURL so the suite holds its own origin on another port.
  const origin = new URL(info.project.use.baseURL).origin;
  const foreign = [];
  page.on('request', request => {
    const url = request.url();
    if (!url.startsWith(origin)) {
      if (fontHosts.test(url) || /\.(woff2?|ttf|otf)(\?|$)/.test(url)) foreign.push(url);
    }
  });
  for (const path of pages) {
    await openPage(page, path);
    // The request log is the assertion, so wait for the faces this page loads before reading it.
    await fontsSettled(page);
  }
  expect(foreign, 'no page fetches a face from another origin').toEqual([]);

  // The known-broken proof for a host-served face: with both font hosts refused, the writing face must still be the
  // bundled Allo rather than a local fallback.
  await page.route(fontHosts, route => route.abort());
  await openPage(page, 'index.html');
  const resolved = await page.evaluate(async () => {
    await document.fonts.load('410 28px Allo');
    await document.fonts.ready;
    const probe = document.createElement('span');
    probe.id = 'type-probe';
    probe.style.cssText = 'position:fixed;left:20px;top:20px;font:410 28px/44.8px Allo,Georgia,serif';
    probe.textContent = 'promotion. i want time';
    document.body.append(probe);
    // Chrome records a node's platform font with the paint, so read the probe after two frames.
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return { ready: document.fonts.check('410 28px Allo'), faces: [...document.fonts].filter(f => f.family === 'Allo').map(f => f.status) };
  });
  expect(resolved.ready, 'Allo is available with the font hosts refused').toBe(true);
  expect(resolved.faces, 'the browser has the face the site ships, not a local substitute').toContain('loaded');
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('DOM.enable');
  await cdp.send('CSS.enable');
  const { root } = await cdp.send('DOM.getDocument');
  const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#type-probe' });
  const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
  expect(fonts.map(font => font.familyName).every(family => /^Allo/.test(family)), `the writing face is the bundled Allo: ${fonts.map(f => f.familyName)}`).toBe(true);
});

test('chinese in the room draws in Resource Han Rounded', async ({ page }) => {
  await page.goto('index.html#trial');
  // D-109: the room fixes its Chinese face at a draft's first Chinese character - the webfont if the file is already
  // resident, the platform face if it is not. An earlier Chinese draft on this page made it resident here, so this
  // measures the face the room draws with on that path, waiting for the face itself.
  await page.evaluate(() => document.fonts.load('28px "Resource Han Rounded"', '\u6211'));
  await page.click('#editor');
  const text = '我写中文草稿';
  await page.keyboard.insertText(text);
  const loaded = await page.evaluate(async text => {
    await document.fonts.ready;
    const editor = getComputedStyle(document.querySelector('#editor'));
    const probe = document.createElement('span');
    probe.id = 'cjk-probe';
    probe.style.cssText = 'position:fixed;left:20px;top:20px;white-space:pre;'
      + `font:${editor.fontWeight} ${editor.fontSize}/${editor.lineHeight} ${editor.fontFamily}`;
    probe.textContent = text;
    document.body.append(probe);
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return { stack: editor.fontFamily, ready: document.fonts.check('400 28px "Resource Han Rounded"', text) };
  }, text);
  expect(loaded.ready, 'the shipped Chinese face covers the draft').toBe(true);
  expect(loaded.stack, 'the writing stack names Allo first and the Chinese face second')
    .toMatch(/^Allo, "Resource Han Rounded",/);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('DOM.enable');
  await cdp.send('CSS.enable');
  const { root } = await cdp.send('DOM.getDocument');
  const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#cjk-probe' });
  const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
  const platform = fonts.map(font => font.familyName);
  expect(platform.filter(family => /^Resource Han Rounded/.test(family)).length, `Chinese draws in Resource Han Rounded, got ${platform}`).toBe(1);
  expect(platform.some(family => /PingFang|Songti|SimSun/.test(family)), 'no system CJK face takes over').toBe(false);
});

test('the clock keeps its width as the session counts down', async ({ page }) => {
  await page.goto('index.html#trial');
  const clock = await page.evaluate(() => {
    const element = document.querySelector('#room-clock');
    const style = getComputedStyle(element);
    const width = value => {
      const previous = element.textContent;
      element.textContent = value;
      const measured = element.getBoundingClientRect().width;
      element.textContent = previous;
      return +measured.toFixed(3);
    };
    return {
      variant: style.fontVariantNumeric,
      size: style.fontSize,
      weight: style.fontWeight,
      family: style.fontFamily,
      one: width('1:00'),
      zero: width('0:59'),
    };
  });
  expect(clock.variant, 'the clock sets tabular digits like the Mac').toBe('tabular-nums');
  expect(clock.size, 'the clock is 15 px like the Mac').toBe('15px');
  expect(clock.weight, 'the clock is semibold like the Mac').toBe('600');
  expect(faceOf(clock), 'the clock is the one face').toBe('writing');
  expect(Math.abs(clock.one - clock.zero), `the clock does not change width between 1:00 (${clock.one}) and 0:59 (${clock.zero})`).toBeLessThanOrEqual(0.01);
});

test('the shared writing roles advance like the Mac', async ({ page }) => {
  // Held, not deleted: the baseline is the Mac's Newsreader, and the Mac lane follows D-119 with its own measured
  // baseline. When that lands this test runs again against the Allo advances on both surfaces.
  test.skip(!baseline.roles.some(role => role.cssFamily === 'Allo'), 'D-119: the Mac still draws Newsreader; the Mac lane re-measures the shared baseline in Allo');
  await page.goto('index.html');
  for (const role of baseline.roles) {
    const advance = await page.evaluate(async ({ family, size, weight, style, string }) => {
      await document.fonts.load(`${style} ${weight} ${size}px "${family}"`, string);
      await document.fonts.ready;
      const probe = document.createElement('span');
      probe.style.cssText = 'position:fixed;left:0;top:0;white-space:pre;letter-spacing:normal;'
        + `font-family:"${family}",serif;font-size:${size}px;font-weight:${weight};font-style:${style}`;
      probe.textContent = string;
      document.body.append(probe);
      const width = probe.getBoundingClientRect().width;
      probe.remove();
      return width;
    }, { family: role.cssFamily, size: role.size, weight: role.cssWeight, style: role.cssStyle, string: role.string });
    const drift = Math.abs(advance - role.advancePt) / role.advancePt;
    expect(drift, `${role.role} "${role.string}" at ${role.size}: the web draws ${advance.toFixed(3)}, the Mac ${role.advancePt}`).toBeLessThanOrEqual(baseline.tolerance);
  }
});

test('the result headings carry the Mac\'s tracking, not the web\'s old negative value', async ({ page }) => {
  await page.goto('index.html');
  const headings = await page.evaluate(() => {
    const read = selector => {
      const style = getComputedStyle(document.querySelector(selector));
      return { family: style.fontFamily, weight: style.fontWeight, letterSpacing: style.letterSpacing };
    };
    return { kept: read('#kept h1'), stopped: read('.room-top h1') };
  });
  for (const [name, heading] of Object.entries(headings)) {
    expect(faceOf(heading), `${name} heading is Allo`).toBe('writing');
    expect(heading.weight, `${name} heading is the display weight (D-119)`).toBe('540');
    expect(heading.letterSpacing, `${name} heading sets no tracking, as the Mac does not`).toBe('normal');
  }
});

test('the kept receipt and the machine-voice labels keep the Mac\'s 13 px medium and its tracking', async ({ page }) => {
  await page.goto('index.html');
  const roles = await page.evaluate(() => {
    const read = selector => {
      const style = getComputedStyle(document.querySelector(selector));
      return { family: style.fontFamily, size: style.fontSize, weight: style.fontWeight, letterSpacing: style.letterSpacing };
    };
    return { receipt: read('.kept-receipt'), note: read('#failure-note'), caption: read('#room-warning'), count: read('#room-count') };
  });
  for (const name of ['receipt', 'caption']) {
    expect(roles[name].size, `${name} is 13 px like the Mac`).toBe('13px');
    expect(roles[name].weight, `${name} is the Mac's medium`).toBe('500');
    expect(faceOf(roles[name]), `${name} is the one face`).toBe('writing');
  }
  expect(roles.receipt.letterSpacing, 'the receipt keeps the Mac\'s .02em').toBe('0.26px');
  expect(roles.note.size, 'the stopped screen\'s consequence line is 15 px').toBe('15px');
  expect(roles.note.weight, 'the consequence line is regular').toBe('400');
  expect(faceOf(roles.note), 'the consequence line is the one face').toBe('writing');
  expect(parseFloat(roles.note.letterSpacing) || 0, 'the consequence line sets no tracking').toBe(0);
  // Round 006 (D-119): the caption is a sentence at note size, so it carries no caps tracking.
  expect(parseFloat(roles.caption.letterSpacing) || 0, 'the warning caption sets no tracking').toBe(0);
  expect(roles.count.size, 'the count is 13 px like the Mac').toBe('13px');
  expect(roles.count.weight, 'the count is regular like the Mac').toBe('400');
  expect(faceOf(roles.count), 'the count is the one face').toBe('writing');
});
