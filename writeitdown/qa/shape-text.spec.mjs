import { test, expect } from '@playwright/test';

// Text wrapping and corner shape, measured from computed styles and bounding boxes rather than eyeballed.
// - Headings balance, paragraphs and list items use pretty, and the two writing sheets keep their own wrapping.
// - Every radius on every shipped page is on the 4 px grid and never below 4, pills and circles stay fully round,
//   and a panel padded p inside a card of radius R takes max(4, R - p) (design rule r = R - p).
// - Continuous corners are progressive enhancement: superellipse on boxes, round on pills.
// - Numbers that update or sit in a column keep their width; a button label never breaks onto a second line.
const pages = ['index.html', 'download/', 'mac.html', 'support.html', 'privacy.html', 'terms.html',
  'what-is-write-it-down.html', 'is-my-writing-saved.html', 'delete-a-draft.html',
  'write-it-down-free-trial.html', 'write-it-down-mac-vs-web.html', 'write-it-down-price.html'];
const px = value => parseFloat(value);
// `corner-shape: round` serialises as superellipse(1).
const ROUND = 'superellipse(1)';
const gridOk = value => value % 4 === 0;

for (const url of pages) {
  test(`${url}: headings balance, text pretty, radii on the 4 px grid`, async ({ page }) => {
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    const report = await page.evaluate(() => {
      const px = value => parseFloat(value);
      const inSheet = element => element.closest('.paper, .room-paper');
      const wrap = element => getComputedStyle(element).getPropertyValue('text-wrap-style');
      const rows = { headings: [], text: [], sheet: [], radii: [], pills: [] };
      // D-060 owns the download head's break (`Write It Down` / `for Mac` on a phone), so balance stays off it.
      const own = element => element.matches('.dl-page .dlhead h1');
      for (const element of document.querySelectorAll('h1, h2, h3')) (inSheet(element) || own(element) ? rows.sheet : rows.headings).push([element.tagName, wrap(element)]);
      for (const element of document.querySelectorAll('p, li')) (inSheet(element) ? rows.sheet : rows.text).push([element.tagName, wrap(element)]);
      for (const element of document.querySelectorAll('body *')) {
        const style = getComputedStyle(element);
        const corners = ['TopLeft', 'TopRight', 'BottomRight', 'BottomLeft'].map(c => style[`border${c}Radius`]);
        for (const radius of corners) {
          if (radius === '0px') continue;
          rows.radii.push({ tag: element.tagName, cls: element.className?.baseVal ?? element.className, radius });
        }
        if (corners.some(radius => px(radius) >= 999)) rows.pills.push({ cls: String(element.className), shape: style.cornerShape });
      }
      return rows;
    });
    for (const [tag, value] of report.headings) expect(value, `${url} <${tag}>`).toBe('balance');
    for (const [tag, value] of report.text) expect(value, `${url} <${tag}>`).toBe('pretty');
    // The sheets keep the wrapping their measured geometry was set with.
    for (const [tag, value] of report.sheet) expect(value, `${url} sheet <${tag}>`).toBe('auto');
    for (const { tag, cls, radius } of report.radii) {
      if (radius.endsWith('%')) continue; // the 50% dot is a circle
      const value = px(radius);
      if (value >= 999) continue; // pills
      expect(gridOk(value) && value >= 4, `${url} ${tag}.${cls} radius ${radius} is on the 4 px grid and at least 4`).toBe(true);
    }
    test.skip(!(await page.evaluate(() => CSS.supports('corner-shape', 'superellipse(1.25)'))), 'no continuous corners in this browser');
    for (const { cls, shape } of report.pills) expect(shape, `${url} pill ${cls}`).toBe(ROUND);
  });
}

test('continuous corners: boxes are superellipse, pills round, the header chip keeps its drawn squircle', async ({ page }) => {
  await page.goto('download/');
  const supported = await page.evaluate(() => CSS.supports('corner-shape', 'superellipse(1.25)'));
  test.skip(!supported, 'no continuous corners in this browser');
  const shapes = await page.evaluate(() => {
    const shape = (selector, pseudo = null) => getComputedStyle(document.querySelector(selector), pseudo).cornerShape;
    return { card: shape('.dlbox'), pill: shape('.btn'), theme: shape('.theme-btn'), chip: shape('.brand', '::before') };
  });
  expect(shapes.card).toBe('superellipse(1.25)');
  expect(shapes.pill).toBe(ROUND);
  expect(shapes.theme).toBe(ROUND);
  expect(shapes.chip).toBe(ROUND);
});

test('the two writing sheets share one radius, the cards share another', async ({ page }) => {
  await page.goto('./');
  const radii = await page.evaluate(() => {
    const radius = selector => getComputedStyle(document.querySelector(selector)).borderTopLeftRadius;
    return { demo: radius('#paper'), room: radius('.room-paper'), card: radius('.cards .card'), mac: radius('.mac-card'), moment: radius('.mo') };
  });
  expect(radii.demo, 'the demo sheet and the room sheet are one object').toBe(radii.room);
  expect(radii.demo).toBe('16px');
  expect([radii.card, radii.mac, radii.moment], 'cards and moments share the card radius').toEqual(['24px', '24px', '24px']);
});

// A panel padded p inside a card of radius R takes max(4, R - p), so both corners share one centre.
const nested = (card, panel) => ({ card, panel });
async function measureNested(page, pairs) {
  return page.evaluate(pairs => pairs.map(({ card, panel }) => {
    const outer = getComputedStyle(document.querySelector(card));
    const inner = getComputedStyle(document.querySelector(panel));
    return { card, panel, R: parseFloat(outer.borderTopLeftRadius), p: parseFloat(outer.paddingLeft), r: parseFloat(inner.borderTopLeftRadius) };
  }), pairs);
}

// The download page keeps no panel inside its cards (finding 43, A4): the hash, the release note and
// the install command open on one hairline rule and carry no fill, no radius and no closed box, so the
// nested-radius rule has nothing left to apply to there.
for (const width of [1440, 700, 360]) {
  test(`the download page's copyable blocks stay hairlines, not panels, at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('download/');
    const rows = await page.evaluate(() => ['.dlbox .sha', '#install code'].flatMap(selector =>
      [...document.querySelectorAll(selector)].map(element => {
        const style = getComputedStyle(element);
        return {
          selector, radius: parseFloat(style.borderTopLeftRadius), fill: style.backgroundColor,
          top: [parseFloat(style.borderTopWidth), style.borderTopStyle],
          closed: ['Right', 'Bottom', 'Left'].map(side => parseFloat(style['border' + side + 'Width'])),
        };
      })));
    expect(rows.map(row => row.selector), 'the two checksum blocks and the install command').toEqual(['.dlbox .sha', '.dlbox .sha', '#install code']);
    for (const row of rows) {
      expect(row.radius, `${row.selector} takes no radius`).toBe(0);
      expect(row.fill, `${row.selector} adds no fill`).toBe('rgba(0, 0, 0, 0)');
      expect(row.top, `${row.selector} opens on one hairline`).toEqual([1, 'solid']);
      expect(row.closed, `${row.selector} closes no box`).toEqual([0, 0, 0]);
    }
  });
}

// The key belongs to the licence card (A3): one hairline above it, and no ring, fill or radius of its
// own. The nested panel was a fourth box on a surface that needs one.
test('the licence key is a line in the card, not a card inside it', async ({ page }) => {
  await page.goto('mac.html');
  await page.evaluate(() => {
    document.querySelector('#license-delivery').hidden = false;
    document.querySelector('#license-result').hidden = false;
  });
  const box = await page.locator('.license-key').evaluate(el => {
    const style = getComputedStyle(el);
    return { top: style.borderTopWidth, right: style.borderRightWidth, bottom: style.borderBottomWidth,
      left: style.borderLeftWidth, style: style.borderTopStyle, radius: style.borderTopLeftRadius,
      background: style.backgroundColor };
  });
  expect(box, 'one hairline on top, nothing on the other three sides').toEqual({
    top: '1px', right: '0px', bottom: '0px', left: '0px', style: 'solid', radius: '0px', background: 'rgba(0, 0, 0, 0)' });
});

test('numbers that update or sit in a column keep their width', async ({ page }) => {
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  const widths = await page.evaluate(() => {
    const probe = (source, text, variant) => {
      const style = getComputedStyle(source);
      const span = document.createElement('span');
      span.style.cssText = `position:absolute;visibility:hidden;white-space:nowrap;font-style:${style.fontStyle};font-weight:${style.fontWeight};font-size:${style.fontSize};font-family:${style.fontFamily};letter-spacing:${style.letterSpacing};font-variant-numeric:${variant ?? style.fontVariantNumeric}`;
      span.textContent = text;
      document.body.append(span);
      const width = span.getBoundingClientRect().width;
      span.remove();
      return +width.toFixed(3);
    };
    const digits = ['0000', '1111', '8888'];
    const clock = document.querySelector('#clock');
    const fact = document.querySelector('.facts b');
    return {
      clock: digits.map(text => probe(clock, text)),
      fact: digits.map(text => probe(fact, text)),
      factVariant: getComputedStyle(fact).fontVariantNumeric,
      // Negative control: the bundled Newsreader face is proportional until tabular-nums is asked for.
      proportional: digits.map(text => probe(fact, text, 'proportional-nums')),
    };
  });
  expect(new Set(widths.clock).size, 'the clock digits share one width').toBe(1);
  expect(new Set(widths.fact).size, 'the price facts share one digit width').toBe(1);
  expect(widths.factVariant).toBe('tabular-nums');
  expect(new Set(widths.proportional).size, 'negative control: proportional Newsreader digits differ').toBeGreaterThan(1);
});

test('the mac page price keeps tabular figures', async ({ page }) => {
  await page.goto('mac.html');
  expect(await page.locator('.doc-price').evaluate(element => getComputedStyle(element).fontVariantNumeric)).toBe('tabular-nums');
});

test('a button label never breaks onto a second line, even on a 320 px phone', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 700 });
  for (const url of ['./', 'download/', 'mac.html']) {
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    const rows = await page.evaluate(() => [...document.querySelectorAll('button, .btn')]
      .filter(element => element.getClientRects().length)
      .map(element => {
        const range = document.createRange();
        range.selectNodeContents(element);
        return { cls: element.className || element.id, white: getComputedStyle(element).whiteSpace, lines: new Set([...range.getClientRects()].map(rect => Math.round(rect.top))).size };
      }));
    expect(rows.length, `${url} has buttons`).toBeGreaterThan(0);
    for (const row of rows) {
      expect(row.white, `${url} ${row.cls}`).toBe('nowrap');
      expect(row.lines, `${url} ${row.cls} stays on one line`).toBe(1);
    }
  }
});

test('body copy never cuts a word in half', async ({ page }) => {
  // A long unbreakable token is what `word-break: break-all` and `line-break: anywhere` were for: they let the
  // browser fill every line to the edge by cutting inside a word. Body copy must not do that - the whole token
  // moves to the next line, or overflows, and no line ever draws half of it.
  const token = 'incomprehensibilities'.repeat(6);
  for (const url of ['./', 'privacy.html', 'support.html']) {
    await page.goto(url);
    await page.evaluate(() => document.fonts.ready);
    const measured = await page.evaluate(token => {
      // A prose paragraph, not code: `overflow-wrap: anywhere` on a code block is deliberate, because a key or a
      // URL has no spaces to break at.
      const host = [...document.querySelectorAll('main p, .doc p, p')]
        .find(paragraph => paragraph.getClientRects().length && paragraph.textContent.trim().split(/\s+/).length > 12);
      if (!host) return null;
      const probe = document.createElement('p');
      probe.className = host.className;
      probe.textContent = `before ${token} after`;
      host.after(probe);
      const range = document.createRange();
      range.setStart(probe.firstChild, 7);
      range.setEnd(probe.firstChild, 7 + token.length);
      const rects = [...range.getClientRects()];
      const lines = new Set(rects.map(rect => Math.round(rect.top))).size;
      const column = Math.round(probe.getBoundingClientRect().width);
      // The token's own width, measured where nothing can wrap it: the wrapping probe's first line is only as
      // wide as its column once a word is being cut.
      const ruler = document.createElement('span');
      ruler.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap';
      ruler.textContent = token;
      probe.append(ruler);
      const width = Math.round(ruler.getBoundingClientRect().width);
      probe.remove();
      return { lines, column, token: width };
    }, token);
    expect(measured, `${url} has no body paragraph to measure`).not.toBeNull();
    expect(measured.token, `${url}: the probe token fits its ${measured.column}px column, so nothing is proven`)
      .toBeGreaterThan(measured.column);
    expect(measured.lines, `${url}: the ${measured.token}px token was cut across ${measured.lines} lines of a ${measured.column}px column`)
      .toBe(1);
  }
});
