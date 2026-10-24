import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const shipped = ['index.html', 'download/index.html', 'mac.html', 'support.html', 'privacy.html', 'terms.html', 'what-is-write-it-down.html', 'write-it-down-mac-vs-web.html', 'write-it-down-free-trial.html', 'write-it-down-price.html', 'delete-a-draft.html', 'is-my-writing-saved.html'];
const dmgURL = 'https://writeitdown.app/download/Write-It-Down-1.0.dmg';
const plistPath = '../apps/macos/FirstLine/Sources/FirstLine/Info.plist';
const appPrice = readFileSync(plistPath, 'utf8').match(/<key>WIDDisplayPrice<\/key>\s*<string>([^<]*)</)[1];

test('Mac page offers the free trial and real Buy without dead or fake CTAs', async ({ page }, info) => {
  await page.goto('mac.html');
  const main = page.locator('main');
  await expect(main.locator('h1')).toHaveText('Write It Down for Mac');
  await expect(page.locator('#price')).toHaveText(`${appPrice} ONCE. TWO MACS. NO SUBSCRIPTION.`);
  await expect(main).toContainText('Your first 3 writing sessions are free.');
  await expect(main).toContainText('USD $4.99 payment to Trefoil Studio covers 2 Macs, free updates, and a 14-day refund.');
  await expect(main).not.toContainText(/buying opens soon|not open yet|coming soon/i);
  await expect(page.locator('#refund + p')).toContainText('14 days from purchase');
  await expect(page.locator('[data-launch="checkout"]')).toHaveAttribute('method', 'post');
  await expect(page.locator('[data-launch="checkout"]')).toHaveAttribute('action', 'https://licenses.writeitdown.app/api/v1/checkout');
  await expect(page.getByRole('button', { name: 'BUY - $4.99', exact: true })).toBeEnabled();
  await expect(page.locator('[data-launch="license"]')).toContainText("paste it into the app's activation field");
  await expect(page.locator('#waitlist-form')).toHaveCount(0);
  await expect(page.locator('.door', { hasText: 'DOWNLOAD FREE TRIAL FOR MAC' })).toHaveAttribute('href', 'download/');
  await page.locator('.door', { hasText: 'TRY IT IN YOUR BROWSER' }).click();
  await expect(page.locator('#editor')).toBeFocused();
  await page.goto('mac.html');
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
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
function releaseCheck({ mac, support, download = readFileSync('download/index.html', 'utf8'), checkout = '' }, ...args) {
  const root = mkdtempSync(join(tmpdir(), 'wid-release-'));
  const site = join(root, 'writeitdown');
  const plistDir = join(root, 'apps/macos/FirstLine/Sources/FirstLine');
  mkdirSync(join(site, 'download'), { recursive: true }); mkdirSync(plistDir, { recursive: true });
  mkdirSync(join(site, 'journey'), { recursive: true });
  writeFileSync(join(site, 'journey/waivers.json'), readFileSync('journey/waivers.json'));
  writeFileSync(join(site, 'mac.html'), mac);
  writeFileSync(join(site, 'download/index.html'), download);
  writeFileSync(join(site, 'support.html'), support);
  writeFileSync(join(plistDir, 'Info.plist'), readFileSync(plistPath, 'utf8')
    .replace(/(<key>WIDCheckoutURL<\/key>\s*<string>)[^<]*/, `$1${checkout}`));
  try {
    return [0, execFileSync('node', ['release-check.mjs', '--root', site, ...args], { encoding: 'utf8', stdio: 'pipe' })];
  } catch (error) {
    return [error.status, error.stderr];
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('release gate rejects missing or invalid purchase and download configuration', () => {
  const mac = readFileSync('mac.html', 'utf8');
  const support = readFileSync('support.html', 'utf8');
  const download = readFileSync('download/index.html', 'utf8');
  const checkout = 'https://writeitdown.app/mac.html';
  const inputs = { mac, support, download, checkout };
  const [ready, output] = releaseCheck(inputs);
  expect(ready, output).toBe(0);
  expect(output).toContain('Not verified live');
  expect(output).toContain('real test order');
  expect(releaseCheck(inputs, '--download')[0]).toBe(0);
  const [live, liveOutput] = releaseCheck(inputs, '--live-sales');
  expect(live).toBe(1);
  expect(liveOutput).toContain('LIVE sales blocked: maintainer installed-DMG TEST acceptance is pending');

  const cases = [
    [{ mac: mac.replace('data-launch="checkout"', 'data-launch-pending="checkout"') }, 'Checkout URL: not confirmed'],
    [{ mac: mac.replace('method="post"', 'method="get"') }, 'Checkout URL: not a POST form'],
    [{ mac: mac.replace('action="https://licenses.writeitdown.app/api/v1/checkout"', 'action="https://example.com/pay"') }, 'Checkout URL: not the license service'],
    [{ mac: mac.replace('data-launch="license"', 'data-launch-pending="license"') }, 'activation steps: not confirmed'],
    [{ mac: mac.replace(/<p data-launch="license">.*?<\/p>/, '<p data-launch="license">TBD</p>') }, 'activation steps: placeholder copy'],
    [{ checkout: '' }, 'WIDCheckoutURL differs'],
    [{ mac: mac.replace(`${appPrice} ONCE.`, '$9 ONCE.') }, 'Price:'],
    [{ support: support.replace(/<a href="mailto:[^"]*">[^<]*<\/a>/g, 'TBD') }, 'Support address'],
    [{ download: download.replace('data-launch="dmg"', 'data-launch-pending="dmg"') }, 'DMG URL: not confirmed'],
    [{ download: download.replace(dmgURL, 'https://example.com/app.dmg') }, 'DMG URL: not a real https .dmg destination'],
    [{ download: download.replace('data-launch="sha256"', 'data-launch-pending="sha256"') }, 'SHA-256: not published'],
    [{ download: download.replace(/<code data-launch="sha256">[^<]*/, '<code data-launch="sha256">TBD') }, 'SHA-256: not 64 lowercase hex digits'],
  ];
  for (const [changes, message] of cases) {
    const [code, out] = releaseCheck({ ...inputs, ...changes });
    expect(code, message).toBe(1);
    expect(out).toContain(message);
  }
});

test('landing: Paper in light - headline, demo card, one room button, sections, honest Mac block', async ({ page }, info) => {
  await page.goto('index.html');
  const hero = page.locator('header.hero');
  await expect(hero.locator('h1')).toHaveText('We force you to write it down');
  await expect(hero.locator('h1 .hand')).toHaveText('write it down');
  await expect(hero.locator('h1 .hand')).toHaveCSS('font-family', /Reenie Beanie/);
  await expect(hero.locator('h1 .l1')).toHaveCSS('font-family', /^"?Newsreader/);
  const families = await page.evaluate(() => [...new Set([...document.fonts].filter(f => f.status === 'loaded').map(f => f.family.replace(/"/g, '')))]);
  expect(families.sort(), 'only the site faces load').toEqual(expect.arrayContaining(['Newsreader', 'Reenie Beanie']));
  expect(families.every(f => ['Newsreader', 'Reenie Beanie', 'IBM Plex Mono'].includes(f)), families.join(', ')).toBe(true);
  const ink = await hero.evaluate(h => {
    const probe = document.createElement('i');
    probe.style.color = getComputedStyle(h).getPropertyValue('--red');
    h.append(probe);
    const hand = getComputedStyle(probe).color;
    probe.remove();
    return { hand, actual: getComputedStyle(h.querySelector('h1 .hand')).color, line1: getComputedStyle(h.querySelector('h1 .l1')).color };
  });
  expect(ink.actual, 'the handwritten words wear the token red').toBe(ink.hand);
  expect(ink.actual, 'the two headline parts differ in color').not.toBe(ink.line1);
  const tokens = await page.locator('#landing').evaluate(e => ['--page', '--sheet', '--ink', '--red', '--r-stage', '--sans'].map(name => getComputedStyle(e).getPropertyValue(name).trim()));
  expect(tokens.every(Boolean), 'design-system tokens are in force on the landing').toBe(true);
  expect(tokens[5], 'the tool face is the system UI stack, not a webfont').toMatch(/system-ui/);
  for (const selector of ['#landing .home-nav .btn', '.cta .btn', '#clock', '#count'])
    await expect(page.locator(selector)).toHaveCSS('font-family', /system-ui/);

  const nav = page.locator('#landing .home-nav a.btn-quiet');
  await expect(nav).toHaveText('Download for Mac');
  await expect(nav).toHaveAttribute('href', 'download/');
  const card = page.locator('#paper');
  await expect(card.locator('#clock')).toBeVisible();
  await expect(card.locator('#count')).toHaveText(/\d+ WORDS?/);
  // Journey: the sheet carries no tag and no saved label; under it there is only the button.
  await expect(card.locator('.tag, .saved')).toHaveCount(0);
  await expect(page.locator('#demo')).not.toContainText(/60 seconds, forward only/i);
  await expect(card).not.toContainText(/nothing is saved/i);
  const cta = page.locator('.cta');
  await expect(cta.locator('> *')).toHaveCount(1);
  await expect(cta).not.toContainText('Stop typing for 8 seconds');
  const door = cta.locator('a.btn-primary');
  await expect(door).toHaveText('Give it 60 seconds');
  await expect(door).toHaveAttribute('href', '#trial');
  await expect(page.locator('#landing a[href="#trial"]').first(), 'the hero button is the first way into the room').toHaveText('Give it 60 seconds');
  const layout = await page.evaluate(() => {
    const r = s => document.querySelector(s).getBoundingClientRect();
    return { card: r('#paper'), paper: r('#paper'), door: r('.cta .btn'), vh: innerHeight };
  });
  expect(layout.paper.height / layout.vh, 'the demo paper is at least 60% of the first viewport').toBeGreaterThanOrEqual(0.6);
  expect(layout.paper.bottom, 'the whole demo paper is on the first screen').toBeLessThanOrEqual(layout.vh);
  expect(layout.door.top, 'the room button sits under the demo card').toBeGreaterThan(layout.card.bottom);
  expect(layout.door.bottom, 'the room button is on the first screen').toBeLessThanOrEqual(layout.vh);
  expect(Math.abs(layout.door.left + layout.door.width / 2 - (layout.card.left + layout.card.width / 2)), 'the button is centred under the sheet').toBeLessThan(1);

  await expect(page.locator('#how')).toContainText('Sixty seconds. Forward only.');
  await expect(page.locator('.cards .card h3')).toHaveText(['No way back', 'Eight seconds of silence', 'Reach zero, keep it']);
  await expect(page.locator('.mo small')).toHaveText([/writing/, /warning/, /deleted/]);
  const mac = page.locator('#mac');
  await expect(mac).toContainText('Your first 3 sessions are free. Free updates.');
  await expect(mac.locator('.facts')).toContainText('$4.99');
  await expect(mac.locator('.facts')).toContainText('2 Macs');
  await expect(mac.locator('.facts')).toContainText('14 days');
  await expect(mac.locator('a[href="download/"]')).toHaveText('Download free trial');
  await expect(mac.locator('a[href="mac.html#buy"]')).toHaveText('Buy for $4.99');
  await expect(page.locator('a[href*="checkout"], a[href$=".dmg"]')).toHaveCount(0);
  await expect(page.locator('.home-foot')).toContainText('Trefoil Studio');
  for (const label of ['Support', 'Privacy', 'Terms']) await expect(page.locator('.home-foot nav a', { hasText: label })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
  await page.screenshot({ path: info.outputPath('landing.png'), fullPage: true });

  await nav.click();
  await expect(page).toHaveURL(/\/download\/$/);
  await expect(page.locator('h1')).toHaveText('Write It Down for Mac');
  await page.goBack();
  await door.click();
  await expect(page.locator('#editor')).toBeFocused();
});

test('light is the default theme; the toggle switches to dark and remembers it', async ({ browser }) => {
  const context = await browser.newContext({ colorScheme: 'dark', storageState: { cookies: [], origins: [] } });
  const page = await context.newPage();
  await page.goto('http://127.0.0.1:8015/writeitdown/index.html');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.locator('#landing .home-nav [data-theme-toggle]').click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  const bg = await page.locator('#landing').evaluate(e => getComputedStyle(e).backgroundColor);
  expect(bg).toBe('rgb(21, 20, 15)');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await context.close();
});

// Journey: one theme icon button, top right in the header of every page with a header; none in the footer.
for (const [path, label] of [['index.html', 'landing'], ['index.html#trial', 'trial'], ['download/', 'download'],
  ['mac.html', 'mac'], ['terms.html', 'terms'], ['privacy.html', 'privacy'], ['support.html', 'support']]) {
  test(`theme toggle is in the ${label} header and flips the theme`, async ({ page }) => {
    await page.goto(path);
    const header = page.locator('nav[aria-label="Main"]:visible');
    await expect(header).toHaveCount(1);
    const toggle = header.locator('button[data-theme-toggle]');
    await expect(toggle).toHaveCount(1);
    await expect(toggle).toBeVisible();
    await expect(page.locator('[data-theme-toggle]:visible')).toHaveCount(1);
    await expect(page.locator('footer [data-theme-toggle]')).toHaveCount(0);
    const place = await toggle.evaluate(button => {
      const r = button.getBoundingClientRect(), nav = button.closest('nav').getBoundingClientRect();
      return { right: nav.right - r.right, top: r.top, width: r.width, height: r.height, overflow: document.documentElement.scrollWidth - innerWidth };
    });
    expect(place.right, 'the toggle ends the header row').toBeLessThan(40);
    expect(place.top, 'the toggle is at the top of the page').toBeLessThan(40);
    expect(Math.min(place.width, place.height)).toBeGreaterThanOrEqual(36);
    expect(place.overflow, 'no horizontal overflow with the toggle in the header').toBeLessThanOrEqual(0);
    const read = () => page.evaluate(() => {
      const surface = [...document.querySelectorAll('#room, .home, .stage')].find(e => e.getClientRects().length);
      return { theme: document.documentElement.dataset.theme, bg: getComputedStyle(surface).backgroundColor,
        label: document.querySelector('nav[aria-label="Main"]:not([hidden] *) [data-theme-toggle]')?.getAttribute('aria-label') };
    });
    const before = await read();
    expect(before.label).toBe(`Switch to ${before.theme === 'dark' ? 'light' : 'dark'} theme`);
    await toggle.focus();
    await expect(toggle).toBeFocused();
    expect(await toggle.evaluate(b => getComputedStyle(b).outlineStyle), 'keyboard focus ring').not.toBe('none');
    await page.keyboard.press('Enter');
    const after = await read();
    expect(after.theme).not.toBe(before.theme);
    expect(after.bg).not.toBe(before.bg);
    expect(after.label).toBe(`Switch to ${after.theme === 'dark' ? 'light' : 'dark'} theme`);
    expect(await page.evaluate(() => localStorage.getItem('writeitdown-theme'))).toBe(after.theme);
  });
}

test('every lockup link keeps a visible keyboard focus ring', async ({ page }) => {
  for (const path of ['index.html', 'index.html#trial', 'download/']) {
    await page.goto(path);
    const brands = page.locator('.brand:visible');
    const count = await brands.count();
    expect(count, `${path}: no visible lockup link`).toBeGreaterThan(0);
    for (let index = 0; index < count; index += 1) {
      const brand = brands.nth(index);
      await brand.focus();
      await page.keyboard.press('Tab');
      await page.keyboard.press('Shift+Tab');
      await expect(brand, `${path} brand ${index}: keyboard focus`).toBeFocused();
      const state = await brand.evaluate(el => {
        const style = getComputedStyle(el);
        const mark = getComputedStyle(el, '::before');
        return { focusVisible: el.matches(':focus-visible'), outlineStyle: style.outlineStyle,
          outlineWidth: style.outlineWidth, maskImage: style.maskImage || style.webkitMaskImage,
          markImage: mark.maskImage || mark.webkitMaskImage };
      });
      expect(state.focusVisible, `${path} brand ${index}: focus-visible`).toBe(true);
      expect(state.outlineStyle, `${path} brand ${index}: focus outline`).toBe('solid');
      expect(state.outlineWidth, `${path} brand ${index}: focus outline width`).toBe('2px');
      expect(state.maskImage, `${path} brand ${index}: outline-clipping mask`).toBe('none');
      expect(state.markImage, `${path} brand ${index}: lockup mask`).toContain('write-it-down-lockup.svg');
    }
  }
});

// The Mac page keeps the document shell but sits on the approved background A (tokens.css page colour), so the
// purchase page and the landing share one canvas and the legacy beige wall cannot come back.
test('the Mac page wears the approved background A canvas, not the legacy beige wall', async ({ page }) => {
  const read = () => page.evaluate(() => {
    const probe = (name) => {
      const raw = getComputedStyle(document.body).getPropertyValue(name).trim();
      const i = document.createElement('i');
      i.style.color = raw;
      document.body.append(i);
      const color = getComputedStyle(i).color;
      i.remove();
      return { raw, color };
    };
    return {
      theme: document.documentElement.dataset.theme,
      stage: getComputedStyle(document.querySelector('.stage')).backgroundColor,
      canvas: getComputedStyle(document.body).backgroundColor,
      door: getComputedStyle(document.querySelector('.door')).color,
      page: probe('--page'),
      wall: probe('--wall'),
    };
  });
  await page.goto('mac.html');
  const mac = await read();
  expect(mac.page.raw, 'tokens.css page colour is in force on the Mac page').not.toBe('');
  expect(mac.stage, 'the Mac page canvas is background A').toBe(mac.page.color);
  expect(mac.canvas, 'the document canvas matches, so overscroll never shows beige').toBe(mac.page.color);
  expect(mac.wall.color, 'the legacy wall name resolves to the page colour on this page').toBe(mac.page.color);
  expect(mac.door, 'the primary button label is the page colour, not beige').toBe(mac.page.color);
  await page.goto('index.html');
  const landing = await page.evaluate(() => getComputedStyle(document.querySelector('#landing')).backgroundColor);
  expect(mac.stage, `${mac.theme}: the purchase page and the landing share one canvas`).toBe(landing);
});

test('landing sections: heading tree, honest facts, FAQ matches its schema, call-back enters the room', async ({ page }) => {
  await page.goto('index.html');
  await expect(page.locator('#landing h1')).toHaveCount(1);
  await expect(page.locator('#landing h2')).toHaveText([
    /What it feels like when you stop/, /Sixty seconds\. Forward only\. Nothing kept\./, 'Real rules, real numbers',
    'Write It Down for Mac', 'Questions, answered', /We force you to write it down/]);
  const ledger = page.locator('#facts .ledger');
  for (const fact of ['Strict 5 s, Standard 8 s or Relaxed 12 s', '1, 5, 10, 20 or 30 minutes', '3 free sessions on the Mac, then $4.99 once', 'Free updates.', 'Trefoil Studio'])
    await expect(ledger).toContainText(fact);
  await expect(page.locator('#mac')).toContainText('macOS 14 Sonoma or later');

  const questions = page.locator('#faq details');
  await expect(questions).toHaveCount(8);
  await expect(questions.first()).toHaveAttribute('open', '');
  const second = questions.nth(1);
  await expect(second.locator('p')).toBeHidden();
  await second.locator('summary').click();
  await expect(second.locator('p')).toBeVisible();
  await second.locator('summary').click();
  await expect(second.locator('p')).toBeHidden();
  const visible = await questions.evaluateAll(list => list.map(d => [d.querySelector('summary').textContent.trim(), d.querySelector('p').textContent.trim()]));
  const graph = JSON.parse(await page.locator('script[type="application/ld+json"]').textContent())['@graph'];
  const faq = graph.find(node => node['@type'] === 'FAQPage');
  expect(faq.mainEntity.map(q => [q.name, q.acceptedAnswer.text]), 'the FAQ schema matches the visible FAQ').toEqual(visible);
  const app = graph.find(node => node['@type'] === 'SoftwareApplication');
  expect(app.offers).toEqual({ '@type': 'Offer', price: '4.99', priceCurrency: 'USD', availability: 'https://schema.org/PreOrder' });
  expect(app.operatingSystem).toBe('macOS 14 or later');
  expect(app.downloadUrl).toBe('https://writeitdown.app/download/');
  const schemaProperties = value => value && typeof value === 'object'
    ? Object.entries(value).flatMap(([key, child]) => [key, ...schemaProperties(child)]) : [];
  for (const property of ['publisher', 'aggregateRating', 'review'])
    expect(schemaProperties(graph)).not.toContain(property);

  await expect(page.locator('#mac a[href="download/"]')).toHaveText('Download free trial');
  await expect(page.locator('#mac a[href="mac.html#buy"]')).toHaveText('Buy for $4.99');
  await expect(page.locator('.home-foot')).toContainText('2026 Trefoil Studio');
  for (const href of ['support.html', 'privacy.html', 'terms.html', 'download/', 'mac.html#buy'])
    await expect(page.locator(`.home-foot a[href="${href}"]`)).toHaveCount(1);
  await page.locator('.callback a.btn-primary').click();
  await expect(page.locator('#editor')).toBeFocused();
});

test('download page states the trial, the DMG, its checksum slot, requirements, and the signer', async ({ page }, info) => {
  await page.goto('download/');
  const main = page.locator('main');
  await expect(page.locator('#trial-terms')).toHaveText('FREE TRIAL: 3 SESSIONS, THEN USD 4.99 ONE-TIME (2 MACS, 14-DAY REFUND).');
  const dmg = page.locator('[data-launch="dmg"]');
  await expect(dmg).toHaveText('Download free trial for Mac');
  await expect(dmg).toHaveAttribute('href', dmgURL);
  const sha = page.locator('#sha256');
  await expect(sha).toBeVisible();
  await expect(sha).toHaveText(/^SHA-256: [0-9a-f]{64}$/);
  await expect(page.locator('#requirements')).toContainText('macOS 14 Sonoma or later');
  await expect(page.locator('#requirements')).toContainText('One universal app for Apple silicon and Intel Macs.');
  await expect(main).toContainText('Ziying WANG (Developer ID)');
  await expect(main).toContainText('Free updates included.');
  await expect(page.locator('a[href*="checkout"]')).toHaveCount(0);
  await expect(page.locator('main a[href="../mac.html#buy"]').first()).toBeVisible();
  await expect(page.locator('h1')).toHaveCount(1);
  for (const id of ['install', 'trial', 'refunds']) await expect(page.locator(`#${id} h2`)).toBeVisible();
  await expect(page.locator('.dl-page [data-theme-toggle]')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
  await page.screenshot({ path: info.outputPath('download.png'), fullPage: true });
});

test('legal pages state the 3-session trial and the local counter', async ({ page }) => {
  await page.goto('privacy.html');
  const privacy = page.locator('#mac + p');
  await expect(privacy).toContainText('Your first 3 writing sessions are free.');
  await expect(privacy).toContainText('USD 4.99 one-time license covers 2 Macs, with a 14-day refund');
  await expect(privacy).toContainText('Free updates included.');
  await expect(privacy).toContainText('local trial session counter in its settings file on the Mac');
  await expect(privacy).toContainText('That counter is not sent anywhere.');

  await page.goto('terms.html');
  const terms = page.locator('#mac + p');
  await expect(terms).toContainText('The Mac app includes 3 free writing sessions.');
  await expect(terms).toContainText('USD 4.99 once for two Macs, with a 14-day refund');
  await expect(terms).toContainText('Free updates included.');

  await page.goto('support.html');
  const support = page.locator('#mac + p');
  await expect(support).toContainText('your first 3 writing sessions are free.');
  await expect(support).toContainText('USD 4.99 one-time license covers 2 Macs, with a 14-day refund');
  await expect(support).toContainText('Free updates included.');

  await page.goto('mac.html');
  const stored = page.locator('#privacy + p');
  await expect(stored).toContainText('local trial session counter in its settings file on the Mac');
  await expect(stored).toContainText('That counter is not sent anywhere.');
  await expect(page.locator('main')).not.toContainText(/purchase is required before|activation before writing/i);
});

test('DMG release packaging refuses unconfigured builds', () => {
  test.skip(test.info().project.name !== '1440-dark-no-preference', 'configuration gate, one project is enough');
  expect(execFileSync('python3', ['../apps/macos/FirstLine/scripts/test-release-config.py'], { encoding: 'utf8' })).toContain('release requires complete safe configuration');
});

test('installer installs the complete purchase bundle and rejects symlinks', () => {
  test.skip(test.info().project.name !== '1440-dark-no-preference', 'filesystem check, one project is enough');
  expect(execFileSync('python3', ['qa/test-install.py'], { encoding: 'utf8' })).toContain('exact production files');
});

test('installer acceptance rejects an installer missing its symlink guard', () => {
  test.skip(test.info().project.name !== '1440-dark-no-preference', 'negative control, one project is enough');
  const root = mkdtempSync(join(tmpdir(), 'wid-broken-install-'));
  try {
    const broken = join(root, 'install.sh');
    writeFileSync(broken, readFileSync('install.sh', 'utf8')
      .replace('  [ ! -L "$TARGET/$file" ] || { echo "Refusing symlink: $file" >&2; exit 1; }', ''));
    expect(() => execFileSync('python3', ['qa/test-install.py', broken], { stdio: 'pipe' })).toThrow();
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('installer acceptance rejects an installer missing its logo-directory guard', () => {
  test.skip(test.info().project.name !== '1440-dark-no-preference', 'negative control, one project is enough');
  const root = mkdtempSync(join(tmpdir(), 'wid-broken-logo-install-'));
  try {
    const broken = join(root, 'install.sh');
    writeFileSync(broken, readFileSync('install.sh', 'utf8')
      .replace(`[ ! -L "$TARGET/logo" ] || { echo 'Refusing a symlink logo directory.' >&2; exit 1; }`, ''));
    expect(() => execFileSync('python3', ['qa/test-install.py', broken], { stdio: 'pipe' })).toThrow();
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
