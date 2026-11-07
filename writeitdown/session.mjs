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

// Han, Hiragana and Katakana (and the prolonged sound mark) are written without spaces, so each one is a
// unit; every other script uses Unicode word boundaries (D-094). The Mac and Windows rooms use the same rule.
const CJK = String.raw`[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\u30FC]`;
const cjkUnits = new RegExp(`(${CJK}\\p{Mark}*)`, 'gu');
const cjkLetter = new RegExp(CJK, 'gu');

export function wordCount(text) {
  const separated = text.replace(cjkUnits, ' $1 ');
  return Array.from(wordSegments.segment(separated)).filter(part => part.isWordLike).length;
}

// The label says characters only when CJK letters are at least half of the draft's letters and digits.
export function usesCharacterCount(text) {
  const cjk = (text.match(cjkLetter) || []).length;
  const letters = (text.match(/[\p{Letter}\p{Number}]/gu) || []).length;
  return cjk > 0 && cjk * 2 >= letters;
}

export function countLabel(text, count = wordCount(text)) {
  const unit = usesCharacterCount(text) ? 'character' : 'word';
  return `${count} ${unit}${count === 1 ? '' : 's'}`;
}

// The history ladder's unit is the line the writer ended with Return (D-088, superseding D-077's
// sentence rule): the text up to a hard break, never a sentence and never a visual row. A line that
// wraps is still one line, so its rows carry one rung and read as one grey, never as a staircase.
// A full stop does not end a line. The Mac and Windows rooms cut the same lines (`HistoryLines.swift`,
// `session/lines.go`); the three surfaces must not drift.
// Rung 0 is the live line, 1 and 2 are the history's two dimmed steps (D-092), GONE is everything older.
export const GONE = 3;

// The text cut into lines, each with its offsets and its rung. A hard break is LF, CRLF or a lone CR
// and belongs to the line it ends. A trailing hard break means the writer is already on a fresh, empty
// line, so every written line sits one rung further back.
export function historyLines(text) {
  const lines = [];
  let start = 0;
  for (const hardBreak of text.matchAll(/\r\n|[\n\r]/g)) {
    const end = hardBreak.index + hardBreak[0].length;
    lines.push({ start, end });
    start = end;
  }
  if (start < text.length) lines.push({ start, end: text.length });
  const live = lines.length - 1 + (text.endsWith('\n') ? 1 : 0);
  return lines.map((line, index) => ({ ...line, rung: Math.min(live - index, GONE) }));
}
