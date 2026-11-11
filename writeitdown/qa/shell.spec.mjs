import { test, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { openPage, sweepTimeout } from './page-sweep.mjs';

// The thirteen shipped pages. Every one of them carries the landing page's design system: the A mark
// lockup on its paper plate, the theme button, the shared footer, and the v2 type and colour roles.
// The support and answer pages are not a reading mode; the purchase page is not a third system.
const pages = ['index.html', 'download/', 'mac.html', 'support.html', 'privacy.html', 'terms.html', 'impressum.html',
  'what-is-write-it-down.html', 'is-my-writing-saved.html', 'delete-a-draft.html',
  'write-it-down-free-trial.html', 'write-it-down-mac-vs-web.html', 'write-it-down-price.html'];
// The purchase page is one screen with no footer and no second section, so it joins the shell identity
// and the one-price-per-page guard, not the document-page and footer contracts the thirteen share.
const purchasePage = 'buy.html';
const documentPages = ['mac.html', 'support.html', 'privacy.html', 'terms.html', 'impressum.html',
  'what-is-write-it-down.html', 'is-my-writing-saved.html', 'delete-a-draft.html',
  'write-it-down-free-trial.html', 'write-it-down-mac-vs-web.html', 'write-it-down-price.html'];
const service = 'https://licenses.writeitdown.app/api/v1';
const licenseKey = 'WID-TEST-PRICE-KEY';
const pricePattern = /(?<![\d.])(?:USD\s*)?\$?\s*4\.99(?:\s*(?:once|one-time))?(?!\d)/gi;

const readShell = page => page.evaluate(async () => {
  await document.fonts.ready;
  const css = (element, pseudo = null) => getComputedStyle(element, pseudo);
  const token = (element, name) => {
    const probe = document.createElement('i');
    probe.style.color = `var(${name})`;
    element.append(probe);
    const color = css(probe).color;
    probe.remove();
    return color;
  };
  const home = [...document.querySelectorAll('.home')].find(element => element.getClientRects().length);
  const nav = [...document.querySelectorAll('nav[aria-label="Main"]')].find(element => element.getClientRects().length);
  const brand = nav.querySelector('.brand');
  const toggle = nav.querySelector('.theme-btn');
  const brandBox = brand.getBoundingClientRect();
  return {
    theme: document.documentElement.dataset.theme,
    brandTop: +brandBox.top.toFixed(2),
    brandHeight: +brandBox.height.toFixed(2),
    plate: css(toggle).backgroundColor,
    plateToken: token(home, '--sheet'),
    plateEdge: css(toggle).borderTopWidth,
    brandInk: css(brand).color,
    inkToken: token(home, '--ink'),
    family: css(home).fontFamily,
    size: css(home).fontSize,
    canvas: css(document.body).backgroundColor,
    pageToken: token(document.body, '--page'),
    footer: !!document.querySelector('.home-foot .foot-grid'),
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    monoLinks: [...document.querySelectorAll('link[rel="stylesheet"], link[rel="preload"]')].filter(link => /IBM\+Plex\+Mono/.test(link.href)).length,
    monoFonts: [...document.fonts].filter(font => /IBM Plex Mono/i.test(font.family) && font.status === 'loaded').length,
  };
});

test('thirteen shipped pages share one header, plate, canvas and body family', async ({ page }) => {
  // Thirteen navigations in one body: budget the walk, not the harness's flat 30 s (#146).
  test.setTimeout(sweepTimeout(pages.length));
  const shells = [];
  for (const path of pages) {
    await openPage(page, path);
    const shell = await readShell(page);
    shells.push({ path, ...shell });
  }
  const summary = shells.map(s => `${s.path}: top ${s.brandTop}, plate ${s.plate}, family ${s.family.slice(0, 20)}, canvas ${s.canvas}`).join(' | ');
  expect(new Set(shells.map(s => s.brandTop)).size, `brand y: ${summary}`).toBe(1);
  expect(new Set(shells.map(s => s.brandHeight)).size, `brand height: ${summary}`).toBe(1);
  expect(new Set(shells.map(s => s.plate)).size, `theme plate: ${summary}`).toBe(1);
  expect(new Set(shells.map(s => s.family)).size, `body family: ${summary}`).toBe(1);
  expect(new Set(shells.map(s => s.canvas)).size, `canvas: ${summary}`).toBe(1);
  for (const shell of shells) {
    const at = `${shell.path}:`;
    expect(shell.brandTop, `${at} the mark sits at the same y as the landing`).toBeGreaterThan(0);
    expect(shell.brandTop, `${at} the mark is inside the header's top third`).toBeLessThan(30);
    expect(shell.plate, `${at} the theme button paints the paper plate, not transparency`).toBe(shell.plateToken);
    expect(shell.plate, `${at} the plate is opaque`).toMatch(/^rgb\(/);
    expect(shell.plateEdge, `${at} the plate keeps its hairline edge`).toBe('1px');
    expect(shell.brandInk, `${at} the lockup wears the ink token`).toBe(shell.inkToken);
    expect(shell.canvas, `${at} the page canvas is background A`).toBe(shell.pageToken);
    expect(shell.footer, `${at} the shared footer is present`).toBe(true);
    expect(shell.overflow, `${at} no horizontal overflow`).toBeLessThanOrEqual(0);
    expect(shell.monoLinks, `${at} no stylesheet requests IBM Plex Mono`).toBe(0);
    expect(shell.monoFonts, `${at} no loaded webfont is IBM Plex Mono`).toBe(0);
  }
});

// D-115: a visitor on any page finds Buy in the top-right corner, immediately left of the page's other pill, and on a
// phone, where that pill steps aside, Buy stays. The hero keeps one action. Protects "I can pay from where I am".
test('the header carries Buy on every page, left of the page action, and the hero keeps one action', async ({ page }, info) => {
  test.setTimeout(sweepTimeout(pages.length + 3));
  const width = info.project.use.viewport.width;
  for (const path of [...pages, purchasePage]) {
    await openPage(page, path);
    const read = await page.evaluate(() => {
      const nav = [...document.querySelectorAll('nav[aria-label="Main"]')].find(n => n.getClientRects().length);
      const shown = el => !!el && el.getClientRects().length > 0;
      const buys = [...nav.querySelectorAll('a.nav-buy')];
      const buy = buys[0];
      const other = nav.querySelector('a.btn-quiet:not(.nav-buy)');
      const box = buy?.getBoundingClientRect() ?? { left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 };
      const theme = nav.querySelector('.theme-btn').getBoundingClientRect();
      return { count: buys.length, text: buy?.textContent, path: buy && new URL(buy.href).pathname, current: buy?.getAttribute('aria-current'),
        visible: shown(buy), otherVisible: shown(other),
        leftOfOther: shown(other) ? box.right <= other.getBoundingClientRect().left : null,
        leftOfTheme: box.right <= theme.left, height: box.height,
        hitTop: document.elementFromPoint(box.left + box.width / 2, box.top - 3.5) === buy,
        hitBottom: document.elementFromPoint(box.left + box.width / 2, box.bottom + 3.5) === buy,
        overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth };
    });
    const at = `${path} at ${width}px:`;
    expect(read.count, `${at} one header Buy`).toBe(1);
    expect(read.text, `${at} the header link is the single word Buy`).toBe('Buy');
    expect(read.path, `${at} the header Buy goes to the purchase page`).toMatch(/^\/(writeitdown\/)?buy(\.html)?$/);
    expect(read.visible, `${at} Buy is visible in the header`).toBe(true);
    expect(read.leftOfTheme, `${at} Buy is left of the theme button`).toBe(true);
    expect(read.hitTop && read.hitBottom, `${at} Buy keeps a 44 px tall hit area`).toBe(true);
    expect(read.overflow, `${at} the page never scrolls sideways`).toBeLessThanOrEqual(0);
    if (read.otherVisible) expect(read.leftOfOther, `${at} Buy is immediately left of the page action`).toBe(true);
    if (width === 390) expect(read.otherVisible, `${at} the page action steps aside on a phone and Buy stays`).toBe(false);
    if (width === 1440) expect(read.otherVisible, `${at} the page action is beside Buy on a computer`).toBe(true);
    expect(read.current, `${at} only the purchase page marks its own Buy as current`).toBe(path === purchasePage ? 'page' : null);
  }
  // The not-found page links its stylesheet by root path, which the local server cannot serve from /writeitdown/, so its
  // header is read as markup: one Buy to /buy, ahead of Download for Mac.
  await openPage(page, '404.html');
  const missing = await page.evaluate(() => {
    const end = document.querySelector('nav[aria-label="Main"] .nav-end');
    return [...end.querySelectorAll('a')].map(a => `${a.textContent}>${a.getAttribute('href')}`);
  });
  expect(missing, '404.html: Buy leads Download for Mac in the header').toEqual(['Buy>/buy', 'Download for Mac>/download/']);
  await openPage(page, 'index.html');
  await expect(page.locator('#landing .cta a'), 'the hero keeps one action: the door').toHaveCount(1);
  await expect(page.locator('#landing .cta a.btn-primary')).toHaveText('Give it 60 seconds');
  await expect(page.locator('.cta-buy'), 'no second buy line under the door').toHaveCount(0);
});

test('the document pages keep 17 px sans copy at the documented measure', async ({ page }) => {
  for (const path of documentPages) {
    await page.goto(path);
    const read = await page.evaluate(() => {
      const css = (selector, pseudo = null) => getComputedStyle(document.querySelector(selector), pseudo);
      const main = document.querySelector('main.doc');
      const paragraph = [...main.querySelectorAll('p')].sort((x, y) => y.textContent.length - x.textContent.length)[0];
      const box = paragraph.getBoundingClientRect();
      return {
        font: css('main.doc p').fontFamily,
        size: css('main.doc p').fontSize,
        width: +box.width.toFixed(1),
        legacy: document.querySelectorAll('.legal, .door, .deck, .logotype, .foot, .stage').length,
        h1: css('main.doc h1').fontFamily,
      };
    });
    expect(read.font, `${path}: body copy is the system tool face`).toMatch(/system-ui/);
    expect(read.size, `${path}: body copy is 17 px`).toBe('17px');
    expect(read.width, `${path}: the measure stays near 62ch`).toBeLessThanOrEqual(62 * 17 * 0.66);
    expect(read.width, `${path}: the measure fills the available column`).toBeGreaterThan(300);
    expect(read.h1, `${path}: headings keep the serif`).toMatch(/Newsreader/);
    expect(read.legacy, `${path}: no retired shell class survives`).toBe(0);
  }
});

test('the purchase page wears the same shell and stops at its actions', async ({ page }) => {
  await openPage(page, 'index.html');
  const landing = await readShell(page);
  await openPage(page, purchasePage);
  const shell = await readShell(page);
  expect(shell.brandTop, 'the mark sits at the landing y').toBe(landing.brandTop);
  expect(shell.brandHeight, 'the mark is the landing size').toBe(landing.brandHeight);
  expect(shell.plate, 'the theme button paints the same plate').toBe(landing.plate);
  expect(shell.brandInk, 'the lockup wears the ink token').toBe(shell.inkToken);
  expect(shell.canvas, 'the page canvas is background A').toBe(shell.pageToken);
  expect(shell.family, 'the same body family as every other page').toBe(landing.family);
  expect(shell.overflow, 'no horizontal overflow').toBeLessThanOrEqual(0);
  await expect(page.locator('link[rel="canonical"]'), 'the clean URL is the canonical, not buy.html').toHaveAttribute('href', 'https://writeitdown.app/buy');
  // Nothing below the actions: no footer, no second section, and no legal or refund band. The refund
  // and the terms live on the checkout, /terms.html and mac.html#refund (rule 30).
  expect(shell.footer, 'the purchase page carries no footer').toBe(false);
  // Nothing else on the page: the price, the licence it buys in three lines, the two actions. An exact
  // reading is the guard, so a fourth line - a reassurance, a payment-processor note, a refund promise -
  // fails here instead of drifting in (rule 30).
  const text = (await page.locator('main').innerText()).replace(/\s+/g, ' ').trim();
  expect(text).toBe('$4.99 once One license for 2 computers. No subscription. Free updates included. Buy for $4.99 once Download free trial');
  await expect(page.locator('main')).not.toContainText(/refund|guarantee|secure|stripe|money.back|risk.free/i);
  await expect(page.locator('main a')).toHaveCount(1);
  await expect(page.locator('main a')).toHaveText('Download free trial');
});

test('the purchase page is one screen at 320, 390 and 1440, with the price as its largest text', async ({ page }, info) => {
  test.skip(info.project.name !== '1440-light-no-preference', 'one project drives its own three widths');  for (const [width, height] of [[320, 700], [390, 844], [1440, 900]]) {
    await page.setViewportSize({ width, height });
    await openPage(page, purchasePage);
    await page.evaluate(() => document.fonts.ready);
    const read = await page.evaluate(() => {
      const box = selector => {
        const rect = document.querySelector(selector).getBoundingClientRect();
        return { top: +rect.top.toFixed(1), bottom: +rect.bottom.toFixed(1), left: +rect.left.toFixed(1), right: +rect.right.toFixed(1), width: +rect.width.toFixed(1) };
      };
      const fontOf = selector => parseFloat(getComputedStyle(document.querySelector(selector)).fontSize);
      // Every rank but the price, so "the largest thing on the page" is a measurement, not an assumption.
      const largestOther = Math.max(...[...document.querySelectorAll('main *')]
        .filter(element => element.getClientRects().length && !element.closest('.buy-price'))
        .map(element => parseFloat(getComputedStyle(element).fontSize)));
      return {
        viewport: { width: innerWidth, height: innerHeight },
        scrollWidth: document.documentElement.scrollWidth,
        scrollHeight: document.documentElement.scrollHeight,
        price: box('.buy-price'), priceFont: fontOf('.buy-price'), largestOther,
        facts: box('.buy-facts'), actions: box('.doc-actions'),
        primary: box('#buy-form button'), ghost: box('.doc-actions>.btn-ghost'),
        factsFont: fontOf('.buy-facts li'),
        text: document.querySelector('.buy-price').textContent.trim(),
      };
    });
    const at = `${width}x${height}`;
    expect(read.text, `${at}: the price is the published string`).toBe('$4.99 once');
    expect(read.scrollWidth, `${at}: never scrolls sideways`).toBeLessThanOrEqual(read.viewport.width);
    expect(read.scrollHeight, `${at}: the page is one screen`).toBeLessThanOrEqual(read.viewport.height);
    expect(read.priceFont, `${at}: the price is the largest thing on the page`).toBeGreaterThan(read.largestOther * 2);
    expect(read.priceFont / read.factsFont, `${at}: the price outranks the facts`).toBeGreaterThan(2);
    expect(read.price.left, `${at}: the price is inside the viewport`).toBeGreaterThanOrEqual(0);
    expect(read.price.right, `${at}: the price is inside the viewport`).toBeLessThanOrEqual(read.viewport.width);
    expect(read.price.bottom, `${at}: the price is above the facts`).toBeLessThan(read.facts.top);
    expect(read.facts.bottom, `${at}: the facts sit above the actions`).toBeLessThan(read.actions.top);
    expect(read.actions.bottom, `${at}: the actions are the last thing on the page`).toBeLessThanOrEqual(read.viewport.height);
    expect(read.primary.top, `${at}: Buy is the first action`).toBeLessThanOrEqual(read.ghost.top);
    // Stacked on a phone, the pair shares one width, so the ghost's edge does not end short of the
    // primary's (D-106). Side by side, each keeps its own.
    if (read.ghost.top >= read.primary.bottom - 1) expect(read.ghost.width, `${at}: the stacked pair shares one width`).toBe(read.primary.width);
    else expect(read.ghost.left, `${at}: side by side, the ghost follows the primary`).toBeGreaterThan(read.primary.right);
  }
});

test('the licence sentence is written once and copied verbatim to the Mac page', async ({ page }) => {
  const sentence = 'One license for 2 computers. No subscription. Free updates included.';
  await page.goto('mac.html');
  await expect(page.locator('#price-row .doc-note'), 'mac.html states the licence facts').toHaveText(sentence);
  await page.goto(purchasePage);
  const facts = await page.locator('.buy-facts li').allInnerTexts();
  expect(facts.join(' '), 'the purchase page states the same facts, word for word').toBe(sentence);
  // Safari drops list semantics from a `ul` whose markers are hidden unless the role is restated, and
  // the phone that reads this page is WebKit. The three facts stay three list items to a screen reader.
  await expect(page.locator('.buy-facts'), 'the facts stay a list in WebKit').toHaveAttribute('role', 'list');
  // The refund is a legal term, not a line beside a Buy button (rule 30): it stays in the page and on
  // /terms.html that own it.
  await page.goto('mac.html');
  await expect(page.locator('#refund + p')).toContainText('14 days from purchase');
  await expect(page.locator('#price-row')).not.toContainText('refund');
});

test('every link on the migrated pages clears 4.5:1 against its canvas', async ({ page }) => {
  const luminance = color => {
    const channels = color.match(/[\d.]+/g).slice(0, 3).map(Number).map(value => {
      const s = value / 255;
      return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  for (const path of documentPages) {
    await page.goto(path);
    const samples = await page.evaluate(() => {
      // A link on a filled or plate surface is read against that surface, not the page canvas.
      const surfaceOf = element => {
        for (let node = element; node; node = node.parentElement) {
          const color = getComputedStyle(node).backgroundColor;
          if (color && color !== 'transparent' && !/,\s*0\)$/.test(color)) return color;
        }
        return getComputedStyle(document.body).backgroundColor;
      };
      return [...document.querySelectorAll('main a, .home-foot a')]
        .filter(link => link.getClientRects().length)
        .map(link => ({ text: link.textContent.trim().slice(0, 24), color: getComputedStyle(link).color, canvas: surfaceOf(link) }));
    });
    expect(samples.length, `${path}: has links to check`).toBeGreaterThan(2);
    for (const sample of samples) {
      const [light, dark] = [luminance(sample.color), luminance(sample.canvas)].sort((a, b) => b - a);
      const ratio = (light + 0.05) / (dark + 0.05);
      expect(ratio, `${path}: "${sample.text}" is ${ratio.toFixed(2)}:1 on ${sample.canvas}`).toBeGreaterThanOrEqual(4.5);
    }
  }
});

test('landing on #buy puts the heading and the price row in view', async ({ page }) => {
  await page.goto('mac.html#buy');
  const view = page.viewportSize();
  const boxes = await page.evaluate(() => {
    const box = selector => {
      const rect = document.querySelector(selector).getBoundingClientRect();
      return { top: +rect.top.toFixed(1), bottom: +rect.bottom.toFixed(1) };
    };
    return {
      heading: box('#buy-heading'),
      price: box('#price-row'),
      margin: parseFloat(getComputedStyle(document.querySelector('#buy')).scrollMarginTop),
      height: innerHeight,
    };
  });
  expect(boxes.margin, 'the buy section reserves scroll margin').toBeGreaterThan(0);
  expect(boxes.heading.top, 'the buy heading starts inside the viewport').toBeGreaterThanOrEqual(0);
  expect(boxes.heading.bottom, 'the buy heading is fully visible').toBeLessThanOrEqual(boxes.height);
  expect(boxes.price.top, 'the price row is not scrolled past').toBeGreaterThanOrEqual(0);
  expect(boxes.price.bottom, 'the price row is fully visible').toBeLessThanOrEqual(boxes.height);
  expect(boxes.height).toBe(view.height);
});

test('the purchase path states one price string', async ({ page, context }) => {
  // Thirteen pages, the purchase page and four visits to it: the walk is what needs the budget.
  test.setTimeout(sweepTimeout(pages.length + 5));
  await page.route('https://fonts.googleapis.com/**', route => route.abort());
  await page.route('https://fonts.gstatic.com/**', route => route.abort());
  const check = async label => {
    const text = (await page.locator('body').innerText()).replace(/\s+/g, ' ').trim();
    const mentions = [...text.matchAll(pricePattern)].map(match => match[0].trim());
    for (const mention of mentions)
      expect(mention, `${label}: price mention "${mention}"`).toBe('$4.99 once');
  };

  for (const path of [...pages, purchasePage]) {
    await openPage(page, path);
    await check(path);
  }

  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  const checkout = `${service}/checkout`;
  const buy = page.locator('#buy-form button');

  await page.goto(purchasePage);
  await expect(page.locator('.buy-price')).toHaveText('$4.99 once');
  await expect(page.getByRole('button', { name: 'Buy for $4.99 once', exact: true })).toBeVisible();

  let finishPending;
  const pending = new Promise(resolve => { finishPending = resolve; });
  await page.route(checkout, async route => {
    await pending;
    await route.abort();
  });
  await buy.click();
  await expect(buy).toHaveText('Opening checkout...');
  await check('buy.html pending');
  finishPending();
  await expect(page.locator('#checkout-status')).toHaveAttribute('role', 'alert');
  await page.unroute(checkout);

  await page.route(checkout, route => route.fulfill({ status: 503, json: {} }));
  await page.goto(purchasePage);
  await buy.click();
  await expect(page.locator('#checkout-status')).toHaveAttribute('role', 'alert');
  await check('buy.html error');
  await page.unroute(checkout);

  await page.route(`${service}/license?session_id=cs_test_price_ready`, route => route.fulfill({ json: { licenseKey } }));
  await page.goto('mac.html?session_id=cs_test_price_ready');
  await expect(page.locator('#license-key')).toHaveText(licenseKey);
  await check('mac.html ready');
  await page.getByRole('button', { name: 'Copy license key', exact: true }).click();
  await expect(page.locator('#copy-license')).toHaveText('Copied');
  await check('mac.html copied');
  await page.unroute(`${service}/license?session_id=cs_test_price_ready`);

  await page.route(`${service}/license?session_id=cs_test_price_unpaid`, route => route.fulfill({ status: 404, json: { error: 'not_found' } }));
  await page.goto('mac.html?session_id=cs_test_price_unpaid');
  await expect(page.locator('#license-status')).toHaveText('Your license is not ready yet.');
  await check('mac.html unpaid');
});

test('the ghost pill keeps one text treatment on the buy path and the landing', async ({ page }) => {
  const decoration = async (path, selector) => {
    await page.goto(path);
    return page.locator(selector).evaluate(element => getComputedStyle(element).textDecorationLine);
  };
  const purchase = await decoration(purchasePage, '#buy .doc-actions>.btn-ghost');
  const buy = await decoration('mac.html', '#buy a.btn-ghost');
  const landing = await decoration('index.html', '#mac a.btn-ghost');
  expect(purchase, 'the purchase card ghost pill').toBe('none');
  expect(buy, 'the buy card ghost pill').toBe('none');
  expect(landing, 'the landing Mac card ghost pill').toBe('none');
  expect(buy).toBe(landing);
  expect(purchase).toBe(landing);
});

test('the landing hand keeps its write-on reveal and drops it under reduced motion', async ({ page }, info) => {
  await page.goto('index.html');
  const name = await page.locator('.home .h1 .hand').evaluate(element => getComputedStyle(element).animationName);
  expect(name, 'the reveal keeps its named animation').toBe(info.project.use.reducedMotion === 'reduce' ? 'none' : 'wid-write');
});

test('the release route server answers a missing page with 404', async ({ request }, info) => {
  test.skip(info.project.name !== '1440-light-no-preference', 'one server run per suite');
  const port = await new Promise((resolve, reject) => {
    const probe = createServer();
    probe.on('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
  const server = spawn(process.execPath, ['journey/serve-local.mjs', '--root', '.', '--port', String(port)],
    { stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('serve-local did not start')), 10_000);
      server.stdout.on('data', chunk => {
        if (/serving/.test(String(chunk))) { clearTimeout(timer); resolve(); }
      });
      server.on('exit', code => reject(new Error(`serve-local exited ${code}`)));
    });
    const missing = await request.get(`http://127.0.0.1:${port}/does-not-exist.html`);
    expect(missing.status(), 'the release server must not fall back to the landing page').toBe(404);
    expect(await missing.text()).not.toContain('<html');
    const absentDmg = await request.get(`http://127.0.0.1:${port}/download/absent-${Date.now()}.dmg`);
    expect(absentDmg.status(), 'a missing disk image is a 404').toBe(404);
    expect((await request.get(`http://127.0.0.1:${port}/support.html`)).status()).toBe(200);
  } finally {
    server.kill();
  }
});

test('404.html is the document shell with one link home and noindex', async ({ page }) => {
  await page.goto('404.html');
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', 'noindex');
  await expect(page.locator('main.doc h1')).toHaveText('Page not found');
  await expect(page.locator('main.doc p')).toHaveCount(1);
  await expect(page.locator('main.doc')).not.toContainText('There is no page at this address.');
  await expect(page.locator('main.doc a')).toHaveCount(1);
  await expect(page.locator('main.doc a')).toHaveAttribute('href', '/');
  const shell = await readShell(page);
  expect(shell.brandTop, '404 header lockup sits where the other pages put it').toBeGreaterThan(0);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  expect(overflow, '404 does not overflow horizontally').toBeLessThanOrEqual(0);
});

test('footers keep Contact without repeating its address in the copy row', async ({ page }) => {
  for (const path of [...pages, '404.html']) {
    await page.goto(path);
    await expect(page.locator('.home-foot .copy span')).toHaveText(['© 2026 Trefoil Studio']);
    await expect(page.locator('.home-foot a[href="mailto:contact@trefoilstudio.com"]')).toHaveText('Contact');
  }
});

test('support keeps each answer once and lists the six answer links without separator dots', async ({ page }) => {
  await page.goto('support.html');
  const main = page.locator('main.doc');
  await expect(main).not.toContainText('You can ask ChatGPT for Write It Down:');
  expect((await main.innerText()).match(/A wiped or closed draft cannot be recovered\./g)).toHaveLength(1);
  const list = page.locator('#answers + ul');
  await expect(list.locator(':scope > li')).toHaveCount(6);
  await expect(list).not.toContainText('·');
  expect(await list.locator('a').evaluateAll(links => links.map(link => [link.textContent, link.getAttribute('href')]))).toEqual([
    ['What is Write It Down?', 'what-is-write-it-down.html'],
    ['Mac app or web room', 'write-it-down-mac-vs-web.html'],
    ['How the free trial works', 'write-it-down-free-trial.html'],
    ['Price and license', 'write-it-down-price.html'],
    ['Deleting a draft', 'delete-a-draft.html'],
    ['Whether writing is saved', 'is-my-writing-saved.html'],
  ]);
  const boxes = await list.locator('a').evaluateAll(links => links.map(link => {
    const box = link.getBoundingClientRect();
    return { left: box.left, right: box.right, top: box.top, bottom: box.bottom };
  }));
  for (const [index, box] of boxes.entries()) {
    expect(box.left).toBeCloseTo(boxes[0].left, 0);
    expect(box.right).toBeLessThanOrEqual(page.viewportSize().width);
    if (index > 0) expect(box.top).toBeGreaterThanOrEqual(boxes[index - 1].bottom);
  }
});

test('the phone room nav keeps only the theme icon, and the Mac link moves into the exit row', async ({ page }, info) => {
  test.skip(info.project.use.viewport.width !== 390, 'phone layout');
  await page.goto('index.html#trial');
  const nav = page.locator('nav[aria-label="Main"]:visible');
  await expect(nav).toHaveCount(1);
  await expect(nav.locator('.brand')).toBeVisible();
  await expect(nav.locator('.theme-btn')).toBeVisible();
  for (const action of await nav.locator('.btn-quiet').all()) await expect(action, 'the phone room header keeps no pill, Buy included (Q-01)').toBeHidden();
  const mac = page.locator('.room .paper-foot .room-mac');
  await expect(mac).toBeVisible();
  await expect(mac).toHaveText('Download for Mac');
  await expect(mac).toHaveAttribute('href', 'download/');
  const geometry = await page.evaluate(() => {
    const box = selector => document.querySelector(selector).getBoundingClientRect();
    return { mac: box('.room .paper-foot .room-mac'), foot: box('.room-paper .paper-foot'), overflow: document.documentElement.scrollWidth - innerWidth };
  });
  expect(geometry.overflow, 'the phone room never scrolls sideways').toBeLessThanOrEqual(0);
  expect(geometry.mac.top, 'the Mac link sits inside the exit row').toBeGreaterThanOrEqual(geometry.foot.top - 0.5);
  expect(geometry.mac.bottom, 'the Mac link sits inside the exit row').toBeLessThanOrEqual(geometry.foot.bottom + 0.5);
});

test('every document page still uses the landing measure, not a second reading mode', async ({ page }) => {
  await page.goto('index.html');
  const landing = await page.evaluate(() => ({
    family: getComputedStyle(document.querySelector('#landing')).fontFamily,
    ink: getComputedStyle(document.querySelector('#landing')).color,
  }));
  for (const path of documentPages) {
    await page.goto(path);
    const doc = await page.evaluate(() => {
      const main = document.querySelector('main.doc');
      return { family: getComputedStyle(document.body).fontFamily, ink: getComputedStyle(main).color };
    });
    expect(doc.family, `${path}: same body family as the landing`).toBe(landing.family);
    expect(doc.ink, `${path}: body copy wears the ink role`).toBe(landing.ink);
  }
});

// The grid: the landing composes its single-column objects inside the header's container (`.wrap`, 1120 px
// with its gutters), so a document is one more such object. Every block of page content therefore starts
// and ends at the same two edges inside the header - either flush with the container or centred in it -
// at every width. A 62ch column left-flush under a full-width header is the defect this pins: the captain
// read mac.html#buy as a narrow block stuck to the logo with an empty band on the right (D-055).
test('every page puts its content on the header grid at 1440, 1024 and 390', async ({ page }, info) => {
  test.skip(info.project.name !== '1440-light-no-preference', 'the test drives its own three widths');
  // Thirteen pages at three widths in one body: thirty-nine navigations, budgeted by the walk.
  test.setTimeout(sweepTimeout(3 * pages.length));
  const read = () => page.evaluate(() => {
    const edges = element => {
      const box = element.getBoundingClientRect();
      const css = getComputedStyle(element);
      return { left: box.left + parseFloat(css.paddingLeft), right: box.right - parseFloat(css.paddingRight) };
    };
    const nav = [...document.querySelectorAll('nav[aria-label="Main"]')].find(element => element.getClientRects().length);
    const header = edges(nav);
    const blocks = [...document.querySelector('main').children]
      .filter(child => child.getClientRects().length)
      .map(child => {
        const box = child.getBoundingClientRect();
        return {
          tag: child.tagName.toLowerCase() + (child.className ? `.${String(child.className).split(' ')[0]}` : ''),
          left: +(box.left - header.left).toFixed(1),
          right: +(header.right - box.right).toFixed(1),
          width: +(box.right - box.left).toFixed(1),
        };
      });
    return { headerWidth: +(header.right - header.left).toFixed(1), blocks };
  });

  for (const width of [1440, 1024, 390]) {
    await page.setViewportSize({ width, height: width === 1440 ? 900 : 844 });
    for (const path of pages) {
      await openPage(page, path);
      await page.evaluate(() => document.fonts.ready);
      const { headerWidth, blocks } = await read();
      expect(headerWidth, `${path} @${width}: the header container has real width`).toBeGreaterThan(200);
      expect(blocks.length, `${path} @${width}: the page has content blocks`).toBeGreaterThan(1);
      for (const block of blocks) {
        const at = `${path} @${width} ${block.tag} starts ${block.left} px and ends ${block.right} px from the header's edges`;
        expect(block.width, `${at}: a block with real width`).toBeGreaterThan(0);
        expect(Math.abs(block.left - block.right), `${at}: flush with the header container or centred in it`).toBeLessThanOrEqual(1);
        if (documentPages.includes(path)) {
          // A document is a centred measure inside the container; only the landing and the download page
          // run a full-bleed band, so only those two may reach past the container's edges.
          expect(block.left, `${at}: a document block may not sit left of the header container`).toBeGreaterThanOrEqual(-0.5);
          expect(block.right, `${at}: a document block may not sit right of the header container`).toBeGreaterThanOrEqual(-0.5);
        }
      }
    }
  }
});
