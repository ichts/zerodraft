import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { chromium, webkit, devices } from '@playwright/test';
import { validateWaivers, assertNoWaivedOffers } from './waivers.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const approved = JSON.parse(await fs.readFile(new URL('./waivers.json', import.meta.url), 'utf8'));
const tmp = path.join(root, 'tmp');
await fs.mkdir(tmp, { recursive: true });
const out = await fs.mkdtemp(path.join(tmp, 'waiver-tests-'));

test('every unasserted step needs a valid, unique approval', () => {
  assert.deepEqual(validateWaivers(approved), approved);
  for (const waiver of approved) {
    assert.throws(() => validateWaivers(approved.filter(item => item.step !== waiver.step)), /no approved waiver/);
    for (const patch of [{ reason: '' }, { approved_by: 'pending' }, { unwaive_when: '' }]) {
      assert.throws(() => validateWaivers(approved.map(item => item === waiver ? { ...item, ...patch } : item)), /invalid waiver/);
    }
  }
  assert.throws(() => validateWaivers([...approved, approved[0]]), /duplicate/);
  assert.throws(() => validateWaivers([...approved, { ...approved[0], step: 'writing' }]), /unknown/);
});

test('the journey executable fails before browser work when any approval is revoked', async () => {
  const copy = path.join(out, 'journey');
  await fs.mkdir(copy);
  for (const name of ['journey.mjs', 'waivers.mjs']) await fs.copyFile(path.join(root, 'journey', name), path.join(copy, name));
  for (const waiver of approved) {
    await fs.writeFile(path.join(copy, 'waivers.json'), JSON.stringify(approved.filter(item => item.step !== waiver.step)));
    const result = spawnSync(process.execPath, [path.join(copy, 'journey.mjs'), '--base', 'http://127.0.0.1:1', '--scenarios', 'silence-wipe'], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert(result.stderr.includes(`FAIL release waivers: unasserted steps have no approved waiver: ${waiver.step}`), result.stderr);
    assert.equal(result.stdout, '');
  }
});

for (const [engine, device] of [[webkit, devices['iPhone 14']], [chromium, {}]]) {
  test(`${engine.name()} rejects waived controls and allows the free release`, async () => {
    const browser = await engine.launch(engine === chromium ? { channel: 'chrome' } : {});
    try {
      const context = await browser.newContext({ ...device, recordVideo: { dir: path.join(out, engine.name()) } });
      const page = await context.newPage();
      await page.setContent('<main><p>BUY - $4.99: COMING SOON.</p><a href="/download/">DOWNLOAD FREE TRIAL</a><button>COPY TEXT</button><form action="/api/waitlist"><button>NOTIFY ME</button></form></main>');
      await assertNoWaivedOffers(page);
      for (const control of [
        '<a href="/checkout/">Continue</a>',
        '<a href="/login">Continue</a>',
        '<a href="/sign_in">Continue</a>',
        '<a href="/pay">Continue</a>',
        '<a href="https://pay.example/">BUY NOW</a>',
        '<button>Sign in</button>',
        '<button aria-label="Log  in">Account</button>',
        '<button title="Purchase">Continue</button>',
        '<input type="submit" value="Pay now">',
        '<input type="button" value="Checkout">',
        '<div role="button">Buy</div>',
        '<div role="link" aria-label="Sign-in"></div>',
        '<form action="/payment"><button>Continue</button></form>',
        '<a data-launch="post-payment-output" href="/result">Get result</a>',
        '<a style="display:none" href="/checkout">Continue</a>',
      ]) {
        await page.setContent(`<main>${control}</main>`);
        await assert.rejects(assertNoWaivedOffers(page), /waived feature offered on page/, control);
      }
      await context.close();
    } finally {
      await browser.close();
    }
  });
}
