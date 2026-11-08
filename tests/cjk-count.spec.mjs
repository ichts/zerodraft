// The root trial counts like the rooms (D-099): every language reads `word` or `words`, one word per CJK
// character, never `characters`.
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/word-count.json', import.meta.url), 'utf8'));

async function typeInTrial(page, text) {
  await page.goto('/index.html');
  await page.locator('a.door').click();
  const editor = page.locator('.trial-editor[role="textbox"]');
  await expect(editor).toBeFocused({ timeout: 2000 });
  await page.keyboard.insertText(text);
}

test('a Chinese draft shows words in the trial corner, never characters', async ({ page }) => {
  await typeInTrial(page, '我们是');
  await expect(page.locator('.chrome-br .label')).toHaveText('3 words');
});

test('one Chinese character reads 1 word', async ({ page }) => {
  await typeInTrial(page, '我');
  await expect(page.locator('.chrome-br .label')).toHaveText('1 word');
});

test('an English draft with one Chinese greeting counts the greeting as two words', async ({ page }) => {
  await typeInTrial(page, 'hello world 你好');
  await expect(page.locator('.chrome-br .label')).toHaveText('4 words');
});

test('a Japanese kana draft shows words', async ({ page }) => {
  await typeInTrial(page, 'こんにちは');
  await expect(page.locator('.chrome-br .label')).toHaveText('5 words');
});

test('the corner label matches the shared fixture for every labelled draft', async ({ page }) => {
  for (const { text, label } of fixture.labels.filter(entry => entry.text.trim())) {
    await typeInTrial(page, text);
    await expect(page.locator('.chrome-br .label'), JSON.stringify(text)).toHaveText(label);
  }
});

test('the kept receipt reads words for a Chinese draft', async ({ page }) => {
  await page.clock.install();
  await typeInTrial(page, '我们是');
  for (let s = 0; s < 60; s += 3) { await page.clock.fastForward(3000); await page.keyboard.insertText('好'); }
  await page.clock.fastForward(3000);
  await expect(page.locator('.receipt-line')).toHaveText(/^0:00 - \d+ words kept\.$/);
  await expect(page.locator('.receipt-line')).not.toContainText('character');
});
