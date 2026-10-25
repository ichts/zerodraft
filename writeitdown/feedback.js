// The refusal: a short, display-synced, interruptible answer to a blocked edit.
// A 200 ms transform-only paper shake and a 220 ms opacity-only red hairline
// flash, both ease-out. A repeat restarts them from the current presentation
// state instead of being dropped. Reduce Motion keeps the flash alone. This is
// the Mac room's case 44 treatment on the web; the two surfaces must not drift.

export const LINE_SHIFT_MS = 180;
export const lineShiftProgress = progress => 1 - (1 - progress) ** 3;

const SHAKE_MS = 200;
const FLASH_MS = 220;

function reducedMotion() {
  return matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function currentTranslateX(paper) {
  const transform = getComputedStyle(paper).transform;
  if (!transform || transform === 'none') return 0;
  const values = transform.match(/matrix\(([^)]+)\)/);
  return values ? parseFloat(values[1].split(',')[4]) || 0 : 0;
}

export function denyFeedback(paper, hairline) {
  const from = currentTranslateX(paper);
  const opacity = hairline ? getComputedStyle(hairline).opacity : 0;
  paper.getAnimations().forEach(animation => animation.cancel());
  if (!reducedMotion()) {
    paper.animate([
      { transform: `translateX(${from}px)`, offset: 0 },
      { transform: 'translateX(-3px)', offset: .18 },
      { transform: 'translateX(2.5px)', offset: .42 },
      { transform: 'translateX(-1px)', offset: .7 },
      { transform: 'translateX(0)', offset: 1 }
    ], { duration: SHAKE_MS, easing: 'ease-out' });
  }
  if (hairline) {
    hairline.getAnimations().forEach(animation => animation.cancel());
    hairline.animate([
      { opacity, offset: 0 },
      { opacity: 1, offset: .08 },
      { opacity: 1, offset: .55 },
      { opacity: 0, offset: 1 }
    ], { duration: FLASH_MS, easing: 'ease-out' });
  }
}
