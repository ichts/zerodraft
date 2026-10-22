import { test, expect } from '@playwright/test';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';

const shipped = ['index.html', 'download/index.html', 'mac.html', 'support.html', 'privacy.html', 'terms.html'];
const dmgURL = 'https://writeitdown.app/download/Write-It-Down-1.0.dmg';
const plistPath = '../apps/macos/FirstLine/Sources/FirstLine/Info.plist';
const appPrice = readFileSync(plistPath, 'utf8').match(/<key>WIDDisplayPrice<\/key>\s*<string>([^<]*)</)[1];

test('Mac page offers the free trial download, keeps buying closed, and has no dead or fake CTA', async ({ page }, info) => {
  await page.goto('mac.html');
  const main = page.locator('main');
  await expect(main.locator('h1')).toHaveText('Write It Down for Mac');
  await expect(page.locator('#price')).toHaveText(`${appPrice} ONCE. TWO MACS. NO SUBSCRIPTION.`);
  await expect(main).toContainText('Your first 3 writing sessions are free. After that, a single $4.99 payment covers 2 Macs and comes with a 14-day refund. Buying opens soon.');
  await expect(main).not.toContainText(/being prepared|when (it|sales) opens?, pick|planned/i);
  await expect(page.locator('#refund + p')).toContainText('14 days from purchase');

  for (const slot of ['checkout', 'license']) {
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
    expect(await door.getAttribute('href')).toMatch(/^(index\.html#trial|download\/|https:\/\/\S+)$/);
  }
  await expect(page.locator('a[href*="checkout"], a[href$=".dmg"]')).toHaveCount(0);
  await expect(page.locator('.door', { hasText: 'DOWNLOAD FREE TRIAL FOR MAC' })).toHaveAttribute('href', 'download/');
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
function releaseCheck({ mac, support, download = readFileSync('download/index.html', 'utf8'), checkout = '' }, ...args) {
  const root = mkdtempSync(join(tmpdir(), 'wid-release-'));
  const site = join(root, 'writeitdown');
  const plistDir = join(root, 'apps/macos/FirstLine/Sources/FirstLine');
  mkdirSync(join(site, 'download'), { recursive: true }); mkdirSync(plistDir, { recursive: true });
  writeFileSync(join(site, 'mac.html'), mac);
  writeFileSync(join(site, 'download/index.html'), download);
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
  const downloadPage = readFileSync('download/index.html', 'utf8');
  const sha = 'a'.repeat(64);
  const fill = ({ buy = checkout,
    steps = 'Open the purchase email, copy the license key, and paste it into Settings.' } = {}) => mac
    .replace(/<p[^>]*data-launch-pending="checkout"[^>]*>.*?<\/p>/, `<a class="door" data-launch="checkout" href="${buy}">BUY</a>`)
    .replace(/<p[^>]*data-launch-pending="license"[^>]*>.*?<\/p>/, `<p data-launch="license">${steps}</p>`);
  const shaLine = /<p[^>]*id="sha256"[^>]*>.*?<\/p>/;
  expect(downloadPage, 'the shipped page publishes a checksum').toMatch(/data-launch="sha256">[0-9a-f]{64}</);
  const pendingPage = downloadPage.replace(shaLine, '<p class="sha" id="sha256" data-launch-pending="sha256">SHA-256: PUBLISHED WITH THE RELEASE.</p>');
  const published = ({ digest = sha, dmg = dmgURL } = {}) => downloadPage
    .replace(shaLine, `<p class="sha" id="sha256">SHA-256: <code data-launch="sha256">${digest}</code></p>`)
    .replace(`href="${dmgURL}"`, `href="${dmg}"`);
  const contact = support;
  const noContact = support.replace(/<a href="mailto:[^"]*">[^<]*<\/a>/g, 'TBD');

  const [current, currentOut] = releaseCheck({ mac, support, download: pendingPage }, '--live');
  expect(current).toBe(1);
  for (const line of ['Checkout URL: not confirmed', 'SHA-256: not published', 'activation steps: not confirmed'])
    expect(currentOut).toContain(line);
  expect(currentOut).not.toContain('DMG URL');

  const [pendingSha, pendingShaOut] = releaseCheck({ mac, support, download: pendingPage }, '--download');
  const [shipped, shippedOut] = releaseCheck({ mac, support }, '--download');
  expect(shipped, shippedOut).toBe(0);
  expect(pendingSha).toBe(1);
  expect(pendingShaOut).toContain('download page is not ready');
  expect(pendingShaOut).toContain('SHA-256: not published');
  expect(pendingShaOut).not.toContain('Checkout');
  const [downloadReady, downloadReadyOut] = releaseCheck({ mac, support, download: published() }, '--download');
  expect(downloadReady).toBe(0);
  expect(downloadReadyOut).toContain('Download page ready');

  const [ready, readyOut] = releaseCheck({ mac: fill(), support: contact, download: published(), checkout });
  expect(ready).toBe(0);
  expect(readyOut).toContain('Not verified live');
  expect(readyOut).toContain('real test order');

  const cases = [
    [{ mac: fill().replace(`<a class="door" data-launch="checkout" href="${checkout}">BUY</a>`,
      `<p data-launch="checkout" href="${checkout}">BUY</p>`) }, 'Checkout URL: not a clickable link'],
    [{ download: published().replace(/<a class="[^"]*" data-launch="dmg"([^>]*)>(.*?)<\/a>/, '<p data-launch="dmg"$1>$2</p>') }, 'DMG URL: not a clickable link'],
    [{ mac: fill().replace(`data-launch="checkout" href="${checkout}"`, 'data-launch="checkout"') }, 'Checkout URL: not a real https destination'],
    [{ download: published().replace(`data-launch="dmg" href="${dmgURL}"`, 'data-launch="dmg"') }, 'DMG URL: not a real https .dmg destination'],
    [{ mac: fill({ buy: 'https://example.com/pay' }), checkout: 'https://example.com/pay' }, 'Checkout URL: not a real https destination'],
    [{ download: published({ dmg: 'https://writeitdown.app/download/app.zip' }) }, 'DMG URL: not a real https .dmg destination'],
    [{ download: published({ dmg: 'https://x.test/Write-It-Down.dmg' }) }, 'DMG URL: not a real https .dmg destination'],
    [{ download: published({ digest: 'TBD' }) }, 'SHA-256: not 64 lowercase hex digits'],
    [{ download: published({ digest: 'A'.repeat(64) }) }, 'SHA-256: not 64 lowercase hex digits'],
    [{ mac: fill({ steps: 'Steps.' }) }, 'activation steps: placeholder copy'],
    [{ mac: fill(), checkout: '' }, 'WIDCheckoutURL differs'],
    [{ mac: fill().replace(`${appPrice} ONCE.`, '$9 ONCE.') }, 'Price:'],
    [{ mac: fill(), support: noContact }, 'Support address'],
  ];
  for (const [input, message] of cases) {
    const [code, out] = releaseCheck({ mac: fill(), support: contact, download: published(), checkout, ...input });
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
  for (const selector of ['.home-nav .btn', '.cta .btn', '#paper .tag', '#clock', '#paper .saved', '#count'])
    await expect(page.locator(selector)).toHaveCSS('font-family', /system-ui/);

  const nav = page.locator('.home-nav a.btn-quiet');
  await expect(nav).toHaveText('Download for Mac');
  await expect(nav).toHaveAttribute('href', 'download/');
  const card = page.locator('#paper');
  await expect(card.locator('.tag')).toHaveText(/60 seconds, forward only/i);
  await expect(card.locator('#clock')).toBeVisible();
  await expect(card.locator('.saved')).toHaveText(/nothing is saved/i);
  await expect(card.locator('#count')).toHaveText(/\d+ WORDS?/);
  const cta = page.locator('.cta');
  await expect(cta.locator('.deck')).toHaveText('Stop typing for 8 seconds and it deletes everything you wrote.');
  const door = cta.locator('a.btn-primary');
  await expect(door).toHaveText('Give it 60 seconds');
  await expect(door).toHaveAttribute('href', '#trial');
  await expect(page.locator('#landing a[href="#trial"]').first(), 'the hero button is the first way into the room').toHaveText('Give it 60 seconds');
  const layout = await page.evaluate(() => {
    const r = s => document.querySelector(s).getBoundingClientRect();
    return { card: r('#paper'), paper: r('#paper'), deck: r('.cta .deck').top, door: r('.cta .btn').bottom, vh: innerHeight };
  });
  expect(layout.paper.height / layout.vh, 'the demo paper is at least 60% of the first viewport').toBeGreaterThanOrEqual(0.6);
  expect(layout.paper.bottom, 'the whole demo paper is on the first screen').toBeLessThanOrEqual(layout.vh);
  expect(layout.deck, 'the deck line sits under the demo card').toBeGreaterThan(layout.card.bottom);
  expect(layout.door, 'the room button is on the first screen').toBeLessThanOrEqual(layout.vh);
  const box = await page.evaluate(() => {
    const r = s => document.querySelector(s).getBoundingClientRect();
    return { deck: r('.cta .deck'), door: r('.cta .btn') };
  });
  const overlap = !(box.deck.right <= box.door.left || box.door.right <= box.deck.left || box.deck.bottom <= box.door.top || box.door.bottom <= box.deck.top);
  expect(overlap, 'the deck line and the room button do not overlap').toBe(false);
  expect(box.deck.bottom, 'the deck line is fully on the first screen').toBeLessThanOrEqual(layout.vh);

  await expect(page.locator('#how')).toContainText('Sixty seconds. Forward only.');
  await expect(page.locator('.cards .card h3')).toHaveText(['No way back', 'Eight seconds of silence', 'Reach zero, keep it']);
  await expect(page.locator('.mo small')).toHaveText([/writing/, /warning/, /deleted/]);
  const mac = page.locator('#mac');
  await expect(mac).toContainText('Your first 3 sessions are free. Buying opens soon.');
  await expect(mac.locator('.facts')).toContainText('$4.99');
  await expect(mac.locator('.facts')).toContainText('2 Macs');
  await expect(mac.locator('.facts')).toContainText('14 days');
  await expect(mac.locator('a[href="download/"]')).toHaveText('Download free trial');
  await expect(mac.locator('a[href="mac.html#waitlist"]')).toHaveText('Get one email when it opens');
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
  await page.locator('.home-foot [data-theme-toggle]').click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  const bg = await page.locator('#landing').evaluate(e => getComputedStyle(e).backgroundColor);
  expect(bg).toBe('rgb(21, 20, 15)');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await context.close();
});

test('landing sections: heading tree, honest facts, FAQ matches its schema, call-back enters the room', async ({ page }) => {
  await page.goto('index.html');
  await expect(page.locator('#landing h1')).toHaveCount(1);
  await expect(page.locator('#landing h2')).toHaveText([
    /What it feels like when you stop/, /Sixty seconds\. Forward only\. Nothing kept\./, 'Real rules, real numbers',
    'Write It Down for Mac', 'Questions, answered', /We force you to write it down/]);
  const ledger = page.locator('#facts .ledger');
  for (const fact of ['Strict 5 s, Standard 8 s or Relaxed 12 s', '1, 5, 10, 20 or 30 minutes', '3 free sessions on the Mac, then $4.99 once', 'Buying opens soon.', 'Trefoil Studio'])
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
  await expect(page.locator('#mac a[href="mac.html#waitlist"]')).toHaveText('Get one email when it opens');
  await expect(page.locator('.home-foot')).toContainText('2026 Trefoil Studio');
  for (const href of ['support.html', 'privacy.html', 'terms.html', 'download/', 'mac.html#waitlist'])
    await expect(page.locator(`.home-foot a[href="${href}"]`)).toHaveCount(1);
  await page.locator('.callback a.btn-primary').click();
  await expect(page.locator('#editor')).toBeFocused();
});

test('download page states the trial, the DMG, its checksum slot, requirements, and the signer', async ({ page }, info) => {
  await page.goto('download/');
  const main = page.locator('main');
  await expect(page.locator('#trial-terms')).toHaveText('FREE TRIAL: 3 SESSIONS, THEN USD 4.99 ONE-TIME (2 MACS, 14-DAY REFUND) - BUYING OPENS SOON.');
  const dmg = page.locator('[data-launch="dmg"]');
  await expect(dmg).toHaveText('Download free trial for Mac');
  await expect(dmg).toHaveAttribute('href', dmgURL);
  const sha = page.locator('#sha256');
  await expect(sha).toBeVisible();
  await expect(sha).toHaveText('SHA-256: 96c0c0a34733f92c1b47b1231c3243612c71614074dd6179ac3d61c80d5462cd');
  await expect(page.locator('#requirements')).toContainText('macOS 14 Sonoma or later');
  await expect(page.locator('#requirements')).toContainText('One universal app for Apple silicon and Intel Macs.');
  await expect(main).toContainText('Ziying WANG (Developer ID)');
  await expect(main).toContainText('Buying is not open yet.');
  await expect(page.locator('a[href*="checkout"]')).toHaveCount(0);
  await expect(page.locator('main a[href="../mac.html#waitlist"]').first()).toBeVisible();
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
  await expect(privacy).toContainText('Buying opens soon.');
  await expect(privacy).toContainText('local trial session counter in its settings file on the Mac');
  await expect(privacy).toContainText('That counter is not sent anywhere.');

  await page.goto('terms.html');
  const terms = page.locator('#mac + p');
  await expect(terms).toContainText('The Mac app includes 3 free writing sessions.');
  await expect(terms).toContainText('USD 4.99 once for two Macs, with a 14-day refund');
  await expect(terms).toContainText('Buying is not open yet.');

  await page.goto('support.html');
  const support = page.locator('#mac + p');
  await expect(support).toContainText('your first 3 writing sessions are free.');
  await expect(support).toContainText('USD 4.99 one-time license covers 2 Macs, with a 14-day refund');
  await expect(support).toContainText('Buying is not open yet.');

  await page.goto('mac.html');
  const stored = page.locator('#privacy + p');
  await expect(stored).toContainText('local trial session counter in its settings file on the Mac');
  await expect(stored).toContainText('That counter is not sent anywhere.');
  await expect(page.locator('main')).not.toContainText(/purchase is required before|activation before writing/i);
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
  test.setTimeout(120000); // A cold Go build shares this budget with both browser submissions.
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
