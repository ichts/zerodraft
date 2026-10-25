// The one status-slot definition shared by the trial room and the landing demo.
// The warning numeral's ink top sits 44 px under the writing baseline, the caption's
// ink top 20 px under the numeral's ink, and the wipe receipt takes the numeral's slot.
// On a tall sheet those Mac offsets are used exactly; when the group cannot fit above
// the footer it moves above the writing line, and the failure block and receipt clamp
// above the footer, so nothing is clipped or laid over the active line or the controls.
// The footer top reserves the measured height of the wrapped confirmation row, and the
// kept screen reserves the inline row's own top, both via a hidden probe at the current
// width, so arming the confirmation neither reflows nor overlaps a result screen.
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

// The kept screen shows the returned draft, so it owes the writer at least one full line
// of it. Its fixed block (title, receipt, controls) and the confirmation row reserved above
// the footer are measured, not assumed: a fallback font that wraps one of them taller would
// otherwise eat the draft's only line, which is what the Linux runner did at 320 px (a
// two-line confirmation reservation left 30.4 px of a 33.6 px line). The kept screen's own
// gaps give way instead, nearest the draft first, and the shrink stops as soon as a line
// fits, so a comfortable sheet keeps its designed rhythm.
const KEPT_GAPS = [['.kept-scroll', '--kept-scroll-gap'], ['.kept-actions', '--kept-actions-gap'], ['.kept-receipt', '--kept-receipt-gap']];

function keepDraftLine(paper) {
  const scroll = paper.querySelector('.kept-scroll');
  const text = paper.querySelector('.kept-text');
  if (!scroll || !text || scroll.getBoundingClientRect().height === 0) return;
  const line = parseFloat(getComputedStyle(text).lineHeight);
  if (!(line > 0)) return;
  for (const [selector, name] of KEPT_GAPS) {
    const short = line - scroll.getBoundingClientRect().height;
    if (short <= 0.5) return;
    const el = paper.querySelector(selector);
    if (!el) continue;
    const gap = parseFloat(getComputedStyle(el).marginTop) || 0;
    if (gap <= 0) continue;
    paper.style.setProperty(name, `${Math.max(0, gap - short)}px`);
  }
}

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
      let hintTop = null;
      if (footer) {
        const footerRect = footer.getBoundingClientRect();
        const hint = footer.querySelector('.exit-hint');
        const stableChildren = [...footer.children]
          .filter(child => !child.classList.contains('exit-hint'))
          .map(child => child.getBoundingClientRect())
          .filter(rect => rect.height > 0);
        // The stable controls can wrap onto more than one row on a narrow sheet, so the block is
        // measured as a whole: the topmost control to the footer's bottom edge. Reserving only the
        // tallest single control let a wrapped row eat a line of the kept draft.
        const stableTop = stableChildren.length
          ? Math.min(...stableChildren.map(rect => rect.top))
          : footerRect.bottom - 44;
        const stableHeight = footerRect.bottom - stableTop;
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
            if (probeRect.height > 0) {
              const wrapped = probeRect.bottom <= stableTop + 1;
              confirmRow = wrapped ? probeRect.height : 0;
              hintTop = wrapped
                ? stableTop - paperTop - probeRect.height
                : stableTop - paperTop + (stableHeight - probeRect.height) / 2;
            }
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
      const keptBottom = Math.max(0, compact
        ? paperHeight - footerTop + gap
        : hintTop != null ? paperHeight - hintTop + gap : paperHeight - footerTop - 24);
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
      keepDraftLine(paper);
      placed = key;
      dirty = false;
    }
  };
}
