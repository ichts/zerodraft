// Regression: the trial's deadline adjudication must run at the key's own
// instant, not only on the 100 ms tick, and the wipe receipt must report the
// deadline that fired rather than the moment the callback arrived.
//
// Root cause (fixed in the same commit): the `data-on:flinput` expression wrote
// `_session.text` unconditionally, so a key that landed between a deadline and
// the pending tick rescued an expired draft or appended after 0:00; and
// sessionWipe reported the caller's wall-clock `remaining`, so a throttled
// catch-up tick printed a receipt computed at arrival time.
//
// The clock is installed before load so nothing here depends on tick timing.
// `setSystemTime` moves Date.now without firing timers, which is exactly the
// "input arrives before the pending tick" order the bug needs; `runFor` fires
// the tick when a test wants the deadline adjudicated by the ticker.
import { test, expect } from '@playwright/test';

const door = 'a.door';
const editor = '.trial-editor[role="textbox"]';
const reportLine = '.report-line';
const keptText = '.kept-text';
const ORIGIN = 1_700_000_000_000;

// Opens the trial, then freezes the clock. The door's focus retry runs on
// animation frames, so it gets one advance before the freeze; focus itself is
// covered by trial-focus.spec.mjs, so this spec focuses the editor directly
// rather than re-testing the door.
async function openTrial(page) {
  await page.clock.install({ time: ORIGIN });
  await page.goto('/index.html');
  await page.locator(door).click();
  await page.clock.runFor(200);
  // Freeze the clock. The bound stays in the future so the call never races the
  // clock's own few milliseconds of drift ("cannot fast-forward to the past").
  await page.clock.pauseAt((await page.evaluate(() => Date.now())) + 1000);
  await page.locator(editor).focus();
  await expect(page.locator(editor)).toBeFocused();
  return page.evaluate(() => Date.now());
}

// Types at 0:00 and then one key every four seconds up to `second`, so the
// session is genuinely alive with a last input at exactly that second: the wipe
// line is then lastInput + 8 s, which is what every deadline assertion below
// needs. Returns the draft text the model should hold after the last key.
async function typeThrough(page, origin, second) {
  await page.keyboard.type('old');
  let text = 'old';
  for (let at = 4000; at < second; at += 4000) {
    await page.clock.setSystemTime(origin + at);
    await page.keyboard.type('x');
    text += 'x';
  }
  await page.clock.setSystemTime(origin + second);
  await page.keyboard.type('x');
  return text + 'x';
}

test('a key after the wipe line starts a fresh draft instead of rescuing the old text', async ({ page }) => {
  const origin = await openTrial(page);
  await page.keyboard.type('old');
  // Past the 8 s wipe line, before the pending tick can adjudicate it.
  await page.clock.setSystemTime(origin + 8100);
  await page.keyboard.type('n');
  await expect(page.locator(editor)).toHaveText('n');
  await expect(page.locator('.trial-report')).toBeHidden();
  // The fresh draft carries a fresh 60 s clock.
  await expect(page.locator('.trial-timer')).toHaveText('1:00');
});

test('a fresh draft announces the receipt for the deadline that fired', async ({ page }) => {
  const origin = await openTrial(page);
  // Last key at 0:08, so the draft was due at 0:16 and 0:44 was unused. The key
  // lands four seconds past that line, before the pending tick: a receipt
  // measured at the key's instant would read 0:40.
  await typeThrough(page, origin, 8000);
  await page.clock.setSystemTime(origin + 20_000);
  await page.keyboard.type('n');
  await expect(page.locator(editor)).toHaveText('n');
  await expect(page.locator('.sr-only')).toHaveText('Draft wiped - 0:44 unused.');
  await expect(page.locator('.trial-report')).toBeHidden();
  // The fresh draft's clock starts at the key, so the next tick still reads 1:00.
  await page.clock.runFor(100);
  await expect(page.locator('.trial-timer')).toHaveText('1:00');
});

test('a key after 0:00 cannot append to the kept draft', async ({ page }) => {
  const origin = await openTrial(page);
  const draft = await typeThrough(page, origin, 55_000);
  await page.clock.setSystemTime(origin + 60_500);
  await page.keyboard.type('n');
  await expect(page.locator('.trial-kept')).toBeVisible();
  await expect(page.locator(keptText)).toHaveText(draft);
  await expect(page.locator(editor)).toHaveText(draft + 'n');
});

test('the wipe receipt reports the deadline that fired, not when the callback arrived', async ({ page }) => {
  const origin = await openTrial(page);
  await page.keyboard.type('old');
  // A throttled catch-up: the tick is only delivered at 9 s, one second after
  // the 8 s wipe line. The draft was due at 8 s, so 60 - 8 = 0:52 was unused.
  await page.clock.setSystemTime(origin + 9000);
  await page.clock.runFor(150);
  await expect(page.locator('.trial-report')).toBeVisible();
  await expect(page.locator(reportLine)).toHaveText('Draft wiped - 0:52 unused.');
});

test('a delayed tick keeps the draft when 0:00 lands before the wipe line', async ({ page }) => {
  const origin = await openTrial(page);
  // Last key at 0:55: the wipe line would be 1:03, past 0:00, so 0:00 wins.
  const draft = await typeThrough(page, origin, 55_000);
  await page.clock.setSystemTime(origin + 61_000);
  await page.clock.runFor(150);
  await expect(page.locator('.trial-kept')).toBeVisible();
  await expect(page.locator(keptText)).toHaveText(draft);
});

test('a tie between 0:00 and the wipe line goes to the wipe', async ({ page }) => {
  const origin = await openTrial(page);
  // Last key at 0:52: the wipe line is exactly 1:00, the same instant as 0:00.
  await typeThrough(page, origin, 52_000);
  await page.clock.setSystemTime(origin + 61_000);
  await page.clock.runFor(150);
  await expect(page.locator('.trial-report')).toBeVisible();
  await expect(page.locator(reportLine)).toHaveText('Draft wiped - 0:00 unused.');
});

// The browser's composition order: compositionstart, one insertCompositionText
// per keystroke inside the composition, then compositionend followed by
// insertFromComposition. The editor is a plain contenteditable, so the event
// order itself is the contract the bridge reads.
async function startComposition(page, text, data) {
  await page.evaluate(([text, data]) => {
    const el = document.querySelector('.trial-editor');
    el.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
    el.textContent = text;
    el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertCompositionText', data }));
  }, [text, data]);
}

async function commitComposition(page, text, data) {
  await page.evaluate(([text, data]) => {
    const el = document.querySelector('.trial-editor');
    el.textContent = text;
    el.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data }));
    el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertFromComposition', data }));
  }, [text, data]);
}

test('a composition committed after the wipe line starts a fresh draft with only the committed text', async ({ page }) => {
  const origin = await openTrial(page);
  await page.keyboard.type('old');
  // Composing counts as activity, so the wipe line is the last composition
  // keystroke plus 8 s. The candidate window then stays open past it, with the
  // pending 100 ms tick not yet delivered.
  await page.clock.setSystemTime(origin + 100);
  await startComposition(page, 'oldに', 'に');
  await page.clock.setSystemTime(origin + 200);
  await startComposition(page, 'oldにほ', 'ほ');
  await page.clock.setSystemTime(origin + 8900);
  // Committing the kanji replaces the marked text: the committed DOM text is
  // not an append of the draft the model holds.
  await commitComposition(page, 'old日本', '日本');
  await expect(page.locator(editor)).toHaveText('日本');
  await expect(page.locator('.trial-timer')).toHaveText('1:00');
  await expect(page.locator('.trial-report')).toBeHidden();
});

test('a composition committed after the wipe line keeps the text it inserted', async ({ page }) => {
  const origin = await openTrial(page);
  await page.keyboard.type('old');
  await page.clock.setSystemTime(origin + 100);
  await startComposition(page, 'oldに', 'に');
  await page.clock.setSystemTime(origin + 200);
  await startComposition(page, 'oldにほ', 'ほ');
  await page.clock.setSystemTime(origin + 8900);
  // The candidate the writer picks equals the marked text, which is already in
  // the model: committing it inserts nothing new and must not blank the room.
  await commitComposition(page, 'oldにほ', 'にほ');
  await expect(page.locator(editor)).toHaveText('にほ');
  await expect(page.locator('.trial-timer')).toHaveText('1:00');
});
