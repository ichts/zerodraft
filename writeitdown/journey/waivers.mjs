export function validateWaivers(waivers) {
  const required = new Set(['sign-in', 'test-payment']);
  if (!Array.isArray(waivers)) throw new Error('waivers must be an array');
  for (const waiver of waivers) {
    if (!waiver || !required.delete(waiver.step)) throw new Error('unknown or duplicate waiver step');
    if (typeof waiver.reason !== 'string' || !waiver.reason.trim()
      || waiver.approved_by !== (waiver.step === 'test-payment'
        ? 'captain integration-only decision 2026-10-23'
        : 'captain release decision 2026-10-22 (relayed by main)')
      || waiver.unwaive_when !== (waiver.step === 'test-payment' ? 'maintainer installed-DMG TEST acceptance passes' : 'feature ships')) throw new Error(`invalid waiver: ${waiver.step}`);
  }
  if (required.size) throw new Error(`unasserted steps have no approved waiver: ${[...required].join(', ')}`);
  return waivers;
}

export function assertLiveSalesAllowed(waivers) {
  if (waivers.some(waiver => waiver.step === 'test-payment'))
    throw new Error('LIVE sales blocked: maintainer installed-DMG TEST acceptance is pending');
}

export async function waivedOffers(page, scope = 'body') {
  return page.locator(scope).locator('a, button, input[type="submit"], input[type="button"], [role="button"], [role="link"], form').evaluateAll(elements => {
    const labelPattern = /^\s*(sign[\s_-]*in|log[\s_-]*in)\b/i;
    const targetPattern = /\/(?:log[\s_-]*in|sign[\s_-]*in)(?:[/?#.]|$)/i;
    return elements.filter(element => {
      const labels = element.tagName === 'FORM' ? [] : [element.textContent, element.getAttribute('aria-label'), element.getAttribute('title'), element.getAttribute('value')];
      return labels.some(label => labelPattern.test(label || ''))
        || targetPattern.test(element.getAttribute('href') || element.getAttribute('action') || '')
        || element.getAttribute('data-launch') === 'sign-in';
    }).map(element => element.getAttribute('aria-label') || element.textContent.trim() || element.getAttribute('value') || element.tagName);
  });
}

export async function assertNoWaivedOffers(page) {
  const offers = await waivedOffers(page);
  if (offers.length) throw new Error(`waived feature offered on page: ${JSON.stringify(offers)}`);
}
