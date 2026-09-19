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
