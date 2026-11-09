// Checkout and key delivery for mac.html. The session credential is read once into page memory;
// the address bar and history keep it only until the license response arrives, then drop it on
// success and failure alike. Keys stay in page memory only.
(() => {
  const form = document.getElementById('buy-form');
  const buy = form.querySelector('button');
  const checkoutStatus = document.getElementById('checkout-status');
  const buyLabel = buy.textContent;
  const service = new URL(form.action).origin;
  const options = { credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer', redirect: 'error' };

  // Both controls swap their label with the state machine, and a control that resizes under the
  // pointer reads as a different control. Each one reserves the width of its widest label in the face
  // the device actually renders, the measured floor room.js gives the kept pill's copy control (D-059):
  // a width tuned on one machine's sans moves the control again on the next.
  const LABELS = {
    '#buy-form button': ['Buy for $4.99 once', 'Opening checkout...', 'Try again'],
    '#copy-license': ['Copy license key', 'Copied'],
  };

  function sizeLabelFloors() {
    const floors = {};
    for (const [selector, labels] of Object.entries(LABELS)) {
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
    // there (site.css, the phone step) instead of ending 18 px short of it.
    if (floors['#buy-form button']) buy.closest('.doc-actions')?.style.setProperty('--copy-floor', floors['#buy-form button']);
  }

  sizeLabelFloors();
  document.fonts.ready.then(sizeLabelFloors);

  window.addEventListener('pageshow', () => {
    buy.disabled = false;
    buy.textContent = buyLabel;
    buy.removeAttribute('aria-busy');
    checkoutStatus.textContent = '';
    checkoutStatus.setAttribute('role', 'status');
  });

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (buy.disabled) return;
    buy.disabled = true;
    buy.textContent = 'Opening checkout...';
    buy.setAttribute('aria-busy', 'true');
    checkoutStatus.setAttribute('role', 'status');
    checkoutStatus.textContent = 'Opening checkout...';
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
      buy.textContent = 'Try again';
      buy.removeAttribute('aria-busy');
    }
  });

  const session = new URLSearchParams(location.search).get('session_id');
  if (!session) return;

  const card = document.getElementById('license-delivery');
  const status = document.getElementById('license-status');
  const key = document.getElementById('license-key');
  const result = document.getElementById('license-result');
  const copy = document.getElementById('copy-license');
  const retryRow = document.getElementById('license-retry-row');
  const retry = document.getElementById('retry-license');
  let deliveredKey = '';
  let latestRequest = 0;

  card.hidden = false;
  card.scrollIntoView({ block: 'start' });

  function checking() {
    status.textContent = 'Checking your license...';
    result.hidden = true;
    retryRow.hidden = true;
  }

  function clearCredential() {
    const clean = new URL(location.href);
    clean.searchParams.delete('session_id');
    history.replaceState(history.state, '', clean.href);
  }

  async function loadLicense() {
    const request = ++latestRequest;
    checking();
    retry.disabled = true;
    retry.setAttribute('aria-busy', 'true');
    try {
      const url = new URL('/api/v1/license', service);
      url.searchParams.set('session_id', session);
      const response = await fetch(url, { ...options, headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error('License unavailable');
      const { licenseKey } = await response.json();
      const candidate = typeof licenseKey === 'string' ? licenseKey.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '') : '';
      if (!candidate) throw new Error('License unavailable');
      if (request !== latestRequest) return;
      deliveredKey = candidate;
      key.textContent = deliveredKey;
      status.textContent = 'Your license key is ready.';
      result.hidden = false;
      sizeLabelFloors();
    } catch {
      if (request !== latestRequest) return;
      status.textContent = 'Your license is not ready yet.';
      retryRow.hidden = false;
    } finally {
      if (request === latestRequest) {
        retry.disabled = false;
        retry.removeAttribute('aria-busy');
        clearCredential();
      }
    }
  }

  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(deliveredKey);
      copy.textContent = 'Copied';
      document.getElementById('copy-status').textContent = '';
    } catch {
      document.getElementById('copy-status').textContent = 'Copy failed. Select the key above and copy it.';
    }
  });

  retry.addEventListener('click', loadLicense);
  loadLicense();
})();
