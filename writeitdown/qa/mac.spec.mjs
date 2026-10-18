import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { CHECKOUT, DOWNLOAD, blockers, readInputs } from '../release-check.mjs';

const shipped = ['index.html', 'mac.html', 'support.html', 'privacy.html', 'terms.html'];
const appPrice = readInputs().plist.match(/<key>WIDDisplayPrice<\/key>\s*<string>([^<]*)</)[1];

test('Mac page states the offer and never shows a dead or fake purchase/download CTA', async ({ page }, info) => {
  await page.goto('mac.html');
  const main = page.locator('main');
  await expect(main.locator('h1')).toHaveText('Write It Down for Mac');
  await expect(page.locator('#price')).toHaveText(`${appPrice} ONCE. TWO MACS. NO SUBSCRIPTION.`);
  await expect(main).toContainText('first three writing sessions are free');
  await expect(main).not.toContainText('Polar');
  await expect(page.locator('#refund + p')).toContainText('14 days from purchase');

  for (const [slot, pattern] of [['checkout', CHECKOUT], ['download', DOWNLOAD]]) {
    const live = page.locator(`[data-launch="${slot}"]`);
    const pending = page.locator(`[data-launch-pending="${slot}"]`);
    const liveCount = await live.count();
    expect(liveCount + await pending.count(), `${slot} must be exactly one link or one pending notice`).toBe(1);
    if (liveCount) {
      expect(await live.evaluate(e => e.tagName)).toBe('A');
      expect(await live.getAttribute('href')).toMatch(pattern);
      await expect(live).toBeVisible();
    } else {
      await expect(pending).toBeVisible();
      expect(await pending.evaluate(e => e.tagName)).not.toBe('A');
      await expect(pending).toContainText('NOT');
    }
  }
  // Every door-styled control is a real link to a launch destination.
  for (const door of await page.locator('.door').all()) {
    expect(await door.evaluate(e => e.tagName)).toBe('A');
    expect(await door.getAttribute('data-launch')).toMatch(/^(checkout|download)$/);
  }
  const width = await page.evaluate(() => [document.documentElement.scrollWidth, innerWidth]);
  expect(width[0]).toBeLessThanOrEqual(width[1]);
  await page.screenshot({ path: info.outputPath('mac.png'), fullPage: true });
});

test('every shipped link resolves and every fragment exists', async ({ page, request }) => {
  const base = new URL('/writeitdown/', 'http://127.0.0.1:8015');
  for (const file of shipped) {
    await page.goto(file);
    const hrefs = await page.locator('a[href]').evaluateAll(links => links.map(a => a.getAttribute('href')));
    for (const href of hrefs) {
      expect(href, `${file}: empty or placeholder link`).not.toMatch(/^(#?|javascript:.*)$/);
      const url = new URL(href, new URL(file, base));
      if (url.origin !== base.origin) {
        expect(url.protocol, `${file}: ${href}`).toBe('https:');
        continue;
      }
      const response = await request.get(url.pathname);
      expect(response.ok(), `${file}: ${href}`).toBe(true);
      if (url.hash && url.hash !== '#trial') {
        expect(await response.text(), `${file}: ${href} fragment`).toContain(`id="${url.hash.slice(1)}"`);
      }
    }
  }
});

test('landing and help pages route to the Mac page', async ({ page }) => {
  await page.goto('index.html');
  await page.locator('.nav-actions a', { hasText: 'MAC APP' }).click();
  await expect(page).toHaveURL(/\/mac\.html$/);
  for (const file of ['support.html', 'privacy.html', 'terms.html']) {
    await page.goto(file);
    await expect(page.locator('.foot-links a[href="mac.html"]')).toHaveText('MAC APP');
  }
  expect(readFileSync('install.sh', 'utf8')).toMatch(/ mac\.html[ ']/);
});

test('release gate blocks until every launch input is real', () => {
  const inputs = readInputs();
  const url = 'https://checkout.example.com/wid';
  const live = inputs.mac
    .replace(/<p[^>]*data-launch-pending="download"[^>]*>.*?<\/p>/, '<a class="door" data-launch="download" href="https://example.com/wid-qa.dmg">DOWNLOAD FOR MAC</a>')
    .replace(/<p[^>]*data-launch-pending="checkout"[^>]*>.*?<\/p>/, `<a class="door" data-launch="checkout" href="${url}">BUY</a>`)
    .replace(/<p[^>]*data-launch-pending="license"[^>]*>.*?<\/p>/, '<p data-launch="license">Steps.</p>')
    .replace(/<p[^>]*data-launch-pending="sha256"[^>]*>.*?<\/p>/, `<p class="report">SHA-256 <code data-launch="sha256">${'0'.repeat(64)}</code></p>`);
  const support = inputs.support.replace('<h2 id="contact">Contact</h2>', '<h2 id="contact">Contact</h2><p><a href="mailto:help@example.com">help@example.com</a></p>');
  const plist = inputs.plist.replace(/(<key>WIDCheckoutURL<\/key>\s*<string>)[^<]*/, `$1${url}`);

  expect(blockers(inputs).length).toBeGreaterThan(0);
  expect(blockers({ mac: live, support, plist })).toEqual([]);
  expect(blockers({ mac: live, support, plist: inputs.plist })).toContain('Checkout URL: Info.plist WIDCheckoutURL differs from mac.html');
  expect(blockers({ mac: live.replace(url, 'http://example.com/pay'), support, plist })).toContain('Checkout URL: malformed in mac.html');
  expect(blockers({ mac: live.replace('wid-qa.dmg', 'wid-qa.zip'), support, plist })).toContain('Signed, notarized DMG URL: malformed in mac.html');
  expect(blockers({ mac: live.replace('<p data-launch="license">Steps.</p>', ''), support, plist })).toContain('License delivery and activation steps: not confirmed in mac.html');
  expect(blockers({ mac: live, support: inputs.support, plist })).toContain('Support address: not listed in support.html#contact');
  expect(blockers({ mac: live.replace(`${appPrice} ONCE.`, '$9 ONCE.'), support, plist }).some(line => line.startsWith('Price:'))).toBe(true);
});
