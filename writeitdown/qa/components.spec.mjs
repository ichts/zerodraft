// The six shared components (Empty, StatusDot, Kbd, Skeleton, Field, Select) behave the way a visitor meets them.
// Each test names what the visitor would notice when it breaks:
//   Field/Select: tapping the label reaches the control, the control is a 44 px target at 16 px so a phone does
//     not zoom, an invalid control is told apart from a valid one.
//   StatusDot: a state is readable without colour (the fill differs), never only a hue.
//   Skeleton: a held place never moves (the wall stays blank), in either motion preference.
//   Kbd: the landing's key caps are real <kbd> elements and keep their illustration size.
//   Empty: one centred sentence with its actions, inside the reading measure.
// The markup is the gallery's own (kit/index.html), so the page a developer looks at is the page that is measured.
import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.goto('kit/index.html');
});

const style = (page, selector, props) => page.evaluate(([sel, list]) => {
  const s = getComputedStyle(document.querySelector(sel));
  return Object.fromEntries(list.map(p => [p, s[p]]));
}, [selector, props]);

const token = (page, name) => page.evaluate(n => {
  const probe = document.createElement('i');
  probe.style.color = `var(${n})`;
  document.querySelector('main').append(probe);
  const rgb = getComputedStyle(probe).color;
  probe.remove();
  return rgb;
}, name);

test('a field is reached through its label, is a 44 px target at 16 px, and an invalid one is told apart', async ({ page }) => {
  await page.locator('label[for="kit-f-rest"]').click();
  await expect(page.locator('#kit-f-rest')).toBeFocused();
  const ok = await style(page, '#kit-f-rest', ['height', 'fontSize', 'borderTopColor', 'borderTopLeftRadius']);
  expect(ok.height).toBe('44px');
  expect(ok.fontSize).toBe('16px');
  expect(ok.borderTopLeftRadius).toBe('8px');
  const bad = await style(page, '#kit-f-bad', ['borderTopColor']);
  expect(bad.borderTopColor).toBe(await token(page, '--red-text'));
  expect(bad.borderTopColor).not.toBe(ok.borderTopColor);
  expect((await style(page, '#kit-f-bad-note', ['color'])).color).toBe(await token(page, '--red-text'));
  expect(await page.locator('#kit-f-bad').getAttribute('aria-describedby')).toBe(await page.locator('#kit-f-bad-note').getAttribute('id'));
});

test('a select is the native control with the same 44 px target, drawn without the platform chrome and with a chevron', async ({ page }) => {
  await page.locator('label[for="kit-s-rest"]').click();
  await expect(page.locator('#kit-s-rest')).toBeFocused();
  const s = await style(page, '#kit-s-rest', ['height', 'appearance']);
  expect(s.height).toBe('44px');
  expect(s.appearance).toBe('none');
  const chevron = await page.evaluate(() => { const c = getComputedStyle(document.querySelector('.select'), '::after'); return { content: c.content, width: c.width }; });
  expect(chevron).toEqual({ content: '""', width: '7px' });
});

test('a status dot differs by fill and not only by colour', async ({ page }) => {
  const dots = await page.evaluate(() => [...document.querySelectorAll('.status-dot')].map(d => {
    const s = getComputedStyle(d);
    return { state: d.dataset.state, bg: s.backgroundColor, w: s.width, h: s.height };
  }));
  expect(dots.map(d => d.state)).toEqual(['idle', 'live', 'error']);
  expect(dots.every(d => d.w === '8px' && d.h === '8px')).toBe(true);
  expect(dots[0].bg).toBe('rgba(0, 0, 0, 0)');
  expect(dots[1].bg).toBe(await token(page, '--ink'));
  expect(dots[2].bg).toBe(await token(page, '--red'));
});

for (const reducedMotion of ['no-preference', 'reduce']) {
  test(`a skeleton never animates (${reducedMotion})`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion });
    for (const id of ['.skeleton:not([data-size])', '.skeleton[data-size="short"]']) {
      const s = await style(page, id, ['animationName', 'transitionDuration']);
      expect(s.animationName).toBe('none');
      expect(s.transitionDuration).toBe('0s');
    }
    const [full, short] = await page.evaluate(() => ['.skeleton:not([data-size])', '.skeleton[data-size="short"]'].map(i => document.querySelector(i).getBoundingClientRect().width));
    expect(short).toBeCloseTo(full * 0.4, 0);
  });
}

test('a named key is a kbd element with its own small cap', async ({ page }) => {
  const k = await style(page, '.kbd:not(.key)', ['display', 'height', 'fontSize', 'fontFamily']);
  expect(k.display).toBe('inline-flex');
  expect(k.fontSize).toBe('13px');
  expect(parseFloat(k.height)).toBeCloseTo(13 * 1.8, 1);
  expect(k.fontFamily).not.toMatch(/mono/i);
});

test('the landing key caps are kbd elements at the illustration size', async ({ page }) => {
  await page.goto('./');
  const caps = await page.evaluate(() => [...document.querySelectorAll('#how .key')].map(k => {
    const r = k.getBoundingClientRect();
    return { tag: k.tagName, h: Math.round(r.height), w: Math.round(r.width) };
  }));
  expect(caps.length).toBe(3);
  expect(caps.every(c => c.tag === 'KBD' && c.h === 50 && c.w >= 58)).toBe(true);
});

test('an empty state is one centred sentence with its action inside the reading measure', async ({ page }) => {
  const e = await style(page, '.empty', ['textAlign', 'display', 'maxWidth']);
  expect(e).toEqual({ textAlign: 'center', display: 'flex', maxWidth: '720px' });
  const title = await style(page, '.empty-title', ['fontFamily', 'fontSize']);
  expect(title.fontFamily).toMatch(/Newsreader/);
  const centred = await page.evaluate(() => {
    const box = document.querySelector('.empty .btn').getBoundingClientRect();
    const empty = document.querySelector('.empty').getBoundingClientRect();
    return Math.abs(box.left + box.width / 2 - (empty.left + empty.width / 2));
  });
  expect(centred).toBeLessThan(2);
});
