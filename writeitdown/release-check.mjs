// Release gate for the Mac sale page. Not shipped to the site.
// `node release-check.mjs` exits 1 and lists every missing launch input until
// mac.html carries a confirmed checkout URL, a signed DMG URL with its SHA-256,
// activation steps proven by a real test order, support.html lists a contact
// address, and the site matches the app's Info.plist.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const CHECKOUT = /^https:\/\/[^\s/]+\/\S*$/;
export const DOWNLOAD = /^https:\/\/\S+\.dmg$/;
export const SHA256 = /^[0-9a-f]{64}$/;

const here = path => fileURLToPath(new URL(path, import.meta.url));
const attr = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];

// Launch slots in mac.html: either a confirmed element or a pending notice.
export const stripComments = html => html.replace(/<!--[\s\S]*?-->/g, '');

export function launchSlots(html) {
  html = stripComments(html);
  const slots = {};
  for (const tag of html.match(/<[a-z]+\s[^>]*data-launch(-pending)?="[^"]+"[^>]*>/g) || []) {
    const pending = attr(tag, 'data-launch-pending');
    const name = pending || attr(tag, 'data-launch');
    slots[name] ||= { pending: 0, live: [] };
    if (pending) slots[name].pending += 1;
    else slots[name].live.push(tag);
  }
  return slots;
}

const plistValue = (plist, key) =>
  plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`))?.[1] ?? '';

export function blockers({ mac, support, plist }) {
  mac = stripComments(mac);
  const slots = launchSlots(mac);
  const found = [];
  const one = (name, check, label) => {
    const slot = slots[name] || { pending: 0, live: [] };
    if (slot.pending || slot.live.length !== 1) return found.push(`${label}: not confirmed in mac.html`), null;
    const value = check(slot.live[0]);
    if (value === null) found.push(`${label}: malformed in mac.html`);
    return value;
  };
  const checkout = one('checkout', tag => CHECKOUT.test(attr(tag, 'href') || '') ? attr(tag, 'href') : null, 'Checkout URL');
  one('download', tag => DOWNLOAD.test(attr(tag, 'href') || '') ? attr(tag, 'href') : null, 'Signed, notarized DMG URL');
  one('sha256', tag => {
    const value = mac.slice(mac.indexOf(tag) + tag.length).split('<')[0].trim();
    return SHA256.test(value) ? value : null;
  }, 'DMG SHA-256');
  one('license', () => true, 'License delivery and activation steps');
  if (!/href="mailto:[^"@\s]+@[^"\s]+"/.test(support.slice(support.indexOf('id="contact"'))))
    found.push('Support address: not listed in support.html#contact');
  const price = plistValue(plist, 'WIDDisplayPrice');
  if (!price || !mac.includes(`${price} ONCE.`)) found.push(`Price: mac.html does not show the app price ${price || '(empty)'}`);
  const appCheckout = plistValue(plist, 'WIDCheckoutURL');
  if (checkout && appCheckout !== checkout) found.push('Checkout URL: Info.plist WIDCheckoutURL differs from mac.html');
  return found;
}

export function readInputs() {
  return {
    mac: readFileSync(here('mac.html'), 'utf8'),
    support: readFileSync(here('support.html'), 'utf8'),
    plist: readFileSync(here('../apps/macos/FirstLine/Sources/FirstLine/Info.plist'), 'utf8'),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const found = blockers(readInputs());
  if (found.length) {
    console.error('Mac sale page is not ready to publish:');
    for (const line of found) console.error(`- ${line}`);
    console.error('Also confirm the live checkout shows the same price before publishing.');
    process.exit(1);
  }
  console.log('PASS: checkout, download, checksum, activation steps, support address, and price are configured.');
}
