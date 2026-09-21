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
  check('surrounding lines masked, active band opaque', css.maskImage.includes('40%') && css.maskImage.includes('60%'));
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
  check('deny feedback holds for 280ms without restarting on repeat', animations.length > 0 && animations.every(a => a.effect.getTiming().duration === 280));
  check('reduced motion has no spatial deny', !matchMedia('(prefers-reduced-motion: reduce)').matches || animations.every(a => a.effect.getKeyframes().every(frame => !frame.transform)));
  return results;
}
