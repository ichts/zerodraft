// D-090: glyph outlines are never filtered, displaced or stroked, and the room's footer is one type style.
//
// Ink: a 2 px SVG feDisplacementMap over fractal noise sat on the writing layer (D-056) and bent every
// glyph outline, at 1x and 2x alike. Nothing that carries words may carry a filter, a text stroke or a
// displacement filter again, in the home demo, the trial room, the failure head or the kept text.
// Footer: the left label, the right count and the phone's Mac link read as one voice, so a state that
// changes one of them fails here with the property that moved.
import { test, expect } from '@playwright/test';

async function enter(page) {
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').click();
  await expect(page.locator('#editor')).toBeFocused();
}

// Every layer that carries the writer's words or the room's own headings. The landing's `.hand` accent is
// marketing type, not a writing layer.
const WORDS = '.home .script, .home .prev-line, #editor, #editor-ink, #editor-ink *, #kept-text, #kept-text *, .room-top h1, .kept-head h1';

const FOOTER_PROPS = ['fontFamily', 'fontSize', 'fontWeight', 'letterSpacing', 'lineHeight', 'textTransform', 'fontVariantNumeric', 'color'];

const footer = page => page.evaluate(props => {
  const read = el => {
    const style = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return { text: el.textContent.trim(), style: Object.fromEntries(props.map(p => [p, style[p]])), centre: rect.top + rect.height / 2 };
  };
  return { left: read(document.querySelector('#exit')), right: read(document.querySelector('#room-count')) };
}, FOOTER_PROPS);

test('no element that carries words is filtered, displaced or stroked', async ({ page }) => {
  await page.goto('./');
  expect(await page.evaluate(() => document.querySelectorAll('feDisplacementMap, feTurbulence').length)).toBe(0);
  const offenders = () => page.evaluate(selector => [...document.querySelectorAll(selector)].flatMap(el => {
    const style = getComputedStyle(el);
    const stroke = parseFloat(style.webkitTextStrokeWidth || '0');
    return style.filter !== 'none' || stroke > 0 ? [`${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''}.${el.className}: filter=${style.filter} stroke=${stroke}`] : [];
  }), WORDS);
  // The home demo's writing layer, mid-loop.
  await page.waitForFunction(() => document.querySelector('.home .script')?.textContent.trim().length > 4);
  expect(await offenders()).toEqual([]);
  await enter(page);
  await page.keyboard.type('Just pretending that I knew what to write.\nA second line.');
  expect(await offenders()).toEqual([]);
});

test('the exit control has a quiet hover, ink focus and a 44 px target without moving its label', async ({ page }) => {
  await enter(page);
  const exit = page.getByRole('button', { name: 'Exit', exact: true });
  await expect(exit).toBeVisible();
  const before = await exit.boundingBox();
  expect(before.height).toBeGreaterThanOrEqual(44);
  const quiet = await exit.evaluate(el => getComputedStyle(el).color);
  await exit.hover();
  const ink = await page.locator('#editor').evaluate(el => getComputedStyle(el).caretColor);
  await expect(exit).toHaveCSS('color', ink);
  expect(await exit.evaluate(el => getComputedStyle(el).color)).not.toBe(quiet);
  expect(await exit.boundingBox()).toEqual(before);
  await page.mouse.move(0, 0);
  await page.locator('#editor').focus();
  await page.keyboard.press('Tab');
  await expect(exit).toBeFocused();
  await expect(exit).toHaveCSS('outline-style', 'solid');
  await expect(exit).toHaveCSS('outline-width', '2px');
  await expect(exit).toHaveCSS('outline-color', ink);
  expect(await exit.boundingBox()).toEqual(before);
});

test('click and Escape share the same two-act exit and typing cancels either', async ({ page }) => {
  await enter(page);
  await page.keyboard.type('Words to delete');
  const exit = page.getByRole('button', { name: 'Exit', exact: true });
  await exit.click();
  await expect(page.locator('#exit-hint')).toContainText('again');
  await expect(page.locator('#room')).toBeVisible();
  await page.keyboard.type('x');
  await expect(page.locator('#exit-hint')).toBeEmpty();
  await page.keyboard.press('Escape');
  await expect(page.locator('#exit-hint')).toContainText('again');
  await exit.click();
  await expect(page.locator('#room')).toBeHidden();
  await expect(page.locator('#editor')).toHaveValue('');
  await expect(page).not.toHaveURL(/#trial/);
});

test('the exit label and the count compute identical font metrics on one baseline', async ({ page }) => {
  await enter(page);
  const empty = await footer(page);
  expect(empty.right.text).toBe('Type to begin');
  expect(empty.left.text).toMatch(/^(Esc to exit|Exit)$/);
  expect(empty.left.style).toEqual(empty.right.style);
  expect(Math.abs(empty.left.centre - empty.right.centre)).toBeLessThan(0.5);
  await page.keyboard.type('one two three');
  const typing = await footer(page);
  expect(typing.right.text).toBe('3 words');
  expect(typing.left.style).toEqual(typing.right.style);
  expect(Math.abs(typing.left.centre - typing.right.centre)).toBeLessThan(0.5);
});
