import { test, expect } from '@playwright/test';

const service = 'https://licenses.writeitdown.app/api/v1';
const key = 'WID-TEST-BUYER-KEY';
const neutral = 'Your licence is not ready yet. Reload in a moment.';
const pageErrors = new WeakMap();

test.beforeEach(async ({ page }) => {
  const errors = [];
  pageErrors.set(page, errors);
  page.on('pageerror', error => errors.push(error.message));
});

test.afterEach(async ({ page }) => {
  expect(pageErrors.get(page), 'no uncaught browser errors').toEqual([]);
});

async function noKey(page) {
  await expect(page.locator('#license-key')).toBeHidden();
  await expect(page.getByRole('button', { name: 'COPY LICENSE KEY', exact: true })).toBeHidden();
}

test('Buy posts once and follows the hosted checkout URL', async ({ page }) => {
  const hosted = 'https://checkout.stripe.com/c/pay/cs_test_browser_fixture';
  let posts = 0;
  await page.route(`${service}/checkout`, async route => {
    expect(route.request().method()).toBe('POST');
    posts += 1;
    await route.fulfill({ json: { url: hosted } });
  });
  await page.route(hosted, route => route.fulfill({ body: '<h1>Hosted checkout fixture</h1>' }));
  await page.goto('mac.html');
  await noKey(page);
  await page.getByRole('button', { name: 'BUY - $4.99', exact: true }).click();
  await expect(page).toHaveURL(hosted);
  expect(posts).toBe(1);
  await page.goBack();
  const buy = page.getByRole('button', { name: 'BUY - $4.99', exact: true });
  await expect(buy).toBeEnabled();
  await expect(page.locator('#checkout-status')).toBeEmpty();
  await buy.click();
  await expect(page).toHaveURL(hosted);
  expect(posts).toBe(2);
});

test('persisted pageshow restores Buy without reloading the document', async ({ page }) => {
  await page.route(`${service}/checkout`, () => {});
  await page.goto('mac.html');
  const buy = page.getByRole('button', { name: 'BUY - $4.99', exact: true });
  await buy.click();
  await expect(buy).toBeDisabled();
  await expect(page.locator('#checkout-status')).toHaveText('Opening checkout...');
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
  await expect(buy).toBeEnabled();
  await expect(page.locator('#checkout-status')).toBeEmpty();
});

test('paid session shows only the fetched key and copies it', async ({ page, context }, info) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.route(`${service}/license?session_id=cs_test_paid_fixture`, async route => {
    expect(route.request().method()).toBe('GET');
    expect(route.request().headers().referer).toBeUndefined();
    await route.fulfill({ json: { licenseKey: key } });
  });
  await page.goto('index.html');
  await page.goto('mac.html?campaign=fixture&session_id=cs_test_paid_fixture#license-heading');
  await expect(page).toHaveURL(/\/mac\.html\?campaign=fixture#license-heading$/);
  await expect(page.locator('#license-key')).toHaveText(key);
  await expect(page.locator('#license-key')).toBeInViewport();
  expect(await page.evaluate(() => [...document.scripts].some(script => script.src.includes('cloudflareinsights')))).toBe(false);
  expect(await page.evaluate(() => Object.keys(localStorage))).toEqual(['writeitdown-theme']);
  await expect(page.locator('#license-result')).toContainText("Paste this key into the app's activation field.");
  const copy = page.getByRole('button', { name: 'COPY LICENSE KEY', exact: true });
  await expect(copy).toBeVisible();
  await copy.click();
  await expect(page.locator('#copy-license')).toHaveText('COPIED');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(key);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
  await page.screenshot({ path: info.outputPath('paid-license.png'), fullPage: true });
  await page.goBack();
  await expect(page).toHaveURL(/\/index\.html$/);
});

for (const state of ['pending', 'unknown']) {
  test(`${state} session shows neutral message and no key`, async ({ page }, info) => {
    await page.route(`${service}/license?session_id=cs_test_${state}_fixture`, route => route.fulfill({ status: 404, json: { error: 'not_found' } }));
    await page.goto(`mac.html?session_id=cs_test_${state}_fixture`);
    await expect(page.locator('#license-status')).toHaveText(neutral);
    await noKey(page);
    await expect(page).toHaveURL(new RegExp(`session_id=cs_test_${state}_fixture$`));
    await page.reload();
    await expect(page.locator('#license-status')).toHaveText(neutral);
    await page.screenshot({ path: info.outputPath(`${state}-license.png`), fullPage: true });
  });
}

for (const failure of ['network', 'http', 'empty', 'malformed', 'non-string']) {
  test(`no license is shown after ${failure} fetch failure`, async ({ page }) => {
    await page.route(`${service}/license?session_id=cs_test_failure_fixture`, route => {
      if (failure === 'network') return route.abort();
      if (failure === 'http') return route.fulfill({ status: 500, json: { licenseKey: key } });
      if (failure === 'malformed') return route.fulfill({ contentType: 'application/json', body: '{' });
      return route.fulfill({ json: { licenseKey: failure === 'empty' ? '' : 42 } });
    });
    await page.goto('mac.html?session_id=cs_test_failure_fixture');
    await expect(page.locator('#license-status')).toHaveText(neutral);
    await noKey(page);
    await expect(page).toHaveURL(/session_id=cs_test_failure_fixture$/);
    await page.unroute(`${service}/license?session_id=cs_test_failure_fixture`);
    await page.route(`${service}/license?session_id=cs_test_failure_fixture`, route => route.fulfill({ json: { licenseKey: key } }));
    await page.reload();
    await expect(page.locator('#license-key')).toHaveText(key);
    await expect(page).toHaveURL(/\/mac\.html$/);
  });
}

test('no key or copy control appears while license fetch is still pending', async ({ page }) => {
  let finish;
  const ready = new Promise(resolve => { finish = resolve; });
  await page.route(`${service}/license?session_id=cs_test_waiting_fixture`, async route => {
    await ready;
    await route.fulfill({ json: { licenseKey: key } });
  });
  await page.goto('mac.html?session_id=cs_test_waiting_fixture');
  await expect(page.locator('#license-status')).toHaveText('Checking your license...');
  await noKey(page);
  finish();
  await expect(page.locator('#license-key')).toHaveText(key);
});

test('no session never requests a license or shows a key', async ({ page }) => {
  const calls = [];
  await page.route(`${service}/license**`, route => {
    calls.push(route.request().url());
    return route.fulfill({ json: { licenseKey: key } });
  });
  await page.goto('mac.html');
  await noKey(page);
  expect(calls).toEqual([]);
});

for (const failure of ['network', 'http', 'invalid-url']) {
  test(`checkout ${failure} restores Buy with an honest error`, async ({ page }) => {
    await page.route(`${service}/checkout`, route => {
      if (failure === 'network') return route.abort();
      return route.fulfill({ status: failure === 'http' ? 503 : 200, json: { url: 'javascript:alert(1)' } });
    });
    await page.goto('mac.html');
    const buy = page.getByRole('button', { name: 'BUY - $4.99', exact: true });
    await buy.click();
    await expect(page.locator('#checkout-status')).toHaveText('Checkout is unavailable. Please try again in a moment.');
    await expect(buy).toBeEnabled();
    await noKey(page);
  });
}
