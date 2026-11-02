import { test, expect } from '@playwright/test';

// The legal notice (Impressum): the operator block the captain approved, verbatim, and the footer
// link on every shipped page. The footer geometry is measured, not eyeballed.
const pages = ['index.html', 'download/', 'mac.html', 'support.html', 'privacy.html', 'terms.html', 'impressum.html',
  'what-is-write-it-down.html', 'is-my-writing-saved.html', 'delete-a-draft.html',
  'write-it-down-free-trial.html', 'write-it-down-mac-vs-web.html', 'write-it-down-price.html'];
const address = 'Balsahout 4, 2719 MJ Zoetermeer, Netherlands';

test('the Impressum names the operator, address and email exactly, and nothing else', async ({ page }) => {
  await page.goto('impressum.html');
  await expect(page).toHaveTitle('Impressum - Write It Down');
  await expect(page.locator('h1')).toHaveText('Impressum');
  const blocks = await page.locator('main.doc > *').evaluateAll(els => els.map(e => e.textContent.replace(/\u00a0/g, ' ').trim()));
  expect(blocks).toEqual([
    'Impressum',
    'Operator', 'Ian Zhou (Trefoil Studio)',
    'Address', address,
    'Email', 'contact@trefoilstudio.com',
    'Responsible for content (§ 18 MStV)', `Ian Zhou, ${address}`,
  ]);
  await expect(page.locator('main.doc a[href="mailto:contact@trefoilstudio.com"]')).toHaveCount(1);
  const text = await page.locator('main.doc').innerText();
  expect(text).not.toMatch(/KvK|VAT|BTW|phone|tel\b|\u2014/i);
});

test('the Impressum is canonical, in the sitemap and linked from every footer', async ({ page, request }) => {
  const xml = await (await request.get('/writeitdown/sitemap.xml')).text();
  expect(xml).toContain('<loc>https://writeitdown.app/impressum.html</loc>');
  await page.goto('impressum.html');
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://writeitdown.app/impressum.html');
  for (const path of pages) {
    await page.goto(path);
    const link = page.locator('.home-foot nav[aria-label="Legal"] a', { hasText: 'Impressum' });
    await expect(link, path).toHaveCount(1);
    await link.click();
    await expect(page, path).toHaveURL(/\/impressum\.html$/);
  }
});

test('the Legal footer column stays aligned with its siblings on every page', async ({ page }) => {
  const read = () => page.evaluate(() => {
    const box = el => { const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, r: r.right }; };
    const columns = [...document.querySelectorAll('.foot-grid nav')].map(nav => ({
      nav: box(nav), links: [...nav.querySelectorAll('a')].map(box),
    }));
    return {
      columns, grid: box(document.querySelector('.foot-grid')),
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      width: document.documentElement.clientWidth,
    };
  });
  const reference = {};
  for (const path of pages) {
    await page.goto(path);
    const m = await read();
    const legal = m.columns[2];
    expect(legal.links.length, `${path}: Legal links`).toBe(3);
    expect(m.overflow, `${path}: no horizontal overflow`).toBeLessThanOrEqual(0);
    for (const link of legal.links) {
      expect(Math.abs(link.x - legal.nav.x), `${path}: link left edge on the column edge`).toBeLessThan(0.5);
      expect(link.r, `${path}: link inside the viewport`).toBeLessThanOrEqual(m.width);
      expect(link.r, `${path}: link inside its grid`).toBeLessThanOrEqual(m.grid.r + 0.5);
    }
    const pitch = legal.links.map((l, i) => i && l.y - legal.links[i - 1].y).slice(1);
    expect(Math.abs(pitch[0] - pitch[1]), `${path}: even link pitch`).toBeLessThan(0.5);
    // A column of three links is as tall as the Product column of three: no row grows.
    expect(Math.abs(legal.nav.h - m.columns[0].nav.h), `${path}: Legal as tall as Product`).toBeLessThan(0.5);
    expect(Math.abs(legal.nav.y - m.columns[1].nav.y), `${path}: Legal on the Help column's row`).toBeLessThan(0.5);
    const key = { w: m.width, gridH: Math.round(m.grid.h * 10) / 10, legalH: Math.round(legal.nav.h * 10) / 10 };
    reference.first ??= key;
    expect(key, `${path}: footer geometry equals the first page's`).toEqual(reference.first);
  }
});
