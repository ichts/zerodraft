# Zero Draft Web Design System (Flood)

This is the visual constitution for all web-facing pages in this repo. It supersedes the Kami system (kept in git history only). Every new page, component, section, or experiment must reference this document. The reference implementation is `design-demos/flood-v2.html`.

## 1. Product soul

Zero Draft is a threat the user hires. Two pains created it:

- Opening a notes app and writing nothing: the inner editor kills sentences before they land.
- A head too full to articulate: the only way out is a stream-of-consciousness dump.

The 8-second deletion is a forcing mechanism: the gun must be faster than the inner editor. Stopping is death; forward motion is survival. The draft you produce is the words that escaped the graveyard.

Positioning line: **删掉草稿的不是这个工具，是你的停顿。纸堆就是证据。** (The tool does not delete your draft; your pause does. The pile is the evidence.)

Lineage: The Most Dangerous Writing App. Zero Draft adds a bounded 60-second session and an artifact you keep.

What we are NOT: a gentle, comforting writing companion. Never soften the deletion into "compost" or reassurance. The threat keeps its teeth.

### Voice

Short, plain sentences about mechanism and consequence. Direct labels: "Start typing", "Keep writing", "Draft deleted". Banned registers: therapeutic, ceremonial, self-help ("honest sentence", "begin when you are ready", "honor your practice"), product advertising inside the graveyard, and any copy that says deletion is okay.

## 2. Design principles

1. **Messy, urgent, raw - never calm or polished.** The old Kami system (parchment, serif serenity, ink blue, printable composure) is dead. This app is a mess in progress.
2. **Copy appears at the moment it explains.** Hero keeps one hook + one CTA. Mechanism lives as spec annotations on the paper. Rules sit beside the objects they constrain. Payoff waits below. No paragraph where a glance works.
3. **Danger is the dramatic climax and must be felt in the body,** not read in small text. Every screen needs a danger state that changes the environment, not just a widget.
4. **The pile does three jobs and no more.** It is the only non-calm element (tone). It reframes nothing - it warns (the graveyard is where stopped drafts go). It replaces a paragraph of persuasion (quantity without judgment, shown not said).
5. **Threat grammar, applicable to any future concept:** the threat is visible at rest, it advances continuously through the silence window, it is violent at the end, and a single keystroke reverses it instantly.

## 3. Color

| Token | Value | Use |
|---|---|---|
| `--bg` | `#f1f0eb` | Page canvas. Neutral bone, never parchment, never beige-calm. |
| `--paper` | `#ffffff` | The one clean surface. Only the paper and result/payoff cards. |
| `--ink` | `#17150f` | Text, primary buttons, borders. |
| `--dim` | `#6b665b` | Secondary text, chrome labels. |
| `--faint` | `#b3ada0` | Placeholders, captions, annotations. |
| `--red` | `#c8392f` | Danger. See the discipline below. |

Red discipline: `#c8392f` means danger, deletion, or a graveyard mark. The only pre-approved non-danger uses are the wordmark underscore, strikethroughs inside fragments, the raw-card tag, and the payoff arrow - all deletion-adjacent. Never spend red on decoration, links, success, or generic accents. UI feedback (copied/saved) uses ink. Blue usage: zero. Selection: `rgba(200,57,47,.22)` (blood-adjacent by nature, allowed).

Shadows: whisper + one diffuse layer max on the paper (`0 1px 0 rgba(23,21,15,.06), 0 24px 60px rgba(23,21,15,.1)`). No hard floating cards, no colored glows outside danger. Danger glow: `0 0 0 4px rgba(200,57,47,.08)` plus the veil (`inset 0 0 140px rgba(200,57,47,.3), inset 0 0 40px rgba(200,57,47,.12)`).

## 4. Typography

Two families, no more.

- **Newsreader** (serif): the human layer. H1/H2 weight 500, draft text and result metric weight 400-500, placeholders italic.
- **IBM Plex Mono**: the machine layer. Fragments, spec annotations, status lines, buttons, clocks, countdown, corpus. Chrome labels uppercase with `.12-.18em` tracking.

Scale:

- H1: `clamp(40px, 5.4vw, 64px)`, line-height 1.06, letter-spacing `-.015em`, `text-wrap: balance`.
- Lead italic: `clamp(17px, 2vw, 21px)`, `--dim`.
- Draft on paper: 19px / 1.8 (mobile 17px).
- Chrome labels: 10-10.5px mono uppercase (mobile 9-9.5px, tracking `.08em`).
- Countdown numeral: mono 500, `clamp(110px, 16vw, 180px)`, `text-align: center`.
- Result metric: `clamp(72px, 9vw, 96px)` serif 500.

Rules: headings use 500, never synthetic bold. All numerals `font-variant-numeric: tabular-nums`. Body weight 400. `::selection` as above. `-webkit-font-smoothing: antialiased`. CJK text deliberately falls back to the system serif (PingFang SC / Songti) - no bundled CJK face; TsangerJinKai02 belonged to the dead system and is banned.

## 5. The flood (signature layer)

An `aria-hidden` texture layer under `.page` (z-index 0): dozens of mono fragments - fossils of drafts that died of hesitation. It is the graveyard made visible and the only non-calm element at rest.

Corpus register (hard rule): every line is a fossil of hesitation - abandoned, interrupted, rationalized, never finished. Typos welcome. `~strike~` for editor kills. Allowed: "saved as draft. never opened again", "rewrite of the rewrite of the openin", "i paused to check my phone. that was it", "written in my head on the train,\ngone by the platform". Banned: comfort ("the good version is in here somewere" read as hope), writing advice, self-help, product slogans ("if i stop moving this page dies"), proud output ("this is bad but its SOMETHING").

Layout algorithm (JS, seeded RNG, re-run on debounced resize and `document.fonts.ready`):

- Protect the clean column: the paper, the payoff block, and the hero text measured by a `Range` over the h1 (true text width, not block width).
- Desktop: fragments live only in the left/right gutters beside the clean column (regions are `overflow: hidden` so fragments clip at the column edge - the mess continues "under" the clean sheet). Gutter opacity `.09-.18` via `--fo`, sizes 13-28px, rotation ±5deg. One near-invisible full-width band (opacity `.05-.10`) may sit above the hero, and one axis band of mess (opacity `.14-.22`, 12-17px, single fragment per row) sits directly in the reading axis between the CTA and the paper - the graveyard reaches the paper's edge without touching the words.
- Mobile (<700px): fragments live in horizontal bands in the gaps between clean blocks (nav-hero, hero-paper, paper-payoff, below payoff), smaller and sparser; never behind the paper or the hero CTA row.
- Stratified rows (~96px desktop, 60px mobile) with jitter; corpus shuffled without repeats; rotation ±5deg.
- The fullscreen trial runs on the same bone ground (`--bg`): on desktop the fossil layer strengthens across both margins (12-22px, opacity `.05-.11`); on mobile it protects a full-width ~200px band around the ~30% anchor line and places fragments in the bands above and below it, never under the current line - the trial is the same world as the landing, never a calmer white void.

States:

- Danger: all fragments `color: var(--red)` and `opacity: min(var(--fo)*3.4, .5)` with a .5s transition - the graveyard closes in.
- Wipe (joinPile): the lost draft (first ~64 chars, whitespace-collapsed) becomes a new fragment - red flash at .85 opacity, then settles over 1.6s to faint ink, persisting for the visit in a dedicated joined sublayer (`#floodJoined` on the landing, `#trialJoined` in the trial) that flood relayout (debounced resize, font readiness) never rebuilds. When the wipe happens in the fullscreen trial, the fragment lands in the trial's joined layer within ~200px of the last line, and the failure surface holds back ~600ms and stays translucent so the arrival is seen first. "gone. it joined the pile." is a warning, delivered deadpan.
- No float, drift, or pulse animations. The pile is dead things; dead things do not move.

## 6. The paper (the tool)

The only clean thing on the page. Anatomy, top to bottom:

1. **Spec header inside the paper** (border-bottom): rules attached to the object they constrain - `forward only / 5s warn / 8s wipe / 60s` (slashes in red) left; `Finish ->` (hidden until session) + `T-01:00` clock right. Never put the rules outside the paper.
2. **Sheet** (`contenteditable`, role textbox multiline): Newsreader 19/1.8, `pre-wrap`, `word-break: break-word`, no outline except `:focus-visible { box-shadow: inset 0 0 0 2px rgba(23,21,15,.35) }`.
3. **Placeholder** carries the mechanism, italic faint, exactly: "Click here. Type anything. / No deleting, no pasting, no undo. / Stop for eight seconds and it's gone."
4. **Countdown overlay** (danger only): red mono numeral centered + caption "keep typing or the draft is deleted", `aria-live="polite"`, `pointer-events: none`.
5. **Footer status line** (border-top): the narrator. Approved lines only:
   - Idle: "the pile is patient. it gets whatever you stop writing."
   - Session: "forward only. don't stop."
   - Blocked action (deny): "no going back." (1.2s, plus a 2px paper shake, 160ms)
   - Wipe: "gone. it joined the pile." in red, durable until the next session starts.
   - Right slot: live word count (replaces the fwd-only tag).
6. **Result card** (covers the paper): serif metric `N`, label "words you would not have written", sub "session: Ns - forward only", and the draft itself printed below the metric in the raw-card treatment (mono ~13px, dashed border, slight rotate, first ~3 lines) - the keep screen shows the goods, not just a number. Actions in this order: **Copy full text (primary, ink)**, Copy for AI (ghost), Download .md (ghost), Go again (text link). On finish: Finish button hides, focus lands on the primary action. Copy for AI = cleanup prompt + raw text via `navigator.clipboard`; Download .md via Blob.

The paper's writing area (preview and live inline editor alike) renders zen-centered: Newsreader, text centered, with the current line anchored at roughly 38% of the sheet height - matching the inline live editor's anchor, so the landing demo and the live session read as one continuous writing view across the handoff. (The fullscreen trial anchors lower, near 30%.)

## 7. Danger choreography

Timings are contract, not taste: danger at 5000ms of silence, deletion at 8000ms, session 60s, tick 100ms. The ticker's authority is exactness.

| Element | Idle/session | Danger (5-8s) | Wipe (8s) |
|---|---|---|---|
| Fragments | faint ink | red, opacity x3.4 cap .5, .5s ease | one new fragment joins (see §5) |
| Veil | transparent | red inset shadow, opacity 1, .35s | clears |
| Paper | ink border | red border + red ring | sheet `blur(6px)` + opacity 0, .45s |
| Sheet | full | opacity .35 | clears to empty |
| Countdown | hidden | red numeral 3-2-1 in the margin beside the current line (never on the words), hint stacked under it, caption | hides |

The countdown never prints on top of the draft. It sits below the current line (or moves above it when the bottom space is tight); the veil and the reddened fragments carry the environmental half of the beat. The draft dims as silence grows - the threat looks like it is already eating the words - but the words are never edited, blurred out, or deleted before the wipe itself. Threat comes from the environment, not from touching the text.
| Clock | ink | red | resets after aftermath |
| Placeholder | mechanism copy | hidden | "Draft deleted. Type to start over." until next session |

Recovery: one keystroke clears danger instantly (all classes off, no lingering transitions). After wipe the "gone" message and "Draft deleted" placeholder persist until the user starts again - deletion has a durable consequence, not a 2-second flash.

Every blocked action (delete, paste, cut, undo, selection-replace) has a body: the narrator flashes "no going back." in red for ~1.2s, the paper shakes 2px for 160ms, and a red hairline flashes on its border for 90ms. The teeth are felt, not just logged.

Demo preview (the page teaches before the user touches it): types the sample once at a human cadence (base 120-190ms per char, longer at spaces, punctuation, and newlines), then holds a mid-sample teaching pause: the real 5-second danger beat is felt, and at 6.5 seconds the danger clears and typing resumes. The sample finishes, then goes silent for real: danger 3-2-1, the draft is deleted at 8 seconds, and its first ~64 chars fly out of the paper into the gutter - a red fossil that settles to faint ink while the narrator turns durable red: "gone. it joined the pile." The placeholder becomes "Draft deleted. Type to start over." The one-shot two-pause arc delivers the entire positioning: survive the beat, lose the next one. Pauses while offscreen (`IntersectionObserver`, threshold .15) or `document.hidden`; the preview clock only advances while unpaused. Any real input (keydown anywhere, click, IME start) interrupts permanently: the preview freezes and restores the completed sample - no fossil, no dead state. Under `prefers-reduced-motion` the dead state renders statically: empty sheet, one settled fossil, the dead red line.

## 8. Motion rules

- One-shot only. No ambient loops, ever - no floating, pulsing, shimmering, drifting.
- Transition budget: interactions `.12-.18s`, state changes `.3-.5s`, wipe ≤ `.62s`. Easing: `ease`/`ease-out`; falls may use `cubic-bezier(.55,0,.85,.36)`.
- `prefers-reduced-motion: reduce`: all transitions and animations off globally (`* { transition: none !important; animation: none !important }`), color changes remain (danger still turns red), wipe is instant, demo renders static, `scroll-behavior: auto`.
- Focus-visible everywhere: `2px solid var(--ink)`, offset 2-3px. Never remove outlines.

## 9. Interaction contract

- **First keystroke anywhere starts the session.** A document-level `keydown` (target is body, printable key, no modifiers) synchronously focuses the editor inside the keystroke so the browser and IME route input to it. The page IS the tool; no click required.
- **Typing or clicking the paper goes straight to the fullscreen trial.** The landing paper is a preview and an invitation, not the writing room: the first input arms the session for one frame, the handoff morph carries the draft into the trial, and keys struck mid-morph are buffered and replayed after focus lands. The inline embedded session is a transient arming step, never a destination.
- **Forward-only guards** on `beforeinput`: block `delete*`, `historyUndo/Redo`, `insertFromPaste/Drop/Yank/ReplacementText/Transpose`; allow `insertText/Paragraph/LineBreak/CompositionText` only with a collapsed caret at the very end (`caretAtEnd()`); `paste/cut/drop` prevented. Every block fires the deny nudge ("no going back." + 2px shake) and restores the caret to the end.
- **IME composition works.** Track `compositionstart/end`; never rewrite the sheet DOM during composition; sync the model on `compositionend`.
- During live typing the browser owns the sheet DOM (flood renders plain text); styled layers may only rebuild the DOM outside composition and always restore the caret to the end.
- Cmd/Ctrl+Enter finishes, Finish button finishes, 60s auto-finishes. Finish hides the Finish control and focuses the primary action.
- No localStorage, no session history, no streaks. The visit remembers nothing except joined fragments (in-DOM only).

## 10. Copy placement map

| Place | Approved copy | Nothing else |
|---|---|---|
| Hero | "It's not supposed to be good yet." / "So we made polishing impossible." / CTA "Give it sixty seconds." + hint "or just click the paper and type" | No mechanism, no rules, no kicker |
| Spec header | "forward only / 5s warn / 8s wipe / 60s" | - |
| Placeholder | "Click here. Type anything. / No deleting, no pasting, no undo. / Stop for eight seconds and it's gone." | - |
| Payoff | kicker "What comes out", H2 "Raw goes in. A draft comes back.", raw card (typos: "ok thesis is peopel dont lack ideas they lack permission...") -> clean card ("People don't lack ideas - they lack permission..."), caption "The shaping happens in whatever AI you already use. Copy for AI puts your raw text and a cleanup prompt on the clipboard - Zero Draft itself has no AI inside. That's the point." | - |
| Result | "N words you would not have written", "session: Ns - forward only" | - |
| Footer | "Zero Draft - the draft before the draft", "your writing never leaves this page" | - |

No em dash (U+2014) and no en dash (U+2013) anywhere in code or copy. Use hyphens.

## 11. Layout and responsive

- `.wrap` max-width 1120px, padding 32px (mobile 20px). Paper `min(700px, 100%)`, min-height 460px (mobile 420px).
- Hero centered, padding 52/26 desktop (40/22 mobile); paper zone padding 24/84 desktop.
- Breakpoints: 820px (payoff stacks, arrow rotates, hero compresses, paper-foot stacks, spec label 9.5px) and 700px (flood switches to band mode).
- `overflow-x: hidden` on body; verify `scrollWidth <= viewport` at 390px.
- Payoff cards: raw = mono 13.5px dashed border, rotate(-.5deg); clean = white paper card, rotate(.4deg). One mild rotation each; never more.

## 12. Anti-patterns (instant rejection)

- Parchment/beige calm, ink blue, Kami tokens, Charter/TsangerJinKai type.
- SaaS tropes: pill buttons, feature card grids, gradient blobs, icon rows, dashboard chrome, centered success panels.
- Comfort or therapy copy; reassuring the user about deletion.
- Ambient animation of any kind; looping demos; parallax.
- Product slogans or instructions inside the graveyard corpus.
- More than two type families; synthetic bold; cool grays.
- Explaining the pile's metaphor in body copy. It is felt through the wipe moment and the footer narrator, never lectured.

## 13. Production port notes

The production `index.html` is Datastar-native; the flood shell ports as skin only. `_session.*` signals stay the single UI truth on `<body>`; `window.FirstLineLandingDemo` stays the stateless browser bridge; JS writes state only by dispatching custom `fl*` events. The demo engine in `flood-v2.html` already mirrors that contract (contenteditable + beforeinput guards + composition flag + document-level first-keystroke), so behaviors port 1:1. The flood layer is an `aria-hidden` DOM layer under `.page`, driven by declarative `data-class` on the danger/complete signals. Zen rendering, the WAAPI morph to the fullscreen trial, and the `#trial` route are untouched. Read the repo AGENTS.md "Web architecture boundary" section before touching production.

## 14. Verification checklist (run for every change)

- Desktop 1440x1000 and mobile 390x844: hero / typed / danger / wipe aftermath / result; `scrollWidth` equals viewport; no console errors.
- Forward-only: Backspace/Delete/Cmd+Z/X/V, paste, cut, drop, selection-replace all blocked with nudge; IME composes; first keystroke without click starts the session.
- Demo: plays once, danger beat visible, static after; interrupt clears; hidden tab pauses; reduced-motion renders static.
- Danger is felt in a full-page screenshot without reading any text.
- `grep -n $'\u2014' and $'\u2013'` return nothing.
- Focus ring visible on every interactive element; countdown announced via `aria-live`.
