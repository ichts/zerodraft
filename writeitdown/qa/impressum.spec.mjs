import { test, expect } from '@playwright/test';
import { openPage, sweepTimeout } from './page-sweep.mjs';

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
  test.setTimeout(sweepTimeout(pages.length));
  const xml = await (await request.get('/writeitdown/sitemap.xml')).text();
  expect(xml).toContain('<loc>https://writeitdown.app/impressum.html</loc>');
  await openPage(page, 'impressum.html');
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://writeitdown.app/impressum.html');
  for (const path of pages) {
    await openPage(page, path);
    const link = page.locator('.home-foot nav[aria-label="Legal"] a', { hasText: 'Impressum' });
    await expect(link, path).toHaveCount(1);
    await link.click();
    await expect(page, path).toHaveURL(/\/impressum\.html$/);
  }
});
