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
  await page.goto('buy.html');
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
  await page.goto('buy.html');
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
    await page.goto('buy.html');
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
  await page.goto('buy.html');
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

// A control whose label changes must not change size: a purchase surface that reflows under the
// pointer reads as a different control, and the reader loses the button they were aiming at.
// Measured, not assumed: each control's widest label is rendered in place, and every state must
// match it, so the assertion fails on the pre-change 183.9 / 191.2 / 114.3 px buy button and
// 167.7 / 99.8 px copy button.
async function naturalWidths(page, selector, labels) {
  return page.evaluate(([selector, labels]) => labels.map(text => {
    const source = document.querySelector(selector);
    const clone = source.cloneNode(false);
    clone.textContent = text;
    clone.style.cssText += ';position:absolute;left:-9999px;top:0;visibility:hidden;min-width:0;width:auto';
    source.parentElement.append(clone);
    const width = clone.getBoundingClientRect().width;
    clone.remove();
    return { text, width: +width.toFixed(1) };
  }), [selector, labels]);
}

const widthOf = (page, selector) => page.locator(selector).evaluate(el => +el.getBoundingClientRect().width.toFixed(1));

test('the buy control keeps one width in idle, pending and error', async ({ page }) => {
  // The first click is refused, so the label becomes `Try again`; the second hangs on the wire, so the
  // pending label stays on screen long enough to measure. An aborted request would fail in a frame and
  // the label would already be back to `Try again` when the assertion reads it.
  let fail = true;
  await page.route(`${service}/checkout`, route => fail ? route.fulfill({ status: 503, json: {} }) : new Promise(() => {}));
  await page.goto('buy.html');
  const buy = page.locator('#buy-form button');
  await expect(buy).toHaveText('Buy for $4.99 once');
  const idle = await widthOf(page, '#buy-form button');
  await buy.click();
  await expect(buy).toHaveText('Try again');
  const error = await widthOf(page, '#buy-form button');
  fail = false;
  await buy.click();
  await expect(buy).toHaveText('Opening checkout...');
  const pending = await widthOf(page, '#buy-form button');
  const labels = await naturalWidths(page, '#buy-form button', ['Buy for $4.99 once', 'Opening checkout...', 'Try again']);
  const widest = Math.max(...labels.map(label => label.width));
  expect(idle, `idle buy width against ${JSON.stringify(labels)}`).toBe(error);
  expect(pending, `pending buy width against ${JSON.stringify(labels)}`).toBe(error);
  expect(idle, 'the widest label fits without a resize').toBeGreaterThanOrEqual(widest);
});

test('the copy control keeps one width in ready and copied', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.route(`${service}/license?session_id=cs_test_copy_width`, route => route.fulfill({ json: { licenseKey: key } }));
  await page.goto('mac.html?session_id=cs_test_copy_width');
  const copy = page.getByRole('button', { name: 'Copy license key', exact: true });
  await expect(copy).toBeVisible();
  const ready = await widthOf(page, '#copy-license');
  await copy.click();
  await expect(page.locator('#copy-license')).toHaveText('Copied');
  const copied = await widthOf(page, '#copy-license');
  const labels = await naturalWidths(page, '#copy-license', ['Copy license key', 'Copied']);
  const widest = Math.max(...labels.map(label => label.width));
  expect(copied, `copied width against ${JSON.stringify(labels)}`).toBe(ready);
  expect(ready, 'the widest label fits without a resize').toBeGreaterThanOrEqual(widest);
});

// One source per label: each control's idle label comes from the markup it renders, so the width it
// reserves tracks a copy edit. A buyer only ever sees the one width they were promised, so the guard
// is that edit itself: widen both markup labels and the reserved widths must follow them. When the
// probes held their own literals instead, a copy edit that lengthened a markup label left the floor
// tuned to the shorter string, and the control shrank when its state machine swapped the label.
const wideBuyLabel = 'Buy Write It Down for $4.99 once';
const wideCopyLabel = 'Copy your license key to the clipboard';

test('the reserved width follows the labels the markup renders', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  // One route per page: the purchase page renders the buy label, the checkout's return page renders the
  // copy label. Rewriting both on one page would prove nothing now that the two controls live apart.
  await page.route('**/buy.html', async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace('>Buy for $4.99 once</button>', `>${wideBuyLabel}</button>`);
    await route.fulfill({ response, body });
  });
  await page.route('**/mac.html?session_id=cs_test_wide_labels', async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace('>Copy license key</button>', `>${wideCopyLabel}</button>`);
    await route.fulfill({ response, body });
  });
  await page.route(`${service}/license?session_id=cs_test_wide_labels`, route => route.fulfill({ json: { licenseKey: key } }));
  let fail = true;
  await page.route(`${service}/checkout`, route => fail ? route.fulfill({ status: 503, json: {} }) : new Promise(() => {}));

  await page.goto('buy.html');
  const buy = page.locator('#buy-form button');
  await expect(buy).toHaveText(wideBuyLabel);
  const idle = await widthOf(page, '#buy-form button');
  await buy.click();
  await expect(buy).toHaveText('Try again');
  const error = await widthOf(page, '#buy-form button');
  fail = false;
  await buy.click();
  await expect(buy).toHaveText('Opening checkout...');
  const pending = await widthOf(page, '#buy-form button');
  const buyLabels = await naturalWidths(page, '#buy-form button', [wideBuyLabel, 'Opening checkout...', 'Try again']);
  expect(idle, `idle buy width against ${JSON.stringify(buyLabels)}`).toBe(error);
  expect(pending, 'pending buy width against the markup label').toBe(error);
  expect(idle, 'the markup buy label fits without a resize').toBeGreaterThanOrEqual(Math.max(...buyLabels.map(label => label.width)));

  await page.goto('mac.html?session_id=cs_test_wide_labels');
  const copy = page.getByRole('button', { name: wideCopyLabel, exact: true });
  await expect(copy).toBeVisible();
  const ready = await widthOf(page, '#copy-license');
  await copy.click();
  await expect(page.locator('#copy-license')).toHaveText('Copied');
  const copied = await widthOf(page, '#copy-license');
  const copyLabels = await naturalWidths(page, '#copy-license', [wideCopyLabel, 'Copied']);
  expect(copied, `copied width against ${JSON.stringify(copyLabels)}`).toBe(ready);
  expect(ready, 'the markup copy label fits without a resize').toBeGreaterThanOrEqual(Math.max(...copyLabels.map(label => label.width)));
});

// The floor is measured from the face the device renders, not tuned to the sans on the author's
// machine, so a wider default sans must still leave each control one width in every state.
test('both controls keep their one width on a wider default sans', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.route('**/tokens.css', async route => {
    const response = await route.fetch();
    const body = (await response.text()).replace(/--sans:[^;]+;/, '--sans:Verdana,"DejaVu Sans",sans-serif;');
    await route.fulfill({ response, body });
  });
  await page.route(`${service}/license?session_id=cs_test_wider_width`, route => route.fulfill({ json: { licenseKey: key } }));
  let fail = true;
  await page.route(`${service}/checkout`, route => fail ? route.fulfill({ status: 503, json: {} }) : new Promise(() => {}));

  await page.goto('mac.html?session_id=cs_test_wider_width');
  const copy = page.getByRole('button', { name: 'Copy license key', exact: true });
  await expect(copy).toBeVisible();
  await expect(copy).toHaveCSS('font-family', /^Verdana/);
  const ready = await widthOf(page, '#copy-license');
  await copy.click();
  await expect(page.locator('#copy-license')).toHaveText('Copied');
  const copied = await widthOf(page, '#copy-license');
  const copyLabels = await naturalWidths(page, '#copy-license', ['Copy license key', 'Copied']);
  expect(copied, `wider-sans copy width against ${JSON.stringify(copyLabels)}`).toBe(ready);
  expect(ready, 'the wider widest label fits without a resize').toBeGreaterThanOrEqual(Math.max(...copyLabels.map(label => label.width)));

  await page.goto('buy.html');
  const buy = page.locator('#buy-form button');
  await expect(buy).toHaveText('Buy for $4.99 once');
  await expect(buy).toHaveCSS('font-family', /^Verdana/);
  const idle = await widthOf(page, '#buy-form button');
  await buy.click();
  await expect(buy).toHaveText('Try again');
  const error = await widthOf(page, '#buy-form button');
  fail = false;
  await buy.click();
  await expect(buy).toHaveText('Opening checkout...');
  const pending = await widthOf(page, '#buy-form button');
  const labels = await naturalWidths(page, '#buy-form button', ['Buy for $4.99 once', 'Opening checkout...', 'Try again']);
  expect(idle, `wider-sans buy width against ${JSON.stringify(labels)}`).toBe(error);
  expect(pending, 'the wider pending label keeps the same width').toBe(error);
  expect(idle, 'the wider widest label fits without a resize').toBeGreaterThanOrEqual(Math.max(...labels.map(label => label.width)));
});

// On a phone the buy row stacks, so the two controls sit one under the other and any width difference
// reads as a near-miss rather than a hierarchy: before the width lock the pair was 182.2 / 183.9 px
// (1.7 px apart), with only the two controls floored it was 182.2 / 192 px (9.8 px apart), and stacked
// it is now 192 / 192 px. Stacked, the ghost takes the primary's measured floor and stays secondary by
// its own surface and colour, not by being narrower; side by side at desktop width it keeps its
// natural width. The row lives on the purchase page, which is where the sale happens.
test('the stacked buy row keeps one width and stays secondary', async ({ page }) => {
  await page.goto('buy.html');
  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 844 });
    const ghost = page.locator('#buy .doc-actions > .btn-ghost');
    const buy = page.locator('#buy-form button');
    const [ghostBox, buyBox] = [await ghost.boundingBox(), await buy.boundingBox()];
    // One control per line on a shared left edge. Which of the two leads is the purchase page's order -
    // the price, its facts, Buy, then the free trial - not this test's subject.
    expect(Math.abs(ghostBox.x - buyBox.x), `the stacked row shares one left edge at ${width}px`).toBeLessThanOrEqual(1);
    expect(ghostBox.y >= buyBox.y + buyBox.height - 1 || buyBox.y >= ghostBox.y + ghostBox.height - 1,
      `the row stacks at ${width}px`).toBe(true);
    expect(+ghostBox.width.toFixed(1), `ghost and primary share one width at ${width}px`).toBe(+buyBox.width.toFixed(1));
    const ghostPaint = await ghost.evaluate(el => {
      const style = getComputedStyle(el);
      return { background: style.backgroundColor, weight: style.fontWeight, family: style.fontFamily };
    });
    const buyPaint = await buy.evaluate(el => {
      const style = getComputedStyle(el);
      return { background: style.backgroundColor, weight: style.fontWeight, family: style.fontFamily };
    });
    expect(ghostPaint.background, 'the ghost stays a ghost').not.toBe(buyPaint.background);
    expect(ghostPaint.weight, 'the ghost keeps one type style with the primary').toBe(buyPaint.weight);
    expect(ghostPaint.family, 'the ghost keeps one family with the primary').toBe(buyPaint.family);
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  const [ghostWide, buyWide] = [await widthOf(page, '#buy .doc-actions > .btn-ghost'), await widthOf(page, '#buy-form button')];
  expect(ghostWide, 'side by side the ghost keeps its natural width').toBeLessThan(buyWide);
});

// A hyphen is a break opportunity, so `14-` / `day refund` split the number from its unit and the
// refund window reads as `14-` until the next line. The one compact label that prints the window
// (the `/download/` requirement card) is 200 px wide and never wraps at a page width, so a width
// check alone could never fail. The gate therefore puts a copy of the real label, with the page's own
// cascade, into a container swept from 40 px to 300 px: wherever the label is forced to wrap, the
// number and its unit must still share one line.
test('the refund window keeps its number and unit on one line', async ({ page }) => {
  await page.goto('download/');
  for (const width of [1440, 480, 390]) {
    await page.setViewportSize({ width, height: 900 });
    const splits = await page.evaluate(() => {
      const item = [...document.querySelectorAll('#requirements li')].find(li => /14.day/.test(li.textContent));
      const probe = item.cloneNode(true);
      probe.style.cssText = 'position:absolute;visibility:hidden;left:0;top:0;margin:0;box-sizing:border-box';
      item.parentNode.appendChild(probe);
      const label = probe.querySelector('b');
      const hits = [];
      for (let box = 40; box <= 300; box += 1) {
        probe.style.width = `${box}px`;
        const walker = document.createTreeWalker(label, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const at = node.nodeValue.search(/14[-\u2011]day/);
          if (at < 0) continue;
          const range = document.createRange();
          range.setStart(node, at);
          range.setEnd(node, at + 6);
          if ([...range.getClientRects()].filter(rect => rect.width > 0).length > 1) hits.push(box);
        }
      }
      probe.remove();
      return hits;
    });
    expect(splits, `the refund window splits in a label box of these widths at ${width}px`).toEqual([]);
  }
});
