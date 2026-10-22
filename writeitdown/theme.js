(() => {
  let preference;
  try { preference = localStorage.getItem('writeitdown-theme'); } catch {}
  function apply(theme) {
    document.documentElement.dataset.theme = theme;
    // The header icon button names the theme it switches to; CSS shows the matching sun or moon.
    document.querySelectorAll('[data-theme-toggle]').forEach(button => {
      button.setAttribute('aria-label', `Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`);
    });
  }
  // Light is the default; dark is an explicit choice that the toggle stores.
  apply(preference === 'dark' ? 'dark' : 'light');
  document.addEventListener('DOMContentLoaded', () => {
    apply(document.documentElement.dataset.theme);
    document.querySelectorAll('[data-theme-toggle]').forEach(button => button.addEventListener('click', () => {
      preference = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      apply(preference);
      try { localStorage.setItem('writeitdown-theme', preference); } catch {}
    }));
  });
})();
