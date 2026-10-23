// Deterministic human-rhythm typing script for the landing demo.
// Seeded LCG, no DOM and no randomness at read time: demo.js replays the
// events, and the qa specs import the same module to seek exact fake-clock
// times. The text is the Gemini demo script picked blind ("option 1",
// work/imposter; options 2 and 3 were not used). The typist writes a false
// start ("prete"), tries Backspace once - the "deny" event: nothing is
// deleted, the sheet shakes and a blocked Backspace keycap shows - then
// carries on forward, and stops mid-sentence so the silence warning plays.
// Every event only ever appends: the demo is forward-only like the room.
export var LINES = [
  "i don't think i'm ready for this promotion.",
  "everyone else seems so smart.",
  "i'm just prete pretending.",
  "maybe i should"
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
      var wait = span(45, 40);
      if (i > 0 && text[i - 1] === " ") wait += span(30, 45);
      if (i > 0 && /[.,]/.test(text[i - 1])) wait += span(220, 140);
      if (i > 0 && text[i - 1] === " " && rnd() < 0.15) wait += span(200, 220);
      t += wait; cur += text[i]; push("type");
    }
  }
  function beat(base, spread) { t += Math.round(base + rnd() * spread); }
  function newline(pause) { beat(pause, 120); dn += 1; cur = ""; push("line"); }

  type(LINES[0]);
  newline(650);
  type(LINES[1]);
  newline(650);
  type("i'm just prete");
  beat(380, 80); // notice the false start
  push("deny"); // tries Backspace: blocked, nothing changes
  beat(900, 100); // the blocked keycap holds, then on
  type(" pretending.");
  newline(650);
  type(LINES[3]);
  return { events: events, typeEnd: t };
}

export var TIMELINE = buildTimeline();
