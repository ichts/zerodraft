// The component gallery (kit/index.html) is a dev page: it stays out of search and out of every shipped page.
import { test, expect } from '@playwright/test';

test('the gallery is a dev page: it is not indexable and is linked from no shipped page', async ({ page }) => {
  await page.goto('kit/index.html');
  expect(await page.locator('meta[name="robots"]').getAttribute('content')).toBe('noindex');
});
