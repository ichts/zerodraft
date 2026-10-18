import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const shipped = ['index.html', 'mac.html', 'support.html', 'privacy.html', 'terms.html'];
const plistPath = '../apps/macos/FirstLine/Sources/FirstLine/Info.plist';
const appPrice = readFileSync(plistPath, 'utf8').match(/<key>WIDDisplayPrice<\/key>\s*<string>([^<]*)</)[1];

test('Mac page sells a paid app, points to the free web trial, and has no dead or fake CTA', async ({ page }, info) => {
  await page.goto('mac.html');
  const main = page.locator('main');
  await expect(main.locator('h1')).toHaveText('Write It Down for Mac');
  await expect(page.locator('#price')).toHaveText(`${appPrice} ONCE. TWO MACS. NO SUBSCRIPTION.`);
  await expect(main).toContainText('The Mac app is paid.');
  await expect(main).not.toContainText(/free (writing )?sessions|three/i);
  await expect(page.locator('#refund + p')).toContainText('14 days from purchase');

  for (const slot of ['checkout', 'download', 'license']) {
    const live = page.locator(`[data-launch="${slot}"]`);
    const pending = page.locator(`[data-launch-pending="${slot}"]`);
    expect(await live.count() + await pending.count(), `${slot}: exactly one live element or one pending notice`).toBe(1);
    if (await pending.count()) {
      await expect(pending).toBeVisible();
      expect(await pending.evaluate(e => e.tagName)).not.toBe('A');
    }
  }
  // Every door-styled control is a real, working link.
  for (const door of await page.locator('.door').all()) {
    expect(await door.evaluate(e => e.tagName)).toBe('A');
    expect(await door.getAttribute('href')).toMatch(/^(index\.html#trial|https:\/\/\S+)$/);
  }
  await page.locator('.door', { hasText: 'TRY IT IN YOUR BROWSER' }).click();
  await expect(page.locator('#editor')).toBeFocused();

  await page.goto('mac.html');
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

test('help pages route to the Mac page', async ({ page }) => {
  for (const file of ['support.html', 'privacy.html', 'terms.html']) {
    await page.goto(file);
    await page.locator('.foot-links a', { hasText: 'MAC APP' }).click();
    await expect(page).toHaveURL(/\/mac\.html$/);
  }
});

// Runs the real release gate CLI against a site copy and returns [exit code, output].
function releaseCheck({ mac, support, checkout = '' }, ...args) {
  const root = mkdtempSync(join(tmpdir(), 'wid-release-'));
  const site = join(root, 'writeitdown');
  const plistDir = join(root, 'apps/macos/FirstLine/Sources/FirstLine');
  mkdirSync(site); mkdirSync(plistDir, { recursive: true });
  writeFileSync(join(site, 'mac.html'), mac);
  writeFileSync(join(site, 'support.html'), support);
  writeFileSync(join(plistDir, 'Info.plist'), readFileSync(plistPath, 'utf8')
    .replace(/(<key>WIDCheckoutURL<\/key>\s*<string>)[^<]*/, `$1${checkout}`));
  try {
    return [0, execFileSync('node', ['release-check.mjs', '--root', site, ...args], { encoding: 'utf8', stdio: 'pipe' })];
  } catch (error) {
    return [error.status, error.stderr];
  }
}

test('release gate stays blocked on missing, fake, or placeholder launch inputs', () => {
  const mac = readFileSync('mac.html', 'utf8');
  const support = readFileSync('support.html', 'utf8');
  const checkout = 'https://pay.writeitdown.app/wid-mac';
  const fill = ({ buy = checkout, dmg = 'https://downloads.writeitdown.app/Write-It-Down-1.0.dmg',
    steps = 'Open the purchase email, copy the license key, and paste it into Settings.' } = {}) => mac
    .replace(/<p[^>]*data-launch-pending="checkout"[^>]*>.*?<\/p>/, `<a class="door" data-launch="checkout" href="${buy}">BUY</a>`)
    .replace(/<p[^>]*data-launch-pending="download"[^>]*>.*?<\/p>/, `<a class="door" data-launch="download" href="${dmg}">DOWNLOAD</a>`)
    .replace(/<p[^>]*data-launch-pending="license"[^>]*>.*?<\/p>/, `<p data-launch="license">${steps}</p>`);
  const contact = support.replace('<h2 id="contact">Contact</h2>', '<h2 id="contact">Contact</h2><p><a href="mailto:help@writeitdown.app">help@writeitdown.app</a></p>');

  const [current, currentOut] = releaseCheck({ mac, support }, '--live');
  expect(current).toBe(1);
  for (const line of ['Checkout URL: not confirmed', 'DMG URL: not confirmed', 'activation steps: not confirmed', 'Support address'])
    expect(currentOut).toContain(line);

  const [ready, readyOut] = releaseCheck({ mac: fill(), support: contact, checkout });
  expect(ready).toBe(0);
  expect(readyOut).toContain('Not verified live');
  expect(readyOut).toContain('real test order');

  const cases = [
    [{ mac: fill({ buy: 'https://example.com/pay' }), checkout: 'https://example.com/pay' }, 'Checkout URL: not a real https destination'],
    [{ mac: fill({ dmg: 'https://downloads.writeitdown.app/app.zip' }) }, 'DMG URL: not a real https .dmg destination'],
    [{ mac: fill({ dmg: 'https://x.test/Write-It-Down.dmg' }) }, 'DMG URL: not a real https .dmg destination'],
    [{ mac: fill({ steps: 'Steps.' }) }, 'activation steps: placeholder copy'],
    [{ mac: fill(), checkout: '' }, 'WIDCheckoutURL differs'],
    [{ mac: fill().replace(`${appPrice} ONCE.`, '$9 ONCE.') }, 'Price:'],
    [{ mac: fill(), support }, 'Support address'],
  ];
  for (const [input, message] of cases) {
    const [code, out] = releaseCheck({ support: contact, checkout, ...input });
    expect(code, message).toBe(1);
    expect(out).toContain(message);
  }
});
