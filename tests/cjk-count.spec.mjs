// The root trial counts like the rooms (D-094): a Chinese draft reads characters, never words, and an
// English draft with one quoted 你好 stays words.
import { test, expect } from '@playwright/test';

async function typeInTrial(page, text) {
  await page.goto('/index.html');
  await page.locator('a.door').click();
  const editor = page.locator('.trial-editor[role="textbox"]');
  await expect(editor).toBeFocused({ timeout: 2000 });
  await page.keyboard.insertText(text);
}

test('a Chinese draft shows characters in the trial corner, never words', async ({ page }) => {
  await typeInTrial(page, '我们是');
  await expect(page.locator('.chrome-br .label')).toHaveText('3 characters');
});

test('an English draft with one Chinese greeting keeps words', async ({ page }) => {
  await typeInTrial(page, 'hello world 你好');
  await expect(page.locator('.chrome-br .label')).toHaveText('4 words');
});

test('a Japanese kana draft shows characters', async ({ page }) => {
  await typeInTrial(page, 'こんにちは');
  await expect(page.locator('.chrome-br .label')).toHaveText('5 characters');
});

test('the kept receipt labels a Chinese draft in characters', async ({ page }) => {
  await page.clock.install();
  await typeInTrial(page, '我们是');
  for (let s = 0; s < 60; s += 3) { await page.clock.fastForward(3000); await page.keyboard.insertText('好'); }
  await page.clock.fastForward(3000);
  await expect(page.locator('.receipt-line')).toHaveText(/^0:00 - \d+ characters? kept\.$/);
});
