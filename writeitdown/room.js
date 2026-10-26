import { fresh, advance, append, clock, wordCount } from './session.mjs';
import { denyFeedback, LINE_SHIFT_MS, lineShiftProgress } from './feedback.js';
import { statusSlot } from './status-slot.js';

const $ = id => document.getElementById(id);
const room = $('room');
const paper = room.querySelector('.room-paper');
const editor = $('editor');
const hairline = $('room-hairline');
const bar = $('room-bar');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const insertions = new Set(['insertText', 'insertParagraph', 'insertLineBreak']);
const SESSION_MS = 60000;
const CONFIRM_MS = 2000;
const EXIT_HINT = 'Press Esc again to leave and delete the draft.';
const WARNING = 'KEEP TYPING OR THE DRAFT IS DELETED.';
$('exit-hint').dataset.hint = EXIT_HINT;
let state = fresh();
let compositionBase = null;
let copyGeneration = 0;
let exitArmedAt = null;
let exitTimer = 0;
let barAnimation = null;
let barStarted = null;
let barSteppedAt = -Infinity;
let shiftFrame = 0;
let shiftRunning = false;
let shiftTarget = -1;

function announce(text) {
  if ($('status').textContent !== text) $('status').textContent = text;
}

const slot = statusSlot({
  paper,
  line: editor,
  pitches: 2,
  numeral: $('room-numeral'),
  caption: $('room-warning'),
  block: $('failed')
});

function placeStatus() {
  if (!room.hidden) slot.place();
}

// --- Bar, history shift, session state ---------------------------------------
function stepBar(fraction) {
  barAnimation?.cancel();
  barAnimation = null;
  bar.style.transform = `scaleX(${Math.max(0, Math.min(1, fraction))})`;
}

// One continuous linear fill over the remaining session time. Ticks never step it
// (the Mac's case 23/51); a new session or Reduce Motion re-anchors it. A wipe stops it
// where the session stopped, so the bar carries the deletion instead of emptying (D-056).
function syncBar(now) {
  if (state.phase === 'kept') { stepBar(0); return; }
  if (state.phase === 'wipe') { stepBar(state.unused / (SESSION_MS / 1000)); return; }
  if (state.started === null) { stepBar(1); return; }
  const remaining = Math.max(0, state.started + SESSION_MS - now);
  if (reduced.matches) {
    if (barAnimation || barStarted !== state.started || now - barSteppedAt >= 500) {
      barStarted = state.started;
      barSteppedAt = now;
      stepBar(remaining / SESSION_MS);
    }
    return;
  }
  if (barAnimation && barStarted === state.started) return;
  barAnimation?.cancel();
  barStarted = state.started;
  bar.style.transform = `scaleX(${remaining / SESSION_MS})`;
  barAnimation = bar.animate([{ transform: bar.style.transform }, { transform: 'scaleX(0)' }],
    { duration: remaining, easing: 'linear', fill: 'forwards' });
}

// A new line shifts the history exactly one pitch, 0.18 s ease-out; typing on the
// same line moves nothing, and Reduce Motion snaps (the Mac's case 48).
function fitEditor({ animate = false } = {}) {
  const target = Math.max(0, editor.scrollHeight - editor.clientHeight);
  // A shift already heading for the same target keeps going, so typing on the same
  // line does not snap a half-finished move; anything else re-anchors here.
  if (shiftRunning && target === shiftTarget) return;
  cancelAnimationFrame(shiftFrame);
  shiftRunning = false;
  const from = editor.scrollTop;
  if (target === from) return;
  const pitch = parseFloat(getComputedStyle(editor).lineHeight);
  // Only a new line (one pitch) animates; a wholesale replacement such as a restore
  // or a test's programmatic insert snaps, so the draft is never left mid-way.
  if (!animate || reduced.matches || Math.abs(target - from) > pitch * 1.5) { editor.scrollTop = target; return; }
  const started = performance.now();
  shiftTarget = target;
  shiftRunning = true;
  const shift = now => {
    const progress = Math.min(1, (now - started) / LINE_SHIFT_MS);
    editor.scrollTop = from + (target - from) * lineShiftProgress(progress);
    if (progress < 1) shiftFrame = requestAnimationFrame(shift);
    else shiftRunning = false;
  };
  shiftFrame = requestAnimationFrame(shift);
}

function render(now = performance.now()) {
  const previous = room.dataset.phase;
  room.dataset.phase = state.phase;
  if (previous !== state.phase) slot.invalidate();
  const failed = state.phase === 'wipe';
  const kept = state.phase === 'kept';
  const cut = failed && now - state.ended < 200;
  room.dataset.cut = String(cut);
  const warning = state.phase === 'warn';
  const strength = cut ? 1 : warning ? reduced.matches ? 1 : (now - state.lastInput - 5000) / 3000 : 0;
  paper.querySelectorAll('.wash').forEach(wash => { wash.style.opacity = strength; });
  $('room-numeral').textContent = warning ? String(Math.ceil((state.lastInput + 8000 - now) / 1000)) : '';
  $('room-warning').textContent = warning ? WARNING : '';
  $('room-danger').hidden = !warning;
  const remaining = state.started === null ? 60 : Math.max(0, Math.ceil((state.started + SESSION_MS - now) / 1000));
  // The clock is the receipt after a wipe: it holds the unused time the session stopped at
  // instead of resetting to a fresh minute, and a new session puts it back to 1:00 (D-056).
  $('room-clock').textContent = clock(failed ? state.unused : kept ? 0 : remaining);
  const count = wordCount(state.text);
  const words = `${count} ${count === 1 ? 'word' : 'words'}`;
  // Empty room: the count slot itself carries the instruction; after a wipe the block does,
  // and the slot returns to the count (the Mac's cases 18/19/50).
  $('room-count').textContent = state.started === null && !failed ? 'Type to start' : words;
  $('failed').hidden = !failed;
  editor.hidden = kept;
  $('kept').hidden = !kept;
  syncBar(now);
  if (warning || failed) placeStatus();
  if (previous === state.phase) return;
  if (warning) announce('Keep typing or the draft is deleted. Three seconds left.');
  if (failed) {
    compositionBase = null;
    editor.value = '';
    fitEditor();
    // The wiped room keeps the caret on the line, exactly as the empty room does.
    editor.focus({ preventScroll: true });
    announce(`You stopped. Draft deleted. ${clock(state.unused)} unused.`);
  }
  if (kept) {
    compositionBase = null;
    $('kept-text').textContent = state.text;
    const minutes = Math.max(Math.round((state.ended - state.started) / 60000), 1);
    $('receipt').textContent = `${minutes} ${minutes === 1 ? 'MINUTE' : 'MINUTES'}. ${count} ${count === 1 ? 'WORD' : 'WORDS'}.`;
    placeStatus();
    announce('You wrote it down. Copy your text before you leave. Nothing is saved.');
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
  denyFeedback(paper, hairline);
  announce('Blocked. Forward only.');
  render();
}

function endCaret() {
  editor.setSelectionRange(editor.value.length, editor.value.length);
}

function clearExitHint() {
  exitArmedAt = null;
  clearTimeout(exitTimer);
  $('exit-hint').textContent = '';
}

// Escape and EXIT are one act, and it takes two of them: the first arms the inline
// confirmation for 2 s, the second leaves. Typing cancels it (the Mac's case 26).
function requestExit() {
  if (exitArmedAt !== null && performance.now() - exitArmedAt <= CONFIRM_MS) { clearExitHint(); exit(); return; }
  exitArmedAt = performance.now();
  $('exit-hint').textContent = EXIT_HINT;
  clearTimeout(exitTimer);
  exitTimer = setTimeout(clearExitHint, CONFIRM_MS);
}

function reset() {
  state = fresh();
  copyGeneration++;
  compositionBase = null;
  clearExitHint();
  editor.value = '';
  $('kept-text').textContent = '';
  $('receipt').textContent = '';
  $('copy').textContent = 'COPY TEXT';
  $('status').textContent = '';
  render();
  fitEditor();
}

function restart() {
  clearExitHint();
  reset();
  editor.focus({ preventScroll: true });
}

function route() {
  const returning = !room.hidden;
  const active = location.hash === '#trial';
  document.documentElement.classList.toggle('in-trial', active);
  $('landing').hidden = active;
  room.hidden = !active;
  slot.invalidate();
  reset();
  if (active) { fitEditor(); editor.focus({ preventScroll: true }); }
  else if (returning) document.querySelector('#landing a[href="#trial"]').focus({ preventScroll: true });
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
  clearExitHint();
  endCaret();
});

editor.addEventListener('input', event => {
  tick();
  clearExitHint();
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
  fitEditor({ animate: true });
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
  if (state.phase === 'wipe' && (event.key === 'Enter' || event.key === 'NumpadEnter')) { event.preventDefault(); restart(); return; }
  if (['Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'PageUp', 'PageDown'].includes(event.key) || ((event.metaKey || event.ctrlKey) && ['z', 'y', 'x', 'v'].includes(event.key.toLowerCase()))) deny(event);
});
for (const name of ['paste', 'cut', 'drop']) editor.addEventListener(name, deny);
editor.addEventListener('pointerup', () => { if (compositionBase === null) endCaret(); });
$('exit').addEventListener('click', requestExit);
$('begin-again').addEventListener('click', restart);
$('restart').addEventListener('click', restart);
paper.addEventListener('pointerdown', event => {
  if (state.phase === 'kept' || event.target.closest('button, a, textarea, input, select, label')) return;
  event.preventDefault();
  editor.focus({ preventScroll: true });
});
// Switching theme from the room header hands the keyboard straight back to the writing.
room.querySelector('[data-theme-toggle]').addEventListener('click', () => {
  if (state.phase !== 'kept') editor.focus({ preventScroll: true });
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !event.isComposing && !room.hidden) requestExit();
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

window.addEventListener('resize', () => { slot.invalidate(); fitEditor(); placeStatus(); });
window.visualViewport?.addEventListener('resize', () => { slot.invalidate(); fitEditor(); placeStatus(); });
document.fonts.ready.then(() => { slot.invalidate(); fitEditor(); placeStatus(); });
reduced.addEventListener('change', tick);
window.addEventListener('hashchange', route);
window.addEventListener('pagehide', reset);
window.addEventListener('pageshow', event => { if (event.persisted) route(); });
document.addEventListener('visibilitychange', tick);
setInterval(tick, 50);
route();
