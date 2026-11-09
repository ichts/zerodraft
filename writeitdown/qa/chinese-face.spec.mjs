import { readFileSync, statSync } from 'node:fs';
import { test, expect } from '@playwright/test';

// D-108: a character the room draws never changes face afterwards. Chinese used to arrive as 13 slices with
// `font-display:swap`, so the first character of every new slice was painted by the platform serif and repainted
// in Zhuque 150-360 ms later, mid-draft, in front of the writer. The room now serves one GB2312 file with
// `font-display:block` and asks for it as the door opens, so a glyph is either not drawn yet or drawn right.
//
// The browser checks below hold the face request open, which is the exact window the old arrangement got wrong: it
// painted the fallback at once and repainted it when the slice landed. A held request makes the window as wide as
// the test needs instead of racing a real network; a font request blocks the load event, so the page is opened to
// DOMContentLoaded, which is already after room.js has routed and asked for the face.
const cjkCss = readFileSync(new URL('../fonts-cjk.css', import.meta.url), 'utf8');
const siteCss = readFileSync(new URL('../site.css', import.meta.url), 'utf8');
const FACE = '**/fonts/zhuque-fangsong*.woff2';

const holdFace = async page => {
  const held = [];
  let release;
  const opened = new Promise(resolve => { release = resolve; });
  await page.route(FACE, async route => {
    held.push(route.request().url());
    await opened;
    await route.continue();
  });
  return { held, release };
};

test('the Chinese face is one file that blocks instead of swapping', async () => {
  const faces = [...cjkCss.matchAll(/@font-face\{[^}]*Zhuque Fangsong[^}]*\}/g)].map(match => match[0]);
  expect(faces).toHaveLength(1);
  expect(faces[0]).toMatch(/font-display:block/);
  expect(faces[0]).not.toMatch(/font-display:swap/);
  const file = faces[0].match(/url\(fonts\/([\w.-]+\.woff2)\)/)[1];
  // GB2312 is 6763 hanzi; one file that carries them all is over 2 MB, a slice of them is not.
  expect(statSync(new URL(`../fonts/${file}`, import.meta.url)).size).toBeGreaterThan(2_000_000);
});

test('composition text carries no face of its own', async () => {
  const rules = [...siteCss.matchAll(/\.editor-ink \.composing[^{]*\{([^}]*)\}/g)].map(match => match[1]);
  expect(rules.length).toBeGreaterThan(0);
  for (const body of rules) {
    expect(body).not.toMatch(/(^|;)\s*(font|font-family|font-size|font-weight|font-style|line-height|letter-spacing)\s*:/);
  }
});

test('the room asks for the face when its door opens, before any character needs it', async ({ page }) => {
  test.setTimeout(90_000);
  const { held } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#room')).toBeVisible();
  await expect.poll(() => held.length).toBe(1);
  const faces = await page.evaluate(() => [...document.fonts]
    .filter(face => face.family.includes('Zhuque'))
    .map(face => ({ status: face.status, range: face.unicodeRange })));
  expect(faces).toHaveLength(1);
  expect(['loading', 'loaded']).toContain(faces[0].status);
});

test('a drawn character is never repainted in another face', async ({ page }) => {
  test.setTimeout(90_000);
  const { release } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#room')).toBeVisible();
  // The caret is drawn inside the same box, so the measurement hides it: a blinking 2 px line would read as the
  // glyph changing.
  await page.addStyleTag({ content: '#editor{caret-color:transparent}' });
  const box = await page.locator('#editor-ink').boundingBox();
  // CDP rather than locator.screenshot(): a Playwright element screenshot waits for document.fonts.ready, and the
  // whole point of this test is to look at the room while a face is still in flight.
  const client = await page.context().newCDPSession(page);
  const shot = async () => {
    const { data } = await client.send('Page.captureScreenshot', {
      format: 'png', fromSurface: true,
      clip: { x: box.x, y: box.y, width: box.width, height: box.height, scale: 1 },
    });
    return data;
  };
  // The sheet and its grain settle on their own schedule; the measurement starts once two frames agree, so a late
  // texture paint cannot be mistaken for the character.
  const settled = async () => {
    let previous = await shot();
    for (let attempt = 0; attempt < 80; attempt += 1) {
      await page.waitForTimeout(60);
      const next = await shot();
      if (next === previous) return next;
      previous = next;
    }
    return previous;
  };
  const empty = await settled();
  await page.locator('#editor').focus();
  await page.keyboard.insertText('我');
  await expect(page.locator('#editor')).toHaveValue('我');
  // The face is still in flight: the room shows the paper the writer typed into, not a stand-in glyph.
  expect(await shot()).toBe(empty);
  release();
  await expect.poll(shot).not.toBe(empty);
  // The line arrives with the room's own entrance, so the clock starts once it stops moving; from that frame on,
  // nothing about the glyph changes again.
  const drawn = await settled();
  const later = [];
  for (let index = 0; index < 5; index += 1) {
    await page.waitForTimeout(80);
    later.push(await shot());
  }
  expect(new Set([drawn, ...later]).size).toBe(1);
});
