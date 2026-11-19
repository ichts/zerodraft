// Which sounds the landing demo owes between two moments of its loop. Pure, so a node test can walk the whole loop.
// A window longer than FRESH_MS means the tab was hidden or the page resumed: it owes nothing, never a burst.
export const FRESH_MS = 250;
const COUNT_MS = 1000;

export function cuesBetween(from, to, events, silentEnd, warnEnd) {
  if (to <= from || to - from > FRESH_MS) return [];
  const cues = [];
  for (const event of events) {
    if ((event.kind === 'type' || event.kind === 'line') && event.t > from && event.t <= to) cues.push({ role: 'key' });
  }
  for (let step = 0; step < 3; step++) {
    const at = silentEnd + step * COUNT_MS;
    if (at > from && at <= to) cues.push({ role: 'warn', step });
  }
  if (warnEnd > from && warnEnd <= to) cues.push({ role: 'wipe' });
  return cues;
}
