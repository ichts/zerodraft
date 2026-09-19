async () => {
  const editor = document.getElementById('editor');
  const room = document.getElementById('room');
  const count = document.getElementById('room-count');
  const results = [];
  const check = (name, ok) => {
    results.push({ name, pass: Boolean(ok) });
    if (!ok) throw new Error(name);
  };
  const reset = () => document.getElementById('restart').click();
  const input = (text, inputType = 'insertText', isComposing = false) => {
    editor.value += text;
    editor.dispatchEvent(new InputEvent('input', { bubbles: true, data: text, inputType, isComposing }));
  };
  reset();
  check('empty', count.textContent === '0 WORDS');
  input('hello world');
  check('Latin', count.textContent === '2 WORDS');
  input(' 中文测试');
  check('mixed Latin and Chinese', count.textContent === '6 WORDS');
  input('，！？ 👨‍👩‍👧‍👦 👍🏽');
  check('punctuation and emoji excluded, graphemes retained', count.textContent === '6 WORDS' && editor.value.endsWith('👍🏽'));
  const original = editor.value;
  for (const type of ['deleteContentBackward', 'insertFromPaste', 'historyUndo', 'insertFromDrop']) {
    const event = new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: type });
    editor.dispatchEvent(event);
    check(type + ' blocked', event.defaultPrevented && editor.value === original);
  }
  editor.setSelectionRange(0, 5);
  const before = new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'insertText', data: 'x' });
  editor.dispatchEvent(before);
  check('selection moved to end before insertion', editor.selectionStart === original.length && editor.selectionEnd === original.length);
  reset();
  editor.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
  input('n', 'insertCompositionText', true);
  check('composition starts session', room.dataset.phase === 'typing');
  editor.value = '你';
  editor.dispatchEvent(new InputEvent('input', { bubbles: true, data: '你', inputType: 'insertCompositionText', isComposing: true }));
  check('composition replacement not denied', editor.value === '你' && count.textContent === '1 WORD');
  editor.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '你' }));
  input('好');
  check('composition commit plus next character', editor.value === '你好' && count.textContent === '2 WORDS');
  reset();
  input(' \n\t');
  check('whitespace excluded', count.textContent === '0 WORDS');
  reset();
  check('no horizontal overflow', document.documentElement.scrollWidth === innerWidth);
  check('entry/restart focuses editor', document.activeElement === editor);
  return results;
}
