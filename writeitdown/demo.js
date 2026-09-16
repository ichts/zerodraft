import { denyFeedback } from './feedback.js';
import { wordCount } from './session.mjs';

(function () {
  "use strict";
  var LINES = [
    "cant say this out loud but",
    "i dont want the promotoin",
    "promotion. i want time off"
  ];
  var PAUSES = [1200, 1000, 0];
  var TYPE_END = 15000, SILENT_END = 20000, WARN_END = 23000, CUT_END = 23200, LOOP = 25000;

  var SEGS = (function () {
    var chars = LINES.reduce(function (n, l) { return n + l.length; }, 0);
    var pauses = PAUSES.reduce(function (a, b) { return a + b; }, 0);
    var per = (TYPE_END - pauses) / chars;
    var t = 0;
    return LINES.map(function (l, i) {
      var seg = { i: i, t0: t, t1: t + l.length * per };
      t = seg.t1 + PAUSES[i];
      return seg;
    });
  })();

  var paper = document.getElementById("paper");
  var washWall = document.getElementById("wash-wall");
  var washPaper = document.getElementById("wash-paper");
  var clockEl = document.getElementById("clock");
  var prevEls = [document.getElementById("prev-0"), document.getElementById("prev-1")];
  var curEl = document.getElementById("cur");
  var numeralEl = document.getElementById("numeral");
  var reportEl = document.getElementById("report");
  var countEl = document.getElementById("count");
  var denied = false;

  var reducedMq = window.matchMedia("(prefers-reduced-motion: reduce)");
  var t0 = Date.now();
  var seen = {};

  function draftAt(t) {
    var done = [], cur = "", s, l, i;
    for (i = 0; i < SEGS.length; i++) {
      s = SEGS[i]; l = LINES[s.i];
      if (t >= s.t1) { done.push(l); cur = l; }
      else if (t > s.t0) { cur = l.slice(0, Math.round(l.length * (t - s.t0) / (s.t1 - s.t0))); break; }
      else break;
    }
    if (done.length && cur === done[done.length - 1]) done = done.slice(0, -1);
    return { done: done, cur: cur };
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
    var backspace = t >= SEGS[1].t1 && t < SEGS[2].t0;
    if (backspace && !denied) denyFeedback(paper);
    denied = backspace;
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
      put(reportEl, "rep", "DRAFT WIPED - 0:37 UNUSED. TYPE TO RESTART.");
      renderDraft({ done: [], cur: "" });
      put(clockEl, "clock", "1:00");
    }
  }

  function renderReduced() {
    denied = false;
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
