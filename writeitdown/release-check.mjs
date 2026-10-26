// Release gate for the Mac download and sale pages. Not shipped to the site.
//
//   node release-check.mjs             static check of every launch input (download page
//                                      and sale page): exits 1 and lists each missing or
//                                      placeholder input.
//   node release-check.mjs --download  only the free-trial download page: the DMG link,
//                                      the Install card's DMG filename and its published
//                                      SHA-256, and, when present, the release note,
//                                      which declares the version of the linked DMG.
//   --live                             after a static pass, fetch the public buy page (never
//                                      create a checkout or payment) and verify the hosted
//                                      DMG against its published SHA-256.
//   --root <dir>                       check another site copy (tests use fixtures).
//
// Passing proves the inputs are present and reachable, not that a purchase works.
// Opening LIVE sales still needs a real TEST checkout, returned license key, installed
// DMG activation and refund verification. Static fixtures do not prove a purchase.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateWaivers, assertLiveSalesAllowed } from './journey/waivers.mjs';

const PLACEHOLDER_HOST = /(^|\.)(example\.(com|net|org)|test|invalid|localhost|local)$|^[\d.]+$|^\[/i;
const PLACEHOLDER_TEXT = /\b(todo|tbd|placeholder|lorem|example)\b/i;

const stripComments = html => html.replace(/<!--[\s\S]*?-->/g, '');
const attr = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];
const VERSION = /^\d+(?:\.\d+)*$/;
const versionOrder = (left, right) => {
  const a = left.split('.').map(Number);
  const b = right.split('.').map(Number);
  for (let index = 0; index < Math.max(a.length, b.length); index += 1) {
    const delta = (a[index] ?? 0) - (b[index] ?? 0);
    if (delta) return delta;
  }
  return 0;
};
const plistValue = (plist, key) =>
  plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`))?.[1] ?? '';

function realURL(value, { dmg = false } = {}) {
  let url;
  try { url = new URL(value); } catch { return false; }
  if (url.protocol !== 'https:' || PLACEHOLDER_HOST.test(url.hostname) || /[()]/.test(value)) return false;
  return dmg ? url.pathname.endsWith('.dmg') : true;
}

function contentOf(html, tag) {
  const name = /^<([a-z]+)/i.exec(tag)[1];
  const start = html.indexOf(tag) + tag.length;
  const re = new RegExp(`<${name}\\b|</${name}>`, 'gi');
  re.lastIndex = start;
  let depth = 1;
  let match;
  while ((match = re.exec(html))) {
    depth += match[0].startsWith('</') ? -1 : 1;
    if (depth === 0) return html.slice(start, match.index);
  }
  return '';
}

// One launch slot: exactly one live element and no pending notice.
function slot(html, name) {
  const tags = html.match(/<[a-z]+\s[^>]*data-launch(-pending)?="[^"]+"[^>]*>/g) || [];
  const live = tags.filter(tag => attr(tag, 'data-launch') === name);
  const pending = tags.filter(tag => attr(tag, 'data-launch-pending') === name);
  if (pending.length || live.length !== 1) return null;
  const tag = live[0];
  return { tag, text: contentOf(html, tag).replace(/<[^>]+>/g, '').trim() };
}

export function blockers({ mac, support, plist }) {
  mac = stripComments(mac);
  const found = [];
  const checkout = slot(mac, 'checkout');
  if (!checkout) found.push('Checkout URL: not confirmed in mac.html');
  else if (!/^<form\s/i.test(checkout.tag) || attr(checkout.tag, 'method') !== 'post')
    found.push('Checkout URL: not a POST form');
  else if (attr(checkout.tag, 'action') !== 'https://licenses.writeitdown.app/api/v1/checkout')
    found.push('Checkout URL: not the license service checkout endpoint');
  const license = slot(mac, 'license');
  if (!license) found.push('License delivery and activation steps: not confirmed in mac.html');
  else if (license.text.length < 40 || PLACEHOLDER_TEXT.test(license.text)) found.push('License delivery and activation steps: placeholder copy');
  const contact = support.slice(support.indexOf('id="contact"'));
  const mail = contact.match(/href="mailto:([^"?]+)"/)?.[1];
  if (!mail || PLACEHOLDER_HOST.test(mail.split('@')[1] || '')) found.push('Support address: not listed in support.html#contact');
  const price = plistValue(plist, 'WIDDisplayPrice');
  if (!price || !mac.toLowerCase().includes(`${price.toLowerCase()} once`))
    found.push(`Price: mac.html does not show the app price ${price || '(empty)'} once`);
  const canonical = mac.match(/<link\s+rel="canonical"\s+href="([^"]+)"/)?.[1];
  if (!realURL(canonical) || plistValue(plist, 'WIDCheckoutURL') !== canonical)
    found.push('Checkout URL: Info.plist WIDCheckoutURL differs from mac.html');
  return found;
}

export function downloadBlockers({ download }) {
  download = stripComments(download);
  const found = [];
  const dmg = slot(download, 'dmg');
  if (!dmg) found.push('DMG URL: not confirmed in download/index.html');
  else if (!/^<a\s/i.test(dmg.tag)) found.push('DMG URL: not a clickable link');
  else if (!realURL(attr(dmg.tag, 'href'), { dmg: true })) found.push('DMG URL: not a real https .dmg destination');
  const sha = slot(download, 'sha256');
  if (!sha) found.push('SHA-256: not published in download/index.html');
  else {
    if (!/^[0-9a-f]{64}$/.test(sha.text)) found.push('SHA-256: not 64 lowercase hex digits');
    if (!/^<span>([0-9a-f]{32})<\/span><span>([0-9a-f]{32})<\/span>$/.test(contentOf(download, sha.tag)))
      found.push('SHA-256: the code element must hold two 32-character spans');
  }
  const installTag = /<div class="card" id="install">/i.exec(download)?.[0];
  const install = installTag ? contentOf(download, installTag) : '';
  const commandTag = /<code\b[^>]*>/i.exec(install)?.[0];
  const commandContent = commandTag ? contentOf(install, commandTag) : '';
  const command = commandContent.replace(/<[^>]+>/g, '').trim();
  const installFile = command.match(/shasum -a 256\s+([^\s]+)/)?.[1];
  if (!/^<span class="cmd-call">shasum -a 256 <\/span><span class="cmd-file">[^<]+<\/span>$/.test(commandContent))
    found.push('Install command: the code element must hold the call span and the filename span');
  let linkedFile = '';
  if (dmg) {
    try { linkedFile = decodeURIComponent(new URL(attr(dmg.tag, 'href')).pathname.split('/').pop()); } catch {}
  }
  if (!installFile) found.push('Install command: the card does not name the DMG file to hash');
  else if (linkedFile && installFile !== linkedFile)
    found.push(`Install command: hashes ${installFile}, not the linked ${linkedFile}`);

  // The release note is optional: when present it is the page's visible claim about the version it
  // links, and it declares that version in data-release-note. A note ahead of or behind the linked
  // DMG is a page and artifact that disagree.
  const linkedVersion = linkedFile.match(/^Write-It-Down-(\d+(?:\.\d+)*)\.dmg$/)?.[1] ?? '';
  if (linkedFile && !linkedVersion) found.push('DMG URL: the file name does not carry the version as Write-It-Down-<version>.dmg');
  const noteTag = download.match(/<p[^>]*\sid="release-notes"[^>]*>/i)?.[0] ?? '';
  if (noteTag) {
    const noteVersion = attr(noteTag, 'data-release-note') ?? '';
    if (attr(noteTag, 'data-launch-pending') !== undefined)
      found.push('Release notes: data-launch-pending is retired; the note declares the linked version');
    if (!VERSION.test(noteVersion)) {
      found.push('Release notes: the note does not declare its version in data-release-note');
    } else if (linkedVersion && versionOrder(noteVersion, linkedVersion) !== 0) {
      found.push(`Release notes: the note declares ${noteVersion} but the download is ${linkedVersion}`);
    }
  }
  return found;
}

async function fetchFailure(name, href, method) {
  try {
    const response = await fetch(href, { method, redirect: 'follow' });
    if (!response.ok) return [`${name}: ${href} answered HTTP ${response.status}`];
    if (name === 'checkout') return [];
    if (!/octet-stream|apple-diskimage|x-apple/.test(response.headers.get('content-type') || ''))
      return [`DMG: ${href} is not served as a disk image`];
    const hash = createHash('sha256');
    for await (const chunk of response.body) hash.update(chunk);
    return [hash.digest('hex')];
  } catch (error) {
    return [`${name}: ${href} unreachable (${error.cause?.code || error.message})`];
  }
}

async function liveBlockers({ mac, download }, { sale }) {
  const found = [];
  if (sale) found.push(...await fetchFailure('checkout', mac.match(/<link\s+rel="canonical"\s+href="([^"]+)"/)[1], 'GET'));
  const page = stripComments(download);
  const [result] = await fetchFailure('DMG', attr(slot(page, 'dmg').tag, 'href'), 'GET');
  if (!/^[0-9a-f]{64}$/.test(result)) found.push(result);
  else if (result !== slot(page, 'sha256').text) found.push(`SHA-256: the served DMG hashes to ${result}, not the published value`);
  return found;
}

export function readInputs(root = fileURLToPath(new URL('.', import.meta.url))) {
  return {
    mac: readFileSync(join(root, 'mac.html'), 'utf8'),
    download: readFileSync(join(root, 'download/index.html'), 'utf8'),
    support: readFileSync(join(root, 'support.html'), 'utf8'),
    plist: readFileSync(join(root, '../apps/macos/FirstLine/Sources/FirstLine/Info.plist'), 'utf8'),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const rootAt = args.indexOf('--root');
  const root = rootAt >= 0 ? args[rootAt + 1] : fileURLToPath(new URL('.', import.meta.url));
  if (args.includes('--live-sales')) {
    try {
      assertLiveSalesAllowed(validateWaivers(JSON.parse(readFileSync(join(root, 'journey/waivers.json'), 'utf8'))));
    } catch (error) {
      console.error(`BLOCKED: ${error.message}`);
      process.exit(1);
    }
  }
  const inputs = readInputs(root);
  const sale = !args.includes('--download');
  let found = [...downloadBlockers(inputs), ...(sale ? blockers(inputs) : [])];
  if (!found.length && args.includes('--live')) found = await liveBlockers(inputs, { sale });
  if (found.length) {
    console.error(sale ? 'BLOCKED: the Mac sale page is not ready to publish.' : 'BLOCKED: the Mac download page is not ready to publish.');
    for (const line of found) console.error(`- ${line}`);
    process.exit(1);
  }
  console.log(args.includes('--live')
    ? 'LIVE CHECK PASSED: inputs present and reachable.'
    : 'STATIC CHECK PASSED: inputs present. Not verified live; run with --live.');
  if (sale) console.log('Still required before LIVE sales: a real test order through checkout, returned license key, installed DMG activation and refund verification. No live payment was attempted.');
  else console.log('Download page ready: the DMG link, the Install command and its published SHA-256 agree.');
}
