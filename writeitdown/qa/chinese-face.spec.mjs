import { test, expect } from '@playwright/test';

// D-109, with D-119's face: the room's Chinese has two hard requirements at once, and they constrain each other.
//   1. A character the room draws is on the sheet at once. `font-display:block` held text invisible while the file
//      was in flight (Chrome: up to 3 s), so on a slow link a writer who typed at once stared at an empty sheet.
//      `font-display:swap` never holds text back.
//   2. A character the room draws never changes face afterwards. Chinese once arrived in slices with `swap`, so the
//      first character of every new slice was painted by the platform face and repainted 150-360 ms later, mid-draft.
// So the room fixes the face at a draft's first Chinese character - Resource Han Rounded if those bytes are already
// resident, the platform face if they are not - and never revisits it until the sheet is empty again.
//
// D-119 moves the request itself: the 1,173,524 B file is asked for only when Chinese input begins - the first
// committed Chinese character, or a composition whose text holds one. A visitor who opens the room and writes English,
// Greek or accented Latin never fetches it; neither does the landing, nor intent on the door.
//
// The browser checks hold the face request open, which is the window the earlier arrangements got wrong: swap painted
// the fallback and repainted it, block painted nothing at all. A held request makes the window as wide as the test
// needs instead of racing a real network; a font request blocks the load event, so the page is opened to
// DOMContentLoaded.
const FACE = '**/fonts/resource-han-rounded*.woff2';
const RHR = /^Resource Han Rounded/;

/** Make the face resident the way an earlier Chinese draft on this page would have: ask for it and wait. */
const faceResident = page => page.evaluate(() => document.fonts.load('28px "Resource Han Rounded"', '\u6211'));

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
  // to arrive in slices with `swap`, so a character whose slice was not resident was painted by the platform face
  // and repainted 150-360 ms later, while it sat on screen. The room decides the draft's face at
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
  expect(first.filter(family => RHR.test(family)), `the held draft drew in the webfont: ${first}`)
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
  expect(both.filter(family => RHR.test(family)), `one draft drew in two faces: ${both}`).toHaveLength(0);
  // The room's own record of the decision, read after the rendered evidence.
  expect(await page.locator('#room').getAttribute('data-cjk-face'), 'the draft did not freeze to the face it had')
    .toBe('platform');
  expect(await writingStack(page), 'a frozen draft names the webfont it did not draw in').not.toMatch(/Resource Han Rounded/);
});

test('composition text is drawn in the draft\'s own face and stays in it when committed', async ({ page }) => {
  test.setTimeout(90_000);
  // A composing run is part of the draft's line: the underlined run the writer watches while choosing a character
  // must be drawn by the same face, at the same size and the same spacing as the character it commits into. A face
  // or a size declared only for the composing span would show up as a jump at the moment of commit.
  await page.goto('./');
  await faceResident(page);
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
  const chinese = fonts => fonts.filter(family => RHR.test(family));
  const composingFonts = await platformFonts(page, '#editor-ink .composing');
  expect(chinese(composingFonts), `the composing run drew in ${composingFonts}`).toHaveLength(1);
  await session.send('Input.insertText', { text: '我' });
  await expect(page.locator('#editor')).toHaveValue('Before. 我');
  await expect(page.locator('#editor-ink .composing'), 'a commit leaves nothing underlined').toHaveCount(0);
  await page.waitForTimeout(120);
  // The committed span also holds the Latin draft, which is Allo by design; the Chinese glyph's own face is
  // what must not change.
  const committedFonts = await platformFonts(page, '#editor-ink span');
  expect(chinese(committedFonts), `the character changed face when it was committed: ${committedFonts}`)
    .toEqual(chinese(composingFonts));
});

test('the room asks for the face when Chinese input begins, never for the door, Latin, Greek or pinyin', async ({ page }) => {
  test.setTimeout(90_000);
  const { held } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#room')).toBeVisible();
  await page.locator('#editor').focus();
  await page.waitForTimeout(400);
  expect(held, 'the door asked for the Chinese face').toHaveLength(0);
  await page.keyboard.insertText('Plain words, café, naïve, αβγ ');
  // Pinyin in the marked text is Latin: a composition starts nothing until it holds a Chinese character.
  const session = await page.context().newCDPSession(page);
  await session.send('Input.imeSetComposition', { text: 'wo', selectionStart: 2, selectionEnd: 2 });
  await page.waitForTimeout(400);
  expect(held, 'Latin, Greek or pinyin asked for the Chinese face').toHaveLength(0);
  await session.send('Input.imeSetComposition', { text: '我', selectionStart: 1, selectionEnd: 1 });
  await expect.poll(() => held.length, { message: 'a Chinese composition did not ask for the face' }).toBe(1);
  await session.send('Input.insertText', { text: '我' });
  await page.keyboard.insertText('写');
  await page.waitForTimeout(300);
  expect(held, 'the face is asked for once per page').toHaveLength(1);
  const faces = await page.evaluate(() => [...document.fonts]
    .filter(face => face.family.includes('Resource Han Rounded')).map(face => face.status));
  expect(faces).toHaveLength(1);
  expect(['loading', 'loaded']).toContain(faces[0]);
});

test('a committed Chinese character asks for the face on its own', async ({ page }) => {
  test.setTimeout(90_000);
  const { held } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await page.locator('#editor').focus();
  await page.keyboard.insertText('我');
  await expect.poll(() => held.length).toBe(1);
});

test('a character typed while the face is in flight is painted at once, and keeps that face', async ({ page }, info) => {
  test.setTimeout(90_000);
  const { release } = await holdFace(page);
  // The room's own clock is held still once the character is in: the measurement spends real seconds on screenshots,
  // and on a loaded host those seconds used to run into the silence warning and the wipe.
  await page.clock.install();
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
  // Two frames are the same drawing when no pixel moves by more than a rounding step. A loaded compositor can
  // re-raster the lit sheet a level or two apart across the whole box (seen: every pixel within 2 of 765); a glyph
  // that changes face moves its own pixels by hundreds.
  const changedPixels = (a, b) => page.evaluate(async ([a, b]) => {
    const load = data => new Promise(resolve => { const image = new Image(); image.onload = () => resolve(image); image.src = `data:image/png;base64,${data}`; });
    const [x, y] = await Promise.all([load(a), load(b)]);
    const canvas = new OffscreenCanvas(x.width, x.height), context = canvas.getContext('2d');
    context.drawImage(x, 0, 0); const one = context.getImageData(0, 0, x.width, x.height).data;
    context.clearRect(0, 0, x.width, x.height);
    context.drawImage(y, 0, 0); const two = context.getImageData(0, 0, x.width, x.height).data;
    let changed = 0;
    for (let i = 0; i < one.length; i += 4)
      if (Math.abs(one[i] - two[i]) + Math.abs(one[i + 1] - two[i + 1]) + Math.abs(one[i + 2] - two[i + 2]) > 24) changed += 1;
    return changed;
  }, [a, b]);
  const empty = await settled();
  await page.locator('#editor').focus();
  await page.keyboard.insertText('我');
  await expect(page.locator('#editor')).toHaveValue('我');
  await page.clock.pauseAt(await page.evaluate(() => Date.now() + 100));
  // The request is still held, so the face cannot arrive. The character must be on the sheet anyway: no block
  // period, no wait for 2.5 MB.
  await page.waitForTimeout(250);
  const painted = await shot();
  expect(await changedPixels(empty, painted), 'the typed character stays invisible while the face is in flight').toBeGreaterThan(20);
  // The baseline for "never changes face" is the settled sheet while the face is still held: on a loaded host the
  // 250 ms shot can land mid-frame, and that is not a face change.
  const held = await settled();
  // The room froze this page load to the platform serif, which is the only face it will draw Chinese in from here.
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('platform');
  expect(await writingStack(page), 'the frozen draft still names the webfont').not.toMatch(/Resource Han Rounded/);
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
  const frames = [held, drawn, ...later];
  const moved = [];
  for (const frame of frames.slice(1)) moved.push(await changedPixels(held, frame));
  if (moved.some(count => count > 0)) {
    // The evidence a reader needs to tell a face change from a repaint: every frame, in order.
    for (const [index, frame] of frames.entries()) await info.attach(`frame-${index}`, { body: Buffer.from(frame, 'base64'), contentType: 'image/png' });
    await info.attach('room', { body: JSON.stringify(await page.evaluate(() => ({ face: document.querySelector('#room').dataset.cjkFace,
      stack: getComputedStyle(document.querySelector('#editor')).fontFamily, phase: document.querySelector('#room').dataset.phase }))), contentType: 'application/json' });
  }
  expect(moved, 'the character changed face after it was drawn').toEqual(moved.map(() => 0));
});

test('a room that finds the face resident draws Chinese in Resource Han Rounded and keeps it', async ({ page }) => {
  test.setTimeout(90_000);
  // An earlier Chinese draft on this page asked for the file, so the face is resident before the first Chinese
  // character of this draft and the room freezes to it.
  await page.goto('./');
  await faceResident(page);
  await page.locator('#landing .cta a[href="#trial"]').click();
  // The door opens on the click's own hash change, one task later; the room focuses the editor itself.
  await expect(page.locator('#room')).toBeVisible();
  await page.waitForFunction(() => document.activeElement?.id === 'editor');
  await page.keyboard.insertText('我写中文');
  await expect(page.locator('#editor')).toHaveValue('我写中文');
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('webfont');
  expect(await writingStack(page)).toMatch(/Resource Han Rounded/);
  // The paint agrees with the stack: Chrome records the platform font with the frame.
  const client = await page.context().newCDPSession(page);
  await client.send('DOM.enable');
  await client.send('CSS.enable');
  const { root } = await client.send('DOM.getDocument');
  const { nodeId } = await client.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#editor-ink span' });
  const { fonts } = await client.send('CSS.getPlatformFontsForNode', { nodeId });
  const platform = fonts.map(font => font.familyName);
  expect(platform.filter(family => RHR.test(family)).length, `Chinese draw in Resource Han Rounded, got ${platform}`).toBe(1);
});

test('the draft after a wipe draws the face that has landed by then', async ({ page }) => {
  test.setTimeout(120_000);
  const { release } = await holdFace(page);
  await page.goto('index.html#trial', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#room')).toBeVisible();
  await page.locator('#editor').focus();
  // The first draft has to accept the platform face: the file is still held.
  await page.keyboard.insertText('我');
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('platform');
  release();
  await page.waitForFunction(() => [...document.fonts]
    .some(face => face.family.includes('Resource Han Rounded') && face.status === 'loaded'), null, { timeout: 60_000 });
  // Now the silence deadline has to take that draft, which is what makes the next sheet empty.
  await page.waitForFunction(() => document.getElementById('room').dataset.phase === 'wipe', null, { timeout: 20_000 });
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBeNull();
  await page.locator('#editor').focus();
  await page.keyboard.insertText('你');
  await page.waitForTimeout(300);
  // Arriving early is only worth its bytes if a later draft uses what arrived.
  expect(await page.locator('#room').getAttribute('data-cjk-face')).toBe('webfont');
  expect(await writingStack(page)).toMatch(/Resource Han Rounded/);
});

test('a visitor who never writes Chinese fetches none of it', async ({ page }) => {
  test.setTimeout(90_000);
  const client = await page.context().newCDPSession(page);
  await client.send('Network.enable');
  const requests = [];
  client.on('Network.requestWillBeSent', event => {
    if (/fonts\/resource-han-rounded[\w.-]*\.woff2/.test(event.request.url)) requests.push(event.request.url);
  });
  // The landing draws no Chinese, intent on the door is not Chinese input, and neither is a Latin draft.
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#landing .cta a[href="#trial"]').hover();
  await page.waitForTimeout(600);
  await page.locator('#landing .cta a[href="#trial"]').click();
  await page.waitForFunction(() => document.activeElement?.id === 'editor');
  await page.keyboard.insertText('the first line of a draft in English');
  await page.waitForTimeout(600);
  expect(requests, 'the Chinese face was fetched without Chinese input').toHaveLength(0);
  await page.keyboard.insertText('我');
  await expect.poll(() => requests.length, { timeout: 20_000 }).toBe(1);
});
