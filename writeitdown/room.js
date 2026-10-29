import { fresh, advance, append, clock, wordCount, historyLines } from './session.mjs';
import { denyFeedback, LINE_SHIFT_MS, lineShiftProgress } from './feedback.js';
import { statusSlot } from './status-slot.js';

const $ = id => document.getElementById(id);
const room = $('room');
const paper = room.querySelector('.room-paper');
const editor = $('editor');
const ink = $('editor-ink');
const hintSlot = $('exit-hint');
const hairline = $('room-hairline');
const bar = $('room-bar');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const insertions = new Set(['insertText', 'insertParagraph', 'insertLineBreak']);
const SESSION_MS = 60000;
const CONFIRM_MS = 2000;
// A touch screen has no Escape key, however wide it is, so the input names the control it can
// actually press and its confirmation tells that thumb what to do next (D-067).
const touchInput = matchMedia('(hover: none), (any-pointer: coarse)');
const EXIT_LABEL = { keyboard: 'ESC - EXIT', touch: 'EXIT' };
const EXIT_HINT = {
  keyboard: 'Press Esc again to leave and delete the draft.',
  touch: 'Tap EXIT again to leave and delete the draft.'
};
const WARNING = 'KEEP TYPING OR THE DRAFT IS DELETED.';
// The first refused delete of a session names the rule in the footer's status slot for two seconds,
// then the slot goes back to what it held (D-076 amends D-046); later refusals only shake.
const REFUSAL = 'FORWARD ONLY. DELETING IS BLOCKED.';
const REFUSAL_MS = 2000;
const hintFor = () => (touchInput.matches ? EXIT_HINT.touch : EXIT_HINT.keyboard);
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
let inkKey = null;
let refusalNoticed = false;
let refusalTimer = 0;

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
// (the Mac's case 23/51); a new session or Reduce Motion re-anchors it. A wipe drains it:
// the stopped screen carries no frozen instrument as a receipt (D-070).
function syncBar(now) {
  if (state.phase === 'kept' || state.phase === 'wipe') { stepBar(0); return; }
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

// The ink layer repeats the draft one span per logical line, each at its rung of the history ladder
// (D-076). It is rebuilt only when the draft or the composing boundary changes, never per tick.
function paintInk() {
  const base = compositionBase === null ? -1 : compositionBase.length;
  const key = `${base}|${editor.value}`;
  if (key === inkKey) return;
  inkKey = key;
  const value = editor.value;
  const parts = [];
  for (const line of historyLines(value)) {
    const cut = base > line.start && base < line.end ? base : null;
    const pieces = cut === null ? [[line.start, line.end]] : [[line.start, cut], [cut, line.end]];
    for (const [start, end] of pieces) parts.push({ text: value.slice(start, end), rung: line.rung, composing: base >= 0 && start >= base });
  }
  const spans = parts.map(part => {
    const span = document.createElement('span');
    span.dataset.rung = String(part.rung);
    if (part.composing) span.className = 'composing';
    span.textContent = part.text;
    return span;
  });
  // A draft that ends on a hard break owes the textarea's empty last line to the ink layer too.
  ink.replaceChildren(...spans, ...(value.endsWith('\n') ? ['\n'] : []));
}

function setScroll(top) {
  editor.scrollTop = top;
  ink.scrollTop = editor.scrollTop;
}

// A new line shifts the history exactly one pitch, 0.18 s ease-out; typing on the
// same line moves nothing, and Reduce Motion snaps (the Mac's case 48).
function fitEditor({ animate = false } = {}) {
  paintInk();
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
  if (!animate || reduced.matches || Math.abs(target - from) > pitch * 1.5) { setScroll(target); return; }
  const started = performance.now();
  shiftTarget = target;
  shiftRunning = true;
  const shift = now => {
    const progress = Math.min(1, (now - started) / LINE_SHIFT_MS);
    setScroll(from + (target - from) * lineShiftProgress(progress));
    if (progress < 1) shiftFrame = requestAnimationFrame(shift);
    else shiftRunning = false;
  };
  shiftFrame = requestAnimationFrame(shift);
}

function render(now = performance.now()) {
  const previous = room.dataset.phase;
  room.dataset.phase = state.phase;
  if (previous !== state.phase) slot.invalidate();
  // A session that ends (wipe or kept) is spent; the next one earns its own notice.
  if (previous !== state.phase && (state.phase === 'wipe' || state.phase === 'kept')) refusalNoticed = false;
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
  const remaining = state.started === null || failed || kept ? 60 : Math.max(0, Math.ceil((state.started + SESSION_MS - now) / 1000));
  // The clock and the 2 pt bar come off the sheet on the stopped screen instead of freezing
  // as a receipt (D-070); the restart brings both back at a fresh minute.
  $('room-clock').textContent = clock(kept ? 0 : remaining);
  const count = wordCount(state.text);
  const words = `${count} ${count === 1 ? 'word' : 'words'}`;
  // Empty room: the count slot itself carries the instruction; after a wipe the block does,
  // and the slot returns to the count (the Mac's cases 18/19/50). On the kept screen the receipt
  // is the only place the session's size is printed, so the corner stays silent (D-062).
  $('room-count').textContent = kept ? '' : state.started === null && !failed ? 'Type to start' : words;
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
    // The editor keeps focus under the transparent writing layer, so typing restarts in place.
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

// Only an attempt to delete earns the notice: Backspace and Delete keys, and the delete input types
// a touch keyboard sends instead of keys. Paste, cut, undo and caret moves just shake.
const isDeletion = event => (event.type === 'keydown' ? ['Backspace', 'Delete'].includes(event.key) : /^delete/.test(event.inputType ?? ''));

function endRefusalNotice() {
  clearTimeout(refusalTimer);
  if (hintSlot.dataset.kind !== 'refusal') return;
  delete hintSlot.dataset.kind;
  hintSlot.textContent = '';
}

function showRefusalNotice() {
  refusalNoticed = true;
  hintSlot.dataset.kind = 'refusal';
  hintSlot.textContent = REFUSAL;
  clearTimeout(refusalTimer);
  refusalTimer = setTimeout(endRefusalNotice, REFUSAL_MS);
}

function deny(event) {
  event.preventDefault();
  denyFeedback(paper, hairline);
  // An armed exit confirmation is the writer's pending decision and keeps the slot; the notice waits.
  if (!refusalNoticed && exitArmedAt === null && isDeletion(event)) showRefusalNotice();
  else announce('Blocked. Forward only.');
  render();
}

function endCaret() {
  editor.setSelectionRange(editor.value.length, editor.value.length);
}

// The slot holds one thing at a time: arming the exit confirmation takes it from a refusal notice, and
// disarming leaves a notice alone to finish its own two seconds.
function clearExitHint() {
  exitArmedAt = null;
  clearTimeout(exitTimer);
  if (hintSlot.dataset.kind !== 'refusal') hintSlot.textContent = '';
}

// The control and its confirmation wear this input's wording. The confirmation's reserved footer
// row is measured from data-hint, so it follows the copy instead of assuming the desktop one.
function syncExitCopy() {
  const hint = hintFor();
  $('exit').textContent = touchInput.matches ? EXIT_LABEL.touch : EXIT_LABEL.keyboard;
  hintSlot.dataset.hint = hint;
  if (exitArmedAt !== null) hintSlot.textContent = hint;
}

// Escape, EXIT and the brand are one act, and it takes two of them: the first arms the inline
// confirmation for 2 s, the second leaves. Typing cancels it (the Mac's case 26). Nothing can
// leave in one act, so a thumb cannot throw a live draft away (D-061).
function requestExit() {
  if (exitArmedAt !== null && performance.now() - exitArmedAt <= CONFIRM_MS) { clearExitHint(); exit(); return; }
  exitArmedAt = performance.now();
  clearTimeout(refusalTimer);
  delete hintSlot.dataset.kind;
  hintSlot.textContent = hintFor();
  clearTimeout(exitTimer);
  exitTimer = setTimeout(clearExitHint, CONFIRM_MS);
}

function reset() {
  state = fresh();
  copyGeneration++;
  compositionBase = null;
  clearExitHint();
  refusalNoticed = false;
  endRefusalNotice();
  editor.value = '';
  $('kept-text').textContent = '';
  $('receipt').textContent = '';
  $('copy-label').textContent = 'COPY TEXT';
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
  paintInk();
});
// A browser that scrolls the textarea on its own (caret into view) carries the ink layer with it.
editor.addEventListener('scroll', () => { ink.scrollTop = editor.scrollTop; });
editor.addEventListener('keydown', event => {
  if (event.isComposing) return;
  if (state.phase === 'wipe' && (event.key === 'Enter' || event.key === 'NumpadEnter')) { event.preventDefault(); restart(); return; }
  if (['Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'PageUp', 'PageDown'].includes(event.key) || ((event.metaKey || event.ctrlKey) && ['z', 'y', 'x', 'v'].includes(event.key.toLowerCase()))) deny(event);
});
for (const name of ['paste', 'cut', 'drop']) editor.addEventListener(name, deny);
editor.addEventListener('pointerup', () => { if (compositionBase === null) endCaret(); });
$('exit').addEventListener('click', requestExit);
// The brand stays reachable without leaving the writing: the first click arms the same
// confirmation as EXIT, the second returns to the landing. Never a one-click navigation.
$('room-brand').addEventListener('click', event => { event.preventDefault(); requestExit(); });
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
  $('copy-label').textContent = copied ? 'COPIED' : 'TRY AGAIN';
  announce(copied ? 'Copied.' : 'Copy failed. Select your kept text and copy it manually.');
});

// The kept pill keeps the width of its widest label on whatever face the device supplies, so the
// floor is measured from the three labels in that face instead of a constant tuned on one machine
// (D-059). "COPIED" and "TRY AGAIN" only exist after a press, so they cannot be measured from the
// live label, and the probe sits on the body: the room is hidden until the writer opens it, and a
// hidden descendant would measure 0.
const COPY_LABELS = ['COPY TEXT', 'COPIED', 'TRY AGAIN'];
function sizeCopyFloor() {
  const label = $('copy-label');
  const style = getComputedStyle(label);
  const probe = document.createElement('span');
  probe.setAttribute('aria-hidden', 'true');
  probe.style.cssText = 'position:absolute;left:-10000px;top:0;visibility:hidden;white-space:nowrap;'
    + `font-family:${style.fontFamily};font-size:${style.fontSize};font-weight:${style.fontWeight};font-style:${style.fontStyle};`
    + `letter-spacing:${style.letterSpacing};word-spacing:${style.wordSpacing};text-transform:${style.textTransform}`;
  document.body.appendChild(probe);
  let widest = 0;
  for (const text of COPY_LABELS) {
    probe.textContent = text;
    widest = Math.max(widest, probe.getBoundingClientRect().width);
  }
  probe.remove();
  if (widest > 0) label.style.setProperty('--copy-floor', `${Math.ceil(widest)}px`);
}

window.addEventListener('resize', () => { syncExitCopy(); sizeCopyFloor(); slot.invalidate(); fitEditor(); placeStatus(); });
window.visualViewport?.addEventListener('resize', () => { syncExitCopy(); sizeCopyFloor(); slot.invalidate(); fitEditor(); placeStatus(); });
document.fonts.ready.then(() => { syncExitCopy(); sizeCopyFloor(); slot.invalidate(); fitEditor(); placeStatus(); });
touchInput.addEventListener('change', () => { syncExitCopy(); slot.invalidate(); placeStatus(); });
reduced.addEventListener('change', tick);
window.addEventListener('hashchange', route);
window.addEventListener('pagehide', reset);
window.addEventListener('pageshow', event => { if (event.persisted) route(); });
document.addEventListener('visibilitychange', tick);
setInterval(tick, 50);
syncExitCopy();
sizeCopyFloor();
route();
