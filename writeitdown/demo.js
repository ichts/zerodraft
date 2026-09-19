import { LINES, TIMELINE } from './demo-timeline.mjs';
import { clock, wordCount } from './session.mjs';

(function () {
  "use strict";
  // TIMELINE paces the typing like a person: uneven keystrokes, word and
  // punctuation pauses, one visible backspace correction. The danger beats
  // stay absolute - 5s of silence after the last key, 3s of warn (wash and
  // 3-2-1), the 200ms cut, then the report holds 2s before the loop restarts.
  var TYPE_END = TIMELINE.typeEnd;
  var SILENT_END = TYPE_END + 5000, WARN_END = SILENT_END + 3000,
      CUT_END = WARN_END + 200, LOOP = CUT_END + 2000;
  var EVENTS = TIMELINE.events;

  var paper = document.getElementById("paper");
  var washWall = document.getElementById("wash-wall");
  var washPaper = document.getElementById("wash-paper");
  var clockEl = document.getElementById("clock");
  var prevEls = [document.getElementById("prev-0"), document.getElementById("prev-1")];
  var curEl = document.getElementById("cur");
  var numeralEl = document.getElementById("numeral");
  var reportEl = document.getElementById("report");
  var countEl = document.getElementById("count");

  var reducedMq = window.matchMedia("(prefers-reduced-motion: reduce)");
  var t0 = Date.now();
  var seen = {};

  function draftAt(t) {
    var snap = { dn: 0, cur: "" }, i;
    for (i = 0; i < EVENTS.length; i++) {
      if (EVENTS[i].t > t) break;
      snap = EVENTS[i];
    }
    return { done: LINES.slice(0, snap.dn), cur: snap.cur };
  }
  function full() { return { done: LINES.slice(0, -1), cur: LINES[LINES.length - 1] }; }
  function clockAt(t) {
    var left = Math.max(0, 60 - Math.floor(t / 1000));
    return left === 60 ? "1:00" : "0:" + String(left).padStart(2, "0");
  }
  function words(d) {
    var s = d.done.concat([d.cur]).join(" ").trim();
    var w = wordCount(s);
    return w + (w === 1 ? " WORD" : " WORDS");
  }

  function put(el, key, v) {
    if (seen[key] !== v) { seen[key] = v; el.textContent = v; }
  }
  function setPhase(name) {
    if (seen.ph !== name) { seen.ph = name; paper.className = "paper " + name; }
  }
  function setWash(k) {
    var wall, pap;
    if (k === "deep") { wall = "var(--deep-wall)"; pap = "var(--deep-paper)"; }
    else if (k == null) { wall = "none"; pap = "none"; }
    else {
      wall = "color-mix(in oklab, var(--wash-wall) " + Math.round(k * 100) + "%, transparent)";
      pap = "color-mix(in oklab, var(--wash-paper) " + Math.round(k * 100) + "%, transparent)";
    }
    if (seen.ww !== wall) { seen.ww = wall; washWall.style.background = wall; }
    if (seen.wp !== pap) { seen.wp = pap; washPaper.style.background = pap; }
  }
  function renderDraft(d) {
    var r = d.done.slice().reverse();
    put(prevEls[0], "p0", r[0] || "");
    put(prevEls[1], "p1", r[1] || "");
    put(curEl, "cur", d.cur);
    put(countEl, "count", words(d));
  }

  function render(t) {
    if (t < SILENT_END) {
      setPhase("type");
      setWash(null);
      put(numeralEl, "num", "");
      put(reportEl, "rep", "");
      renderDraft(t < TYPE_END ? draftAt(t) : full());
      put(clockEl, "clock", clockAt(t));
    } else if (t < WARN_END) {
      setPhase("warn");
      setWash((t - SILENT_END) / 3000);
      put(numeralEl, "num", String(3 - Math.floor((t - SILENT_END) / 1000)));
      put(reportEl, "rep", "");
      renderDraft(full());
      put(clockEl, "clock", clockAt(t));
    } else if (t < CUT_END) {
      setPhase("cut");
      setWash("deep");
      put(numeralEl, "num", "");
      put(reportEl, "rep", "");
      renderDraft({ done: [], cur: "" });
      put(clockEl, "clock", "1:00");
    } else {
      setPhase("report");
      setWash(null);
      put(numeralEl, "num", "");
      put(reportEl, "rep", "DRAFT WIPED - " + clock(60 - Math.round(CUT_END / 1000)) + " UNUSED. TYPE TO RESTART.");
      renderDraft({ done: [], cur: "" });
      put(clockEl, "clock", "1:00");
    }
  }

  function renderReduced() {
    setPhase("still");
    setWash(null);
    put(numeralEl, "num", "");
    put(reportEl, "rep", "");
    renderDraft(full());
    put(clockEl, "clock", "1:00");
  }

  function tick() {
    if (document.hidden || document.getElementById('landing').hidden) return;
    if (reducedMq.matches) { renderReduced(); return; }
    render((Date.now() - t0) % LOOP);
  }

  tick();
  setInterval(tick, 50);
  if (reducedMq.addEventListener) reducedMq.addEventListener("change", tick);
})();
