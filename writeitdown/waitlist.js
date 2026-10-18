// Progressive enhancement for the Mac waitlist form on mac.html. Without JavaScript the form
// posts normally and the service redirects to mac.html#waitlist-<outcome>, which CSS reveals.
(() => {
  const form = document.getElementById('waitlist-form');
  if (!form || !window.fetch) return;
  const status = document.getElementById('waitlist-status');
  const button = form.querySelector('button[type="submit"]');
  const message = outcome => (document.getElementById('waitlist-' + outcome) ||
    document.getElementById('waitlist-error')).textContent;

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (button.disabled) return;
    if (location.hash.startsWith('#waitlist-')) history.replaceState(null, '', location.pathname + location.search);
    button.disabled = true;
    form.dataset.outcome = 'sending';
    status.textContent = 'SENDING...';
    let outcome = 'error';
    try {
      const response = await fetch(form.action, {
        method: 'POST',
        headers: { Accept: 'application/json' },
        body: new URLSearchParams(new FormData(form)),
      });
      outcome = (await response.json()).status || 'error';
    } catch {
      outcome = 'error';
    }
    status.textContent = message(outcome);
    form.dataset.outcome = outcome;
    button.disabled = false;
  });
})();
