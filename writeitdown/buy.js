// Checkout and key delivery for the purchase path, in one file because both pages share it: buy.html
// carries the checkout form, and mac.html - the checkout's fixed return URL - carries the delivery card.
// Return credentials and email activation fragments are consumed into page memory and removed from
// the address bar immediately. No credential is persisted or sent as a referrer.
(() => {
  const form = document.getElementById('buy-form');
  // The licence service, named once: the checkout form on buy.html posts to it, and the key is fetched
  // from it on the return page. qa/checkout.spec.mjs intercepts this origin, so a typo here fails there.
  const SERVICE = 'https://licenses.writeitdown.app';
  const options = { credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer', redirect: 'error' };

  // One source per label: the probe measures the strings the state machine writes, so a copy edit
  // cannot drift between the reserved width and the label that lands in it.
  const buy = form?.querySelector('button');
  const copy = document.getElementById('copy-license');
  const LABELS = {
    buy: buy && { idle: buy.textContent, busy: 'Opening checkout...', retry: 'Try again' },
    copy: copy && { idle: copy.textContent, done: 'Copied' },
  };

  // Both controls swap their label with the state machine, and a control that resizes under the
  // pointer reads as a different control. Each one reserves the width of its widest label in the face
  // the device actually renders, the measured floor room.js gives the kept pill's copy control (D-059):
  // a width tuned on one machine's sans moves the control again on the next.
  const WIDTH_PROBES = {
    '#buy-form button': LABELS.buy ? Object.values(LABELS.buy) : [],
    '#copy-license': LABELS.copy ? Object.values(LABELS.copy) : [],
  };

  function sizeLabelFloors() {
    const floors = {};
    for (const [selector, labels] of Object.entries(WIDTH_PROBES)) {
      if (!labels.length) continue;
      const control = document.querySelector(selector);
      if (!control || !control.offsetParent) continue;
      const probe = control.cloneNode(false);
      probe.removeAttribute('id');
      probe.style.cssText = 'position:absolute;left:-10000px;top:0;visibility:hidden;min-width:0';
      control.parentElement.append(probe);
      let widest = 0;
      for (const text of labels) {
        probe.textContent = text;
        widest = Math.max(widest, probe.getBoundingClientRect().width);
      }
      probe.remove();
      if (widest > 0) {
        floors[selector] = `${Math.ceil(widest)}px`;
        control.style.setProperty('--copy-floor', floors[selector]);
      }
    }
    // Stacked on a phone, the row's ghost sits directly under the primary, so it shares that floor
    // there (site.css, the phone step) instead of ending 9.8 px short of it.
    if (floors['#buy-form button']) buy.closest('.doc-actions')?.style.setProperty('--copy-floor', floors['#buy-form button']);
  }

  sizeLabelFloors();
  document.fonts.ready.then(sizeLabelFloors);

  if (form) {
    const checkoutStatus = document.getElementById('checkout-status');

    window.addEventListener('pageshow', () => {
      buy.disabled = false;
      buy.textContent = LABELS.buy.idle;
      buy.removeAttribute('aria-busy');
      checkoutStatus.textContent = '';
      checkoutStatus.setAttribute('role', 'status');
    });

    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (buy.disabled) return;
      buy.disabled = true;
      buy.textContent = LABELS.buy.busy;
      buy.setAttribute('aria-busy', 'true');
      checkoutStatus.setAttribute('role', 'status');
      checkoutStatus.textContent = LABELS.buy.busy;
      try {
        const response = await fetch(form.action, { ...options, method: 'POST', headers: { Accept: 'application/json' } });
        if (!response.ok) throw new Error('Checkout unavailable');
        const { url } = await response.json();
        const hosted = new URL(url);
        if (hosted.origin !== 'https://checkout.stripe.com' || hosted.username || hosted.password)
          throw new Error('Invalid checkout destination');
        location.assign(hosted.href);
      } catch {
        checkoutStatus.textContent = 'Checkout is unavailable. Please try again in a moment.';
        checkoutStatus.setAttribute('role', 'alert');
        buy.disabled = false;
        buy.textContent = LABELS.buy.retry;
        buy.removeAttribute('aria-busy');
      }
    });
  }

  const fragment = new URLSearchParams(location.hash.slice(1));
  const session = fragment.get('session_id') || new URLSearchParams(location.search).get('session_id');
  const hasActivation = fragment.has('activate');
  const activation = fragment.get('activate');
  if (!session && !hasActivation) return;

  const clean = new URL(location.href);
  clean.searchParams.delete('session_id');
  if (hasActivation || fragment.has('session_id')) clean.hash = '';
  history.replaceState(history.state, '', clean.href);

  const card = document.getElementById('license-delivery');
  if (!card) return;

  const status = document.getElementById('license-status');
  const key = document.getElementById('license-key');
  const result = document.getElementById('license-result');
  const retryRow = document.getElementById('license-retry-row');
  const retry = document.getElementById('retry-license');
  const activate = document.getElementById('activate-license');
  const appKey = value => /^cs_(test_|live_)[A-Za-z0-9_]+$/.test(value) && value.length <= 100;
  let deliveredKey = '';
  let latestRequest = 0;

  card.hidden = false;
  card.scrollIntoView({ block: 'start' });

  function checking() {
    status.textContent = 'Checking your license...';
    result.hidden = true;
    retryRow.hidden = true;
  }

  function showKey(value) {
    deliveredKey = value;
    key.textContent = value;
    status.textContent = 'Your license key is ready.';
    activate.hidden = !appKey(value);
    if (!activate.hidden) activate.href = `writeitdown://activate#key=${encodeURIComponent(value)}`;
    result.hidden = false;
    sizeLabelFloors();
  }

  async function loadLicense() {
    const request = ++latestRequest;
    checking();
    retry.disabled = true;
    retry.setAttribute('aria-busy', 'true');
    try {
      const url = new URL('/api/v1/license', SERVICE);
      url.searchParams.set('session_id', session);
      const response = await fetch(url, { ...options, headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error('License unavailable');
      const { licenseKey } = await response.json();
      const candidate = typeof licenseKey === 'string' ? licenseKey.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '') : '';
      if (!candidate) throw new Error('License unavailable');
      if (request !== latestRequest) return;
      showKey(candidate);
    } catch {
      if (request !== latestRequest) return;
      status.textContent = 'Your license is not ready yet.';
      retryRow.hidden = false;
    } finally {
      if (request === latestRequest) {
        retry.disabled = false;
        retry.removeAttribute('aria-busy');
      }
    }
  }

  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(deliveredKey);
      copy.textContent = LABELS.copy.done;
      document.getElementById('copy-status').textContent = '';
    } catch {
      document.getElementById('copy-status').textContent = 'Copy failed. Select the key above and copy it.';
    }
  });

  retry.addEventListener('click', loadLicense);
  if (hasActivation) {
    if (!session && fragment.getAll('activate').length === 1 && appKey(activation)) showKey(activation);
    else status.textContent = 'Your license is not ready yet.';
  } else loadLicense();
})();
