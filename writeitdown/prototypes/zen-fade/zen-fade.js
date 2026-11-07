// Zen fade options prototype: five panels, one keystroke feed. [POS] throwaway evidence page for the captain's pick;
// it shares the room's pitch, shift easing, tokens and Wheat sheet and nothing else. Not shipped (install.sh does not copy it).
import { LINE_SHIFT_MS, lineShiftProgress } from '../../feedback.js';

const VARIANTS = [
  ['old', 'Keep', 'the old mask, unchanged: one gradient on the aperture box'],
  ['a', 'A', 'the old mask, hung on the live line - Return moves it one line'],
  ['b', 'B', 'old gradient numbers, one opacity per Return line, dissolving'],
  ['c', 'C', 'flat dim like iA Writer, Typora, Calmly Writer'],
  ['now', 'Now', 'main today (D-088): Return ladder 100 / 84.7 / 76.9 / 0']
];
const TEXT = {
  en: ['I keep telling myself the deadline is somewhere far away.',
    'It is not. It is in the next room, kettle already on.',
    'This one runs long on purpose, so it wraps across the sheet and the fade has to decide what a line is before the writer ever presses Return.',
    'Then Return.',
    'And again, the last line, still live.'],
  zh: ['我总告诉自己，截止日期还很远。',
    '其实不远，它就在隔壁房间，水已经烧上了。',
    '这一行故意写得很长，长到要在纸上折成两行三行，这样淡出就得先想清楚什么才算一行，而写的人还没有按下回车。',
    '然后回车。',
    '再来一行，这是最后一行，还活着。']
};
const params = new URLSearchParams(location.search);
const only = params.get('only');
const num = (key, fallback) => (params.has(key) ? Number(params.get(key)) : fallback);
const knobs = { h1: num('h1', .22), h2: num('h2', .07), flat: num('flat', .25), ms: num('ms', 320) };
if (params.get('theme') === 'dark') document.documentElement.dataset.theme = 'dark';
if (only) document.body.dataset.only = only;

const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function panel([id, name, note]) {
  const root = document.createElement('section');
  root.className = 'panel';
  root.dataset.v = id;
  root.innerHTML = `<h2>${name} <span>${note}</span></h2><div class="sheet" data-paper><div class="stack"><div class="scroller"></div></div></div>`;
  const sheet = root.querySelector('.sheet');
  const stack = root.querySelector('.stack');
  const scroller = root.querySelector('.scroller');
  sheet.style.setProperty('--u', '1');
  const caret = Object.assign(document.createElement('span'), { className: 'caret' });
  let spans = [];
  let live = null;
  let shiftFrame = 0;
  let shiftRunning = false;
  let shiftTarget = -1;

  const startLine = () => {
    const span = Object.assign(document.createElement('span'), { className: 'l' });
    const mark = Object.assign(document.createElement('i'), { className: 'mark' });
    span.append(mark, document.createTextNode(''), caret);
    scroller.append(span);
    spans.push(span);
    live = span;
  };
  const setRungs = () => spans.forEach((span, i) => { span.dataset.rung = String(spans.length - 1 - i); });
  // --live: where the live line's first row starts inside the aperture (the A mask hangs on it).
  const syncLive = () => {
    const rect = live.firstChild.getBoundingClientRect();
    stack.style.setProperty('--live', `${rect.top - stack.getBoundingClientRect().top}px`);
  };
  const setScroll = top => { scroller.scrollTop = top; syncLive(); };
  const fit = (animate) => {
    const target = Math.max(0, scroller.scrollHeight - scroller.clientHeight);
    if (shiftRunning && target === shiftTarget) return;
    cancelAnimationFrame(shiftFrame);
    shiftRunning = false;
    const from = scroller.scrollTop;
    if (target === from) { syncLive(); return; }
    const pitch = parseFloat(getComputedStyle(scroller).lineHeight);
    if (!animate || reduced.matches || Math.abs(target - from) > pitch * 1.5) { setScroll(target); return; }
    const started = performance.now();
    shiftTarget = target;
    shiftRunning = true;
    const step = now => {
      const progress = Math.min(1, (now - started) / LINE_SHIFT_MS);
      setScroll(from + (target - from) * lineShiftProgress(progress));
      if (progress < 1) shiftFrame = requestAnimationFrame(step);
      else shiftRunning = false;
    };
    shiftFrame = requestAnimationFrame(step);
  };
  const reset = () => {
    cancelAnimationFrame(shiftFrame);
    shiftRunning = false;
    scroller.replaceChildren();
    spans = [];
    startLine();
    setRungs();
    scroller.scrollTop = 0;
    syncLive();
  };
  const append = ch => {
    if (ch === '\n') {
      live.childNodes[1].data += '\n';
      startLine();
      setRungs();
    } else {
      live.childNodes[1].data += ch;
    }
    fit(true);
  };
  const knob = () => {
    root.style.setProperty('--h1', knobs.h1);
    root.style.setProperty('--h2', knobs.h2);
    root.style.setProperty('--flat', knobs.flat);
    root.style.setProperty('--ms', `${id === 'c' ? 120 : knobs.ms}ms`);
  };
  reset();
  knob();
  return { id, root, scroller, stack, append, reset, knob, spans: () => spans };
}

const grid = document.getElementById('grid');
const panels = VARIANTS.filter(([id]) => !only || id === only).map(panel);
grid.append(...panels.map(p => p.root));
window.WriteItDownPaper?.mountAll();

let run = 0;
async function play() {
  const token = ++run;
  panels.forEach(p => p.reset());
  await sleep(500);
  for (const line of TEXT[params.get('text') || 'en']) {
    for (const ch of line) {
      if (token !== run) return;
      panels.forEach(p => p.append(ch));
      await sleep(36);
    }
    if (token !== run) return;
    await sleep(350);
    panels.forEach(p => p.append('\n'));
    await sleep(1100);
  }
}

const bar = document.querySelector('.bar');
for (const key of Object.keys(knobs)) {
  const input = bar.querySelector(`#${key}`);
  const output = input.nextElementSibling;
  input.value = knobs[key];
  output.textContent = knobs[key];
  input.addEventListener('input', () => {
    knobs[key] = Number(input.value);
    output.textContent = input.value;
    panels.forEach(p => p.knob());
    const next = new URLSearchParams(location.search);
    next.set(key, input.value);
    history.replaceState(null, '', `?${next}`);
  });
}
document.getElementById('replay').addEventListener('click', () => { play(); });
document.getElementById('live').addEventListener('click', () => { run += 1; panels.forEach(p => p.reset()); document.body.dataset.live = 'true'; });
document.getElementById('copy').addEventListener('click', () => navigator.clipboard?.writeText(`h1=${knobs.h1} h2=${knobs.h2} flat=${knobs.flat} ms=${knobs.ms}`));
addEventListener('keydown', event => {
  if (document.body.dataset.live !== 'true' || event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.key === 'Enter') panels.forEach(p => p.append('\n'));
  else if (event.key.length === 1) panels.forEach(p => p.append(event.key));
  else return;
  event.preventDefault();
});

window.zenFade = { panels, play, knobs };
if (!params.has('paused')) play();
