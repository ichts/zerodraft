// The paper mode (D-119): lamp (the default), paper or slate, set on <html data-theme> from <head> so no page paints the
// wrong paper first. Every `.modes` radio group on the page shows and changes it; the choice is the one stored key.
(() => {
  const KEY = 'writeitdown-theme';
  const MODES = ['lamp', 'paper', 'slate'];
  // light and dark were the two themes before the modes; each maps to the mode that took its place.
  const LEGACY = { light: 'paper', dark: 'lamp' };
  let stored;
  try { stored = localStorage.getItem(KEY); } catch {}
  function apply(mode) {
    document.documentElement.dataset.theme = mode;
    document.querySelectorAll('.modes input').forEach(input => { input.checked = input.value === mode; });
  }
  apply(MODES.includes(stored) ? stored : LEGACY[stored] || 'lamp');
  document.addEventListener('DOMContentLoaded', () => {
    apply(document.documentElement.dataset.theme);
    document.querySelectorAll('.modes input').forEach(input => input.addEventListener('change', () => {
      apply(input.value);
      try { localStorage.setItem(KEY, input.value); } catch {}
    }));
  });
})();
