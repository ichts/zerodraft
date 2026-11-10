import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { sweepTimeout } from './page-sweep.mjs';

const shipped = ['index.html', 'download/index.html', 'mac.html', 'support.html', 'privacy.html', 'terms.html', 'impressum.html', 'what-is-write-it-down.html', 'write-it-down-mac-vs-web.html', 'write-it-down-free-trial.html', 'write-it-down-price.html', 'delete-a-draft.html', 'is-my-writing-saved.html'];
const dmgURL = 'https://writeitdown.app/download/Write-It-Down-1.1.dmg';
const dmgFile = new URL(dmgURL).pathname.split('/').pop();
const plistPath = '../apps/macos/FirstLine/Sources/FirstLine/Info.plist';
const appPrice = readFileSync(plistPath, 'utf8').match(/<key>WIDDisplayPrice<\/key>\s*<string>([^<]*)</)[1];
// Every shipped page carries the same shell: the landing header lockup with its plate, the theme
// button and the three-column footer. #trial is the room on the landing page.
const shellPages = [...shipped, 'index.html#trial'];

test('Mac page offers the free trial and real Buy without dead or fake CTAs', async ({ page }, info) => {
  await page.goto('mac.html');
  const main = page.locator('main');
  await expect(main.locator('h1')).toHaveText('Write It Down for Mac');
  await expect(page.locator('#price')).toHaveText(`${appPrice} once`);
  // The card states its facts once (A3): the price line and the note under it carry the price, the two
  // computers, the free updates and the refund window. The paragraph that repeated them is gone. The
  // Activate section states the 3 free sessions and the one-license-two-computers rule, and Refunds
  // states the 14-day window as the policy behind the note.
  await expect(page.locator('#buy-heading + #price-row'), 'the price line follows the heading').toHaveCount(1);
  await expect(main).not.toContainText('one license covers 2 computers');
  await expect(page.locator('#price-row .doc-note')).toHaveText('2 computers. No subscription. Free updates. 14\u2011day refund.');
  await expect(page.locator('#activate + p')).toContainText('3 free sessions');
  await expect(main).not.toContainText(/buying opens soon|not open yet|coming soon/i);
  await expect(page.locator('#refund + p')).toContainText('14 days from purchase');
  await expect(page.locator('[data-launch="checkout"]')).toHaveAttribute('method', 'post');
  await expect(page.locator('[data-launch="checkout"]')).toHaveAttribute('action', 'https://licenses.writeitdown.app/api/v1/checkout');
  await expect(page.getByRole('button', { name: 'Buy for $4.99 once', exact: true })).toBeEnabled();
  await expect(page.locator('[data-launch="license"]')).toContainText("paste it into the app's activation field");
  await expect(page.locator('#waitlist-form')).toHaveCount(0);
  await expect(page.locator('#buy').getByRole('link', { name: 'Download free trial', exact: true })).toHaveAttribute('href', 'download/');
  await expect(page.locator('#buy-heading')).toHaveText('Buy Write It Down');
  await expect(page.locator('#price-row')).toContainText('2 computers. No subscription.');
  await expect(page.locator('#requirements + p')).toContainText('Requires macOS 14 Sonoma or later');
  await expect(page.locator('#activate + p')).toContainText('One license works on two computers.');
  await expect(page.locator('#refund + p')).toContainText('the license stops working on every computer.');
  // The page sells only what ships: the Mac app. No Windows sale, price, activation or download claim,
  // anywhere in the rendered page or in its search description, until a Store listing is actually live (C3).
  await expect(page.locator('body')).not.toContainText(/Windows/i);
  await expect(page.locator('meta[name="description"]')).toHaveCount(1);
  await expect(page.locator('meta[name="description"]')).not.toHaveAttribute('content', /Windows/i);
  await expect(page.locator('a[href*="windows" i], a[href*="microsoft" i]')).toHaveCount(0);
  await page.locator('.doc-buy a[href="index.html#trial"]').click();
  await expect(page.locator('#editor')).toBeFocused();
  await page.goto('mac.html');
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
  await page.screenshot({ path: info.outputPath('mac.png'), fullPage: true });
});

test('every shipped link resolves and every fragment exists', async ({ page, request }, info) => {
  // Thirteen pages and every link on them: the walk, not the harness's flat 30 s, owns the budget.
  test.setTimeout(sweepTimeout(shipped.length));
  // Derived from the configured baseURL so the suite still holds its own origin when it runs on
  // another port; the default remains http://127.0.0.1:8015/writeitdown/.
  const base = new URL('/writeitdown/', info.project.use.baseURL);
  // Host artifacts the repository does not hold, so this static server cannot answer them: the
  // archived 1.0 disk image is placed on the host under download/releases/ and never enters the
  // deploy bundle (README, "The 1.0 archive"). Its address and its place on the page are
  // asserted by "the download page offers 1.1 as current and 1.0 as the archived previous version".
  const hostArtifacts = new Set([new URL('download/releases/Write-It-Down-1.0.dmg', base).pathname]);
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
      if (hostArtifacts.has(url.pathname)) continue;
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
    await page.locator('.home-foot a', { hasText: 'Buy for Mac' }).click();
    await expect(page).toHaveURL(/\/mac\.html#buy$/);
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
  const publishedHash = download.match(/<code data-launch="sha256">([\s\S]*?)<\/code>/)?.[1].replace(/<[^>]+>/g, '') ?? '';
  // The page ships its own release note, so the note controls rewrite that element in place and the
  // linked version comes from the DMG file name the page itself publishes.
  const linkedVersion = dmgFile.replace(/^Write-It-Down-|\.dmg$/g, '');
  const aheadVersion = linkedVersion.split('.').map((part, index, parts) => index === parts.length - 1 ? String(Number(part) + 1) : part).join('.');
  const withNote = attrs => download.replace(/(<p[^>]*\sid="release-notes")[^>]*>/, `$1 ${attrs}>`);
  // The archive note is rewritten in place too, so a case can hand the check a wrong or unpublished
  // archived version without touching the rest of the page.
  const withArchive = href => download.replace(/(id="previous-version"[\s\S]*?<a\s[^>]*href=")[^"]*/, `$1${href}`);
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
    [{ mac: mac.replaceAll(`${appPrice} once`, '$9 once') }, 'Price:'],
    [{ support: support.replace(/<a href="mailto:[^"]*">[^<]*<\/a>/g, 'TBD') }, 'Support address'],
    [{ download: download.replace('data-launch="dmg"', 'data-launch-pending="dmg"') }, 'DMG URL: not confirmed'],
    [{ download: download.replace(dmgURL, 'https://example.com/app.dmg') }, 'DMG URL: not a real https .dmg destination'],
    [{ download: download.replaceAll(dmgFile, 'Write-It-Down.dmg') }, 'DMG URL: the file name does not carry the version'],
    [{ download: download.replace('data-launch="sha256"', 'data-launch-pending="sha256"') }, 'SHA-256: not published'],
    [{ download: download.replace(/(<code data-launch="sha256">)[\s\S]*?(<\/code>)/, '$1TBD$2') }, 'SHA-256: not 64 lowercase hex digits'],
    [{ download: download.replace(/(<code data-launch="sha256">)[\s\S]*?(<\/code>)/, `$1<span>${publishedHash}</span>$2`) }, 'SHA-256: the code element must hold two 32-character spans'],
    [{ download: download.replace(`<span class="cmd-file">${dmgFile}</span>`, '<span class="cmd-file">Write-It-Down-0.9.dmg</span>') }, 'Install command: hashes Write-It-Down-0.9.dmg'],
    [{ download: download.replace(/(<code>)[\s\S]*?(<\/code>)/, `$1shasum -a 256 ${dmgFile}$2`) }, 'Install command: the code element must hold the call span and the filename span'],
    [{ download: download.replace(/<code>[\s\S]*?<\/code>/, '<code>shasum -a 256</code>') }, 'Install command: the card does not name'],
    [{ download: withNote(`data-release-note="${aheadVersion}"`) }, `Release notes: the note declares ${aheadVersion} but the download is ${linkedVersion}`],
    [{ download: download.replaceAll(dmgFile, `Write-It-Down-${aheadVersion}.dmg`) }, `Release notes: the note declares ${linkedVersion} but the download is ${aheadVersion}`],
    [{ download: withNote(`data-release-note="${linkedVersion}" data-launch-pending="release-notes"`) }, 'Release notes: data-launch-pending is retired'],
    [{ download: withNote('') }, 'Release notes: the note does not declare its version in data-release-note'],
    [{ download: withArchive(`releases/Write-It-Down-${linkedVersion}.dmg`) }, `Previous version: the note archives ${linkedVersion} but the download is ${linkedVersion}`],
    [{ download: withArchive(`releases/Write-It-Down-${aheadVersion}.dmg`) }, `Previous version: the note archives ${aheadVersion} but the download is ${linkedVersion}`],
    [{ download: withArchive('/download/releases/Write-It-Down-1.0.dmg') }, 'Previous version: the note does not link releases/Write-It-Down-<version>.dmg'],
    [{ download: withArchive('releases/Write-It-Down.dmg') }, 'Previous version: the note does not link releases/Write-It-Down-<version>.dmg'],
  ];
  // The release note is optional. When present it declares the linked artifact version and no
  // pending mark; the page ships one that names the version it links.
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
  await expect(hero.locator('p.sub'), 'the subheadline carries the rule in the captain\'s words').toHaveText('Forward only. Pause and the draft disappears. Keep going and you get to keep it.');
  const families = await page.evaluate(() => [...new Set([...document.fonts].filter(f => f.status === 'loaded').map(f => f.family.replace(/"/g, '')))]);
  expect(families.sort(), 'only the site faces load').toEqual(expect.arrayContaining(['Newsreader', 'Reenie Beanie']));
  expect(families.every(f => ['Newsreader', 'Reenie Beanie'].includes(f)), families.join(', ')).toBe(true);
  const ink = await hero.evaluate(h => {
    const probe = document.createElement('i');
    probe.style.color = getComputedStyle(h).getPropertyValue('--red-text');
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
  for (const selector of ['#landing .home-nav .btn', '.cta .btn', '.cta .cta-buy', '#clock', '#count'])
    await expect(page.locator(selector)).toHaveCSS('font-family', /system-ui/);

  const nav = page.locator('#landing .home-nav a.btn-quiet');
  await expect(nav).toHaveText('Download for Mac');
  await expect(nav).toHaveAttribute('href', 'download/');
  const card = page.locator('#paper');
  await expect(card.locator('#clock')).toBeVisible();
  await expect(card.locator('#count')).toHaveText(/^((\d+ words?)?)$/);
  // Journey: the sheet carries no tag and no saved label; under it there is only the button.
  await expect(card.locator('.tag, .saved')).toHaveCount(0);
  await expect(page.locator('#demo')).not.toContainText(/60 seconds, forward only/i);
  await expect(card).not.toContainText(/nothing is saved/i);
  const cta = page.locator('#landing .cta');
  // The entrance band holds the door and the one quiet route to the purchase (D-110): the door stays the only way
  // into the room, and the buy line is the only way to pay without leaving the first screen. It reuses the
  // published price string, wears the site's underlined-link treatment instead of a second pill, and keeps a
  // 40 px touch target.
  await expect(cta.locator('> *'), 'the entrance band holds the door and its quiet buy line, nothing else').toHaveCount(2);
  await expect(cta.locator('> a'), 'the entrance band holds two links and no other control').toHaveCount(2);
  const buyLine = cta.locator('a.cta-buy');
  await expect(buyLine, 'the buy line reuses the published price string').toHaveText('Buy for $4.99 once');
  await expect(buyLine, 'the buy line goes to the purchase card').toHaveAttribute('href', 'mac.html#buy');
  const buyLineInk = await buyLine.evaluate(e => {
    const s = getComputedStyle(e);
    return { decoration: s.textDecorationLine, colour: s.color, height: e.getBoundingClientRect().height,
      ink: getComputedStyle(e.closest('.home')).getPropertyValue('--ink').trim() };
  });
  expect(buyLineInk.decoration, 'the buy line wears the underline, not a second pill').toBe('underline');
  expect(buyLineInk.height, 'the buy line keeps a 40 px touch target on a phone').toBeGreaterThanOrEqual(39.5);
  const door = cta.locator('a.btn-primary');
  await expect(door).toHaveText('Give it 60 seconds');
  await expect(door).toHaveAttribute('href', '#trial');
  await expect(page.locator('#landing a.btn-primary[href="#trial"]'), 'one door on the page, not two').toHaveCount(1);
  await expect(page.locator('#landing a[href="#trial"]').first(), 'the hero button is the first way into the room').toHaveText('Give it 60 seconds');
  // Measured from the top of the document: a test that scrolled the page would otherwise read a smaller gap than
  // the layout has, which says nothing about the spacing the visitor sees.
  const layout = await page.evaluate(() => {
    window.scrollTo(0, 0);
    const pin = document.createElement('style');
    pin.textContent = '.home{--sans:Arial, sans-serif}';
    document.head.append(pin);
    const r = s => document.querySelector(s).getBoundingClientRect();
    const home = document.querySelector('#landing');
    const token = n => parseFloat(getComputedStyle(home).getPropertyValue(n));
    const out = {
      card: r('#paper'), sub: r('.hero-sub'), door: r('#landing .cta .btn'), vh: innerHeight,
      ctaTop: parseFloat(getComputedStyle(document.querySelector('#landing .cta')).paddingTop),
      stageTop: parseFloat(getComputedStyle(document.querySelector('#demo')).marginTop),
      tokens: { s1: token('--s1'), s2: token('--s2'), s3: token('--s3'), s4: token('--s4'), s5: token('--s5'), s7: token('--s7') },
    };
    pin.remove();
    return out;
  });
  const phone = page.viewportSize().width <= 820;
  expect(layout.card.height / layout.vh, 'the demo paper is at least 60% of the first viewport').toBeGreaterThanOrEqual(0.6);
  expect(Math.min(layout.card.height, layout.vh) / layout.vh, 'the demo paper keeps at least 60% of the first viewport').toBeGreaterThanOrEqual(0.6);
  expect(layout.door.top, 'the door sits under the subheadline').toBeGreaterThan(layout.sub.bottom);
  expect(layout.door.bottom, 'the door is on the first screen').toBeLessThanOrEqual(layout.vh);
  expect(layout.door.bottom, 'the door sits above the demo sheet').toBeLessThanOrEqual(layout.card.top);
  expect(Math.abs(layout.door.left + layout.door.width / 2 - (layout.card.left + layout.card.width / 2)), 'the button is centred over the sheet').toBeLessThan(1);
  expect(layout.ctaTop, 'the headline group closes on the spacing scale').toBe(phone ? layout.tokens.s4 : layout.tokens.s5);
  // The buy line is a quiet route of its own, not a footnote to the door (D-110 as amended): it starts at least one
  // scale step below the door's box - so a thumb aimed at the door cannot land on it - and the sheet starts at least
  // one step below it, which keeps the price off the paper.
  expect(layout.stageTop, 'the sheet keeps the scale gap under the door group').toBe(phone ? layout.tokens.s2 : layout.tokens.s7);
  const buyBox = await cta.locator('a.cta-buy').evaluate(e => e.getBoundingClientRect());
  expect(buyBox.top - layout.door.bottom, 'the buy line owns at least 12 px of air under the door').toBeGreaterThanOrEqual(11.5);
  expect(layout.card.top - buyBox.bottom, 'the sheet owns at least 8 px of air under the buy line').toBeGreaterThanOrEqual(7.5);

  await expect(page.locator('#facts, .points, .callback'), 'the facts table, the points band and the closing block are gone').toHaveCount(0);
  await expect(page.locator('#landing')).not.toContainText('No account. Nothing is saved. Just the timer.');
  await expect(page.locator('#landing')).not.toContainText(/Real rules, real numbers|Straight answers|A native writing room/);

  await expect(page.locator('#how')).toContainText('Sixty seconds. Forward only.');
  await expect(page.locator('#how .card .txt')).toHaveText(['Forward only, no deleting.', '8 seconds of silence deletes the draft.', 'Write to 0:00 and the text is yours.']);
  await expect(page.locator('#how .card h3'), 'each card carries one line and no title').toHaveCount(0);
  await expect(page.locator('.mo small')).toHaveText([/writing/, /warning/, /deleted/]);
  const mac = page.locator('#mac');
  await expect(mac.locator('.facts')).toContainText('$4.99 once');
  await expect(mac.locator('.facts')).toContainText('2 computers');
  await expect(mac.locator('.facts')).toContainText('14 days');
  await expect(mac.locator('a[href="download/"]')).toHaveText('Download free trial');
  await expect(mac.locator('a[href="mac.html#buy"]')).toHaveText('Buy for $4.99 once');
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

test.describe('light is the default theme', () => {
  test.use({ colorScheme: 'dark', storageState: { cookies: [], origins: [] } });
  test('the toggle switches to dark and remembers it', async ({ page }) => {
    const loaded = await page.goto('index.html');
    expect(loaded, 'the suite serves the page through its own baseURL').not.toBeNull();
    expect(loaded.status(), 'the page loads from the suite origin').toBeLessThan(400);
    expect(new URL(page.url()).protocol, 'the page has a real http(s) origin').toMatch(/^https?:$/);
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
    await page.locator('#landing .home-nav [data-theme-toggle]').click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
    const bg = await page.locator('#landing').evaluate(e => getComputedStyle(e).backgroundColor);
    expect(bg).toBe('rgb(21, 20, 15)');
    // D-103: red as words is brightened in dark (big Lc 45, small Lc 60); the fill red keeps its value.
    const reds = () => page.evaluate(() => {
      const color = (selector, prop = 'color') => getComputedStyle(document.querySelector(selector))[prop];
      return { hand: color('#landing h1 .hand'), numeral: color('.mo .n'), label: color('.line8 .lab b'), track: color('.line8 .track i', 'backgroundColor') };
    });
    expect(await reds()).toEqual({ hand: 'rgb(246, 113, 90)', numeral: 'rgb(246, 113, 90)', label: 'rgb(255, 155, 136)', track: 'rgb(228, 96, 74)' });
    await page.locator('#landing .home-nav [data-theme-toggle]').click();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
    expect(await reds(), 'light keeps the one pen red everywhere').toEqual({ hand: 'rgb(176, 42, 30)', numeral: 'rgb(176, 42, 30)', label: 'rgb(176, 42, 30)', track: 'rgb(176, 42, 30)' });
    await page.locator('#landing .home-nav [data-theme-toggle]').click();
    await page.reload();
    await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  });
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

// The landing header is the same shell as every other page: its box spans the page container, so the
// brand sits on the left gutter and the theme button on the right one. A flex item that shrinks to its
// content still clears the overflow, overlap and 6 px gutter checks above while the whole lockup moves
// inward, so this test pins the box to the container the sections below it use.
test('the landing header spans the page container at every width', async ({ page }) => {
  // Six widths, each with a fresh load and the fonts resolved: the 30 s default budget is a
  // navigation budget, and on a loaded machine this sweep spends it inside the loop.
  test.slow();
  for (const width of [320, 375, 390, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 844 });
    await page.goto('index.html');
    await page.evaluate(() => document.fonts.ready);
    const state = await page.evaluate(() => {
      const nav = document.querySelector('#landing .home-nav');
      const navBox = nav.getBoundingClientRect();
      const brand = nav.querySelector('.brand').getBoundingClientRect();
      const button = nav.querySelector('.theme-btn').getBoundingClientRect();
      const style = getComputedStyle(nav);
      const section = document.querySelector('#landing .sect').getBoundingClientRect();
      return {
        left: navBox.left, width: navBox.width,
        containerLeft: section.left, containerWidth: section.width,
        brandInset: brand.left - navBox.left, buttonInset: navBox.right - button.right,
        paddingLeft: parseFloat(style.paddingLeft), paddingRight: parseFloat(style.paddingRight),
      };
    });
    const at = `${width}px:`;
    expect(state.left, `${at} the header starts on the page container's left edge`).toBeCloseTo(state.containerLeft, 0);
    expect(state.width, `${at} the header spans the page container`).toBeCloseTo(state.containerWidth, 0);
    expect(state.brandInset, `${at} the brand sits on the left gutter`).toBeCloseTo(state.paddingLeft, 0);
    expect(state.buttonInset, `${at} the theme button sits on the right gutter`).toBeCloseTo(state.paddingRight, 0);
  }
});

const measureHeaderMark = (brand) => brand.evaluate(async (el) => {
  const box = el.getBoundingClientRect();
  const scale = 2;
  const width = Math.round(box.width * scale), height = Math.round(box.height * scale);
  const raster = async (pseudo) => {
    const style = getComputedStyle(el, pseudo);
    const image = new Image();
    image.src = (style.maskImage || style.webkitMaskImage).match(/url\("?([^"\)]+)"?\)/)[1];
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = width; canvas.height = height;
    const context = canvas.getContext('2d');
    const w = parseFloat(style.width), h = parseFloat(style.height);
    const size = style.maskSize || style.webkitMaskSize;
    const ratio = size === 'contain' ? Math.min(w / image.width, h / image.height)
      : size === 'cover' ? Math.max(w / image.width, h / image.height)
      : w / image.width;
    const dw = image.width * ratio, dh = image.height * ratio;
    const x = parseFloat(style.left), y = parseFloat(style.top) + (h - dh) / 2;
    context.drawImage(image, x * scale, y * scale, dw * scale, dh * scale);
    const pixels = context.getImageData(0, 0, width, height).data;
    return { alpha: (x, y) => pixels[(y * width + x) * 4 + 3], color: style.backgroundColor };
  };
  const plate = await raster('::before'), glyph = await raster('::after');
  const chip = Math.round(box.height * scale);
  let chipInk = 0, chipHole = 0;
  const glyphBounds = [chip, chip, -1, -1], holeBounds = [chip, chip, -1, -1];
  const extend = (bounds, x, y) => {
    bounds[0] = Math.min(bounds[0], x); bounds[1] = Math.min(bounds[1], y);
    bounds[2] = Math.max(bounds[2], x); bounds[3] = Math.max(bounds[3], y);
  };
  for (let y = 0; y < chip; y += 1) for (let x = 0; x < chip; x += 1) {
    if (glyph.alpha(x, y) > 127) extend(glyphBounds, x, y);
    if (plate.alpha(x, y) > 127 && glyph.alpha(x, y) > 127) {
      chipHole += 1; extend(holeBounds, x, y);
    } else if (plate.alpha(x, y) > 127) chipInk += 1;
  }
  const columns = [];
  for (let x = Math.round(chip / 3); x < Math.round(2 * chip / 3); x += 1) {
    let ink = 0, total = 0;
    for (let y = Math.round(chip * 0.45); y < Math.round(chip * 0.95); y += 1) {
      total += 1; if (glyph.alpha(x, y) > 215) ink += 1;
    }
    columns.push(ink / total);
  }
  const floor = Math.min(...columns), margin = 0.04;
  let best = { length: 0, left: floor, right: floor };
  for (let start = 1; start < columns.length - 1; start += 1) {
    if (columns[start] > floor + margin) continue;
    let end = start;
    while (end + 1 < columns.length && columns[end + 1] <= floor + margin) end += 1;
    if (end + 1 >= columns.length) break;
    const length = end - start + 1;
    const left = Math.max(...columns.slice(0, start)), right = Math.max(...columns.slice(end + 1));
    if (left > floor + margin && right > floor + margin && length > best.length) best = { length, left, right };
    start = end;
  }
  let wordInk = 0, wordTotal = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = Math.min(width, chip + Math.round(box.height * 0.3 * scale)); x < width; x += 1) {
      wordTotal += 1; if (glyph.alpha(x, y) > 127) wordInk += 1;
    }
  }
  const luminance = color => {
    const channels = color.match(/[\d.]+/g).slice(0, 3).map(Number).map(c => {
      const s = c / 255;
      return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  const plateLight = luminance(plate.color), glyphLight = luminance(glyph.color);
  return {
    box: { width: +box.width.toFixed(2), height: +box.height.toFixed(2) },
    chipInkShare: chipInk / (chip * chip), chipHoleShare: chipHole / (chip * chip),
    glyphBounds, holeBounds,
    splitLength: best.length, splitContrast: +(Math.min(best.left, best.right) - floor).toFixed(2),
    topOfChipIsPlate: plate.alpha(Math.round(chip / 2), Math.round(chip * 0.06)) > 127,
    wordInkShare: wordInk / wordTotal, polarity: plateLight - glyphLight,
  };
});

// The captain's report: the header read as plain words because the lockup was the wordmark alone, and the
// split W inside it is invisible at 21 px. The header must show the A mark as its own chip beside the
// wordmark. The mask is read at the rendered header size, so this fails on a wordmark-only lockup and on a
// solid tile without the split.
test('the header lockup shows the A mark chip beside the wordmark', async ({ page }, info) => {
  // Fourteen pages, each measured at its rendered header size: budget the walk (#146).
  test.setTimeout(sweepTimeout(shellPages.length));
  for (const path of shellPages) {
    await page.goto(path);
    const brands = page.locator('.brand:visible');
    expect(await brands.count(), `${path}: visible lockup`).toBeGreaterThan(0);
    for (let index = 0; index < await brands.count(); index += 1) {
      const mark = await measureHeaderMark(brands.nth(index));
      const at = `${path} at ${mark.box.width}x${mark.box.height}:`;
      expect(mark.chipInkShare, `${at} the left square is the plate, not a bare letter`).toBeGreaterThan(0.6);
      expect(mark.chipInkShare, `${at} the W leaves visible plate around it`).toBeLessThan(0.95);
      expect(mark.chipHoleShare, `${at} the W strokes occupy the chip`).toBeGreaterThan(0.05);
      expect(mark.chipHoleShare, `${at} the W leaves most of the plate visible`).toBeLessThan(0.4);
      for (let axis = 0; axis < 4; axis += 1)
        expect(Math.abs(mark.glyphBounds[axis] - mark.holeBounds[axis]), `${at} the W stays aligned with the plate`).toBeLessThanOrEqual(3);
      const direction = info.project.use.colorScheme === 'light' ? 1 : -1;
      expect(mark.polarity * direction, `${at} light plate with dark glyphs, dark plate with light glyphs`).toBeGreaterThan(0.6);
      if (path === 'index.html' && index === 0) {
        await page.screenshot({ path: info.outputPath('header.png'), clip: { x: 0, y: 0, width: page.viewportSize().width, height: 110 } });
      }
      expect(mark.topOfChipIsPlate, `${at} the plate covers the top of the chip`).toBe(true);
      expect(mark.box.height, `${at} the chip is square and sits inside the lockup box`).toBeGreaterThan(16);
      expect(mark.box.width, `${at} the lockup is the chip plus the wordmark`).toBeGreaterThan(mark.box.height * 5);
      expect(mark.splitLength, `${at} the split survives at header size`).toBeGreaterThanOrEqual(2);
      expect(mark.splitContrast, `${at} the split has a W stroke on each side`).toBeGreaterThan(0.05);
      expect(mark.wordInkShare, `${at} the wordmark follows the chip`).toBeGreaterThan(0.06);
      expect(mark.wordInkShare, `${at} the wordmark follows the chip`).toBeLessThan(0.4);
    }
  }
});

// One brand rule for every page: the chip plate is a single `--brand-plate` token per theme, resolved where the
// other colour roles live (tokens.css). A per-page fallback let mac.html resolve its own paper colour, so the
// same lockup read as a chip on the landing and as a bare mark on the mac page. This reads the rendered
// ::before background, so a page-level override or a reintroduced fallback chain fails here.
test('the header chip paints one plate colour on every page', async ({ page }) => {
  test.setTimeout(sweepTimeout(shellPages.length));
  const samples = [];
  for (const path of shellPages) {
    await page.goto(path);
    const brand = page.locator('.brand:visible').first();
    expect(await brand.count(), `${path}: visible lockup`).toBeGreaterThan(0);
    const controlEdge = await page.locator('nav[aria-label="Main"]:visible .theme-btn').first().evaluate(button => {
      const style = getComputedStyle(button);
      return `${style.borderTopWidth} ${style.borderTopStyle} ${style.borderTopColor}`;
    });
    samples.push(await brand.evaluate((el, [pagePath, edge]) => {
      const plate = getComputedStyle(el, '::before');
      return {
        path: pagePath,
        theme: document.documentElement.dataset.theme,
        plate: plate.backgroundColor,
        token: getComputedStyle(el).getPropertyValue('--brand-plate').trim(),
        edge: `${plate.borderTopWidth} ${plate.borderTopStyle} ${plate.borderTopColor}`,
        controlEdge: edge,
      };
    }, [path, controlEdge]));
  }
  const theme = samples[0].theme;
  expect(new Set(samples.map(s => s.theme)).size, 'every page renders the same stored theme').toBe(1);
  const plates = new Set(samples.map(s => s.plate));
  expect(plates.size, `${theme}: one plate colour, not ${samples.map(s => `${s.path}=${s.plate}`).join(', ')}`).toBe(1);
  expect(samples[0].plate, `${theme}: the plate is opaque`).toMatch(/^rgba?\(.*, 1\)$|^rgb\(/);
  const tokens = new Set(samples.map(s => s.token));
  expect(tokens.size, `${theme}: one --brand-plate token, not ${samples.map(s => `${s.path}=${s.token || '(unset)'}`).join(', ')}`).toBe(1);
  expect(samples[0].token, `${theme}: the plate resolves the --brand-plate token, not a page-local fallback`).not.toBe('');
  for (const sample of samples) {
    expect(sample.edge, `${theme} ${sample.path}: the plate edge is a solid 1 px line`).toMatch(/^1px solid /);
    expect(sample.edge, `${theme} ${sample.path}: the plate edge is the theme button's hairline`).toBe(sample.controlEdge);
    expect(sample.edge, `${theme} ${sample.path}: the plate edge is visible`).not.toMatch(/,\s*0\)$/);
  }
});

// Narrow phones: /download/ carries the widest header (brand, page action, theme button), so it decides the
// responsive step. These point samples keep the visual checks at the widths a phone actually uses; the sweep
// below owns the every-width fit.
for (const actionWidth of [0, 164]) test(`the header keeps its right gutter and a legible chip at 360 px${actionWidth ? ' with wider system-font metrics' : ''}`, async ({ page }, info) => {
  // Thirteen pages at three widths, each with a load, the fonts and a measurement: under parallel load
  // this sweep timed out at the 30 s default budget while every assertion inside it held. The budget is
  // the walk's page count, not a flat multiplier on the harness's ceiling (#146).
  test.setTimeout(sweepTimeout(3 * shellPages.length));
  for (const width of [360, 375, 390]) {
    await page.setViewportSize({ width, height: 844 });
    const lockups = [];
    for (const path of shellPages) {
      await page.goto(path);
      // Linux system fonts make the download action wider than macOS does. Exercise that layout on either OS.
      if (actionWidth) await page.addStyleTag({ content: `nav .btn-quiet { min-width: ${actionWidth}px }` });
      const nav = page.locator('nav[aria-label="Main"]:visible').first();
      const header = await nav.evaluate(nav => {
        const brand = nav.querySelector('.brand');
        const button = nav.querySelector('.theme-btn');
        return {
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          gutter: window.innerWidth - button.getBoundingClientRect().right,
          lockup: parseFloat(getComputedStyle(brand).fontSize),
          gap: nav.querySelector('.nav-end').getBoundingClientRect().left - brand.getBoundingClientRect().right,
        };
      });
      const at = `${path} at ${width}px:`;
      lockups.push(header.lockup);
      expect(header.overflow, `${at} the page never scrolls sideways`).toBeLessThanOrEqual(0);
      expect(header.gap, `${at} the brand and controls never overlap`).toBeGreaterThanOrEqual(0);
      expect(header.gutter, `${at} the theme button keeps the 6 px right gutter`).toBeGreaterThanOrEqual(6);
      if (width !== 360) continue;
      await page.screenshot({ path: info.outputPath(`header-360-${path.replace(/[^a-z0-9]/gi, '-')}.png`), clip: { x: 0, y: 0, width, height: 110 } });
      const mark = await measureHeaderMark(nav.locator('.brand'));
      expect(mark.box.height, `${at} the chip is at least 16 px tall`).toBeGreaterThanOrEqual(16);
      expect(mark.chipInkShare, `${at} the smallest lockup is still a plate`).toBeGreaterThan(0.6);
      expect(mark.splitLength, `${at} the split survives at the smallest lockup`).toBeGreaterThanOrEqual(2);
      expect(mark.splitContrast, `${at} the split has a W stroke on each side`).toBeGreaterThan(0.05);
    }
    expect(new Set(lockups).size, `${width}px: landing, room, download and mac share one lockup step`).toBe(1);
  }
});

// A breakpoint that moves leaves a band where the row no longer fits, and sampled widths can step over it. Sweep
// every width on the widest header page under the wider-font action model, so a hole fails instead of passing
// between samples.
test('the header holds its gutter at every width from 320 to 1440 px', async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto('download/');
  await page.addStyleTag({ content: 'nav .btn-quiet { min-width: 164px }' });
  const widths = [];
  for (let width = 320; width <= 420; width += 1) widths.push(width);
  for (let width = 428; width <= 1440; width += 8) widths.push(width);
  const failures = [];
  for (const width of widths) {
    await page.setViewportSize({ width, height: 844 });
    const state = await page.evaluate(() => {
      const nav = [...document.querySelectorAll('nav[aria-label="Main"]')].find(nav => nav.getClientRects().length);
      const button = nav.querySelector('.theme-btn'), action = nav.querySelector('.btn-quiet');
      const box = button.getBoundingClientRect();
      return { overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        gutter: innerWidth - box.right, button: Math.min(box.width, box.height),
        action: !!action && action.getClientRects().length > 0 };
    });
    const wantsAction = width >= 380;
    if (state.overflow > 0 || state.gutter < 6 || state.button < 36 || state.action !== wantsAction)
      failures.push(`${width}px: overflow ${state.overflow}, gutter ${state.gutter.toFixed(1)}, button ${state.button}, action ${state.action}`);
  }
  expect(failures, failures.slice(0, 16).join('; ')).toEqual([]);
});

test('every lockup link keeps a visible keyboard focus ring', async ({ page }) => {
  test.setTimeout(sweepTimeout(shellPages.length));
  for (const path of shellPages) {
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
        const mark = getComputedStyle(el, '::after');
        const probe = document.createElement('span');
        probe.style.color = 'var(--ink)';
        el.parentElement.appendChild(probe);
        const ink = getComputedStyle(probe).color;
        probe.remove();
        return { focusVisible: el.matches(':focus-visible'), outlineStyle: style.outlineStyle,
          outlineWidth: style.outlineWidth, color: style.color, ink,
          maskImage: style.maskImage || style.webkitMaskImage,
          markImage: mark.maskImage || mark.webkitMaskImage };
      });
      expect(state.focusVisible, `${path} brand ${index}: focus-visible`).toBe(true);
      expect(state.outlineStyle, `${path} brand ${index}: focus outline`).toBe('solid');
      expect(state.outlineWidth, `${path} brand ${index}: focus outline width`).toBe('2px');
      expect(state.color, `${path} brand ${index}: brand ink`).toBe(state.ink);
      expect(state.maskImage, `${path} brand ${index}: outline-clipping mask`).toBe('none');
      expect(state.markImage, `${path} brand ${index}: lockup mask`).toContain('write-it-down-lockup.svg');
    }
  }
});

// The purchase page is the last thing a buyer sees before paying, so it wears the same document
// shell as every other shipped page: the landing header, the shared footer, the .home canvas and
// the v2 pill, with no second button system left on the page.
test('the Mac page is the shared document shell, not a second design system', async ({ page }) => {
  await page.goto('mac.html');
  const shell = await page.evaluate(() => {
    const probe = () => {
      const i = document.createElement('i');
      i.style.color = 'var(--page)';
      document.body.append(i);
      const color = getComputedStyle(i).color;
      i.remove();
      return color;
    };
    const primary = document.querySelector('.doc-buy .btn-primary');
    return {
      bodyHome: document.body.classList.contains('home'),
      doc: !!document.querySelector('main.doc'),
      legacy: document.querySelectorAll('.stage, .legal, .door, .deck, .logotype, .foot').length,
      canvas: getComputedStyle(document.body).backgroundColor,
      page: probe(),
      footer: !!document.querySelector('.home-foot .foot-grid'),
      radius: getComputedStyle(primary).borderRadius,
      height: getComputedStyle(primary).height,
      label: getComputedStyle(primary).color,
      onInk: getComputedStyle(document.querySelector('.doc-buy')).getPropertyValue('--on-ink').trim(),
      onInkColor: (() => {
        const i = document.createElement('i');
        i.style.color = 'var(--on-ink)';
        document.body.append(i);
        const color = getComputedStyle(i).color;
        i.remove();
        return color;
      })(),
    };
  });
  expect(shell.bodyHome, 'the page resolves the shared tokens').toBe(true);
  expect(shell.doc, 'the page uses the shared document shell').toBe(true);
  expect(shell.legacy, 'no legacy shell class survives on the purchase page').toBe(0);
  expect(shell.canvas, 'the page canvas is background A').toBe(shell.page);
  expect(shell.footer, 'the shared footer is present').toBe(true);
  expect(shell.radius, 'the primary control is the v2 pill').toBe('999px');
  expect(shell.height, 'the primary control is the v2 48 px pill').toBe('48px');
  expect(shell.label, 'the pill label wears the on-ink token').toBe(shell.onInkColor);
  expect(shell.onInk, 'the on-ink token resolves').not.toBe('');
  await page.goto('index.html');
  const landing = await page.evaluate(() => getComputedStyle(document.querySelector('#landing')).backgroundColor);
  expect(shell.canvas, 'the purchase page and the landing share one canvas').toBe(landing);
});

test('landing sections: heading tree, Mac facts, FAQ matches its schema, the door enters the room', async ({ page }) => {
  await page.goto('index.html');
  await expect(page.locator('#landing h1')).toHaveCount(1);
  await expect(page.locator('#landing h2')).toHaveText([
    /What it feels like when you stop/, /Sixty seconds\. Forward only\. Nothing kept\./,
    'Write It Down for Mac', 'Questions, answered']);
  await expect(page.locator('#core > p.sub, #how > p.sub')).toHaveCount(0);
  const questions = page.locator('#faq details');
  await expect(questions).toHaveCount(8);
  await expect(questions.first()).toHaveAttribute('open', '');
  const second = questions.nth(1);
  await expect(second.locator('p')).toBeHidden();
  await second.locator('summary').click();
  await expect(second.locator('p')).toBeVisible();
  await second.locator('summary').click();
  await expect(second.locator('p')).toBeHidden();
  // The visible FAQ's word-for-word match against its `FAQPage` schema is `qa/seo.spec.mjs`'s: it walks every
  // shipped page's JSON-LD in one place. This page test keeps the part that is about this page's markup - the
  // question tree and the accordion's first item - and reads the schema only for the Mac facts below.
  const graph = JSON.parse(await page.locator('script[type="application/ld+json"]').textContent())['@graph'];
  const app = graph.find(node => node['@type'] === 'SoftwareApplication');
  expect(app.offers).toEqual({ '@type': 'Offer', price: '4.99', priceCurrency: 'USD', availability: 'https://schema.org/PreOrder' });
  expect(app.operatingSystem).toBe('macOS 14 or later');
  expect(app.downloadUrl).toBe('https://writeitdown.app/download/');
  const schemaProperties = value => value && typeof value === 'object'
    ? Object.entries(value).flatMap(([key, child]) => [key, ...schemaProperties(child)]) : [];
  for (const property of ['publisher', 'aggregateRating', 'review'])
    expect(schemaProperties(graph)).not.toContain(property);

  await expect(page.locator('#mac a[href="download/"]')).toHaveText('Download free trial');
  await expect(page.locator('#mac a[href="mac.html#buy"]')).toHaveText('Buy for $4.99 once');
  await expect(page.locator('.home-foot')).toContainText('2026 Trefoil Studio');
  for (const href of ['support.html', 'privacy.html', 'terms.html', 'download/', 'mac.html#buy'])
    await expect(page.locator(`.home-foot a[href="${href}"]`)).toHaveCount(1);
  await page.locator('#landing .cta a.btn-primary').click();
  await expect(page.locator('#editor')).toBeFocused();
});

test('download page states the trial, the DMG, its checksum slot, requirements, and the signer', async ({ page }, info) => {
  await page.goto('download/');
  const main = page.locator('main');
  await expect(page.locator('#requirements')).toContainText('3 free sessions');
  await expect(page.locator('#requirements')).toContainText('$4.99 once');
  await expect(page.locator('#requirements')).toContainText('2 computers, 14-day refund');
  const dmg = page.locator('[data-launch="dmg"]');
  await expect(dmg).toHaveText('Download free trial for Mac');
  await expect(dmg).toHaveAttribute('href', dmgURL);
  const sha = page.locator('#sha256');
  await expect(sha).toBeVisible();
  await expect(sha).toHaveText(/^SHA-256: [0-9a-f]{64}$/);
  await expect(page.locator('#requirements')).toContainText('macOS 14 Sonoma or later');
  await expect(page.locator('#requirements')).toContainText('One universal app for Apple silicon and Intel Macs.');
  await expect(main).toContainText('Ziying WANG (Developer ID)');
  await expect(page.locator('#install')).toContainText(`shasum -a 256 ${dmgFile}`);
  await expect(main).toContainText('Free updates included.');
  await expect(page.locator('a[href*="checkout"]')).toHaveCount(0);
  await expect(page.locator('main a[href="../mac.html#buy"]').first()).toBeVisible();
  await expect(page.locator('h1')).toHaveCount(1);
  for (const id of ['install', 'trial']) await expect(page.locator(`#${id} h2`)).toBeVisible();
  // The facts rows state the trial, the price, the seats and the refund once. The Activate card
  // keeps the one thing they do not say, how to activate, and the Refunds card is gone (finding 11).
  await expect(page.locator('#refunds')).toHaveCount(0);
  await expect(page.locator('#trial')).not.toContainText('3 free sessions');
  await expect(page.locator('#trial')).not.toContainText('$4.99');
  await expect(page.locator('#trial')).not.toContainText('14 days');
  await expect(page.locator('#trial a[href="../mac.html#buy"]')).toHaveText('Buy a license');
  await expect(page.locator('.dl-page [data-theme-toggle]')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
  await page.screenshot({ path: info.outputPath('download.png'), fullPage: true });
});

// One version is current and the older one stays reachable: the download link, the Install command
// and the release note name the same current version, the archive note links the previous one under
// releases/, and the archive note is a quiet line under the requirements, never a second download.
test('the download page offers 1.1 as current and 1.0 as the archived previous version', async ({ page }, info) => {
  test.slow();
  await page.goto('download/');
  await page.evaluate(() => document.fonts.ready);
  const projectWidth = page.viewportSize().width;
  expect(dmgFile, 'the current download is 1.1').toBe('Write-It-Down-1.1.dmg');
  const current = page.locator('[data-launch="dmg"]');
  await expect(current).toHaveCount(1);
  await expect(current).toHaveAttribute('href', dmgURL);
  await expect(page.locator('#install .cmd-file')).toHaveText(dmgFile);
  await expect(page.locator('#release-notes')).toHaveAttribute('data-release-note', '1.1');
  // The page's whole DMG link set: the current download and one archived version, nothing else.
  const dmgLinks = page.locator('main a[href$=".dmg"]');
  await expect(dmgLinks).toHaveCount(2);
  const hrefs = await dmgLinks.evaluateAll(links => links.map(a => a.getAttribute('href')));
  expect(hrefs.sort()).toEqual([dmgURL, 'releases/Write-It-Down-1.0.dmg'].sort());
  const at = 'the archive note:';
  const note = page.locator('#previous-version');
  await expect(note).toBeVisible();
  await expect(note).toContainText('Previous version: 1.0.');
  await expect(note).toContainText('A 1.0 installation cannot update itself.');
  await expect(note).toContainText('is a fresh install of 1.0 only.');
  const archive = note.locator('a');
  await expect(archive).toHaveText('Write-It-Down-1.0.dmg');
  await expect(archive).toHaveAttribute('href', 'releases/Write-It-Down-1.0.dmg');
  expect(await archive.evaluate(link => link.hasAttribute('data-launch')), `${at} no launch slot`).toBe(false);
  // Not a second current download: no button role, no primary styling, and it sits below the
  // requirements rather than beside the download action.
  await expect(archive).not.toHaveClass(/btn/);
  const noteRow = await page.evaluate(() => {
    const note = document.querySelector('#previous-version');
    const box = note.getBoundingClientRect();
    const card = document.querySelector('.dlbox');
    const cardBox = card.getBoundingClientRect();
    const pad = parseFloat(getComputedStyle(card).paddingLeft);
    const border = parseFloat(getComputedStyle(card).borderLeftWidth);
    const style = getComputedStyle(note);
    const link = note.querySelector('a');
    return {
      top: box.top,
      left: box.left,
      right: box.right,
      requirementsBottom: document.querySelector('#requirements').getBoundingClientRect().bottom,
      currentBottom: document.querySelector('[data-launch="dmg"]').getBoundingClientRect().bottom,
      requirementsLeft: document.querySelector('#requirements').getBoundingClientRect().left,
      contentLeft: cardBox.left + border + pad,
      contentRight: cardBox.right - border - parseFloat(getComputedStyle(card).paddingRight),
      colour: style.color,
      background: getComputedStyle(card).backgroundColor,
      linkUnderline: getComputedStyle(link).textDecorationLine,
      linkDisplay: getComputedStyle(link).display,
    };
  });
  expect(noteRow.top, `${at} sits below the download action, not beside it`).toBeGreaterThan(noteRow.currentBottom);
  expect(noteRow.top, `${at} sits below the requirements it follows`).toBeGreaterThan(noteRow.requirementsBottom);
  expect(Math.abs(noteRow.left - noteRow.requirementsLeft), `${at} starts on the requirements' edge`).toBeLessThanOrEqual(0.5);
  expect(Math.abs(noteRow.left - noteRow.contentLeft), `${at} starts on the card's content edge`).toBeLessThanOrEqual(0.5);
  expect(noteRow.right, `${at} never overflows the card`).toBeLessThanOrEqual(noteRow.contentRight + 0.5);
  expect(contrast(noteRow.colour, noteRow.background), `${at} text contrast`).toBeGreaterThanOrEqual(4.5);
  expect(noteRow.linkUnderline, `${at} the archive link is underlined`).toBe('underline');
  expect(noteRow.linkDisplay, `${at} the link is not a block control`).toBe('inline');
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
  // The archived filename is a string a reader may need to match against a file on disk, so it never
  // breaks across lines, at the narrowest shipped width as well (Q-28).
  for (const width of [projectWidth, 320]) {
    await page.setViewportSize({ width, height: 844 });
    const narrow = await page.evaluate(() => {
      const link = document.querySelector('#previous-version a');
      const note = document.querySelector('#previous-version').getBoundingClientRect();
      const card = document.querySelector('.dlbox');
      const cardBox = card.getBoundingClientRect();
      const style = getComputedStyle(card);
      return {
        rects: link.getClientRects().length,
        text: link.textContent,
        noteRight: note.right,
        contentRight: cardBox.right - parseFloat(style.borderLeftWidth) - parseFloat(style.paddingRight),
        overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      };
    });
    expect(narrow.rects, `the archived filename stays whole at ${width}px`).toBe(1);
    expect(narrow.text, `the archived filename at ${width}px`).toBe('Write-It-Down-1.0.dmg');
    expect(narrow.noteRight, `the note fits the card at ${width}px`).toBeLessThanOrEqual(narrow.contentRight + 0.5);
    expect(narrow.overflow, `the page never scrolls sideways at ${width}px`).toBeLessThanOrEqual(0);
    await page.locator('#previous-version').scrollIntoViewIfNeeded();
    await page.locator('.dlbox').screenshot({ path: info.outputPath(`download-archive-note-${width}.png`) });
  }
});

// Contrast of two computed colours, measured the WCAG way (the site's own tokens, not a guess).
function contrast(left, right) {
  const parse = color => color.match(/[\d.]+/g).slice(0, 3).map(Number);
  const channel = value => {
    const unit = value / 255;
    return unit <= 0.04045 ? unit / 12.92 : ((unit + 0.055) / 1.055) ** 2.4;
  };
  const luminance = color => {
    const [r, g, b] = parse(color).map(channel);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const [light, dark] = [luminance(left), luminance(right)].sort((a, b) => b - a);
  return (light + 0.05) / (dark + 0.05);
}

test('the download head breaks without an orphan and its checksum block reads', async ({ page }, info) => {
  await page.goto('download/');
  await page.evaluate(() => document.fonts.ready);
  const readHead = () => page.evaluate(() => {
    const h1 = document.querySelector('.dlhead h1');
    // Every word's own rect, grouped into rendered lines: this is the break the reader sees.
    const range = document.createRange();
    const lines = [];
    const walker = document.createTreeWalker(h1, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      let offset = 0;
      for (const word of node.textContent.split(/(\s+)/)) {
        if (word.trim()) {
          range.setStart(node, offset);
          range.setEnd(node, offset + word.length);
          const rect = range.getClientRects()[0];
          let line = lines.find(entry => Math.abs(entry.top - rect.top) < 2);
          if (!line) lines.push(line = { top: rect.top, left: rect.left, words: [] });
          else line.left = Math.min(line.left, rect.left);
          line.words.push(word);
        }
        offset += word.length;
      }
    }
    const box = element => {
      const rect = element.getBoundingClientRect();
      return { x: rect.x, width: rect.width, height: rect.height, centre: rect.x + rect.width / 2 };
    };
    const sub = document.querySelector('.dlhead .sub');
    const subStyle = getComputedStyle(sub);
    // 34ch measured by the page itself, in the deck's own font: the cap is a reading measure.
    const probe = document.createElement('span');
    probe.style.cssText = `position:absolute;visibility:hidden;white-space:nowrap;font:${subStyle.font};width:34ch`;
    sub.parentElement.append(probe);
    const ch34 = probe.getBoundingClientRect().width;
    probe.remove();
    const subRange = document.createRange();
    subRange.selectNodeContents(sub);
    const subInkLeft = subRange.getClientRects()[0]?.left ?? sub.getBoundingClientRect().left;
    return {
      lines: lines.map(line => line.words.join(' ')),
      h1InkLeft: lines.length ? lines[0].left : null,
      h1Align: getComputedStyle(h1).textAlign,
      h1: box(h1),
      sub: { ...box(sub), align: subStyle.textAlign, inkLeft: subInkLeft, measure: parseFloat(subStyle.maxWidth),
        ch34 },
    };
  });
  const read = await readHead();
  const phone = page.viewportSize().width <= 420;
  if (phone) {
    // No one-word last line: the headline breaks as `Write It Down` / `for Mac`.
    expect(read.lines.length).toBeGreaterThan(1);
    for (const line of read.lines) expect(line.split(' ').length, `the line \`${line}\` holds more than one word`).toBeGreaterThan(1);
    // The deck is a reading column on the headline's own left edge, not seven centred lines.
    expect(read.sub.align).toBe('left');
    expect(read.h1Align).toBe('left');
    expect(read.h1InkLeft, 'the headline ink and the deck ink share one left edge').toBeCloseTo(read.sub.inkLeft, 0);
    expect(read.sub.measure, 'the deck is capped at 34ch').toBeLessThanOrEqual(read.sub.ch34 + 0.5);
  } else {
    expect(read.lines).toEqual(['Write It Down for Mac']);
    expect(read.h1Align).toBe('center');
    expect(read.sub.align).toBe('center');
    expect(read.sub.centre).toBeCloseTo(read.h1.centre, 0);
  }
  await page.screenshot({ path: info.outputPath('download-head.png'), fullPage: false });
  // The phone head is one left-aligned block at every phone width: the headline ink and the deck
  // ink start on the same edge, and the H1 still breaks into two lines with no one-word line.
  for (const width of [390, 375, 320]) {
    await page.setViewportSize({ width, height: page.viewportSize().height });
    await page.evaluate(() => document.fonts.ready);
    const head = await readHead();
    expect(head.h1Align, `${width}: the phone head is left-aligned`).toBe('left');
    expect(head.sub.align, `${width}: the phone deck is left-aligned`).toBe('left');
    expect(head.h1InkLeft, `${width}: the headline ink and the deck ink share one edge`).toBeCloseTo(head.sub.inkLeft, 0);
    expect(head.lines.length, `${width}: the phone headline breaks into two lines`).toBeGreaterThan(1);
    for (const line of head.lines) expect(line.split(' ').length, `${width}: the line \`${line}\` holds more than one word`).toBeGreaterThan(1);
    expect(head.sub.measure, `${width}: the deck stays within 34ch`).toBeLessThanOrEqual(head.sub.ch34 + 0.5);
  }
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  // Both copyable strings are visible whole at every width: the hash's two atomic 32-character
  // halves share a line when they fit and wrap when they do not, and the command breaks at its
  // argument boundary with the filename whole (D-060).
  for (const width of [1440, 1024, 390, 375, 320]) {
    await page.setViewportSize({ width, height: page.viewportSize().height });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(100);
    const strings = await page.evaluate(() => {
      const lineBands = element => {
        const range = document.createRange();
        range.selectNodeContents(element);
        const bands = [];
        for (const line of range.getClientRects()) {
          const band = bands.find(b => line.top < b.bottom && line.bottom > b.top);
          if (band) { band.top = Math.min(band.top, line.top); band.bottom = Math.max(band.bottom, line.bottom); }
          else bands.push({ top: line.top, bottom: line.bottom });
        }
        return bands.length;
      };
      const inside = element => {
        const box = element.getBoundingClientRect();
        const range = document.createRange();
        range.selectNodeContents(element);
        return [...range.getClientRects()].every(line => line.left >= box.left - 0.5 && line.right <= box.right + 0.5);
      };
      const block = element => ({
        overflowX: getComputedStyle(element).overflowX,
        scrollWidth: element.scrollWidth, clientWidth: element.clientWidth,
        text: element.textContent,
      });
      const hash = document.querySelector('#sha256');
      const hashCode = hash.querySelector('code');
      const install = document.querySelector('#install code');
      return {
        hashText: hashCode.textContent,
        hashBands: lineBands(hashCode),
        hashLines: [...hashCode.children].map(span => ({
          text: span.textContent, font: parseFloat(getComputedStyle(span).fontSize),
          bands: lineBands(span), inside: inside(span), top: span.getBoundingClientRect().top,
          scrollWidth: span.scrollWidth, clientWidth: span.clientWidth,
        })),
        hashLabelInside: inside(hash.querySelector('.sha-label')),
        hashBlock: block(hash),
        hashColor: getComputedStyle(hashCode).color,
        panelBackground: getComputedStyle(hash).backgroundColor,
        cardBackground: getComputedStyle(hash.closest('.card')).backgroundColor,
        panelBorder: getComputedStyle(hash).borderTop, panelRadius: getComputedStyle(hash).borderTopLeftRadius,
        page: getComputedStyle(document.body).backgroundColor,
        // Card in card (rule 14.4 d): a copyable block that still carries its own fill, a radius or a
        // closed border is a panel inside the card. One hairline top is the only line it may keep.
        nestedPanels: [hash, document.querySelector('#release-notes'), install].filter(element => {
          const style = getComputedStyle(element);
          const sides = ['Top', 'Right', 'Bottom', 'Left']
            .filter(side => parseFloat(style['border' + side + 'Width']) > 0 && style['border' + side + 'Style'] !== 'none').length;
          return style.backgroundColor !== 'rgba(0, 0, 0, 0)' || parseFloat(style.borderTopLeftRadius) > 0 || sides > 1;
        }).length,
        commandText: install.textContent,
        commandParts: [...install.children].map(span => ({ text: span.textContent, bands: lineBands(span), inside: inside(span) })),
        commandBlock: block(install),
        ghost: document.querySelectorAll('.dlscroll, .is-more').length,
      };
    });
    expect(strings.hashText, `${width}: the published hash`).toMatch(/^[0-9a-f]{64}$/);
    expect(strings.hashLines.map(line => line.text), `${width}: two 32-character hash lines`).toEqual([
      strings.hashText.slice(0, 32), strings.hashText.slice(32),
    ]);
    for (const line of strings.hashLines) {
      expect(line.bands, `${width}: each hash line stays unbroken`).toBe(1);
      expect(line.inside, `${width}: each hash line sits inside the panel`).toBe(true);
      expect(line.scrollWidth, `${width}: the hash line is not clipped`).toBeLessThanOrEqual(line.clientWidth + 1);
    }
    const expectedLines = width >= 1024 ? 1 : 2;
    expect(strings.hashBands, `${width}: the hash uses ${expectedLines} rendered line(s)`).toBe(expectedLines);
    if (expectedLines === 1) expect(Math.abs(strings.hashLines[1].top - strings.hashLines[0].top), `${width}: both halves share one line`).toBeLessThan(1);
    else expect(strings.hashLines[1].top, `${width}: the second half wraps below the first`).toBeGreaterThan(strings.hashLines[0].top);
    expect(strings.hashLabelInside, `${width}: the SHA-256 label sits inside the panel`).toBe(true);
    expect(strings.hashBlock.overflowX, `${width}: the hash panel is not a scroll container`).not.toMatch(/auto|scroll/);
    expect(strings.hashBlock.scrollWidth, `${width}: the hash panel does not overflow`).toBeLessThanOrEqual(strings.hashBlock.clientWidth + 1);
    expect(strings.hashLines[0].font, `${width}: the hash keeps its size floor`).toBeCloseTo(width <= 364 ? 12 : 13, 1);
    expect(strings.commandText, `${width}: the copied command`).toBe(`shasum -a 256 ${dmgFile}`);
    expect(strings.commandParts.map(part => part.text), `${width}: the command breaks at its argument boundary`).toEqual(['shasum -a 256 ', dmgFile]);
    for (const part of strings.commandParts) {
      expect(part.bands, `${width}: each command part stays on one line`).toBe(1);
      expect(part.inside, `${width}: each command part sits inside the block`).toBe(true);
    }
    expect(strings.commandBlock.overflowX, `${width}: the command block is not a scroll container`).not.toMatch(/auto|scroll/);
    expect(strings.commandBlock.scrollWidth, `${width}: the command block does not overflow`).toBeLessThanOrEqual(strings.commandBlock.clientWidth + 1);
    expect(strings.ghost, `${width}: no scroller or fade remains`).toBe(0);
    expect(strings.nestedPanels, `${width}: no copyable block is a card inside a card`).toBe(0);
    expect(strings.panelBackground, `${width}: the hash adds no fill of its own`).toBe('rgba(0, 0, 0, 0)');
    expect(strings.panelRadius, `${width}: the hash adds no radius`).toBe('0px');
    expect(strings.panelBorder, `${width}: the hash opens on one hairline top`).toMatch(/^1px solid/);
    expect(contrast(strings.hashColor, strings.cardBackground), `${width}: the hash stays legible`).toBeGreaterThanOrEqual(4.5);
    await page.locator('[data-copy="sha256"]').click();
    await expect(page.locator('#copy-sha256-status')).toHaveText('Copied.');
    await expect(page.locator('[data-copy="sha256"]')).toHaveText('COPIED');
    expect(await page.evaluate(() => navigator.clipboard.readText()), `${width}: COPY returns the whole hash`).toBe(strings.hashText);
    await page.locator('[data-copy="install"]').click();
    await expect(page.locator('#copy-install-status')).toHaveText('Copied.');
    await expect(page.locator('[data-copy="install"]')).toHaveText('COPIED');
    expect(await page.evaluate(() => navigator.clipboard.readText()), `${width}: COPY returns the whole command`).toBe(strings.commandText);
  }
  await expect(page.locator('[data-copy="sha256"]')).toHaveAccessibleName('Copy the SHA-256');
  await expect(page.locator('[data-copy="install"]')).toHaveAccessibleName('Copy the install command');
  await page.evaluate(() => {
    Object.defineProperty(navigator.clipboard, 'writeText', { value: () => Promise.reject(new Error('blocked')), configurable: true });
    document.execCommand = () => false;
  });
  await page.locator('[data-copy="install"]').click();
  await expect(page.locator('[data-copy="install"]')).toHaveText('COPY');
  await expect(page.locator('#copy-install-status')).toHaveText('Copy failed. Select the text and copy it.');
  await page.waitForTimeout(2100);
  await expect(page.locator('[data-copy="install"]')).toHaveText('COPY');
  await expect(page.locator('#copy-install-status')).toHaveText('Copy failed. Select the text and copy it.');
  await expect(page.locator('[data-copy="sha256"]')).toHaveText('COPY');
  await expect(page.locator('#copy-sha256-status')).toHaveText('');
});

test('legal pages state the 3-session trial, the local counter and the opt-in updates', async ({ page }) => {
  // Four pages read in one body.
  test.setTimeout(sweepTimeout(4));
  await page.goto('privacy.html');
  const privacy = page.locator('#mac + p');
  await expect(privacy).toContainText('Your first 3 writing sessions are free.');
  await expect(privacy).toContainText('license covers 2 computers for $4.99 once, with a 14-day refund');
  await expect(privacy).toContainText('Free updates included.');
  await expect(privacy).toContainText('local trial session counter in its settings file on the Mac');
  await expect(privacy).toContainText('That counter is not sent anywhere.');
  const updateNotice = page.locator('#mac ~ p').filter({ hasText: 'Updates are opt-in.' });
  await expect(updateNotice).toHaveCount(1);
  await expect(updateNotice).toContainText('No check runs unless you turn on');
  await expect(updateNotice).toContainText('Check for updates automatically');
  await expect(updateNotice).toContainText('Check for Updates…');

  // Only the Mac app ships, so the Windows app block and its licence terms are gone (C3).
  await expect(page.locator('#windows')).toHaveCount(0);
  await expect(page.locator('body')).not.toContainText(/Windows/i);
  // Checkout names Stripe, word for word, in the Mac app block.
  const stripeSentence = "Checkout uses Stripe's page under its privacy policy. Stripe shares your email address and order details with us for support and refunds; we do not receive your card details.";
  const macCheckout = page.locator('#mac ~ p').filter({ hasText: 'Downloading the app makes an ordinary request' });
  await expect(macCheckout).toHaveCount(1);
  await expect(macCheckout).toContainText(stripeSentence);
  await expect(page.locator('main')).not.toContainText('payment provider');
  // The outside-request list names the apps that exist, not only the Mac page.
  await expect(page.locator('main')).toContainText('The only outside requests are the cookieless analytics beacon and, on the Mac page and in the Mac app, the license service.');

  await page.goto('terms.html');
  const terms = page.locator('#mac + p');
  await expect(terms).toContainText('The Mac app includes 3 free writing sessions.');
  await expect(terms).toContainText('$4.99 once for two computers, with a 14-day refund');
  await expect(terms).toContainText('Free updates included.');

  await page.goto('support.html');
  const support = page.locator('#mac + p');
  await expect(support).toContainText('your first 3 writing sessions are free.');
  await expect(support).toContainText('license covers 2 computers for $4.99 once, with a 14-day refund');
  await expect(support).toContainText('Free updates included.');

  await page.goto('mac.html');
  const stored = page.locator('#privacy + p');
  await expect(stored).toContainText('local trial session counter in its settings file on the Mac');
  await expect(stored).toContainText('That counter is not sent anywhere.');
  await expect(page.locator('main')).not.toContainText(/purchase is required before|activation before writing/i);
});

test('DMG release packaging refuses unconfigured builds', () => {
  test.skip(test.info().project.name !== '1440-dark-no-preference', 'configuration gate, one project is enough');
  expect(execFileSync('python3', ['../apps/macos/FirstLine/scripts/test-release-config.py'], { encoding: 'utf8' })).toContain('release requires complete license and update configuration');
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

// T3 `Buy to checkout` is the income path, and its cost is reach: how far down the landing a buyer must scroll
// before they can pay. Measured on main 89b4870 with scripts/core-tasks/measure-web.mjs: the landing's only buy
// entry sits 2.64 screens down at 1440 and 3.92 at 390. That is the number to beat, not to grow - a section added
// above the Mac card, or a taller demo, must not push the purchase further away without someone noticing. The
// no-scroll detour (header `Download for Mac` -> the download page's own Buy) is asserted to stay in the first
// screen for the same reason: it is the route a buyer can already take that costs no scrolling.
test('the buy entry is no further down the landing than it is today, and the no-scroll detour still exists', async ({ page }) => {
  await page.goto('index.html');
  const reach = await page.evaluate(() => {
    const a = [...document.querySelectorAll('#landing a')].find(x => /Buy for \$4\.99/.test(x.textContent));
    if (!a) return null;
    const r = a.getBoundingClientRect();
    return { screens: Math.round(((r.top + scrollY) / innerHeight) * 100) / 100, inFirstScreen: r.top < innerHeight };
  });
  expect(reach, 'the landing still sells the Mac app from its Mac card').not.toBeNull();
  // 2.75 / 4.05 leave room for a pixel of layout rounding, not for a new section.
  const cap = page.viewportSize().width >= 1024 ? 2.75 : 4.05;
  expect(reach.screens, `the landing buy entry is ${reach.screens} screens down, and its measured reach on 89b4870 was 2.64 at 1440 and 3.92 at 390`).toBeLessThanOrEqual(cap);
  await page.goto('download/');
  const detour = await page.evaluate(() => {
    const a = [...document.querySelectorAll('a')].find(x => /Buy for \$4\.99/.test(x.textContent));
    if (!a) return null;
    const r = a.getBoundingClientRect();
    return { top: Math.round(r.top), inFirstScreen: r.top < innerHeight && r.bottom > 0 };
  });
  expect(detour, 'the download page still offers the purchase').not.toBeNull();
  expect(detour.inFirstScreen, 'the download page sells without scrolling').toBe(true);
});

// The buy line shipped after 320/375/390/1440 were measured. This sweeps the tablet band - the sizes between the
// phone sweep and the desktop target - and holds the same three promises there: the line is on the first screen,
// nothing overflows sideways, and the sheet keeps its 61% floor (D-110, D-068).
test('the buy line holds through the tablet band', async ({ page }, info) => {
  test.skip(!['1440-light-no-preference', '390-light-no-preference'].includes(info.project.name), 'One project sweeps the band');
  for (const size of [{ width: 600, height: 800 }, { width: 768, height: 1024 }, { width: 834, height: 1112 }, { width: 1024, height: 768 }, { width: 1180, height: 820 }]) {
    await page.setViewportSize(size);
    await page.goto('index.html');
    await page.evaluate(() => document.fonts.ready);
    const read = await page.evaluate(() => {
      const box = selector => { const r = document.querySelector(selector).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, right: r.right, height: r.height }; };
      const door = box('#landing .cta .btn');
      const buy = box('#landing .cta .cta-buy');
      const sheet = box('#paper');
      return { viewport: innerHeight, viewportWidth: innerWidth, scrollWidth: document.documentElement.scrollWidth,
        door, buy, sheet, first: box('.first-screen') };
    });
    const label = `${size.width}x${size.height}`;
    expect(await page.locator('#landing .cta a[href="mac.html#buy"]').count(), `${label}: one quiet buy line in the door band`).toBe(1);
    expect(read.buy.top, `${label}: the buy line is on the first screen`).toBeLessThan(read.viewport);
    expect(read.buy.top, `${label}: the buy line sits under the door`).toBeGreaterThanOrEqual(read.door.bottom - 0.5);
    expect(Math.abs(read.buy.left + (read.buy.right - read.buy.left) / 2 - (read.door.left + read.door.right) / 2), `${label}: the line is centred on the door`).toBeLessThan(1);
    expect(read.scrollWidth, `${label}: no horizontal overflow`).toBeLessThanOrEqual(read.viewportWidth);
    expect(read.sheet.height / read.viewport, `${label}: the sheet keeps its 61% floor`).toBeGreaterThanOrEqual(0.61 - 1 / read.viewport);
    expect(Math.abs(read.sheet.bottom - read.first.bottom), `${label}: the sheet still owns the first screen's remainder`).toBeLessThanOrEqual(1);
  }
});
