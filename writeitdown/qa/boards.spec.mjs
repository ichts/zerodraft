// The per-state design boards (docs/design/*.dc.html, built from docs/design/canvas.json) agree with the system.
// Each board names regions by token; this drives the real screen into the board's state and fails when
//   - a region's computed colour differs from what its token resolves to on that element (the board is out of date),
//   - a listed string is not on screen in that state,
//   - the board itself does not load, or its swatches do not draw the token they name.
// Projects cover light and dark at 1440 and 390, so every board is checked in both themes at both widths.
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const canvas = JSON.parse(readFileSync(join(here, '../../docs/design/canvas.json'), 'utf8'));

const TYPED = 'The first line of a draft, written forward';
const SERVICE = 'https://licenses.writeitdown.app/api/v1';

// A paused fake clock makes every state reproducible: the warn ramp, the wipe and the kept screen land on the
// second, not on a race.
async function open(page, url) {
  await page.clock.install({ time: new Date('2026-10-25T12:00:00Z') });
  await page.clock.pauseAt(new Date('2026-10-25T12:00:01Z'));
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.goto(url);
}
const settle = async page => { await page.evaluate(() => document.fonts.ready); await page.clock.runFor(50); };
const enter = async page => {
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.clock.fastForward(400);
  await page.locator('#editor').focus();
};
const typed = async page => { await enter(page); await page.keyboard.insertText(TYPED); await page.clock.runFor(400); };
const after = ms => async page => { await typed(page); await page.clock.fastForward(ms); await settle(page); };
// The kept screen needs a writer who never stops for five seconds: one key every four seconds until the deadline.
const keptAtZero = async page => {
  await typed(page);
  for (let elapsed = 0; elapsed < 60000; elapsed += 4000) {
    await page.clock.fastForward(4000);
    await page.keyboard.insertText(' x');
  }
  await page.clock.fastForward(2000);
  await settle(page);
};

const DRIVERS = {
  landing: async (page) => { await settle(page); },
  'room-fresh': async page => { await enter(page); await settle(page); },
  'room-typing': async page => { await typed(page); await settle(page); },
  'room-warn': after(5300),
  'room-wiped': after(8300),
  'room-kept': keptAtZero,
  settled: settle,
  'buy-error': async page => {
    await page.route(`${SERVICE}/checkout`, route => route.fulfill({ status: 500, body: '{}' }));
    await settle(page);
    await page.locator('#buy-form button').click();
    await page.clock.runFor(200);
    await expect(page.locator('#checkout-status')).toHaveAttribute('role', 'alert');
  },
  'license-error': async page => { await page.clock.runFor(200); await expect(page.locator('#license-status')).not.toBeEmpty(); },
};

// A route has to be in place before the page loads for the states that talk to the service.
const BEFORE_LOAD = {
  'license-error': page => page.route(`${SERVICE}/license*`, route => route.fulfill({ status: 404, body: '{}' })),
};

const tokenColour = (page, selector, token) => page.evaluate(([sel, name]) => {
  const target = document.querySelector(sel);
  const el = target.matches('textarea, input') ? target.parentElement : target;
  const probe = document.createElement('i');
  probe.style.color = `var(${name})`;
  el.append(probe);
  const resolved = getComputedStyle(probe).color;
  probe.remove();
  return resolved;
}, [selector, token]);

const drawn = (page, selector, property) => page.evaluate(([sel, prop]) => getComputedStyle(document.querySelector(sel))[prop], [selector, property]);

for (const board of canvas.boards) {
  test(`${board.screen} - ${board.state}: every region draws its token, every string is on screen`, async ({ page }) => {
    await BEFORE_LOAD[board.drive]?.(page);
    await open(page, board.url);
    await DRIVERS[board.drive](page);
    for (const region of board.regions) {
      expect(await drawn(page, region.selector, region.property), `${region.name} (${region.selector} ${region.property})`)
        .toBe(await tokenColour(page, region.selector, region.token));
    }
    const flat = s => s.replace(/\s+/g, ' ').toLowerCase();
    const text = flat(await page.locator('body').innerText());
    for (const string of board.strings) expect(text, `string "${string}"`).toContain(flat(string));
  });

  test(`${board.screen} - ${board.state}: the board loads and its swatches draw their tokens`, async ({ page }) => {
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', m => m.type() === 'error' && errors.push(m.text()));
    await page.goto(`../docs/design/${board.file}.dc.html`);
    const rows = await page.evaluate(() => [...document.querySelectorAll('tr')].slice(1).map(tr => {
      const swatch = tr.querySelector('.swatch');
      const probe = document.createElement('i');
      probe.style.color = `var(${tr.children[3].textContent})`;
      document.body.append(probe);
      const resolved = getComputedStyle(probe).color;
      probe.remove();
      return { token: tr.children[3].textContent, drawn: getComputedStyle(swatch).backgroundColor, resolved };
    }));
    expect(rows.length).toBe(board.regions.length);
    for (const row of rows) expect(row.drawn, row.token).toBe(row.resolved);
    expect(errors).toEqual([]);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow, 'the board scrolls sideways').toBe(0);
    const split = await page.evaluate(() => [...document.querySelectorAll('td:nth-child(3) code')].filter(c => c.getClientRects().length > 1).map(c => c.textContent));
    expect(split, 'a property name breaks mid-word').toEqual([]);
  });
}
