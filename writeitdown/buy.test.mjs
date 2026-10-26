import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const script = new vm.Script(await readFile(new URL('./buy.js', import.meta.url), 'utf8'));
const cleanURL = 'https://writeitdown.app/mac.html';

async function deliver(licenseKey, { succeed = true, failures = 0 } = {}) {
  const nodes = new Map();
  const copies = [];
  const replacements = [];
  const fetches = [];
  const element = id => {
    if (!nodes.has(id)) nodes.set(id, {
      hidden: true, textContent: '', listeners: {},
      addEventListener(name, handler) { this.listeners[name] = handler; },
      setAttribute() {},
      removeAttribute() {},
      scrollIntoView() {},
    });
    return nodes.get(id);
  };
  const form = element('buy-form');
  form.action = 'https://licenses.writeitdown.app/api/v1/checkout';
  form.querySelector = () => element('buy-button');
  const fetch = async url => {
    fetches.push(String(url));
    if (fetches.length <= failures || !succeed) throw new Error('unreachable');
    return { ok: true, json: async () => ({ licenseKey }) };
  };
  const context = vm.createContext({
    URL, URLSearchParams,
    document: { getElementById: element },
    window: { addEventListener() {} },
    location: {
      search: '?session_id=cs_test_fixture',
      href: 'https://writeitdown.app/mac.html?session_id=cs_test_fixture',
    },
    history: { state: null, replaceState: (...args) => replacements.push(args[2]) },
    navigator: { clipboard: { writeText: async text => copies.push(text) } },
    fetch,
  });
  script.runInContext(context);
  await new Promise(resolve => setImmediate(resolve));
  return { element, copies, replacements, fetches };
}

for (const credential of ['KEY', '\u00a0', '\u2003KEY\u00a0', '\u2028', '\v', '\f', 'K E\tY\r\n内']) {
  test(`delivery preserves credential bytes ${JSON.stringify(credential)}`, async () => {
    const page = await deliver(` \t\r\n${credential}\r\n\t `);
    assert.equal(page.element('license-key').textContent, credential);
    assert.equal(page.element('license-result').hidden, false);
    assert.equal(page.element('license-retry-row').hidden, true);
    await page.element('copy-license').listeners.click();
    assert.deepEqual(page.copies, [credential]);
    assert.equal(page.element('copy-license').textContent, 'Copied');
    assert.deepEqual(page.replacements, [cleanURL]);
  });
}

for (const credential of ['', ' \t\r\n', null, 42]) {
  test(`delivery rejects empty or non-string credential ${JSON.stringify(credential)}`, async () => {
    const page = await deliver(credential);
    assert.equal(page.element('license-result').hidden, true);
    assert.equal(page.element('license-key').textContent, '');
    assert.equal(page.element('license-status').textContent, 'Your license is not ready yet.');
    assert.equal(page.element('license-retry-row').hidden, false);
    assert.deepEqual(page.replacements, [cleanURL]);
    assert.deepEqual(page.copies, []);
  });
}

test('a failed fetch clears the credential from the URL and offers a retry', async () => {
  const page = await deliver(null, { succeed: false });
  assert.equal(page.element('license-status').textContent, 'Your license is not ready yet.');
  assert.equal(page.element('license-result').hidden, true);
  assert.equal(page.element('license-retry-row').hidden, false);
  assert.deepEqual(page.replacements, [cleanURL]);
});

test('a failed delivery keeps the credential so Check again retries from memory', async () => {
  const page = await deliver('KEY', { failures: 1 });
  assert.equal(page.element('license-status').textContent, 'Your license is not ready yet.');
  assert.equal(page.element('license-retry-row').hidden, false);
  assert.deepEqual(page.replacements, [cleanURL]);
  assert.equal(page.element('retry-license').disabled, false);
  await page.element('retry-license').listeners.click();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.element('license-key').textContent, 'KEY');
  assert.equal(page.element('license-status').textContent, 'Your license key is ready.');
  assert.equal(page.element('license-retry-row').hidden, true);
  assert.equal(page.fetches.length, 2);
  for (const url of page.fetches) assert.match(url, /session_id=cs_test_fixture/);
  assert.deepEqual(page.replacements, [cleanURL, cleanURL]);
});
