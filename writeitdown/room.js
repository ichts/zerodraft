import { fresh, advance, append, clock, wordCount } from './session.mjs';

const $ = id => document.getElementById(id);
const room = $('room');
const editor = $('editor');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const insertions = new Set(['insertText', 'insertParagraph', 'insertLineBreak']);
let state = fresh();
let compositionBase = null;
let deniedUntil = 0;
let copyGeneration = 0;

function announce(text) {
  if ($('status').textContent !== text) $('status').textContent = text;
}

function render(now = performance.now()) {
  const previous = room.dataset.phase;
  room.dataset.phase = state.phase;
  const kept = state.phase === 'kept';
  const cut = state.phase === 'wipe' && now - state.ended < 200;
  room.dataset.cut = String(cut);
  const warning = state.phase === 'warn';
  const strength = cut ? 1 : warning ? reduced.matches ? 1 : (now - state.lastInput - 5000) / 3000 : 0;
  room.querySelectorAll('.wash').forEach(wash => { wash.style.opacity = strength; });
  $('room-numeral').textContent = warning ? String(Math.ceil((state.lastInput + 8000 - now) / 1000)) : '';
  $('room-warning').textContent = warning ? 'KEEP TYPING OR THE DRAFT IS DELETED.' : '';
  const remaining = kept ? 0 : state.started === null ? 60 : Math.max(0, Math.ceil((state.started + 60000 - now) / 1000));
  $('room-clock').textContent = clock(remaining);
  const count = wordCount(state.text);
  const words = `${count} ${count === 1 ? 'WORD' : 'WORDS'}`;
  $('room-count').textContent = words;
  $('room-report').textContent = state.phase === 'wipe' ? `DRAFT WIPED - ${clock(state.unused)} UNUSED. TYPE TO RESTART.` : '';
  editor.hidden = kept;
  $('kept').hidden = !kept;
  room.dataset.denied = String(now < deniedUntil);
  if (previous === state.phase) return;
  if (warning) announce('Keep typing or the draft is deleted. Three seconds left.');
  if (state.phase === 'wipe') {
    compositionBase = null;
    editor.value = '';
    editor.blur();
    editor.focus({ preventScroll: true });
    announce($('room-report').textContent);
  }
  if (kept) {
    compositionBase = null;
    $('kept-text').textContent = state.text;
    $('receipt').textContent = `0:00 - ${words} KEPT.`;
    announce('You wrote it down. Copy your text before leaving.');
    $('copy').focus({ preventScroll: true });
  }
}

function tick() {
  if (room.hidden) return;
  const now = performance.now();
  state = advance(state, now);
  render(now);
}

function deny(event) {
  event.preventDefault();
  deniedUntil = performance.now() + 160;
  announce('BLOCKED. FORWARD ONLY.');
  render();
}

function endCaret() {
  editor.setSelectionRange(editor.value.length, editor.value.length);
}

function reset() {
  state = fresh();
  copyGeneration++;
  compositionBase = null;
  editor.value = '';
  $('kept-text').textContent = '';
  $('receipt').textContent = '';
  $('copy').textContent = 'COPY TEXT';
  $('status').textContent = '';
  render();
}

function route() {
  const returning = !room.hidden;
  const active = location.hash === '#trial';
  $('landing').hidden = active;
  room.hidden = !active;
  reset();
  if (active) editor.focus({ preventScroll: true });
  else if (returning) document.querySelector('.door').focus({ preventScroll: true });
}

function exit() {
  history.replaceState(null, '', location.pathname + location.search);
  route();
}

editor.addEventListener('beforeinput', event => {
  tick();
  if (state.phase === 'kept') { event.preventDefault(); return; }
  if (event.isComposing || /Composition/.test(event.inputType)) return;
  if (!insertions.has(event.inputType)) {
    deny(event);
    return;
  }
  endCaret();
});

editor.addEventListener('input', event => {
  tick();
  if (state.phase === 'kept') { editor.value = state.text; return; }
  const base = compositionBase ?? state.text;
  const composing = event.isComposing || /Composition/.test(event.inputType);
  if ((!composing && !insertions.has(event.inputType)) || !editor.value.startsWith(base)) {
    editor.value = state.text;
    endCaret();
    deny(event);
    return;
  }
  const addition = editor.value.slice(base.length);
  if (compositionBase !== null) {
    const active = append(state, addition || event.data || '', performance.now());
    state = { ...active, text: editor.value };
  } else state = append(state, addition, performance.now());
  render();
  editor.scrollTop = editor.scrollHeight;
});

editor.addEventListener('compositionstart', () => {
  tick();
  endCaret();
  compositionBase = state.text;
});
editor.addEventListener('compositionend', () => {
  compositionBase = null;
  endCaret();
});
editor.addEventListener('keydown', event => {
  if (event.isComposing) return;
  if (['Backspace', 'Delete'].includes(event.key) || ((event.metaKey || event.ctrlKey) && ['z', 'y', 'x', 'v'].includes(event.key.toLowerCase()))) deny(event);
});
for (const name of ['paste', 'cut', 'drop']) editor.addEventListener(name, deny);
editor.addEventListener('pointerup', () => { if (compositionBase === null) endCaret(); });
$('exit').addEventListener('click', exit);
$('restart').addEventListener('click', () => { reset(); editor.focus(); });
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !event.isComposing && !room.hidden) exit();
});

function fallbackCopy(text) {
  const field = document.createElement('textarea');
  field.value = text;
  field.setAttribute('readonly', '');
  field.style.cssText = 'position:fixed;top:0;left:-9999px';
  document.body.append(field);
  field.select();
  const copied = document.execCommand('copy');
  field.remove();
  $('copy').focus();
  if (!copied) throw new Error('Clipboard unavailable');
}

$('copy').addEventListener('click', async () => {
  const generation = copyGeneration;
  const text = state.text;
  let copied = false;
  try {
    await navigator.clipboard.writeText(text);
    copied = true;
  } catch {
    try { fallbackCopy(text); copied = true; } catch {}
  }
  if (generation !== copyGeneration) return;
  $('copy').textContent = copied ? 'COPIED' : 'TRY COPY AGAIN';
  announce(copied ? 'Copied.' : 'Copy failed. Select your kept text and copy it manually.');
});

window.addEventListener('hashchange', route);
window.addEventListener('pagehide', reset);
window.addEventListener('pageshow', event => { if (event.persisted) route(); });
document.addEventListener('visibilitychange', tick);
setInterval(tick, 50);
route();
