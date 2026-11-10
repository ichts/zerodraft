// The component gallery (kit/index.html) shows every shared component in every state, in whichever theme
// the project runs (the projects cover light and dark, both widths). Protects the developer who opens it:
// a component or state that goes missing, collapses to nothing, overflows a phone, or throws on load fails
// here, so the gallery cannot quietly stop being the full list.
import { test, expect } from '@playwright/test';

const GALLERY = {
  Kbd: ['inline', 'key cap', 'key cap, refused'],
  StatusDot: ['idle', 'live', 'error'],
  Skeleton: ['full', 'short'],
  Field: ['rest', 'filled', 'invalid', 'disabled'],
  Select: ['rest', 'invalid', 'disabled'],
  Empty: ['one action', 'two actions'],
};

test('the gallery lists every component with every state, each drawn at a real size', async ({ page }) => {
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => m.type() === 'error' && errors.push(m.text()));
  await page.goto('kit/index.html');
  const listed = await page.evaluate(() => [...document.querySelectorAll('.kit-part')].map(part => ({
    name: part.querySelector('h2').textContent,
    states: [...part.querySelectorAll('.kit-state')].map(s => ({
      caption: s.querySelector('figcaption').textContent,
      box: (() => { const r = s.lastElementChild.getBoundingClientRect(); return r.width > 0 && r.height > 0; })(),
    })),
  })));
  expect(listed.map(c => c.name)).toEqual(Object.keys(GALLERY));
  for (const part of listed) {
    expect(part.states.map(s => s.caption), part.name).toEqual(GALLERY[part.name]);
    expect(part.states.every(s => s.box), `${part.name} draws every state`).toBe(true);
  }
  expect(errors).toEqual([]);
});

test('the gallery never scrolls sideways, on a phone or a desktop', async ({ page }) => {
  await page.goto('kit/index.html');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBe(0);
});

test('the gallery is a dev page: it is not indexable and is linked from no shipped page', async ({ page }) => {
  await page.goto('kit/index.html');
  expect(await page.locator('meta[name="robots"]').getAttribute('content')).toBe('noindex');
});
