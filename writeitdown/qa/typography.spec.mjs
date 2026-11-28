import { readFileSync } from 'node:fs';
import { test, expect } from '@playwright/test';
import { fontsSettled, openPage, sweepTimeout } from './page-sweep.mjs';

// The shared type set (D-125). The Mac app and writeitdown.app draw text with the same faces: Allo for
// every product role (what the writer writes, every heading, everything the tool says), Resource Han
// Rounded for the same roles in Chinese, and the system monospace for literal machine strings (a shell
// command, a hash). Reenie Beanie is the one declared exception: the landing's hand accent, marketing
// only, never in the room and never on the Mac (D-057).
//
// A role that leaves this set fails here rather than on a captain's screen. The Mac half of the same
// contract is apps/macos/FirstLine/Tests/FirstLineTests/TypographyParityTests.swift; both halves read
// qa/shared-type-baseline.json for the advances, so a size, face or tracking change on either surface
// fails the other surface's test with a readable number.
const SHARED = {
  product: /^"?Allo"?$/,
  chinese: /^"Resource Han Rounded"$/,
  machine: /^(ui-monospace|SFMono-Regular|Menlo|monospace)$/,
  accent: /^"Reenie Beanie"$/,
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
    const stray = rows.filter(row => {
      const face = faceOf(row);
      if (face === 'accent') return !/\bhand\b/.test(row.classes);
      return !['product', 'chinese', 'machine'].includes(face);
    });
    expect(stray.map(row => `${path} ${row.tag}.${row.classes}: ${row.family}`), `${path}: a text role left the shared set`).toEqual([]);
    const machine = rows.filter(row => faceOf(row) === 'machine');
    expect(machine.every(row => row.tag === 'code' || row.inCode), `${path}: monospace is reserved for code, found ${machine.map(r => `${r.tag}${r.inCode ? ' (in code)' : ''}`).join(',')}`).toBe(true);
  }
  // The census is only a guard if it actually sees the shared faces on the pages that carry them.
  expect([...found.keys()].sort(), 'the shared faces are present and named').toEqual(['accent', 'machine', 'product']);
  expect(found.get('accent').length, 'the hand accent exists on the landing only').toBeLessThanOrEqual(3);
  expect(found.get('accent').every(row => row.startsWith('index.html ')), 'the hand accent stays on the landing').toBe(true);
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

  // With both font hosts refused, the writing face must still be the bundled Allo rather than a local fallback.
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
    return { ready: document.fonts.check('410 28px Allo'), faces: [...document.fonts].filter(f => f.family.replace(/"/g, '') === 'Allo').map(f => f.status) };
  });
  expect(resolved.ready, 'Allo is available with the font hosts refused').toBe(true);
  expect(resolved.faces, 'the browser has the faces the site ships, not a local substitute').toContain('loaded');
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('DOM.enable');
  await cdp.send('CSS.enable');
  const { root } = await cdp.send('DOM.getDocument');
  const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#type-probe' });
  const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
  expect(fonts.map(font => font.familyName), 'the writing face is the bundled Allo').toEqual(['Allo Variable']);
});

test('chinese in the room draws in Resource Han Rounded', async ({ page }) => {
  await page.goto('index.html#trial');
  // D-109: the room fixes its Chinese face at a draft's first Chinese character - Resource Han Rounded if the file is
  // already resident, the platform face if it is not - and never revisits it until the sheet is empty again. This measures the face the room draws
  // with on the normal path, where a trial link the visitor touched has prefetched the file, so it waits for the face
  // itself rather than for `document.fonts.check()`, which reports true while the file is still only loading.
  await page.waitForFunction(() => [...document.fonts]
    .some(face => face.family.includes('Resource Han Rounded') && face.status === 'loaded'), null, { timeout: 30_000 });
  await page.click('#editor');
  const text = '我写中文草稿';
  await page.keyboard.insertText(text);
  const loaded = await page.evaluate(async text => {
    await document.fonts.load('400 28px "Resource Han Rounded"', text);
    await document.fonts.ready;
    const editor = getComputedStyle(document.querySelector('#editor'));
    const probe = document.createElement('span');
    probe.id = 'cjk-probe';
    probe.style.cssText = 'position:fixed;left:20px;top:20px;white-space:pre;'
      + `font:${editor.fontWeight} ${editor.fontSize}/${editor.lineHeight} ${editor.fontFamily}`;
    probe.textContent = text;
    document.body.append(probe);
    // Same paint dependency as the Allo probe above.
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
  expect(platform.filter(family => /^Resource Han Rounded/.test(family)).length, `Chinese draw in Resource Han Rounded, got ${platform}`).toBe(1);
  expect(platform.some(family => /PingFang|Songti|SimSun/.test(family)), 'no system CJK face takes over').toBe(false);
});

test('the shared writing roles advance like the Mac', async ({ page }) => {
  await page.goto('index.html');
  for (const role of baseline.roles) {
    const advance = await page.evaluate(async ({ family, size, weight, style, numeric, string }) => {
      await document.fonts.load(`${style} ${weight} ${size}px "${family}"`, string);
      await document.fonts.ready;
      const probe = document.createElement('span');
      probe.style.cssText = 'position:fixed;left:0;top:0;white-space:pre;letter-spacing:normal;'
        + `font-family:"${family}",serif;font-size:${size}px;font-weight:${weight};font-style:${style};font-variant-numeric:${numeric}`;
      probe.textContent = string;
      document.body.append(probe);
      const width = probe.getBoundingClientRect().width;
      probe.remove();
      return width;
    }, { family: role.cssFamily, size: role.size, weight: role.cssWeight, style: role.cssStyle, numeric: role.cssNumeric ?? 'normal', string: role.string });
    const drift = Math.abs(advance - role.advancePt) / role.advancePt;
    expect(drift, `${role.role} "${role.string}" at ${role.size}: the web draws ${advance.toFixed(3)}, the Mac ${role.advancePt}`).toBeLessThanOrEqual(baseline.tolerance);
  }
});
