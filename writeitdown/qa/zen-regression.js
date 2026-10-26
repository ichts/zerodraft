async () => {
  const editor = document.getElementById('editor');
  const results = [];
  const check = (name, pass) => {
    results.push({ name, pass: Boolean(pass) });
    if (!pass) throw new Error(name);
  };
  document.getElementById('restart').click();
  const text = ('A private messy draft keeps moving forward. 中文继续写。👨‍👩‍👧‍👦\n').repeat(60) + 'The active line';
  editor.value = text;
  editor.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
  const css = getComputedStyle(editor);
  const line = parseFloat(css.lineHeight);
  check('long multilingual draft retained', editor.value === text);
  check('fixed five-line aperture displays two faded previous lines and centered active line', Math.abs(editor.clientHeight - 5 * line) < 1);
  check('symmetric two-line padding centers active line', Math.abs(parseFloat(css.paddingTop) - 2 * line) < 1 && css.paddingTop === css.paddingBottom);
  check('editor has no user-scrollable overflow or scrollbar', css.overflowY === 'hidden' && css.scrollbarWidth === 'none');
  check('latest line pinned to center', Math.abs(editor.scrollHeight - editor.clientHeight - editor.scrollTop) < 2);
  const mask = css.maskImage || css.webkitMaskImage;
  const bands = [...mask.matchAll(/(rgba?\([^)]*\))\s+([\d.]+)px/g)].map(m => ({ color: m[1], px: parseFloat(m[2]) }));
  check('stepped per-line mask, not a continuous gradient', bands.length === 7);
  // D-056: the ladder is the theme's two history stops (contrast steps on the Note paper), then the
  // active line at full ink, then nothing. The contrast floor itself is owned by qa/paper.spec.mjs.
  const historyStops = [
    Number(css.getPropertyValue('--paper-history-2')),
    Number(css.getPropertyValue('--paper-history-1')),
  ];
  const bandAlpha = colour => {
    const match = /rgba\(0, 0, 0, ([\d.]+)\)/.exec(colour);
    return match ? Number(match[1]) : (/^rgb\(0, 0, 0\)$/.test(colour) ? 1 : 0);
  };
  check('two back the second history stop, one back the first, active 100%, nothing below',
    Math.abs(bandAlpha(bands[0].color) - historyStops[0]) < 0.011 &&
    Math.abs(bandAlpha(bands[2].color) - historyStops[1]) < 0.011 &&
    /^rgb\(0, 0, 0\)$/.test(bands[4].color) && /0, 0, 0, 0\)$/.test(bands[6].color));
  const ladder = [0, 1, 1, 2, 2, 3, 3];
  check('mask stops follow the fixed pitch', bands.every((band, i) => Math.abs(band.px - ladder[i] * line) < 1.1));
  check('page has no vertical or horizontal overflow', document.documentElement.scrollHeight === innerHeight && document.documentElement.scrollWidth === innerWidth);
  const top = editor.scrollTop;
  for (const key of ['Backspace', 'Delete', 'ArrowUp', 'PageUp']) {
    const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
    editor.dispatchEvent(event);
    check(key + ' cannot alter draft or scroll position', event.defaultPrevented && editor.value === text && editor.scrollTop === top);
  }
  const cut = new Event('cut', { bubbles: true, cancelable: true });
  editor.dispatchEvent(cut);
  check('cut blocked', cut.defaultPrevented && editor.value === text);
  const animations = editor.closest('.room-paper').getAnimations();
  const hairline = document.querySelector('#room-hairline').getAnimations();
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  check('refusal: 200 ms transform-only shake, or none under Reduce Motion',
    reduced ? animations.length === 0 : animations.length === 1 && animations.every(a => a.effect.getTiming().duration === 200 && a.effect.getKeyframes().every(frame => !frame.opacity)));
  check('refusal: 220 ms opacity-only hairline flash', hairline.length === 1 && hairline.every(a => a.effect.getTiming().duration === 220 && a.effect.getKeyframes().every(frame => !frame.transform)));
  check('reduced motion has no spatial deny', !reduced || animations.length === 0);
  return results;
}
