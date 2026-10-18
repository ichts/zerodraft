import { test, expect } from '@playwright/test';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';

const shipped = ['index.html', 'mac.html', 'support.html', 'privacy.html', 'terms.html'];
const plistPath = '../apps/macos/FirstLine/Sources/FirstLine/Info.plist';
const appPrice = readFileSync(plistPath, 'utf8').match(/<key>WIDDisplayPrice<\/key>\s*<string>([^<]*)</)[1];

test('Mac page sells a paid app, points to the free web trial, and has no dead or fake CTA', async ({ page }, info) => {
  await page.goto('mac.html');
  const main = page.locator('main');
  await expect(main.locator('h1')).toHaveText('Write It Down for Mac');
  await expect(page.locator('#price')).toHaveText(`${appPrice} ONCE. TWO MACS. NO SUBSCRIPTION.`);
  await expect(main).toContainText('The Mac app will be paid when sales open.');
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
  // Every door-styled control is a real, working link, except the waitlist form's own submit.
  await expect(page.locator('#waitlist-form button.door[type="submit"]')).toHaveText('NOTIFY ME');
  for (const door of await page.locator('.door:not(#waitlist-form .door)').all()) {
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
      if (url.protocol === 'mailto:') {
        expect(href, `${file}: mailto must be the confirmed contact`).toBe('mailto:contact@trefoilstudio.com');
        continue;
      }
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
  const contact = support;
  const noContact = support.replace(/<a href="mailto:[^"]*">[^<]*<\/a>/g, 'TBD');

  const [current, currentOut] = releaseCheck({ mac, support }, '--live');
  expect(current).toBe(1);
  for (const line of ['Checkout URL: not confirmed', 'DMG URL: not confirmed', 'activation steps: not confirmed'])
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
    [{ mac: fill(), support: noContact }, 'Support address'],
  ];
  for (const [input, message] of cases) {
    const [code, out] = releaseCheck({ support: contact, checkout, ...input });
    expect(code, message).toBe(1);
    expect(out).toContain(message);
  }
});

test('landing keeps Try web primary and offers the Mac app as a secondary coming-soon link', async ({ page }) => {
  await page.goto('index.html');
  const hero = page.locator('header.hero');
  await expect(hero.locator('.door')).toHaveText('Give it sixty seconds.');
  const secondary = hero.locator('a.hero-secondary');
  await expect(secondary).toHaveText(/BUY MAC USD 4\.99 - COMING SOON/);
  await expect(page.locator('a[href*="checkout"], a[href$=".dmg"]')).toHaveCount(0);
  await secondary.click();
  await expect(page).toHaveURL(/\/mac\.html#waitlist$/);
  await expect(page.locator('#waitlist-form')).toBeVisible();
});

test('installer refuses to publish the signup form before the collector answers', () => {
  test.skip(test.info().project.name !== '1440-dark-no-preference', 'filesystem check, one project is enough');
  expect(execFileSync('python3', ['qa/test-install.py'], { encoding: 'utf8' })).toContain('refused while the waitlist collector is down');
});

const respond = (status, outcome) => route => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify({ status: outcome }) });
async function fillWaitlist(page) {
  await page.locator('#waitlist-email').fill('reader@example.com');
  await page.locator('input[name="consent"]').check();
}

test('waitlist states its consent and reports each JavaScript outcome', async ({ page }, info) => {
  await page.goto('mac.html');
  await expect(page.locator('h2#waitlist')).toHaveText('Purchase opens soon');
  await expect(page.locator('.waitlist-consent')).toContainText('That is the only email.');
  await expect(page.locator('.waitlist-zh')).toContainText('仅此一封');
  let body = '';
  for (const [status, outcome, text] of [[200, 'joined', 'YOU ARE ON THE LIST'], [400, 'invalid', 'ENTER A VALID EMAIL'],
    [429, 'limited', 'TOO MANY TRIES'], [500, 'error', 'NOT SAVED']]) {
    await page.route('**/api/waitlist', route => { body = route.request().postData(); return respond(status, outcome)(route); });
    await fillWaitlist(page);
    await page.locator('#waitlist-form button').click();
    await expect(page.locator('#waitlist-status')).toContainText(text);
    await expect(page).toHaveURL(/mac\.html$/);
    await page.locator('#waitlist-form').screenshot({ path: info.outputPath(`waitlist-js-${outcome}.png`) });
    await page.unroute('**/api/waitlist');
  }
  const sent = new URLSearchParams(body);
  expect([sent.get('email'), sent.get('consent'), sent.get('website')]).toEqual(['reader@example.com', 'yes', '']);

  // A collector that is down or not deployed never reads as success.
  await page.route('**/api/waitlist', route => route.abort());
  await page.locator('#waitlist-form button').click();
  await expect(page.locator('#waitlist-status')).toContainText('NOT SAVED');
  await page.unroute('**/api/waitlist');
  await page.route('**/api/waitlist', route => route.fulfill({ status: 404, contentType: 'text/html', body: 'Not found' }));
  await page.locator('#waitlist-form button').click();
  await expect(page.locator('#waitlist-status')).toContainText('NOT SAVED');
});

test('browser validation blocks an empty address or missing consent before any request', async ({ page }) => {
  let requests = 0;
  await page.route('**/api/waitlist', route => { requests++; return respond(200, 'joined')(route); });
  await page.goto('mac.html');
  await page.locator('#waitlist-form button').click();
  await expect(page.locator('#waitlist-email')).toBeFocused();
  await page.locator('#waitlist-email').fill('reader@example.com');
  await page.locator('#waitlist-form button').click();
  await expect(page.locator('input[name="consent"]')).toBeFocused();
  expect(requests).toBe(0);
});

test('keyboard reaches email, consent, and submit in order', async ({ page }) => {
  await page.route('**/api/waitlist', respond(200, 'joined'));
  await page.goto('mac.html');
  await page.locator('#waitlist-email').focus();
  await page.keyboard.type('reader@example.com');
  await page.keyboard.press('Tab');
  await expect(page.locator('input[name="consent"]')).toBeFocused();
  await page.keyboard.press('Space');
  await page.keyboard.press('Tab');
  if (await page.evaluate(() => !!document.activeElement.closest('a'))) await page.keyboard.press('Tab');
  await expect(page.locator('#waitlist-form button')).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.locator('#waitlist-status')).toContainText('YOU ARE ON THE LIST');
});

test('actual Mac form registers through the Go collector with JS and without JS', async ({ page, browser }) => {
  test.skip(test.info().project.name !== '1440-dark-no-preference', 'one real collector run is enough');
  const root = mkdtempSync(join(tmpdir(), 'wid-collector-'));
  const binary = join(root, 'collector');
  const build = spawnSync('go', ['build', '-o', binary, '.'], { cwd: '../services/waitlist', encoding: 'utf8' });
  expect(build.status, build.stderr).toBe(0);
  const listener = createServer();
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const file = join(root, 'subscribers.tsv');
  const collector = spawn(binary, [], {
    env: { ...process.env, WAITLIST_ADDR: `127.0.0.1:${port}`, WAITLIST_FILE: file,
      WAITLIST_ORIGIN: 'http://127.0.0.1:8015', WAITLIST_RETURN_URL: 'http://127.0.0.1:8015/writeitdown/mac.html' },
    stdio: 'ignore',
  });
  const forward = async route => {
    const response = await route.fetch({ url: `http://127.0.0.1:${port}/api/waitlist`, maxRedirects: 0 });
    await route.fulfill({ response });
  };
  let noJS;
  try {
    await expect.poll(async () => {
      try { return (await fetch(`http://127.0.0.1:${port}/api/waitlist/health`)).status; }
      catch { return 0; }
    }, { timeout: 15000 }).toBe(200);
    await page.route('**/api/waitlist', forward);
    await page.goto('mac.html');
    await fillWaitlist(page);
    await page.locator('#waitlist-form button').click();
    await expect(page.locator('#waitlist-status')).toContainText('YOU ARE ON THE LIST');
    expect(readFileSync(file, 'utf8')).toMatch(/\treader@example\.com\n$/);

    noJS = await browser.newContext({ baseURL: 'http://127.0.0.1:8015/writeitdown/', javaScriptEnabled: false });
    await noJS.route('**/api/waitlist', forward);
    const plain = await noJS.newPage();
    await plain.goto('mac.html');
    await plain.locator('#waitlist-email').fill('second@example.com');
    await plain.locator('input[name="consent"]').check();
    await plain.locator('#waitlist-form button').click();
    await expect(plain).toHaveURL(/mac\.html#waitlist-joined$/);
    await expect(plain.locator('#waitlist-joined')).toBeVisible();
    expect(readFileSync(file, 'utf8').split('\n').filter(Boolean)).toHaveLength(2);
  } finally {
    await noJS?.close();
    collector.kill();
    rmSync(root, { recursive: true, force: true });
  }
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });
  test('the form posts and the returned fragment shows exactly one outcome', async ({ page }, info) => {
    for (const outcome of ['joined', 'invalid', 'limited', 'error']) {
      await page.route('**/api/waitlist', route => route.fulfill({ status: 303, headers: { Location: `/writeitdown/mac.html#waitlist-${outcome}` } }));
      await page.goto('mac.html');
      await expect(page.locator('.waitlist-note:visible')).toHaveCount(0);
      await fillWaitlist(page);
      await page.locator('#waitlist-form button').click();
      await expect(page).toHaveURL(new RegExp(`#waitlist-${outcome}$`));
      await expect(page.locator(`#waitlist-${outcome}`)).toBeVisible();
      await expect(page.locator('.waitlist-note:visible')).toHaveCount(1);
      await page.locator('#waitlist-form').screenshot({ path: info.outputPath(`waitlist-nojs-${outcome}.png`) });
      await page.unroute('**/api/waitlist');
    }
  });
});
