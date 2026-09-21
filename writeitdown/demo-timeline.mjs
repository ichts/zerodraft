// Deterministic human-rhythm typing script for the landing demo.
// Seeded LCG, no DOM and no randomness at read time: demo.js replays the
// events, and the qa specs import the same module to seek exact fake-clock
// times. The script types the private messy draft with uneven keystrokes,
// word and punctuation pauses, and one visible self-correction: the typo
// "promotino" is deleted with two quick backspaces, then retyped.
export var LINES = [
  "cant say this out loud but",
  "i dont want the promotion",
  "promotion. i want time off"
];

export function buildTimeline() {
  var seed = 7;
  function rnd() { seed = seed * 48271 % 2147483647; return (seed - 1) / 2147483646; }
  function span(base, spread) { return Math.round(base + rnd() * spread); }
  var t = 500; // eyes on the page before the first key
  var events = [], dn = 0, cur = "";
  function push(kind) { events.push({ t: t, kind: kind, cur: cur, dn: dn }); }
  function type(text) {
    for (var i = 0; i < text.length; i++) {
      var wait = span(70, 55);
      if (i > 0 && text[i - 1] === " ") wait += span(45, 70);
      if (i > 0 && text[i - 1] === ".") wait += span(260, 180);
      if (i > 0 && text[i - 1] === " " && rnd() < 0.18) wait += span(240, 260);
      t += wait; cur += text[i]; push("type");
    }
  }
  function back(n) {
    for (var i = 0; i < n; i++) { t += span(90, 60); cur = cur.slice(0, -1); push("back"); }
  }
  function beat(base, spread) { t += Math.round(base + rnd() * spread); }
  function newline(pause) { beat(pause, 120); dn += 1; cur = ""; push("line"); }

  type(LINES[0]);
  newline(800);
  type("i dont want the promotino");
  beat(420, 100); // notice the typo
  back(2); // delete "no"
  beat(220, 80); // think
  type("on"); // retype the ending
  newline(800);
  type(LINES[2]);
  return { events: events, typeEnd: t };
}

export var TIMELINE = buildTimeline();
