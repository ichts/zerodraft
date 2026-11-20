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

test('the shared writing roles advance like the Mac', async ({ page }) => {
  // Both surfaces draw Allo and Resource Han Rounded (D-119, D-120); the numeral is measured with its tabular figures.
  await page.goto('index.html');
  for (const role of baseline.roles) {
    const advance = await page.evaluate(async ({ family, size, weight, style, numeric, string }) => {
      await document.fonts.load(`${style} ${weight} ${size}px "${family}"`, string);
      await document.fonts.ready;
      const probe = document.createElement('span');
      probe.style.cssText = 'position:fixed;left:0;top:0;white-space:pre;letter-spacing:normal;'
        + `font-family:"${family}",serif;font-size:${size}px;font-weight:${weight};font-style:${style};`
        + `font-variant-numeric:${numeric}`;
      probe.textContent = string;
      document.body.append(probe);
      const width = probe.getBoundingClientRect().width;
      probe.remove();
      return width;
    }, { family: role.cssFamily, size: role.size, weight: role.cssWeight, style: role.cssStyle,
      numeric: role.cssNumeric ?? 'normal', string: role.string });
    const drift = Math.abs(advance - role.advancePt) / role.advancePt;
    expect(drift, `${role.role} "${role.string}" at ${role.size}: the web draws ${advance.toFixed(3)}, the Mac ${role.advancePt}`).toBeLessThanOrEqual(baseline.tolerance);
  }
});
