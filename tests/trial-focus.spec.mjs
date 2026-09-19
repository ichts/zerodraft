// Regression: the door must leave the trial editor focused so the first
// keystrokes reach it. Root cause (fixed): the bridge called focus() once on
// the next rAF while .trial-overlay still computed visibility:hidden, the
// call silently no-oped, and it was never retried - document.activeElement
// stayed <body> and keystrokes typed after the door went nowhere until the
// user clicked the paper.
//
// The fix retries focus per animation frame until the overlay computes
// visible (bounded: isTrial() guard plus a 1s cap). These specs fail on the
// unfixed code because the editor never receives focus on its own.
import { test, expect } from '@playwright/test';

const doorSelector = 'a.door';
const editorSelector = '.trial-editor[role="textbox"]';

async function expectDoorAutofocus(page) {
  await page.goto('/index.html');
  const door = page.locator(doorSelector);
  await door.waitFor();
  await door.click();
  const editor = page.locator(editorSelector);
  // Focus must arrive on the real entry path, with no click on the paper.
  // The bound is generous; the fix lands focus within the 120ms snap window.
  await expect(editor).toBeFocused({ timeout: 2000 });
  // Typing immediately once focused must reach the editor in full.
  const sentence = 'the door puts me in the room';
  await page.keyboard.type(sentence, { delay: 20 });
  await expect(editor).toHaveText(sentence);
}

test('door click autofocuses the trial editor and typing lands', async ({ page }) => {
  await expectDoorAutofocus(page);
});

test.describe('prefers-reduced-motion', () => {
  test.use({ reducedMotion: 'reduce' });

  test('door click still autofocuses the trial editor', async ({ page }) => {
    await expectDoorAutofocus(page);
  });
});
