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

test('the journey rejects a LIVE sales claim while installed-DMG TEST acceptance is pending', () => {
  const result = spawnSync(process.execPath, [path.join(root, 'journey/journey.mjs'), '--base', 'http://127.0.0.1:1', '--live-sales'], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /LIVE sales blocked: maintainer installed-DMG TEST acceptance is pending/);
  assert.equal(result.stdout, '');
});

for (const [engine, device] of [[webkit, devices['iPhone 14']], [chromium, {}]]) {
  test(`${engine.name()} rejects waived sign-in controls and allows purchase integration`, async () => {
    const browser = await engine.launch(engine === chromium ? { channel: 'chrome' } : {});
    try {
      const context = await browser.newContext({ ...device, recordVideo: { dir: path.join(out, engine.name()) } });
      const page = await context.newPage();
      await page.setContent('<main><a href="/download/">DOWNLOAD FREE TRIAL</a><button>COPY TEXT</button><form action="https://licenses.writeitdown.app/api/v1/checkout"><button>BUY - $4.99</button></form><button>COPY LICENSE KEY</button></main>');
      await assertNoWaivedOffers(page);
      for (const control of [
        '<a href="/sign-in/">Continue</a>',
        '<a href="/login">Continue</a>',
        '<a href="/sign_in">Continue</a>',
        '<a href="/log-in">Continue</a>',
        '<a href="https://account.example/">SIGN IN</a>',
        '<button>Sign in</button>',
        '<button aria-label="Log  in">Account</button>',
        '<button title="Sign in">Continue</button>',
        '<input type="submit" value="Log in">',
        '<input type="button" value="Sign-in">',
        '<div role="button">Sign in</div>',
        '<div role="link" aria-label="Sign-in"></div>',
        '<form action="/login"><button>Continue</button></form>',
        '<a data-launch="sign-in" href="/account">Continue</a>',
        '<a style="display:none" href="/sign-in">Continue</a>',
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
