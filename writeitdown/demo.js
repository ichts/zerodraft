import { LINES, TIMELINE } from './demo-timeline.mjs';
import { clock, wordCount } from './session.mjs';
import { denyFeedback } from './feedback.js';

(function () {
  "use strict";
  // TIMELINE paces the typing like a person: uneven keystrokes, word and
  // punctuation pauses, and one blocked Backspace (the deny beat: the sheet shakes
  // and a red hairline flashes; nothing is deleted). The danger beats stay
  // absolute - 5 s of silence after the last key, 3 s of warn (wash and 3-2-1),
  // the 200 ms cut, then the failure screen before the loop restarts. The room
  // itself is the same room the trial and the Mac app show.
  var TYPE_END = TIMELINE.typeEnd;
  var SILENCE_MS = 5000, WARN_MS = 3000, CUT_MS = 200, REPORT_HOLD_MS = 2000;
  var SILENT_END = TYPE_END + SILENCE_MS, WARN_END = SILENT_END + WARN_MS,
      CUT_END = WARN_END + CUT_MS, LOOP = CUT_END + REPORT_HOLD_MS;
  var EVENTS = TIMELINE.events;
  var DENY = EVENTS.filter(function (e) { return e.kind === "deny"; })[0];

  var paper = document.getElementById("paper");
  var washPaper = document.getElementById("wash-paper");
  var hairline = document.getElementById("demo-hairline");
  var clockEl = document.getElementById("clock");
  var prevEls = [document.getElementById("prev-0"), document.getElementById("prev-1")];
  var curEl = document.getElementById("cur");
  var scriptEl = document.querySelector(".script");
  var warnEl = document.getElementById("warn");
  var numeralEl = document.getElementById("numeral");
  var captionEl = document.getElementById("warn-caption");
  var stoppedEl = document.getElementById("demo-stopped");
  var reportEl = document.getElementById("report");
  var countEl = document.getElementById("count");
  var barEl = document.getElementById("bar");

  var reducedMq = window.matchMedia("(prefers-reduced-motion: reduce)");
  var t0 = Date.now();
  var seen = {};
  var lastT = -1;
  var barAnimation = null;

  // The status slot is placed by ink, exactly as in the trial room (Mac case 34/35):
  // the numeral's ink top 44 px under the writing baseline, the caption's ink top
  // 20 px under the numeral's ink, and the wipe receipt in the numeral's slot.
  var ink = (function () {
    var context;
    return function (text, font, lineHeight) {
      if (!context) context = document.createElement("canvas").getContext("2d");
      context.font = font;
      var metrics = context.measureText(text || "0");
      var ascent = metrics.fontBoundingBoxAscent, descent = metrics.fontBoundingBoxDescent;
      var inkAscent = metrics.actualBoundingBoxAscent;
      return {
        ascent: ascent,
        halfLeading: (lineHeight - (ascent + descent)) / 2,
        inkTop: (lineHeight - (ascent + descent)) / 2 + ascent - inkAscent,
        inkHeight: inkAscent + metrics.actualBoundingBoxDescent
      };
    };
  })();
  function fontOf(el) {
    var style = getComputedStyle(el);
    return { css: style.fontStyle + " " + style.fontWeight + " " + style.fontSize + " " + style.fontFamily,
      size: parseFloat(style.fontSize), lineHeight: parseFloat(style.lineHeight) };
  }
  function placeStatus() {
    var script = fontOf(scriptEl);
    var scriptInk = ink("H", script.css, script.lineHeight);
    var baseline = scriptEl.getBoundingClientRect().top - paper.getBoundingClientRect().top
      + scriptInk.halfLeading + scriptInk.ascent;
    var numeral = fontOf(numeralEl);
    var numeralInk = ink(numeralEl.textContent, numeral.css, numeral.lineHeight);
    var caption = fontOf(captionEl);
    var report = fontOf(reportEl);
    paper.style.setProperty("--danger-top", (baseline + 44 - numeralInk.inkTop) + "px");
    paper.style.setProperty("--caption-gap",
      (numeralInk.inkTop + numeralInk.inkHeight + 20 - numeral.size - ink(captionEl.textContent, caption.css, caption.lineHeight).inkTop) + "px");
    paper.style.setProperty("--receipt-top", (baseline + 44 - ink(reportEl.textContent, report.css, report.lineHeight).inkTop) + "px");
  }

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
    return w + (w === 1 ? " word" : " words");
  }

  function put(el, key, v) {
    if (seen[key] !== v) { seen[key] = v; el.textContent = v; }
  }
  function setPhase(name) {
    if (seen.ph === name) return false;
    seen.ph = name;
    paper.className = "paper " + name;
    return true;
  }
  function setWash(k) {
    var pap;
    if (k === "deep") pap = "var(--deep-paper)";
    else if (k == null) pap = "none";
    else pap = "color-mix(in oklab, var(--wash-paper) " + Math.round(k * 100) + "%, transparent)";
    if (seen.wp !== pap) { seen.wp = pap; washPaper.style.background = pap; }
  }
  // The draining minute: one continuous linear animation per loop, never a stepped tick.
  function startBar() {
    if (barAnimation) barAnimation.cancel();
    barAnimation = null;
    if (reducedMq.matches) { barEl.style.transform = "scaleX(1)"; return; }
    barEl.style.transform = "scaleX(1)";
    barAnimation = barEl.animate([{ transform: "scaleX(1)" }, { transform: "scaleX(0)" }],
      { duration: 60000, easing: "linear", fill: "forwards" });
  }
  function renderDraft(d) {
    var r = d.done.slice().reverse();
    put(prevEls[0], "p0", r[0] || "");
    put(prevEls[1], "p1", r[1] || "");
    put(curEl, "cur", d.cur);
    put(countEl, "count", d.done.length + d.cur.length ? words(d) : "Type to start");
  }

  // The refusal is a pure function of t; it fires once as t crosses the deny beat
  // (not when a hidden tab resumes far past it).
  function renderDeny(t) {
    if (DENY && lastT < DENY.t && t >= DENY.t && t - DENY.t < 250) denyFeedback(paper, hairline);
    lastT = t;
  }

  function render(t) {
    if (t < lastT) lastT = -1;
    renderDeny(t);
    if (t < SILENT_END) {
      if (setPhase("type")) startBar();
      setWash(null);
      numeralEl.textContent = "";
      captionEl.textContent = "";
      warnEl.hidden = true;
      stoppedEl.hidden = true;
      put(reportEl, "rep", "");
      renderDraft(t < TYPE_END ? draftAt(t) : full());
      put(clockEl, "clock", clockAt(t));
    } else if (t < WARN_END) {
      setPhase("warn");
      setWash((t - SILENT_END) / WARN_MS);
      numeralEl.textContent = String(3 - Math.floor((t - SILENT_END) / 1000));
      captionEl.textContent = "KEEP TYPING OR THE DRAFT IS DELETED.";
      warnEl.hidden = false;
      stoppedEl.hidden = true;
      put(reportEl, "rep", "");
      renderDraft(full());
      put(clockEl, "clock", clockAt(t));
      placeStatus();
    } else if (t < CUT_END) {
      setPhase("cut");
      setWash("deep");
      numeralEl.textContent = "";
      captionEl.textContent = "";
      warnEl.hidden = true;
      stoppedEl.hidden = true;
      put(reportEl, "rep", "");
      renderDraft({ done: [], cur: "" });
      put(clockEl, "clock", "1:00");
    } else {
      // The failure screen: the same headline and red receipt the room and the Mac show.
      setPhase("report");
      setWash(null);
      numeralEl.textContent = "";
      captionEl.textContent = "";
      warnEl.hidden = true;
      stoppedEl.hidden = false;
      put(reportEl, "rep", "DRAFT DELETED AT " + clock(60 - Math.round(CUT_END / 1000)) + ". TYPE TO START AGAIN.");
      renderDraft({ done: [], cur: "" });
      put(countEl, "count", "0 words");
      put(clockEl, "clock", "1:00");
      placeStatus();
    }
  }

  function renderReduced() {
    setPhase("still");
    barAnimation = barEl.getAnimations()[0] || null;
    if (barAnimation) barAnimation.cancel();
    barEl.style.transform = "scaleX(1)";
    setWash(null);
    numeralEl.textContent = "";
    captionEl.textContent = "";
    warnEl.hidden = true;
    stoppedEl.hidden = true;
    put(reportEl, "rep", "");
    renderDraft(full());
    put(clockEl, "clock", "1:00");
  }

  function tick() {
    if (document.hidden || document.getElementById('landing').hidden) return;
    if (reducedMq.matches) { renderReduced(); return; }
    render((Date.now() - t0) % LOOP);
  }

  startBar();
  tick();
  setInterval(tick, 50);
  if (reducedMq.addEventListener) reducedMq.addEventListener("change", function () { barAnimation = null; tick(); });
  document.fonts.ready.then(function () { placeStatus(); });
  window.addEventListener("resize", placeStatus);
})();
