// The one status-slot definition shared by the trial room and the landing demo.
// The warning numeral's ink top sits 44 px under the writing baseline, the caption's
// ink top 20 px under the numeral's ink, and the wipe receipt takes the numeral's slot.
// On a tall sheet those Mac offsets are used exactly; when the group cannot fit above
// the footer it moves above the writing line, and the failure block and receipt clamp
// above the footer, so nothing is clipped or laid over the active line or the controls.
// The footer top reserves the measured height of the confirmation row (one or two
// lines at the current width) via a hidden probe, so arming the confirmation neither
// reflows nor overlaps a result screen.
// Placement is cached on the three strings and re-anchored only when the caller marks
// the geometry dirty (resize, font load, route or visibility change), so the 50 ms
// render can ask for it without forcing style or layout reads when nothing changed.

// Paper heights below this use the compact result typography. The reservation of
// the confirmation row is handled in the placement, not in this threshold.
const COMPACT_BELOW = 480;

const ink = (() => {
  let context;
  return (text, font, lineHeight) => {
    context ??= document.createElement('canvas').getContext('2d');
    context.font = font;
    const metrics = context.measureText(text || '0');
    const ascent = metrics.fontBoundingBoxAscent;
    const descent = metrics.fontBoundingBoxDescent;
    const inkAscent = metrics.actualBoundingBoxAscent;
    return {
      ascent,
      halfLeading: (lineHeight - (ascent + descent)) / 2,
      inkTop: (lineHeight - (ascent + descent)) / 2 + ascent - inkAscent,
      inkHeight: inkAscent + metrics.actualBoundingBoxDescent
    };
  };
})();

function fontOf(el) {
  const style = getComputedStyle(el);
  return { css: `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`,
    size: parseFloat(style.fontSize), lineHeight: parseFloat(style.lineHeight) };
}

export function statusSlot({ paper, line, pitches, numeral, caption, receipt, block }) {
  let placed = null;
  let dirty = true;
  return {
    invalidate() { dirty = true; },
    place() {
      const key = `${numeral.textContent}\u0000${caption.textContent}\u0000${receipt.textContent}`;
      if (!dirty && key === placed) return;
      const paperRect = paper.getBoundingClientRect();
      const paperTop = paperRect.top;
      const paperHeight = paperRect.height;
      const writing = fontOf(line);
      const writingInk = ink('H', writing.css, writing.lineHeight);
      const lineTop = line.getBoundingClientRect().top - paperTop + writing.lineHeight * pitches;
      const baseline = lineTop + writingInk.halfLeading + writingInk.ascent;
      const numeralFont = fontOf(numeral);
      const numeralInk = ink(numeral.textContent, numeralFont.css, numeralFont.lineHeight);
      const captionFont = fontOf(caption);
      const receiptFont = fontOf(receipt);
      const footer = paper.querySelector('.paper-foot');
      let footerTop = paperHeight - 60;
      let confirmRow = 0;
      if (footer) {
        const footerRect = footer.getBoundingClientRect();
        const hint = footer.querySelector('.exit-hint');
        const stableChildren = [...footer.children].filter(child => !child.classList.contains('exit-hint'));
        const stableHeight = stableChildren.length
          ? Math.max(...stableChildren.map(child => child.getBoundingClientRect().height)) : 44;
        const stableTop = footerRect.bottom - stableHeight;
        if (hint) {
          const text = hint.dataset.hint || hint.textContent;
          if (text) {
            const probe = hint.cloneNode(false);
            probe.removeAttribute('id');
            probe.removeAttribute('role');
            probe.removeAttribute('aria-live');
            probe.setAttribute('aria-hidden', 'true');
            probe.textContent = text;
            probe.style.visibility = 'hidden';
            footer.append(probe);
            const probeRect = probe.getBoundingClientRect();
            if (probeRect.height > 0 && probeRect.bottom <= stableTop + 1) confirmRow = probeRect.height;
            probe.remove();
          }
        }
        footerTop = stableTop - paperTop - confirmRow;
      }
      const gap = 8;
      const captionInk = ink(caption.textContent, captionFont.css, captionFont.lineHeight);
      const captionGap = numeralInk.inkTop + numeralInk.inkHeight + 20 - numeralFont.size - captionInk.inkTop;
      const numeralTop = baseline + 44 - numeralInk.inkTop;
      const groupHeight = numeralFont.lineHeight + captionGap + captionFont.lineHeight;
      const belowLine = footerTop - gap - groupHeight;
      const aboveLine = lineTop - gap - groupHeight;
      const dangerTop = numeralTop <= belowLine ? numeralTop : Math.max(0, Math.min(numeralTop, aboveLine));
      const receiptInk = ink(receipt.textContent, receiptFont.css, receiptFont.lineHeight);
      const receiptHeight = receipt.getBoundingClientRect().height || receiptFont.lineHeight;
      const receiptTop = Math.min(baseline + 44 - receiptInk.inkTop, footerTop - gap - receiptHeight);
      paper.style.setProperty('--danger-top', `${dangerTop}px`);
      paper.style.setProperty('--caption-gap', `${captionGap}px`);
      paper.style.setProperty('--receipt-top', `${Math.max(0, receiptTop)}px`);
      if (block && !block.hidden && block.offsetHeight > 0) {
        const blockHeight = block.getBoundingClientRect().height;
        paper.style.setProperty('--room-top', `${Math.max(gap, Math.min(72, receiptTop - gap - blockHeight))}px`);
      }
      const compact = paperHeight < COMPACT_BELOW;
      const keptBottom = confirmRow || compact
        ? Math.max(0, paperHeight - footerTop + gap)
        : Math.max(0, paperHeight - footerTop - 24);
      const compactVars = ['--kept-title', '--kept-receipt-gap', '--kept-actions-gap', '--kept-scroll-gap'];
      paper.style.setProperty('--kept-top', `${compact ? 8 : 72}px`);
      paper.style.setProperty('--kept-bottom', `${keptBottom}px`);
      if (compact) {
        paper.style.setProperty('--kept-title', 'var(--t-kept-compact)');
        paper.style.setProperty('--kept-receipt-gap', '6px');
        paper.style.setProperty('--kept-actions-gap', '8px');
        paper.style.setProperty('--kept-scroll-gap', '4px');
      } else {
        compactVars.forEach(name => paper.style.removeProperty(name));
      }
      placed = key;
      dirty = false;
    }
  };
}
