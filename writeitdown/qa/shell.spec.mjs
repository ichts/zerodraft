import { test, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';

// The twelve shipped pages. Every one of them carries the landing page's design system: the A mark
// lockup on its paper plate, the theme button, the shared footer, and the v2 type and colour roles.
// The support and answer pages are not a reading mode; the purchase page is not a third system.
const pages = ['index.html', 'download/', 'mac.html', 'support.html', 'privacy.html', 'terms.html',
  'what-is-write-it-down.html', 'is-my-writing-saved.html', 'delete-a-draft.html',
  'write-it-down-free-trial.html', 'write-it-down-mac-vs-web.html', 'write-it-down-price.html'];
const documentPages = ['mac.html', 'support.html', 'privacy.html', 'terms.html',
  'what-is-write-it-down.html', 'is-my-writing-saved.html', 'delete-a-draft.html',
  'write-it-down-free-trial.html', 'write-it-down-mac-vs-web.html', 'write-it-down-price.html'];

const readShell = page => page.evaluate(() => {
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
  };
});

test('twelve shipped pages share one header, plate, canvas and body family', async ({ page }) => {
  const shells = [];
  for (const path of pages) {
    await page.goto(path);
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
  }
});

test('the document pages keep 17 px sans copy at the documented measure', async ({ page }) => {
  for (const path of documentPages) {
    await page.goto(path);
    const read = await page.evaluate(() => {
      const css = (selector, pseudo = null) => getComputedStyle(document.querySelector(selector), pseudo);
      const main = document.querySelector('main.doc');
      const paragraph = [...main.querySelectorAll('p')].find(p => p.textContent.trim().length > 80);
      const box = paragraph.getBoundingClientRect();
      return {
        font: css('main.doc p').fontFamily,
        size: css('main.doc p').fontSize,
        width: +box.width.toFixed(1),
        legacy: document.querySelectorAll('.legal, .door, .deck, .logotype, .foot, .stage').length,
        monoLinks: [...document.querySelectorAll('link[rel="stylesheet"]')].filter(link => /IBM\+Plex\+Mono/.test(link.href)).length,
        h1: css('main.doc h1').fontFamily,
      };
    });
    expect(read.font, `${path}: body copy is the system tool face`).toMatch(/system-ui/);
    expect(read.size, `${path}: body copy is 17 px`).toBe('17px');
    expect(read.width, `${path}: the measure stays near 62ch`).toBeLessThanOrEqual(62 * 17 * 0.66);
    expect(read.width, `${path}: the measure fills the available column`).toBeGreaterThan(300);
    expect(read.h1, `${path}: headings keep the serif`).toMatch(/Newsreader/);
    expect(read.legacy, `${path}: no retired shell class survives`).toBe(0);
    expect(read.monoLinks, `${path}: the retired mono face is not loaded`).toBe(0);
  }
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

test('the purchase page states one price string', async ({ page }) => {
  await page.goto('mac.html');
  await expect(page.locator('#price')).toHaveText('$4.99 once');
  await expect(page.getByRole('button', { name: 'Buy for $4.99 once', exact: true })).toBeVisible();
  const text = await page.locator('main').innerText();
  for (const stale of ['USD $4.99', 'BUY - $4.99', '$4.99 ONCE', 'USD 4.99'])
    expect(text, `stale price string "${stale}"`).not.toContain(stale);
});

test('the ghost pill keeps one text treatment on the buy path and the landing', async ({ page }) => {
  const decoration = async (path, selector) => {
    await page.goto(path);
    return page.locator(selector).evaluate(element => getComputedStyle(element).textDecorationLine);
  };
  const buy = await decoration('mac.html', '#buy a.btn-ghost');
  const landing = await decoration('index.html', '#mac a.btn-ghost');
  expect(buy, 'the buy card ghost pill').toBe('none');
  expect(landing, 'the landing Mac card ghost pill').toBe('none');
  expect(buy).toBe(landing);
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

test('the phone room nav keeps only the theme icon, and the Mac link moves into the exit row', async ({ page }, info) => {
  test.skip(info.project.use.viewport.width !== 390, 'phone layout');
  await page.goto('index.html#trial');
  const nav = page.locator('nav[aria-label="Main"]:visible');
  await expect(nav).toHaveCount(1);
  await expect(nav.locator('.brand')).toBeVisible();
  await expect(nav.locator('.theme-btn')).toBeVisible();
  await expect(nav.locator('.btn-quiet')).toBeHidden();
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
