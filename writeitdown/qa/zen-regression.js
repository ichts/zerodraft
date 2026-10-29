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
  // D-076: the aperture is one hard clip at the third pitch, and the history steps live on the ink layer's
  // spans, one per logical line. The contrast floor itself is owned by qa/paper.spec.mjs.
  const stackStyle = getComputedStyle(editor.closest('.editor-stack'));
  const mask = stackStyle.maskImage || stackStyle.webkitMaskImage;
  const stops = [...mask.matchAll(/([\d.]+)px/g)].map(m => parseFloat(m[1]));
  check('aperture is one hard clip at the third pitch, not a gradient', stops.length === 2 && stops.every(px => Math.abs(px - 3 * line) < 1.1));
  const ink = document.getElementById('editor-ink');
  const spans = [...ink.querySelectorAll('[data-rung]')];
  check('ink layer repeats the draft, one span per logical line', spans.length > 61 && ink.textContent.replace(/\n$/, '') === text);
  const opacityOf = rung => spans.filter(span => span.dataset.rung === String(rung)).map(span => Number(getComputedStyle(span).opacity));
  const historyStops = [Number(css.getPropertyValue('--paper-history-1')), Number(css.getPropertyValue('--paper-history-2'))];
  check('active line 100%, one back the first history stop, two back the second, older gone',
    opacityOf(0).length === 1 && opacityOf(0)[0] === 1 &&
    opacityOf(1).length === 1 && Math.abs(opacityOf(1)[0] - historyStops[0]) < 0.011 &&
    opacityOf(2).length === 1 && Math.abs(opacityOf(2)[0] - historyStops[1]) < 0.011 &&
    opacityOf(3).length === spans.length - 3 && opacityOf(3).every(opacity => opacity === 0));
  check('the textarea itself paints no glyphs, so the ink layer is the only text', getComputedStyle(editor).color === 'rgba(0, 0, 0, 0)');
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
