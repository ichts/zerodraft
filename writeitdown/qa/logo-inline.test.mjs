// site.css draws the header lockup from two inlined masks so the mark is on the first frame (no request after the
// CSS). The files in logo/ stay the source: each inlined mask must decode to its file byte for byte.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const site = new URL('../', import.meta.url);
const css = readFileSync(new URL('site.css', site), 'utf8');

for (const [name, file] of [['--mask-plate', 'logo/write-it-down-lockup-plate.svg'], ['--mask-mark', 'logo/write-it-down-lockup.svg']]) {
  test(`${name} is ${file}, inlined`, () => {
    const found = css.match(new RegExp(`${name}:url\\("data:image/svg\\+xml,([^"]*)"\\)`));
    assert.ok(found, `site.css declares ${name} as an inline SVG`);
    assert.equal(decodeURIComponent(found[1]), readFileSync(new URL(file, site), 'utf8'));
  });
}
