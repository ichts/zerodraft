// The shared components (StatusDot, Skeleton, Field, Select) behave the way a visitor meets them.
// Each test names what the visitor would notice when it breaks:
//   Field/Select: tapping the label reaches the control, the control is a 44 px target at 16 px so a phone does
//     not zoom, an invalid control is told apart from a valid one.
//   StatusDot: a state is readable without colour (the fill differs), never only a hue.
//   Skeleton: a held place never moves (the wall stays blank), in either motion preference.
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
  expect(bad.borderTopColor).toBe(await token(page, '--red'));
  expect(bad.borderTopColor).not.toBe(ok.borderTopColor);
  expect((await style(page, '#kit-f-bad-note', ['color'])).color).toBe(await token(page, '--red'));
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
