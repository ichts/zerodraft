import { test, expect } from '@playwright/test';

// Text wrapping measured from computed styles and bounding boxes rather than eyeballed: a button label never breaks
// onto a second line, and body copy never cuts a word in half.
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
