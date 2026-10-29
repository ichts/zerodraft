export function fresh() {
  return { phase: 'rest', text: '', started: null, lastInput: null, ended: null, unused: 60 };
}

export function advance(state, now) {
  if (state.started === null || !['typing', 'warn'].includes(state.phase)) return state;
  const finish = state.started + 60000;
  const wipe = state.lastInput + 8000;
  if (now >= Math.min(finish, wipe)) {
    if (wipe <= finish || !state.text.trim()) {
      return { ...fresh(), phase: 'wipe', ended: Math.min(finish, wipe), unused: Math.max(0, Math.ceil((finish - wipe) / 1000)) };
    }
    return { ...state, phase: 'kept', ended: finish, unused: 0 };
  }
  return { ...state, phase: now - state.lastInput >= 5000 ? 'warn' : 'typing' };
}

export function append(state, text, now) {
  state = advance(state, now);
  if (state.phase === 'kept') return state;
  if (!text) return state;
  return { ...state, phase: 'typing', text: state.text + text, started: state.started ?? now, lastInput: now, ended: null };
}

export function clock(seconds) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

const wordSegments = new Intl.Segmenter(undefined, { granularity: 'word' });

// Han characters count individually; other scripts use Unicode word boundaries.
export function wordCount(text) {
  const separated = text.replace(/(\p{Script=Han}\p{Mark}*)/gu, ' $1 ');
  return Array.from(wordSegments.segment(separated)).filter(part => part.isWordLike).length;
}

// The history ladder's unit is the logical line, not the visual row (D-077): a sentence, or the text
// up to a hard line break. Every row of one logical line carries one rung, so a long sentence that
// wraps reads as one grey, never as a staircase. The Mac room cuts the same lines with the same
// Unicode sentence rules (`HistoryLines.swift`); the two surfaces must not drift.
// Rung 0 is the live line, 1 and 2 are the ladder's two readable steps, GONE is everything older.
export const GONE = 3;

const sentenceSegments = new Intl.Segmenter(undefined, { granularity: 'sentence' });

// The text cut into logical lines, each with its offsets and its rung. A trailing hard break means
// the writer is already on a fresh, empty line, so every written line sits one rung further back.
export function historyLines(text) {
  const lines = Array.from(sentenceSegments.segment(text), part => ({ start: part.index, end: part.index + part.segment.length }));
  const live = lines.length - 1 + (text.endsWith('\n') ? 1 : 0);
  return lines.map((line, index) => ({ ...line, rung: Math.min(live - index, GONE) }));
}
