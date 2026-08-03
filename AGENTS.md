# Project instructions

These repository-specific rules extend the global `~/.pi/agent/AGENTS.md`. Do not duplicate global rules here. The sections below add the discipline and product contracts that are specific to First Line; the global file still owns the universal rules (no em dash, no unrequested co-authored trailer, no editing generated files, no exposed secrets, and no commit/push/deploy without authorization).

## How to work here

- Address the developer as 哥 and communicate with the developer in Chinese. Keep product copy and the public pages in the product's own English voice.
- Do not disclose private chain-of-thought. Give conclusions, evidence, tradeoffs, and validation results.
- Treat strict feedback as concern for product quality, not hostility. Stay calm, direct, and accurate. Treat praise as a reason to hold the bar, not lower it.
- When a requirement is incomplete, first read the current code and tests, `design/DESIGN.md`, the nearest module `AGENTS.md`, and project history; then ask only the smallest decision question that actually blocks progress.
- Surface high-impact hidden choices early: a new dependency, a state-model change, a new top-level modal or route, or a security or architecture boundary. Argue against shortsighted or speculative directions and offer a simpler, verifiable alternative.
- Do not escalate every task into speculative architecture. Exploration must converge to a decision or a bounded experiment.
- The user is building a durable product, not stacking features. Protect consistency, real usefulness, and long-term maintainability over local convenience.

## Diagnosis and product judgment

Use these as internal reasoning lenses; do not emit long philosophy.

Three layers, in order:

1. Phenomenon - the symptom, error, failing state, or user confusion, reproduced as the real user sees it.
2. Essence - the root cause, ownership boundary, data flow, and module interaction that produced it.
3. Design - the simpler system shape that prevents recurrence and stays coherent as the product evolves.

Work order: how to fix -> why it broke -> how to make it right by design -> concrete implementation and validation.

Classify the work before executing, and act on the classification:

- Known knowns: confirmed direction and explicit requirements.
- Known unknowns: questions the user already wants explored.
- Unknown knowns: frameworks, dependencies, data models, security, or architecture choices the agent must actively expose.
- Unknown unknowns: hidden assumptions that could rot the product or architecture later.

## Code quality and taste

Treat the principles as design checks, not as license to manufacture abstraction.

- SRP / OCP / LSP / ISP / DIP: one reason to change; add a stable extension point only after a real change appears; preserve the observable contract callers depend on; keep interfaces narrow and shaped by the consumer; isolate volatile infrastructure behind a clear boundary when it lowers coupling.
- DRY / KISS / YAGNI: eliminate duplicated knowledge, not merely similar-looking code; prefer simple and explicit over clever; do not build for an unconfirmed future.

Size and structure signals:

- Functions usually under about 20 lines and doing one thing; nesting usually under three levels.
- A single source file over about 800 lines is a strong refactor signal, not a reason to split arbitrarily. `index.html` is a deliberate exception: it is the single deployable landing artifact and stays one file.
- Split by directory only when responsibility stops being easy to scan.

Bad smells to challenge: rigidity, needless duplication, cyclic ownership, fragility, obscure naming, data clumps, growing special cases (the real problem is usually the data model), and over-design for imagined change. Fix local and safe smells inside the area you touch; report broader risks as bounded follow-ups instead of silently widening scope.

## Entropy control

Before adding a new pattern, check how this codebase already handles the same class of problem, then match it:

- Web UI state: the only truth is the `_session.*` signals on `<body>`; write them only through the `fl*` custom-event bridge (see "Web architecture boundary"). Never introduce a second state system or a `root`/`mergePaths` write path.
- Web visuals: reuse the `design/DESIGN.md` tokens, fossil rules, and danger choreography before inventing a variant.
- macOS: follow the existing deadline adjudication, navigation routing, persistence, deny-feedback, and reduced-motion patterns; extend the existing types instead of adding a parallel one. New top-level modals must join the existing pending-modal routing, not each go their own way.

The goal is that code from ten contributors reads as one design language.

Design authority: the web surface answers to `design/DESIGN.md` (Flood); the macOS app answers to Apple HIG first (see `apps/macos/FirstLine/AGENTS.md`). Generic design and motion skills are transferable methodology only and never override the platform constitution.

## Current product and scope

- First Line is the current product. The root web surface is its public landing site and browser trial.
- `apps/macos/FirstLine/` is the native macOS implementation. It is a separate Swift-native track and does not share a Datastar runtime with the web surface.
- Zero Draft is the historical product origin. Historical files are not requirements for current First Line work unless the task explicitly targets them.
- Current code and tests override historical PRDs, plans, screenshots, and prototypes when they disagree.

## Root web surface

- `index.html` is the canonical landing page and deployment source of truth.
- `kami-landing.html` is a visual reference copy. Do not assume it is synchronized with `index.html`.
- `download.html`, `checkout-success.html`, `help.html`, `privacy.html`, `refund.html`, `terms.html`, and `release-notes.html` are supporting public pages.
- The supporting public pages (`download.html`, `checkout-success.html`, `help.html`, `privacy.html`, `refund.html`, `terms.html`, `release-notes.html`) are self-contained static HTML with inline vanilla CSS and JavaScript and no framework.
- `index.html` (the landing and trial surface) is Datastar-native: it loads `datastar-pro.js` as an ES module and keeps inline CSS plus an inline browser-bridge module. Do not add any other build framework. Do not regress the landing back to a parallel vanilla state machine.
- The trial/demo API is `window.FirstLineLandingDemo`. It is now the browser-bridge layer (see "Web architecture boundary"): a set of stateless functions that read the DOM, perform browser-only work, and dispatch custom `fl*` DOM events. Preserve `.demo-writing-surface`, `.live-demo-editor`, `.demo-session-bar`, `.demo-result`, `.demo-failure`, `.demo-toast`, `.demo-prompt`, `.trial-overlay`, `.trial-writing-surface`, `.trial-editor`, `[data-trial-launch]`, and the `#trial` route.
- Preserve the forward-only writing contract: input appends at the end; deletion, paste, cut, undo, and selection replacement stay blocked; IME composition remains usable; danger begins after 5 seconds of silence and failure clears the current draft at 8 seconds.
- A trial session completes either by writing for the full 60 seconds or by clicking Finish (also Cmd/Ctrl+Enter). Both paths lead to the same result card.
- The trial result card offers Copy full text, Copy for AI, and Download .md as export actions. Copy for AI formats the draft with a cleanup prompt for the user's AI-to-Obsidian workflow.
- The trial provides an optional writing prompt behind a "Need a prompt?" toggle. Prompts are suggestions only; they never auto-insert text.
- The trial does not persist writing statistics, session history, streaks, or any localStorage data. The result card shows only the current session's word count and duration.
- On all devices, the landing paper shows the demo preview on load. The first keystroke interrupts the demo and starts a live session with no click required: focus is set synchronously inside that keystroke, so the browser and IME route input to the editor (this does not rely on load-time programmatic focus, which is unreliable in real browsers and for IME).
- The landing paper is a preview and an invitation, not the writing room. The first keystroke (or click/tap on the paper) arms the session for one frame, then the handoff WAAPI morph carries the draft and the remaining time into the fullscreen trial. Keys struck mid-morph are buffered and replayed into the trial editor after focus lands. The inline embedded session is a transient arming step, never a destination; IME composition finishes inline before the morph triggers.
- A writing session renders zen-style in the fullscreen trial: only the current line is fully visible, the previous line is faint, older lines are transparent, and the current line stays anchored at a fixed point (~35% of the viewport height) via internal scrolling - the window does not scroll. Result and failure render over the trial surface.
- The landing page is the tool: no practice or privacy sections below the hero. The footer carries the one-line privacy promise and the support links.
- The landing preview (touch devices and the reference animation) uses motion to explain that contract. It should type once when the writing surface enters view, hold a mid-sample pause long enough to show the real 5-second danger threshold and then recover (danger clears, typing resumes), finish the sample, then go silent for real and die at the 8-second wipe - leaving a fossil in the pile and the durable red dead state - and then remain static. Activating the paper stops playback permanently for the visit.
- Never turn the landing preview into an ambient loop. Pause its timeline while offscreen or while the document is hidden, finish it when entering the trial, and render the dead state statically under `prefers-reduced-motion` (empty sheet, one settled fossil, the dead red line). A live session never pauses: silence danger and deletion keep running while offscreen or hidden.

## Web architecture boundary

Runtime on the landing/trial surface: Datastar Pro v1.0.2 (`datastar-pro.js`, loaded as `type="module"`). v1 colon syntax only (`data-signals`, `data-computed`, `data-text`, `data-show`, `data-class`, `data-attr`, `data-on:*`, `data-on-interval`, `data-effect`, `data-ignore`). Pure frontend: no backend, no SSE, no `@get/@post`, no `data-persist`, no `data-query-string`.

- Signals are the ONLY UI-state truth. The session state lives in the `_session.*` signal object declared on `<body>` via `data-signals` (context, active, failed, complete, text, startedAt, duration, lastInputAt, remaining, dangerSeconds, dangerActive, resultText, resultWords, promptOpen, promptIndex, promptText, toastVisible, toastText, morphing). `_session.clock` is `data-computed`. There is NO parallel JS state object.
- The runtime also exports `root`, `mergePatch`, `mergePaths`, and `getPath`. `root` IS the same page signal store the bindings read, and writing it from JavaScript does update bindings. Those exports are a thinly documented, version-sensitive programmatic surface, not an officially preferred application API. The project deliberately does NOT write signals through them. Its single JS-to-signal policy is the custom-event bridge: JavaScript dispatches custom `fl*` DOM events and `data-on:fl*` expressions write the signals. This is a project-chosen boundary, not a runtime limitation. Do not switch to `root`/`mergePaths` writes and do not mix the two write policies.
- `window.FirstLineLandingDemo` is a stateless browser-bridge module. It holds no UI state (only genuinely non-UI plumbing: the IME composition flag, timers and observers, demo animation timeline counters, focus return references, and WAAPI/geometry state). Bridge contract:
  - READ UI state from the DOM (element text, the `body.trial-mode` / `.demo-writing-surface.is-live` / `body.trial-morphing` classes (all declarative `data-class`, mirroring `_session.context`/`_session.morphing`), and contenteditable state) or from values passed in by expressions; never from the signal store directly.
  - WRITE UI state by dispatching custom `fl*` DOM events on `document.body` (e.g. `flinput`, `flactivate`, `flentertrial`, `flexittrial`, `flcomplete`, `flfail`, `fldanger`, `fltoast`, `flprompt*`, `flreset`, `flmorphing`, `flroutecheck`). The matching `data-on:fl*` expressions on `<body>` translate each event's `evt.detail` into signal patches.
- The session ticker is a `data-on-interval__duration.100ms` expression that reads signals and calls the pure `FirstLineLandingDemo.tickDispatch(...)` helper, which dispatches `flcomplete` / `flfail` / `fldanger`. Pure helpers called from expressions are allowed; they must be stateless.
- DOM side-effects of state transitions (blur, contenteditable toggle, focus move, inline chrome hide) run in `FirstLineLandingDemo.onComplete` / `onFail`, invoked from `data-effect` expressions that watch `_session.complete` / `_session.failed`.
- Custom JavaScript remains only for browser-only capabilities: contenteditable selection and forward-only guards, IME composition, the zen renderer, the WAAPI morph, clipboard and Blob download, and the demo typing sequencer. The session editor subtree carries `data-ignore` so Datastar does not fight the zen-rendered contenteditable DOM; the editors' `is-demo-danger` class is therefore applied imperatively by the bridge while the writing-surface class is declarative (`data-class`).
- `datastar-inspector.js` is a dev-only tool. It is loaded and the `<datastar-inspector>` element is mounted only when the page is opened with `?debug`; it is never present in production markup.
- Do not maintain duplicate truth in signals and JavaScript. Durable business truth would belong to the server; the landing has no server, so the transient UI signals on `<body>` are the whole truth.
- The supporting public pages remain vanilla static HTML with no framework. Do not migrate them without explicit authorization.

## Product voice

- Explain the mechanism and consequence in short, plain sentences.
- Position First Line as an opinionated forced-output writing tool: the user writes forward, cannot edit the first draft, and loses it after eight seconds of silence.
- Take inspiration from the uninterrupted-output idea behind 750 Words, but do not imply an affiliation or claim features such as streaks, history, accounts, or analytics.
- Avoid therapeutic, ceremonial, or self-help language such as "honest sentence", "long practice", or "begin when you are ready". Prefer direct labels such as "Start typing", "Keep writing", and "Draft deleted".

## Visual system: Flood (landing) and Kami heritage (supporting pages)

The landing page uses the Flood design system defined in `design/DESIGN.md` - that document is the visual constitution for all landing work (tokens, the fossil layer rules, paper anatomy, danger choreography, motion rules, anti-patterns). Read it before changing landing markup or CSS. Its short form:

- canvas: neutral bone `#f1f0eb` (never parchment); the paper is the only clean white surface
- the background is flooded with aria-hidden mono fossils of drafts that died of hesitation, confined to gutters and small bands outside the clean column; danger turns them red
- Newsreader (human layer) + IBM Plex Mono (machine layer); red `#c8392f` is reserved for danger and deletion-adjacent marks; blue usage is zero
- danger is environmental: red veil, reddened fossils, a countdown that hangs above the current line and never prints on top of the draft
- a wiped draft joins the pile: its first ~64 chars become a new fossil, and the narrator line turns durable red until the next session
- one-shot motion only; no ambient loops; `prefers-reduced-motion` renders everything static

The supporting public pages (`download.html`, `checkout-success.html`, `help.html`, `privacy.html`, `refund.html`, `terms.html`, `release-notes.html`) remain self-contained vanilla static pages on the retired Kami heritage (parchment, serif, ink blue). Do not migrate them to a framework or to Flood without explicit authorization.

Do not introduce unrelated SaaS or Mole-style cards, pill buttons, cool gray palettes, or decorative component systems on any page. Footer, FAQ, help, privacy, and release sections must serve a real support, legal, or release need.

## Historical material

- `prototype.html`, `src/styles/`, `datastar-inspector.js`, and `datastar-pro.js` belong to the legacy Zero Draft web app, except that `datastar-pro.js` and `datastar-inspector.js` are now ALSO the live runtime/dev-tool for the First Line landing (see "Web architecture boundary"); treat them as active there.
- `zerodraft-prd.md` and `docs/design-system.md` describe the historical product and design system.
- Do not restore Datastar behavior, legacy signals, old visual tokens, or `zerodraft_history` persistence into the current landing unless explicitly requested.

## Development and validation

Preview the web surface over HTTP:

```bash
python3 -m http.server 8000
# Open http://localhost:8000/index.html
```

There is no automated root-web test suite. For web changes:

- inspect affected pages at desktop and mobile widths
- exercise the browser trial's typing, danger recovery, failure, completion, keyboard restrictions, and IME behavior when relevant
- verify focus visibility and `prefers-reduced-motion` behavior for interaction or motion changes
- verify visual layout consistency: hero content width and left edge must align with the footer; centered elements must be centered; text must not be clipped or orphaned; interactive elements must have consistent radius, color, and spacing
- capture screenshots of every changed state (landing hero, demo animation stages, trial typed/danger/failure/complete, morph handoff) and inspect them before reporting completion

For native macOS work, follow the deeper instructions under `apps/macos/AGENTS.md` and `apps/macos/FirstLine/AGENTS.md`. From `apps/macos/FirstLine/`, run:

```bash
swift build
swift test
```

UI, editor, or motion changes on the macOS app must also be exercised in a real debug window (typing, danger, failure, aftermath, deny feedback, success, reduced motion, and the fossil gutter at the minimum window width) and the result recorded in `apps/macos/FirstLine/docs/MANUAL_QA.md`.

## Delivery contract

After a meaningful change, report:

1. Core implementation - what changed and why it removes the root cause.
2. Taste self-check - special cases, responsibility boundaries, complexity, naming, compatibility, and the validation actually performed.
3. Improvements - only concrete residual risks or bounded follow-ups, no speculative backlog.

## GEB fractal documentation protocol

The map must match the terrain. Code is the machine view; the `AGENTS.md` files and source headers are the semantic view. When they disagree, the change is not finished.

- L1 `/AGENTS.md`: this file - product scope, the web and macOS boundaries, and cross-cutting contracts.
- L2 `/{module}/AGENTS.md`: module map, members, exposed interface, and local boundaries (for example `apps/macos/AGENTS.md` and `apps/macos/FirstLine/AGENTS.md`).
- L3 source-file headers: the macOS Swift sources carry `[INPUT] / [OUTPUT] / [POS] / [PROTOCOL]` contract headers; keep them current when dependencies, exports, or responsibility change.

The web surface is a single `index.html`, so its durable truth lives in `design/DESIGN.md` (visual constitution), the "Web architecture boundary" section above, and the `_session` signals - not in an L2/L3 hierarchy. Apply L3 headers only to hand-written, structured source with a real responsibility; do not spray them onto generated or vendored files (`datastar-pro.js`, `datastar-inspector.js`) or the supporting static pages.

Workflow after a code change: code -> nearest header and L2 check -> L1 check -> validation -> done. Before entering a module: nearest `AGENTS.md` -> module `AGENTS.md` -> relevant L3 header -> code.
