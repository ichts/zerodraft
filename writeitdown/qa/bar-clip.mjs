// The session bar reveals a fixed rounded border with clip-path: inset(0 R% 0 0). These helpers read
// the remaining fraction back from that string, however the browser serialises it.
export function barFraction(clip) {
  const right = /^inset\(0(?:px)? ([\d.e+-]+)%/.exec(clip)?.[1];
  if (right === undefined) throw new Error(`not a bar clip: ${clip}`);
  return 1 - Number(right) / 100;
}
export const EMPTY_BAR = /^inset\(0(?:px)? 100% 0(?:px)? 0(?:px)?\)$/;
