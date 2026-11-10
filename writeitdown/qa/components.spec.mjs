// The six shared components (Empty, StatusDot, Kbd, Skeleton, Field, Select) behave the way a visitor meets them.
// Each test names what the visitor would notice when it breaks:
//   Field/Select: tapping the label reaches the control, the control is a 44 px target at 16 px so a phone does
//     not zoom, an invalid control is told apart from a valid one.
//   StatusDot: a state is readable without colour (the fill differs), never only a hue.
//   Skeleton: a held place never moves (the wall stays blank), in either motion preference.
//   Kbd: the landing's key caps are real <kbd> elements and keep their illustration size.
//   Empty: one centred sentence with its actions, inside the reading measure.
// The markup is injected into a shipped page so the components are measured against the real stylesheet.
import { test, expect } from '@playwright/test';

const FIXTURE = `
<div id="fx">
  <div class="field" id="f1"><label class="field-label" for="f1-in">Label</label><input class="field-input" id="f1-in" placeholder="Hint" aria-describedby="f1-note"><p class="field-note" id="f1-note">Note</p></div>
  <div class="field" id="f2" data-state="error"><label class="field-label" for="f2-in">Label</label><input class="field-input" id="f2-in" aria-invalid="true" aria-describedby="f2-note"><p class="field-note" id="f2-note">Note</p></div>
  <div class="field" id="f3"><label class="field-label" for="s1">Label</label><span class="select"><select class="field-input" id="s1"><option>One</option><option>Two</option></select></span></div>
  <p><span class="status"><i class="status-dot" data-state="idle"></i>Idle</span> <span class="status"><i class="status-dot" data-state="live"></i>Live</span> <span class="status"><i class="status-dot" data-state="error"></i>Error</span></p>
  <div aria-busy="true"><span class="skeleton" id="sk1" aria-hidden="true"></span><span class="skeleton" id="sk2" data-size="short" aria-hidden="true"></span></div>
  <p>Press <kbd class="kbd" id="kb">Esc</kbd> to leave.</p>
  <div class="empty" id="em"><p class="empty-title">Page not found</p><div class="empty-actions"><a class="btn btn-ghost" href="/">Go to the home page</a></div></div>
</div>`;

test.beforeEach(async ({ page }) => {
  await page.goto('support.html');
  await page.evaluate(html => document.querySelector('main').insertAdjacentHTML('beforeend', html), FIXTURE);
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
  await page.locator('label[for="f1-in"]').click();
  await expect(page.locator('#f1-in')).toBeFocused();
  const ok = await style(page, '#f1-in', ['height', 'fontSize', 'borderTopColor', 'borderTopLeftRadius']);
  expect(ok.height).toBe('44px');
  expect(ok.fontSize).toBe('16px');
  expect(ok.borderTopLeftRadius).toBe('8px');
  const bad = await style(page, '#f2-in', ['borderTopColor']);
  expect(bad.borderTopColor).toBe(await token(page, '--red-text'));
  expect(bad.borderTopColor).not.toBe(ok.borderTopColor);
  expect((await style(page, '#f2 .field-note', ['color'])).color).toBe(await token(page, '--red-text'));
  expect(await page.locator('#f2-in').getAttribute('aria-describedby')).toBe(await page.locator('#f2 .field-note').getAttribute('id'));
});

test('a select is the native control with the same 44 px target, drawn without the platform chrome and with a chevron', async ({ page }) => {
  await page.locator('label[for="s1"]').click();
  await expect(page.locator('#s1')).toBeFocused();
  const s = await style(page, '#s1', ['height', 'appearance']);
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
    for (const id of ['#sk1', '#sk2']) {
      const s = await style(page, id, ['animationName', 'transitionDuration']);
      expect(s.animationName).toBe('none');
      expect(s.transitionDuration).toBe('0s');
    }
    const [full, short] = await page.evaluate(() => ['#sk1', '#sk2'].map(i => document.querySelector(i).getBoundingClientRect().width));
    expect(short).toBeCloseTo(full * 0.4, 0);
  });
}

test('a named key is a kbd element with its own small cap', async ({ page }) => {
  const k = await style(page, '#kb', ['display', 'height', 'fontSize', 'fontFamily']);
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
  const e = await style(page, '#em', ['textAlign', 'display', 'maxWidth']);
  expect(e).toEqual({ textAlign: 'center', display: 'flex', maxWidth: '720px' });
  const title = await style(page, '.empty-title', ['fontFamily', 'fontSize']);
  expect(title.fontFamily).toMatch(/Newsreader/);
  const centred = await page.evaluate(() => {
    const box = document.querySelector('#em .btn').getBoundingClientRect();
    return Math.abs(box.left + box.width / 2 - innerWidth / 2);
  });
  expect(centred).toBeLessThan(2);
});
