let audio;
const feedback = new WeakMap();
const FEEDBACK_DURATION = 280;

function unlock(event) {
  if (!event.isTrusted) return;
  const Audio = window.AudioContext || window.webkitAudioContext;
  if (!Audio) return;
  audio ??= new Audio();
  if (audio.state === 'suspended') audio.resume().catch(() => {});
}
document.addEventListener('pointerdown', unlock);
document.addEventListener('keydown', unlock);

export function denyFeedback(paper) {
  if (feedback.get(paper)?.playState === 'running') return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!reduced) paper.animate([
    { transform: 'translateX(0)', offset: 0 },
    { transform: 'translateX(-2px)', offset: .18 },
    { transform: 'translateX(2px)', offset: .38 },
    { transform: 'translateX(-1px)', offset: .56 },
    { transform: 'translateX(0)', offset: .7 },
    { transform: 'translateX(0)', offset: 1 }
  ], { duration: FEEDBACK_DURATION, easing: 'ease-out' });
  feedback.set(paper, paper.animate([
    { outline: '1px solid var(--alarm)' }, { outline: '1px solid var(--alarm)' }
  ], { duration: FEEDBACK_DURATION }));
  if (audio?.state !== 'running') return;
  const tone = audio.createOscillator();
  const gain = audio.createGain();
  tone.frequency.setValueAtTime(110, audio.currentTime);
  gain.gain.setValueAtTime(0.035, audio.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + 0.09);
  tone.connect(gain).connect(audio.destination);
  tone.start();
  tone.stop(audio.currentTime + 0.09);
  tone.onended = () => { tone.disconnect(); gain.disconnect(); };
}
