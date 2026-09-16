let audio;

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
  paper.getAnimations().forEach(animation => animation.cancel());
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!reduced) paper.animate([
    { transform: 'translateX(0)' }, { transform: 'translateX(-2px)' },
    { transform: 'translateX(2px)' }, { transform: 'translateX(0)' }
  ], { duration: 160 });
  paper.animate([{ outline: '1px solid var(--alarm)' }, { outline: '1px solid var(--alarm)' }], { duration: 90 });
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
