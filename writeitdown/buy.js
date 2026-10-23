// Hosted checkout and buyer-key delivery. Neither keys nor session credentials are persisted.
(() => {
  const form = document.getElementById('buy');
  const buy = form.querySelector('button');
  const checkoutStatus = document.getElementById('checkout-status');
  const service = new URL(form.action).origin;
  const options = { credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer', redirect: 'error' };

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (buy.disabled) return;
    buy.disabled = true;
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
      buy.disabled = false;
    }
  });

  const session = new URLSearchParams(location.search).get('session_id');
  if (!session) return;
  const status = document.getElementById('license-status');
  const key = document.getElementById('license-key');
  const copy = document.getElementById('copy-license');
  document.getElementById('license-delivery').hidden = false;
  status.textContent = 'Checking your license...';

  async function loadLicense() {
    try {
      const url = new URL('/api/v1/license', service);
      url.searchParams.set('session_id', session);
      const response = await fetch(url, { ...options, headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error('License unavailable');
      const { license_key } = await response.json();
      if (typeof license_key !== 'string' || !license_key.trim()) throw new Error('License unavailable');
      key.textContent = license_key;
      status.textContent = 'Your license key is ready.';
      document.getElementById('license-result').hidden = false;
    } catch {
      status.textContent = 'Your licence is not ready yet. Reload in a moment.';
    }
  }

  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(key.textContent);
      copy.textContent = 'COPIED';
      document.getElementById('copy-status').textContent = '';
    } catch {
      document.getElementById('copy-status').textContent = 'Copy failed. Select the key above and copy it.';
    }
  });
  loadLicense();
})();
