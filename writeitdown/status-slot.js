// The one status-slot definition shared by the trial room and the landing demo.
// The warning numeral's ink top sits 44 px under the writing baseline, the caption's
// ink top 20 px under the numeral's ink, and the wipe receipt takes the numeral's slot.
// Placement is cached on the three strings and re-anchored only when the caller marks
// the geometry dirty (resize, font load, route or visibility change), so the 50 ms
// render can ask for it without forcing style or layout reads when nothing changed.

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

export function statusSlot({ paper, line, pitches, numeral, caption, receipt }) {
  let placed = null;
  let dirty = true;
  return {
    invalidate() { dirty = true; },
    place() {
      const key = `${numeral.textContent}\u0000${caption.textContent}\u0000${receipt.textContent}`;
      if (!dirty && key === placed) return;
      const writing = fontOf(line);
      const writingInk = ink('H', writing.css, writing.lineHeight);
      const baseline = line.getBoundingClientRect().top - paper.getBoundingClientRect().top
        + writing.lineHeight * pitches + writingInk.halfLeading + writingInk.ascent;
      const numeralFont = fontOf(numeral);
      const numeralInk = ink(numeral.textContent, numeralFont.css, numeralFont.lineHeight);
      const captionFont = fontOf(caption);
      const receiptFont = fontOf(receipt);
      paper.style.setProperty('--danger-top', `${baseline + 44 - numeralInk.inkTop}px`);
      paper.style.setProperty('--caption-gap', `${numeralInk.inkTop + numeralInk.inkHeight + 20 - numeralFont.size - ink(caption.textContent, captionFont.css, captionFont.lineHeight).inkTop}px`);
      paper.style.setProperty('--receipt-top', `${baseline + 44 - ink(receipt.textContent, receiptFont.css, receiptFont.lineHeight).inkTop}px`);
      placed = key;
      dirty = false;
    }
  };
}
