import { test, expect } from '@playwright/test';

// D-109: the room's Chinese has two hard requirements at once, and they constrain each other.
//   1. A character the room draws is on the sheet at once. `font-display:block` held text invisible while 2,589,548 B
//      was in flight (Chrome: up to 3 s), so on a slow link a writer who clicked and typed at once stared at an empty
//      sheet. `font-display:swap` never holds text back.
//   2. A character the room draws never changes face afterwards. Chinese used to arrive as 13 slices with `swap`,
//      so the first character of every new slice was painted by the platform serif and repainted in Zhuque
//      150-360 ms later, mid-draft, in front of the writer.
// `font-display:optional` satisfies neither the product nor the browser: Chrome abandons an optional face for the
// whole document at the first paint without it, and keeps the platform face even when the file has been resident for
// seconds before the first Chinese character (measured here, and the reason the room decides instead). So the room
// fixes the face at a draft's first Chinese character - Zhuque if those bytes are already resident, the platform serif
// if they are not - and never revisits it until the sheet is empty again. The tests below drive that decision from
// either side, and from the draft after the one that had to accept the platform serif.
//
// A third requirement keeps the 2,589,548 B off the landing: a visitor who never touches a trial link fetches none of
// it, and pointer, focus or touch on that link starts the fetch early, at low priority.
//
// The browser checks hold the face request open, which is the window the earlier arrangements got wrong: swap painted
// the fallback and repainted it, block painted nothing at all. A held request makes the window as wide as the test
// needs instead of racing a real network; a font request blocks the load event, so the page is opened to
// DOMContentLoaded, which is already after room.js has routed and asked for the face.
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

// What Chrome actually drew the text with, not what the stylesheet asked for.
const platformFonts = async (page, selector) => {
  const client = await page.context().newCDPSession(page);
  await client.send('DOM.enable');
  await client.send('CSS.enable');
  const { root } = await client.send('DOM.getDocument');
  const { nodeId } = await client.send('DOM.querySelector', { nodeId: root.nodeId, selector });
  const { fonts } = await client.send('CSS.getPlatformFontsForNode', { nodeId });
  return fonts.map(font => font.familyName);
};

const writingStack = page => page.locator('#editor').evaluate(editor => getComputedStyle(editor).fontFamily);

test('one draft keeps one Chinese face from its first character to its last', async ({ page }) => {
  test.setTimeout(90_000);
  // The promise a writer can see, measured on what Chrome drew with rather than on the stylesheet. Chinese used
  // to arrive as 13 slices with `swap`, so a character whose slice was not resident was painted by the platform
  // serif and repainted in Zhuque 150-360 ms later, while it sat on screen. The room decides the draft's face at
  // its first Chinese character and keeps it until the sheet is empty, so the file landing - and a later
  // character typed while it is resident - must leave the draft on the face it started with.
  const { release } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#room')).toBeVisible();
  await page.locator('#editor').focus();
  await page.keyboard.insertText('我');
  await expect(page.locator('#editor')).toHaveValue('我');
  await page.waitForTimeout(250);
  const first = await platformFonts(page, '#editor-ink span');
  expect(first.filter(family => /^Zhuque Fangsong/.test(family)), `the held draft drew in Zhuque: ${first}`)
    .toHaveLength(0);
  // The file lands now, which is the window the slices repainted in, and a second character arrives while it is
  // resident. Neither may pull this draft onto the webfont.
  release();
  await page.evaluate(() => document.fonts.ready);
  await page.keyboard.insertText('写');
  await expect(page.locator('#editor')).toHaveValue('我写');
  await page.waitForTimeout(250);
  expect(await page.locator('#room').getAttribute('data-phase'), 'the measurement ran into the silence warning')
    .toMatch(/^(typing|rest)$/);
  const both = await platformFonts(page, '#editor-ink span');
  expect(both, `the draft changed face when the file landed: ${first} then ${both}`).toEqual(first);
  expect(both.filter(family => /^Zhuque Fangsong/.test(family)), `one draft drew in two faces: ${both}`).toHaveLength(0);
  // The room's own record of the decision, read after the rendered evidence.
  expect(await page.locator('#room').getAttribute('data-cjk-face'), 'the draft did not freeze to the face it had')
    .toBe('platform');
  expect(await writingStack(page), 'a frozen draft names the webfont it did not draw in').not.toMatch(/Zhuque/);
});

test('composition text is drawn in the draft\'s own face and stays in it when committed', async ({ page }) => {
  test.setTimeout(90_000);
  // A composing run is part of the draft's line: the underlined run the writer watches while choosing a character
  // must be drawn by the same face, at the same size and the same spacing as the character it commits into. A face
  // or a size declared only for the composing span would show up as a jump at the moment of commit.
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').hover();
  await page.waitForFunction(() => [...document.fonts]
    .some(face => face.family.includes('Zhuque') && face.status === 'loaded'), null, { timeout: 60_000 });
  await page.locator('#landing .cta a[href="#trial"]').click();
  await expect(page.locator('#room')).toBeVisible();
  await page.waitForFunction(() => document.activeElement?.id === 'editor');
  await page.keyboard.insertText('Before. ');
  const session = await page.context().newCDPSession(page);
  await session.send('Input.imeSetComposition', { text: '我', selectionStart: 1, selectionEnd: 1 });
  const composing = page.locator('#editor-ink .composing');
  await expect(composing, 'the composing run is not on the ink layer').toHaveCount(1);
  const own = await composing.evaluate(span => {
    const style = getComputedStyle(span), draft = getComputedStyle(document.querySelector('#editor'));
    return [style.fontFamily, style.fontSize, style.fontWeight, style.lineHeight, style.letterSpacing]
      .map((value, index) => value === [draft.fontFamily, draft.fontSize, draft.fontWeight, draft.lineHeight,
        draft.letterSpacing][index]);
  });
  expect(own, 'the composing run carries a face or a size of its own').toEqual([true, true, true, true, true]);
  const chinese = fonts => fonts.filter(family => /^Zhuque Fangsong/.test(family));
  const composingFonts = await platformFonts(page, '#editor-ink .composing');
  expect(chinese(composingFonts), `the composing run drew in ${composingFonts}`).toHaveLength(1);
  await session.send('Input.insertText', { text: '我' });
  await expect(page.locator('#editor')).toHaveValue('Before. 我');
  await expect(page.locator('#editor-ink .composing'), 'a commit leaves nothing underlined').toHaveCount(0);
  await page.waitForTimeout(120);
  // The committed span also holds the Latin draft, which is Newsreader by design; the Chinese glyph's own face is
  // what must not change.
  const committedFonts = await platformFonts(page, '#editor-ink span');
  expect(chinese(committedFonts), `the character changed face when it was committed: ${committedFonts}`)
    .toEqual(chinese(composingFonts));
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

test('a character typed while the face is in flight is painted at once, and keeps that face', async ({ page }) => {
  test.setTimeout(90_000);
  const { release } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#room')).toBeVisible();
  // The caret is drawn inside the same box, so the measurement hides it: a blinking 2 px line would read as the
  // glyph appearing.
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
  // The request is still held, so the face cannot arrive. The character must be on the sheet anyway: no block
  // period, no wait for 2.5 MB.
  await page.waitForTimeout(250);
  const painted = await shot();
  expect(painted, 'the typed character stays invisible while the face is in flight').not.toBe(empty);
  // The room froze this page load to the platform serif, which is the only face it will draw Chinese in from here.
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('platform');
  expect(await writingStack(page), 'the frozen draft still names the webfont').not.toMatch(/Zhuque/);
  // The face now lands. A character already on the sheet must not change face. The window is kept short because the
  // room starts its silence warning five seconds after the last key, and that wash would read as a repaint.
  release();
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(200);
  const drawn = await shot();
  const later = [];
  for (let index = 0; index < 4; index += 1) {
    await page.waitForTimeout(60);
    later.push(await shot());
  }
  expect(await page.locator('#room').getAttribute('data-phase'), 'the measurement ran into the silence warning').toMatch(/^(typing|rest)$/);
  expect(new Set([painted, drawn, ...later]).size, 'the character changed face after it was drawn').toBe(1);
});

test('a room that finds the face resident draws Chinese in Zhuque and keeps it', async ({ page }) => {
  test.setTimeout(90_000);
  // The intended path: intent on a trial link prefetches the file while the visitor reads, so the face is resident
  // before the first Chinese character and the room freezes to it.
  await page.goto('./');
  await page.locator('#landing .cta a[href="#trial"]').hover();
  await page.waitForFunction(() => [...document.fonts]
    .some(face => face.family.includes('Zhuque') && face.status === 'loaded'), null, { timeout: 60_000 });
  await page.locator('#landing .cta a[href="#trial"]').click();
  // The door opens on the click's own hash change, one task later; the room focuses the editor itself.
  await expect(page.locator('#room')).toBeVisible();
  await page.waitForFunction(() => document.activeElement?.id === 'editor');
  await page.keyboard.insertText('我写中文');
  await expect(page.locator('#editor')).toHaveValue('我写中文');
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('webfont');
  expect(await writingStack(page)).toMatch(/Zhuque Fangsong/);
  // The paint agrees with the stack: Chrome records the platform font with the frame.
  const client = await page.context().newCDPSession(page);
  await client.send('DOM.enable');
  await client.send('CSS.enable');
  const { root } = await client.send('DOM.getDocument');
  const { nodeId } = await client.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#editor-ink span' });
  const { fonts } = await client.send('CSS.getPlatformFontsForNode', { nodeId });
  const platform = fonts.map(font => font.familyName);
  expect(platform.filter(family => /^Zhuque Fangsong/.test(family)).length, `Chinese draw in Zhuque Fangsong, got ${platform}`).toBe(1);
});

test('the draft after a wipe draws the face that has landed by then', async ({ page }) => {
  test.setTimeout(120_000);
  const { release } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#room')).toBeVisible();
  await page.locator('#editor').focus();
  // The first draft has to accept the platform serif: the file is still held.
  await page.keyboard.insertText('我');
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('platform');
  release();
  await page.waitForFunction(() => [...document.fonts]
    .some(face => face.family.includes('Zhuque') && face.status === 'loaded'), null, { timeout: 60_000 });
  // Now the silence deadline has to take that draft, which is what makes the next sheet empty.
  await page.waitForFunction(() => document.getElementById('room').dataset.phase === 'wipe', null, { timeout: 20_000 });
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBeNull();
  await page.locator('#editor').focus();
  await page.keyboard.insertText('你');
  await page.waitForTimeout(300);
  // Arriving early is only worth its bytes if a later draft uses what arrived.
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('webfont');
  expect(await writingStack(page)).toMatch(/Zhuque Fangsong/);
});

test('a visitor who never touches the trial fetches no Chinese, and intent starts it early at low priority', async ({ page }) => {
  test.setTimeout(90_000);
  const client = await page.context().newCDPSession(page);
  await client.send('Network.enable');
  const requests = [];
  client.on('Network.requestWillBeSent', event => {
    if (/fonts\/zhuque-fangsong[\w.-]*\.woff2/.test(event.request.url)) requests.push(event.request.initialPriority);
  });
  // The face is not requested on arrival: the landing draws no Chinese, and 2.5 MB is not a page weight to pay for
  // a bounce.
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(600);
  expect(requests, 'a landing with no interaction requested the Chinese face').toHaveLength(0);
  // Intent on the door is the trigger, and it must not compete with the landing's own paint: the request is low
  // priority, started once the frame after the intent has gone idle.
  await page.locator('#landing .cta a[href="#trial"]').hover();
  await expect.poll(() => requests.length, { timeout: 20_000 }).toBeGreaterThan(0);
  expect(requests[0]).toBe('Low');
});
