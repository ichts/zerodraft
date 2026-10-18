// Release gate for the Mac sale page. Not shipped to the site.
//
//   node release-check.mjs           static check: exits 1 and lists every missing
//                                    or placeholder launch input.
//   node release-check.mjs --live    static check, then fetches the checkout and DMG
//                                    URLs and fails unless both answer for real.
//   --root <dir>                     check another site copy (tests use fixtures).
//
// Passing proves the inputs are present and reachable, not that a purchase works.
// Opening sales still needs a real test order (checkout, license email, activation,
// refund) and an explicit go from the owner.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PLACEHOLDER_HOST = /(^|\.)(example\.(com|net|org)|test|invalid|localhost|local)$|^[\d.]+$|^\[/i;
const PLACEHOLDER_TEXT = /\b(todo|tbd|placeholder|lorem|example)\b/i;

const stripComments = html => html.replace(/<!--[\s\S]*?-->/g, '');
const attr = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];
const plistValue = (plist, key) =>
  plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`))?.[1] ?? '';

function realURL(value, { dmg = false } = {}) {
  let url;
  try { url = new URL(value); } catch { return false; }
  if (url.protocol !== 'https:' || PLACEHOLDER_HOST.test(url.hostname) || /[()]/.test(value)) return false;
  return dmg ? url.pathname.endsWith('.dmg') : true;
}

// One launch slot: exactly one live element and no pending notice.
function slot(html, name) {
  const tags = html.match(/<[a-z]+\s[^>]*data-launch(-pending)?="[^"]+"[^>]*>/g) || [];
  const live = tags.filter(tag => attr(tag, 'data-launch') === name);
  const pending = tags.filter(tag => attr(tag, 'data-launch-pending') === name);
  if (pending.length || live.length !== 1) return null;
  const tag = live[0];
  const after = html.slice(html.indexOf(tag) + tag.length);
  return { tag, text: after.slice(0, after.search(/<\/[a-z]+>/)).replace(/<[^>]+>/g, '').trim() };
}

export function blockers({ mac, support, plist }) {
  mac = stripComments(mac);
  const found = [];
  const checkout = slot(mac, 'checkout');
  if (!checkout) found.push('Checkout URL: not confirmed in mac.html');
  else if (!realURL(attr(checkout.tag, 'href'))) found.push('Checkout URL: not a real https destination');
  const download = slot(mac, 'download');
  if (!download) found.push('Signed, notarized DMG URL: not confirmed in mac.html');
  else if (!realURL(attr(download.tag, 'href'), { dmg: true })) found.push('Signed, notarized DMG URL: not a real https .dmg destination');
  const license = slot(mac, 'license');
  if (!license) found.push('License delivery and activation steps: not confirmed in mac.html');
  else if (license.text.length < 40 || PLACEHOLDER_TEXT.test(license.text)) found.push('License delivery and activation steps: placeholder copy');
  const contact = support.slice(support.indexOf('id="contact"'));
  const mail = contact.match(/href="mailto:([^"?]+)"/)?.[1];
  if (!mail || PLACEHOLDER_HOST.test(mail.split('@')[1] || '')) found.push('Support address: not listed in support.html#contact');
  const price = plistValue(plist, 'WIDDisplayPrice');
  if (!price || !mac.includes(`${price} ONCE.`)) found.push(`Price: mac.html does not show the app price ${price || '(empty)'}`);
  if (checkout && plistValue(plist, 'WIDCheckoutURL') !== attr(checkout.tag, 'href'))
    found.push('Checkout URL: Info.plist WIDCheckoutURL differs from mac.html');
  return found;
}

async function liveBlockers(mac) {
  mac = stripComments(mac);
  const found = [];
  for (const [name, method] of [['checkout', 'GET'], ['download', 'HEAD']]) {
    const href = attr(slot(mac, name).tag, 'href');
    try {
      const response = await fetch(href, { method, redirect: 'follow' });
      if (!response.ok) found.push(`${name}: ${href} answered HTTP ${response.status}`);
      else if (name === 'download' && !/octet-stream|apple-diskimage|x-apple/.test(response.headers.get('content-type') || ''))
        found.push(`download: ${href} is not served as a disk image`);
    } catch (error) {
      found.push(`${name}: ${href} unreachable (${error.cause?.code || error.message})`);
    }
  }
  return found;
}

export function readInputs(root = fileURLToPath(new URL('.', import.meta.url))) {
  return {
    mac: readFileSync(join(root, 'mac.html'), 'utf8'),
    support: readFileSync(join(root, 'support.html'), 'utf8'),
    plist: readFileSync(join(root, '../apps/macos/FirstLine/Sources/FirstLine/Info.plist'), 'utf8'),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const rootAt = args.indexOf('--root');
  const inputs = readInputs(rootAt >= 0 ? args[rootAt + 1] : undefined);
  let found = blockers(inputs);
  if (!found.length && args.includes('--live')) found = await liveBlockers(inputs.mac);
  if (found.length) {
    console.error('BLOCKED: the Mac sale page is not ready to publish.');
    for (const line of found) console.error(`- ${line}`);
    process.exit(1);
  }
  console.log(args.includes('--live')
    ? 'LIVE CHECK PASSED: inputs present and reachable.'
    : 'STATIC CHECK PASSED: inputs present. Not verified live; run with --live.');
  console.log('Still required before opening sales: a real test order through checkout, license email, activation and refund, a delivered test email to the support address, and an explicit go.');
}
