import { test, expect } from '@playwright/test';

const service = 'https://licenses.writeitdown.app/api/v1';
const key = 'WID-TEST-BUYER-KEY';
const neutral = 'Your license is not ready yet.';
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
  await expect(page.getByRole('button', { name: 'Copy license key', exact: true })).toBeHidden();
}

// The session credential is read once and removed from the address bar and history when the
// license response arrives, on success and on failure alike; the retry control is the in-page
// replacement for a reload, and it keeps retrying from page memory.
async function credentialCleared(page) {
  expect(new URL(page.url()).searchParams.has('session_id'), 'session_id left in the URL').toBe(false);
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
  await page.getByRole('button', { name: 'Buy for $4.99 once', exact: true }).click();
  await expect(page).toHaveURL(hosted);
  expect(posts).toBe(1);
  await page.goBack();
  const buy = page.getByRole('button', { name: 'Buy for $4.99 once', exact: true });
  await expect(buy).toBeEnabled();
  await expect(page.locator('#checkout-status')).toBeEmpty();
  await buy.click();
  await expect(page).toHaveURL(hosted);
  expect(posts).toBe(2);
});

test('the pending state is visible, and pageshow restores Buy without reloading', async ({ page }) => {
  await page.route(`${service}/checkout`, () => {});
  await page.goto('mac.html');
  const buy = page.locator('#buy-form button');
  await buy.click();
  await expect(buy).toBeDisabled();
  await expect(buy).toHaveText('Opening checkout...');
  await expect(buy).toHaveAttribute('aria-busy', 'true');
  expect(await buy.evaluate(b => getComputedStyle(b).opacity), 'the working control is visibly busy').toBe('0.6');
  await expect(page.locator('#checkout-status')).toHaveText('Opening checkout...');
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
  await expect(buy).toBeEnabled();
  await expect(buy).toHaveText('Buy for $4.99 once');
  await expect(buy).not.toHaveAttribute('aria-busy', 'true');
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
  await expect(page.locator('#license-result')).toContainText('Save this key; this page will not show it again.');
  await expect(page.locator('#license-retry-row')).toBeHidden();
  await credentialCleared(page);
  const copy = page.getByRole('button', { name: 'Copy license key', exact: true });
  await expect(copy).toBeVisible();
  await copy.click();
  await expect(page.locator('#copy-license')).toHaveText('Copied');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(key);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize().width);
  await page.screenshot({ path: info.outputPath('paid-license.png'), fullPage: true });
  await page.goBack();
  await expect(page).toHaveURL(/\/index\.html$/);
});

test('a key padded by the service is displayed and copied without the padding', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.route(`${service}/license?session_id=cs_test_padded_fixture`,
    route => route.fulfill({ json: { licenseKey: `\r\n  ${key} \t\n` } }));
  await page.goto('mac.html?session_id=cs_test_padded_fixture');
  await expect(page.locator('#license-result')).toBeVisible();
  // toHaveText normalizes whitespace, so compare the raw text to pin the exact bytes.
  expect(await page.locator('#license-key').textContent()).toBe(key);
  await page.getByRole('button', { name: 'Copy license key', exact: true }).click();
  await expect(page.locator('#copy-license')).toHaveText('Copied');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(key);
});

for (const credential of ['\u00a0', '\u2003KEY\u00a0', '\u2028', '\v', '\f', 'K E\tY\r\n内']) {
  test(`key delivery preserves non-padding bytes ${JSON.stringify(credential)}`, async ({ page, context }) => {
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.route(`${service}/license?session_id=cs_test_unicode_fixture`,
      route => route.fulfill({ json: { licenseKey: ` \t\r\n${credential}\r\n\t ` } }));
    await page.goto('mac.html?session_id=cs_test_unicode_fixture');
    await expect(page.locator('#license-result')).toBeVisible();
    expect(await page.locator('#license-key').textContent()).toBe(credential);
    await page.getByRole('button', { name: 'Copy license key', exact: true }).click();
    await expect(page.locator('#copy-license')).toHaveText('Copied');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(credential);
  });
}

for (const state of ['pending', 'unknown']) {
  test(`${state} session shows neutral message, no key, and drops the credential`, async ({ page }, info) => {
    await page.route(`${service}/license?session_id=cs_test_${state}_fixture`, route => route.fulfill({ status: 404, json: { error: 'not_found' } }));
    await page.goto(`mac.html?session_id=cs_test_${state}_fixture`);
    await expect(page.locator('#license-status')).toHaveText(neutral);
    await noKey(page);
    await credentialCleared(page);
    await expect(page.locator('#retry-license')).toBeVisible();
    await page.reload();
    // A reload cannot replay the credential: it is gone from the URL and history, and the buyer
    // retries with the card's own control instead.
    await expect(page.locator('#license-delivery')).toBeHidden();
    await noKey(page);
    await page.screenshot({ path: info.outputPath(`${state}-license.png`), fullPage: true });
  });
}

for (const failure of ['network', 'http', 'empty', 'padding', 'malformed', 'non-string']) {
  test(`no license is shown after ${failure} fetch failure`, async ({ page }) => {
    await page.route(`${service}/license?session_id=cs_test_failure_fixture`, route => {
      if (failure === 'network') return route.abort();
      if (failure === 'http') return route.fulfill({ status: 500, json: { licenseKey: key } });
      if (failure === 'malformed') return route.fulfill({ contentType: 'application/json', body: '{' });
      return route.fulfill({ json: { licenseKey: failure === 'empty' ? '' : failure === 'padding' ? ' \t\r\n' : 42 } });
    });
    await page.goto('mac.html?session_id=cs_test_failure_fixture');
    await expect(page.locator('#license-status')).toHaveText(neutral);
    await noKey(page);
    await credentialCleared(page);
    await page.unroute(`${service}/license?session_id=cs_test_failure_fixture`);
    await page.route(`${service}/license?session_id=cs_test_failure_fixture`, route => route.fulfill({ json: { licenseKey: key } }));
    await page.locator('#retry-license').click();
    await expect(page.locator('#license-key')).toHaveText(key);
    await expect(page.locator('#license-retry-row')).toBeHidden();
    await credentialCleared(page);
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

test('a late failure from an older license request cannot overwrite the newest success', async ({ page }) => {
  let releaseOlder;
  const older = new Promise(resolve => { releaseOlder = resolve; });
  let calls = 0;
  await page.route(`${service}/license?session_id=cs_test_race_fixture`, async route => {
    calls += 1;
    if (calls === 1) {
      await older;
      await route.fulfill({ status: 404, json: { error: 'not_found' } });
      return;
    }
    await route.fulfill({ json: { licenseKey: key } });
  });
  await page.goto('mac.html?session_id=cs_test_race_fixture');
  await expect(page.locator('#license-status')).toHaveText('Checking your license...');
  await expect(page.locator('#retry-license')).toBeDisabled();
  await page.evaluate(() => {
    document.getElementById('retry-license').dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
  await expect(page.locator('#license-key')).toHaveText(key);
  await expect(page.locator('#license-status')).toHaveText('Your license key is ready.');
  await expect(page.locator('#license-retry-row')).toBeHidden();
  await credentialCleared(page);
  releaseOlder();
  await expect(page.locator('#license-status')).toHaveText('Your license key is ready.');
  await expect(page.locator('#license-retry-row')).toBeHidden();
  expect(calls).toBe(2);
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
    const buy = page.locator('#buy-form button');
    await buy.click();
    await expect(page.locator('#checkout-status')).toHaveText('Checkout is unavailable. Please try again in a moment.');
    await expect(page.locator('#checkout-status')).toHaveAttribute('role', 'alert');
    await expect(buy).toBeEnabled();
    await expect(buy).toHaveText('Try again');
    await noKey(page);
  });
}

test('a checkout retry announces Opening checkout as status, not alert', async ({ page }) => {
  let finishRetry;
  const retryPending = new Promise(resolve => { finishRetry = resolve; });
  let calls = 0;
  await page.route(`${service}/checkout`, async route => {
    calls += 1;
    if (calls === 1) return route.fulfill({ status: 503, json: {} });
    await retryPending;
    return route.abort();
  });
  await page.goto('mac.html');
  const buy = page.locator('#buy-form button');
  const status = page.locator('#checkout-status');
  await buy.click();
  await expect(status).toHaveText('Checkout is unavailable. Please try again in a moment.');
  await expect(status).toHaveAttribute('role', 'alert');
  await buy.click();
  await expect(status).toHaveText('Opening checkout...');
  await expect(status).toHaveAttribute('role', 'status');
  await expect(buy).toBeDisabled();
  finishRetry();
  await expect(status).toHaveText('Checkout is unavailable. Please try again in a moment.');
  await expect(status).toHaveAttribute('role', 'alert');
  expect(calls).toBe(2);
});
