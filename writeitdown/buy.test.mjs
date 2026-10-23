import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const script = new vm.Script(await readFile(new URL('./buy.js', import.meta.url), 'utf8'));

async function deliver(licenseKey) {
  const nodes = new Map();
  const copies = [];
  const replacements = [];
  const element = id => {
    if (!nodes.has(id)) nodes.set(id, {
      hidden: true, textContent: '', listeners: {},
      addEventListener(name, handler) { this.listeners[name] = handler; },
    });
    return nodes.get(id);
  };
  const form = element('buy');
  form.action = 'https://licenses.writeitdown.app/api/v1/checkout';
  form.querySelector = () => element('buy-button');
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
    fetch: async () => ({ ok: true, json: async () => ({ licenseKey }) }),
  });
  script.runInContext(context);
  await new Promise(resolve => setImmediate(resolve));
  return { element, copies, replacements };
}

for (const credential of ['KEY', '\u00a0', '\u2003KEY\u00a0', '\u2028', '\v', '\f', 'K E\tY\r\n内']) {
  test(`delivery preserves credential bytes ${JSON.stringify(credential)}`, async () => {
    const page = await deliver(` \t\r\n${credential}\r\n\t `);
    assert.equal(page.element('license-key').textContent, credential);
    assert.equal(page.element('license-result').hidden, false);
    await page.element('copy-license').listeners.click();
    assert.deepEqual(page.copies, [credential]);
    assert.equal(page.element('copy-license').textContent, 'COPIED');
    assert.deepEqual(page.replacements, ['https://writeitdown.app/mac.html']);
  });
}

for (const credential of ['', ' \t\r\n', null, 42]) {
  test(`delivery rejects empty or non-string credential ${JSON.stringify(credential)}`, async () => {
    const page = await deliver(credential);
    assert.equal(page.element('license-result').hidden, true);
    assert.equal(page.element('license-key').textContent, '');
    assert.equal(page.element('license-status').textContent, 'Your licence is not ready yet. Reload in a moment.');
    assert.deepEqual(page.replacements, []);
    assert.deepEqual(page.copies, []);
  });
}
