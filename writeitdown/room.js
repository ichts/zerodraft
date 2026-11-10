import { fresh, advance, append, clock, wordCount, countLabel, historyLines, nextTransition } from './session.mjs';
import { denyFeedback, GROW_MS, LINE_SHIFT_MS, lineShiftProgress } from './feedback.js';
import { statusSlot, placeNote } from './status-slot.js';

const $ = id => document.getElementById(id);
const room = $('room');
const paper = room.querySelector('.room-paper');
const editor = $('editor');
const ink = $('editor-ink');
const hintSlot = $('exit-hint');
const refusalNote = $('refusal-note');
const hairline = $('room-hairline');
const bar = $('room-bar');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const insertions = new Set(['insertText', 'insertParagraph', 'insertLineBreak']);
const SESSION_MS = 60000;
const CONFIRM_MS = 2000;
// A touch screen has no Escape key, however wide it is, so the input names the control it can
// actually press and its confirmation tells that thumb what to do next (D-067).
const touchInput = matchMedia('(hover: none), (any-pointer: coarse)');
const EXIT_LABEL = { keyboard: 'Esc to exit', touch: 'Exit' };
const EXIT_HINT = {
  keyboard: 'Press Esc again to leave and delete the draft.',
  touch: 'Tap EXIT again to leave and delete the draft.'
};
const WARNING = 'KEEP TYPING OR THE DRAFT IS DELETED.';
// The first refused delete of a session names the rule once, centred just under the line being written,
// for two seconds (D-100 moves D-077's notice out of the footer); later refusals only shake.
const REFUSAL = 'You can only add the next word.';
const REFUSAL_MS = 2000;
// The note's baseline sits this far under the live line's baseline, the same on the Mac and Windows rooms.
const REFUSAL_BELOW = 34;
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
// 'webfont' or 'platform', chosen at the first Chinese character of a draft and then fixed until that draft ends
// (D-109). A draft boundary is the room's own empty sheet - the door opening, a restart after a wipe - so a second
// draft on a slow link draws the face that has landed by then instead of the one the first draft had to accept.
let cjkFace = null;

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
  bar.style.clipPath = `inset(0 ${(1 - Math.max(0, Math.min(1, fraction))) * 100}% 0 0)`;
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
  bar.style.clipPath = `inset(0 ${(1 - remaining / SESSION_MS) * 100}% 0 0)`;
  barAnimation = bar.animate([{ clipPath: bar.style.clipPath }, { clipPath: 'inset(0 100% 0 0)' }],
    { duration: remaining, easing: 'linear', fill: 'forwards' });
}

// The ink layer repeats the draft one span per line (ended by Return), each at its rung of the history (D-092). Spans
// are reused and only their rung changes, so the lines above dissolve to their next step through the CSS transition
// the moment Return lands instead of being rebuilt at their final value. It is repainted only when the draft or the
// composing boundary changes, never per tick.
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
  // A draft that ends on a hard break owes the textarea's empty last line to the ink layer too.
  while (ink.lastChild && ink.lastChild.nodeType === Node.TEXT_NODE) ink.lastChild.remove();
  const spans = Array.from(ink.children);
  parts.forEach((part, index) => {
    const span = spans[index] ?? ink.appendChild(document.createElement('span'));
    span.dataset.rung = String(part.rung);
    span.classList.toggle('composing', part.composing);
    if (span.textContent !== part.text) span.textContent = part.text;
  });
  spans.slice(parts.length).forEach(span => span.remove());
  if (value.endsWith('\n')) ink.append('\n');
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
  // A session that ends (wipe or kept) is spent and takes its note with it; the next one earns its own.
  if (previous !== state.phase && (state.phase === 'wipe' || state.phase === 'kept')) refusalNoticed = false;
  // The warning numeral owns the space under the line, so a note still showing steps aside.
  if (previous !== state.phase && state.phase !== 'typing' && state.phase !== 'rest') endRefusalNotice();
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
  const words = countLabel(state.text, count);
  // Empty room: the count slot itself carries the instruction; after a wipe the block does,
  // and the slot returns to the count (the Mac's cases 18/19/50). On the kept screen the receipt
  // is the only place the session's size is printed, so the corner stays silent (D-062).
  $('room-count').textContent = kept ? '' : state.started === null && !failed ? 'Type to begin' : words;
  $('failed').hidden = !failed;
  editor.hidden = kept;
  // The ink layer is the draft's visible paint, so the kept screen hides it with the textarea;
  // left showing, it repeats the draft under the kept block and draws it twice.
  ink.hidden = kept;
  $('kept').hidden = !kept;
  syncBar(now);
  if (warning || failed) placeStatus();
  if (previous === state.phase) return;
  if (warning) announce('Keep typing or the draft is deleted. Three seconds left.');
  if (failed) {
    compositionBase = null;
    cjkFace = null;
    delete room.dataset.cjkFace;
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
    $('receipt').textContent = `${minutes} ${minutes === 1 ? 'minute' : 'minutes'}. ${words}.`;
    placeStatus();
    announce('You wrote it down. Copy your text before you leave. Nothing is saved.');
    $('copy').focus({ preventScroll: true });
  }
}

/* The 50 ms interval draws the clock, but a sample can land up to 50 ms after a transition and its callback can run
   later still, so a transition would wait for the sampler instead of its instant. Both automatic transitions - the
   warning at the fifth second of silence and the end - are absolute times, so they get their own timer, armed from
   `nextTransition` after every tick (D-111, D-112). Re-arming on each tick also means drift never accumulates: each
   arm is measured from the clock, not from the previous timer. */
let deadlineTimer = 0;
function armDeadline() {
  clearTimeout(deadlineTimer);
  const next = nextTransition(state);
  deadlineTimer = next === null ? 0 : setTimeout(() => { deadlineTimer = 0; tick(); }, Math.max(1, Math.ceil(next - performance.now())));
}

function tick() {
  if (room.hidden) return;
  const now = performance.now();
  state = advance(state, now);
  render(now);
  armDeadline();
}

// Only an attempt to delete earns the notice: Backspace and Delete keys, and the delete input types
// a touch keyboard sends instead of keys. Paste, cut, undo and caret moves just shake.
const isDeletion = event => (event.type === 'keydown' ? ['Backspace', 'Delete'].includes(event.key) : /^delete/.test(event.inputType ?? ''));

function placeRefusalNote() {
  placeNote({ paper, line: editor, pitches: 2, note: refusalNote, below: REFUSAL_BELOW });
}

function endRefusalNotice() {
  clearTimeout(refusalTimer);
  refusalNote.dataset.shown = 'false';
}

function showRefusalNotice() {
  refusalNoticed = true;
  refusalNote.textContent = REFUSAL;
  placeRefusalNote();
  refusalNote.dataset.shown = 'true';
  announce(REFUSAL);
  clearTimeout(refusalTimer);
  refusalTimer = setTimeout(endRefusalNotice, REFUSAL_MS);
}

function deny(event) {
  event.preventDefault();
  denyFeedback(paper, hairline);
  // Only a live line has room under it: on the warning and the stopped screen the notice waits unspent.
  if (!refusalNoticed && (state.phase === 'typing' || state.phase === 'rest') && isDeletion(event)) showRefusalNotice();
  else announce('Blocked. Forward only.');
  render();
}

function endCaret() {
  editor.setSelectionRange(editor.value.length, editor.value.length);
}

function clearExitHint() {
  exitArmedAt = null;
  clearTimeout(exitTimer);
  hintSlot.textContent = '';
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
  hintSlot.textContent = hintFor();
  clearTimeout(exitTimer);
  exitTimer = setTimeout(clearExitHint, CONFIRM_MS);
}

function reset() {
  state = fresh();
  copyGeneration++;
  compositionBase = null;
  cjkFace = null;
  delete room.dataset.cjkFace;
  clearExitHint();
  refusalNoticed = false;
  endRefusalNotice();
  editor.value = '';
  $('kept-text').textContent = '';
  $('receipt').textContent = '';
  $('copy-label').textContent = 'Copy text';
  $('status').textContent = '';
  render();
  fitEditor();
}

function restart() {
  clearExitHint();
  reset();
  editor.focus({ preventScroll: true });
}

let routed = false;
let growing = [];
// The moment the door's grow stops owning the main thread; the font engine waits for it (D-109).
let growUntil = 0;

// The door opens (D-097): the room's paper is the landing's demo paper grown, and the brand row slides to its
// place, instead of the demo vanishing and a new paper appearing 160 px away. Only transforms and an opacity
// fade run; the room's layout is final from the first frame, so the editor is live at once.
function boxes() {
  const rect = selector => document.querySelector(selector)?.getBoundingClientRect();
  return { paper: rect('#landing #paper'), brand: rect('#landing .home-nav .brand'), end: rect('#landing .home-nav .nav-end') };
}

const inView = r => r && r.width > 0 && r.bottom > 0 && r.top < innerHeight;

function growInto(from) {
  if (reduced.matches || !inView(from.paper)) return;
  // The site's one ease-out (tokens.css), the same curve the Mac grow uses.
  const easing = getComputedStyle(paper).getPropertyValue('--ease-out').trim() || 'ease-out';
  const options = { duration: GROW_MS, easing };
  const to = paper.getBoundingClientRect();
  if (!to.width || !to.height) return;
  growing.push(paper.animate([
    { transformOrigin: '0 0', transform: `translate(${from.paper.left - to.left}px, ${from.paper.top - to.top}px) scale(${from.paper.width / to.width}, ${from.paper.height / to.height})` },
    { transformOrigin: '0 0', transform: 'none' }
  ], options));
  for (const el of paper.children) {
    if (el.hidden || el.matches('.sheet-paper, .bar, .wash, .hairline')) continue;
    const end = getComputedStyle(el).opacity;
    growing.push(el.animate([{ opacity: 0 }, { opacity: end }],
      { duration: GROW_MS * 0.7, delay: GROW_MS * 0.3, easing: 'ease-out', fill: 'backwards' }));
  }
  for (const [selector, was] of [['.room-nav .brand', from.brand], ['.room-nav .nav-end', from.end]]) {
    const el = room.querySelector(selector);
    const now = el.getBoundingClientRect();
    if (!inView(was) || !now.width) continue;
    growing.push(el.animate([{ transform: `translate(${was.left - now.left}px, ${was.top - now.top}px)` }, { transform: 'none' }], options));
  }
  // Named so the browser suite can wait for the door to finish before it measures geometry.
  for (const a of growing) a.id = 'door';
}

function route() {
  const returning = !room.hidden;
  const active = location.hash === '#trial';
  growing.forEach(a => a.cancel());
  growing = [];
  growUntil = 0;
  const from = active && !returning && routed ? boxes() : null;
  document.documentElement.classList.toggle('in-trial', active);
  $('landing').hidden = active;
  room.hidden = !active;
  routed = true;
  slot.invalidate();
  reset();
  if (active) {
    fitEditor();
    editor.focus({ preventScroll: true });
    if (from) { growInto(from); growUntil = performance.now() + GROW_MS; }
    warmRoomFace();
  }
  else if (returning) document.querySelector('#landing a[href="#trial"]').focus({ preventScroll: true });
}

// Chinese is one GB2312 file and a draft draws it in exactly one face (D-109). Which face is decided at the draft's
// first Chinese character and never revisited until the sheet is empty again: Zhuque if its bytes are already
// resident, the platform serif if they are not. That decision is what makes both promises true at once - the
// character is on the sheet at once, and no character ever changes face afterwards no matter when the file lands.
// `font-display:swap` in `fonts-cjk.css` is the second guard under the same promise: a path that painted Chinese
// without reaching this decision falls back to visible text, never to an invisible one.
//
// Chrome cannot be trusted with `font-display:optional` here: it abandons an optional face for the whole document at
// the first paint that happens without it, and it then keeps the platform face even when the file has been resident
// for seconds before the first Chinese character (measured, and held in `qa/chinese-face.spec.mjs`).
function adoptCjkFace(text) {
  if (cjkFace || !/[\u3400-\u9fff\uf900-\ufaff]/.test(text)) return;
  const face = [...document.fonts].find(candidate => candidate.family.includes('Zhuque Fangsong'));
  cjkFace = face?.status === 'loaded' ? 'webfont' : 'platform';
  room.dataset.cjkFace = cjkFace;
}

// The room asks the font engine for the face as its route opens, in the second a writer spends reading the empty
// sheet; a trial link that has already shown intent has asked earlier (prefetchRoomFace), so the face is normally
// resident before the first keystroke. Nothing on the landing asks for it, and the landing draws no Chinese
// (D-057). The request waits out the door's own grow: decoding 2.5 MB of font is main-thread work and the grow owns
// those 240 ms.
let faceWarmed = false;
let faceTimer = 0;
function askForRoomFace() {
  if (faceWarmed || !document.fonts?.load) return;
  // Decoding 2.5 MB is main-thread work and the door's grow owns the 240 ms after the route opens, so the ask
  // (however early the bytes arrived) lands after it. One rule, whichever path got here.
  const wait = growUntil - performance.now();
  if (wait > 0) {
    clearTimeout(faceTimer);
    faceTimer = setTimeout(askForRoomFace, Math.ceil(wait) + 20);
    return;
  }
  faceWarmed = true;
  document.fonts.load('28px "Zhuque Fangsong"', '我').catch(() => {});
}

function warmRoomFace() {
  // A prefetch already in flight asks the font engine itself when its bytes land; asking here as well would send the
  // same 2.5 MB twice on the link that can least afford it.
  if (faceAsked) return;
  askForRoomFace();
}

// The face is 2,589,548 B and it belongs to the room, not to the landing: a visitor who reads and leaves pays none
// of it. Intent on a trial link - pointer, touch or focus - starts the fetch while they read, so on a slow link the
// file is already arriving when the door opens instead of starting then (D-109). It runs after the frame that
// painted the intent and on an idle main thread, so it can never delay first paint, LCP or the door's grow.
// Two steps, because they have different priorities and only a preload can be told to be low: the bytes travel as a
// low-priority preload (the only request on the wire, and `document.fonts.load()` here would be VeryHigh and would
// compete with the landing's own paint), then the idle main thread hands those cached bytes to the font engine so
// the first character finds a resident face instead of paying for the decode under the door.
let faceAsked = false;

// The face's file name lives in the generated `fonts-cjk.css`, so the preload reads it from there instead of
// repeating a second copy that a rebuild could leave pointing at a file that no longer exists.
function faceFile() {
  for (const sheet of document.styleSheets) {
    let rules;
    try { rules = sheet.cssRules; } catch { continue; }
    for (const rule of rules) {
      if (rule.constructor.name !== 'CSSFontFaceRule' || !rule.style.fontFamily.includes('Zhuque Fangsong')) continue;
      const url = rule.style.src.match(/url\(["']?([^"')]+)["']?\)/);
      if (url) return url[1];
    }
  }
  return null;
}

const whenIdle = run => (window.requestIdleCallback || (later => setTimeout(later, 0)))(run, { timeout: 2000 });

function prefetchRoomFace() {
  if (faceAsked || faceWarmed || !room.hidden) return;
  const href = faceFile();
  if (!href) return;
  faceAsked = true;
  const link = document.createElement('link');
  link.rel = 'preload';
  link.as = 'font';
  link.type = 'font/woff2';
  // A font preload without crossOrigin is a different fetch from the font request and is made twice;
  // fetchpriority is the only lever that keeps the 2.5 MB off the landing's critical path.
  link.crossOrigin = 'anonymous';
  link.setAttribute('fetchpriority', 'low');
  link.addEventListener('load', () => whenIdle(askForRoomFace), { once: true });
  link.href = href;
  document.head.append(link);
}

function prefetchSoon() {
  requestAnimationFrame(() => whenIdle(prefetchRoomFace));
}

for (const entry of document.querySelectorAll('#landing a[href="#trial"]')) {
  for (const type of ['pointerenter', 'pointerdown', 'touchstart', 'focus']) {
    entry.addEventListener(type, prefetchSoon, { once: true, passive: true });
  }
}

// The room's sheet is hidden until the door opens, so its texture used to be painted on the page in the click's
// own task - a 4 MP canvas, over a second on a 2x screen (D-103). Instead the room is measured while it is
// hidden (shown and hidden again inside one task, so no frame sees it) and paper.js's worker textures the sheet
// at exactly that size before anyone clicks. The click then finds the sheet painted.
function warmPaper() {
  if (!room.hidden || !window.WriteItDownPaper) return;
  const root = document.documentElement;
  const focused = document.activeElement;
  const { scrollX, scrollY } = window;
  root.classList.add('in-trial');
  room.hidden = false;
  const [width, height] = [paper.clientWidth, paper.clientHeight];
  room.hidden = true;
  root.classList.remove('in-trial');
  // The in-trial page does not scroll, so the landing's offset would be lost with it.
  if (window.scrollY !== scrollY) window.scrollTo({ left: scrollX, top: scrollY, behavior: 'instant' });
  if (document.activeElement !== focused) focused?.focus?.({ preventScroll: true });
  window.WriteItDownPaper.warm(paper, width, height);
}

let warmTimer = 0;
function warmSoon(delay = 200) {
  clearTimeout(warmTimer);
  warmTimer = setTimeout(() => (window.requestIdleCallback || (f => f()))(warmPaper, { timeout: 500 }), delay);
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
  adoptCjkFace(addition);
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
  $('copy-label').textContent = copied ? 'Copied' : 'Try copy again';
  announce(copied ? 'Copied.' : 'Copy failed. Select your kept text and copy it manually.');
});

// The kept pill keeps the width of its widest label on whatever face the device supplies, so the
// floor is measured from the three labels in that face instead of a constant tuned on one machine
// (D-059). "Copied" and "Try copy again" only exist after a press, so they cannot be measured from the
// live label, and the probe sits on the body: the room is hidden until the writer opens it, and a
// hidden descendant would measure 0.
const COPY_LABELS = ['Copy text', 'Copied', 'Try copy again'];
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

window.addEventListener('resize', () => { warmSoon(); syncExitCopy(); sizeCopyFloor(); slot.invalidate(); fitEditor(); placeStatus(); });
window.visualViewport?.addEventListener('resize', () => { warmSoon(); syncExitCopy(); sizeCopyFloor(); slot.invalidate(); fitEditor(); placeStatus(); });
document.fonts.ready.then(() => { syncExitCopy(); sizeCopyFloor(); slot.invalidate(); fitEditor(); placeStatus(); });
touchInput.addEventListener('change', () => { syncExitCopy(); slot.invalidate(); placeStatus(); });
reduced.addEventListener('change', tick);
window.addEventListener('hashchange', route);
window.addEventListener('pagehide', reset);
window.addEventListener('pageshow', event => { if (event.persisted) route(); });
document.addEventListener('visibilitychange', tick);
setInterval(tick, 50);
new MutationObserver(() => warmSoon()).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
syncExitCopy();
sizeCopyFloor();
route();
warmSoon(0);
