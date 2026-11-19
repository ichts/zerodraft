// Landing-demo sound, Nib set. The writing room never imports this module and the refusal stays silent (D-046).
// Web Audio is the one browser API that starts a decoded sample within a few milliseconds, so this stays hand-written.
// Off by default; nothing is created or fetched before the visitor's click on the sound button, and nothing is stored.
const BASE = 'sound/';
const FILES = { key: 8, warn: 3, wipe: 1 };
const DEFAULT_VOLUME = 40;

const toggle = document.querySelector('[data-sound-toggle]');
const slider = document.querySelector('[data-sound-volume]');
const pop = document.querySelector('[data-sound-pop]');
let context = null, master = null, buffers = null, on = false, volume = DEFAULT_VOLUME, lastKey = -1;
const log = [];

// A quadratic slider law: 40 is gain 0.16 (-16 dB), 100 is full scale.
const gainOf = value => (Number(value) / 100) ** 2;

async function load() {
  const entries = await Promise.all(Object.entries(FILES).map(async ([role, count]) => [role,
    await Promise.all(Array.from({ length: count }, async (_, i) =>
      context.decodeAudioData(await (await fetch(`${BASE}nib-${role}-${i + 1}.wav`)).arrayBuffer())))]));
  return Object.fromEntries(entries);
}

function show() {
  toggle.setAttribute('aria-pressed', String(on));
  toggle.setAttribute('aria-label', on ? 'Turn sound off' : 'Turn sound on');
  pop.hidden = !on;
}

async function setOn(next) {
  on = next;
  show();
  if (!on) { master?.gain.setTargetAtTime(0, context.currentTime, 0.02); return; }
  try {
    if (!context) {
      context = new AudioContext({ latencyHint: 'interactive' });
      master = context.createGain();
      master.gain.value = 0;
      master.connect(context.destination);
    }
    buffers ??= await load();
    await context.resume();
    // The first start() in a fresh context pays a one-off cost; one silent strike keeps the first real one fast.
    const warm = context.createBufferSource(), mute = context.createGain();
    warm.buffer = buffers.key[0];
    mute.gain.value = 0;
    warm.connect(mute).connect(context.destination);
    warm.start(0);
    master.gain.setTargetAtTime(gainOf(volume), context.currentTime, 0.02);
  } catch (error) {
    on = false;
    show();
    throw error;
  }
}

function start({ role, step = 0 }) {
  const asked = performance.now();
  const pool = buffers[role];
  let index = role === 'warn' ? step : 0;
  if (role === 'key') { do index = Math.floor(Math.random() * pool.length); while (index === lastKey); lastKey = index; }
  const source = context.createBufferSource();
  source.buffer = pool[index];
  const level = context.createGain();
  if (role === 'key') {  // a small pitch and level spread so no two strikes are identical
    source.playbackRate.value = 1 + (Math.random() - 0.5) * 0.06;
    level.gain.value = 10 ** (((Math.random() - 0.5) * 3) / 20);
  }
  source.connect(level).connect(master);
  source.start(0);
  // scheduleMs: from the call to the sample handed to the audio thread; the device adds base + output latency.
  log.push({ role, scheduleMs: performance.now() - asked, base: context.baseLatency, output: context.outputLatency ?? null });
  if (log.length > 200) log.shift();
}

toggle?.addEventListener('click', () => setOn(!on));
slider?.addEventListener('input', () => {
  volume = slider.value;
  if (on) master.gain.setTargetAtTime(gainOf(volume), context.currentTime, 0.015);
});

export const landingSound = {
  cue(cues) { if (on && buffers && context.state === 'running') cues.forEach(start); },
  log
};
