# Project instructions

These repository-specific rules extend the global `~/.pi/agent/AGENTS.md`. Do not duplicate global rules here.

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
- Clicking or tapping the paper also activates it - that is how touch users begin, so page load never summons the on-screen keyboard.
- Activating the paper (first keystroke, click, tap, or Enter/Space while focused) stops any preview playback and turns the paper into an inline session editor with the same forward-only, 60-second, 5-second/8-second contract.
- An inline session renders zen-style like the fullscreen trial: only the current line is fully visible, the previous line is faint, older lines are transparent, and the current line stays anchored at a fixed point (38% of the paper height) via internal scrolling - the window does not scroll. Result and failure cards render inline in place of the paper. Starting the fullscreen trial from an active inline session carries the draft and remaining time into the fullscreen editor; otherwise the fullscreen trial starts fresh.
- The landing page is the tool: no practice or privacy sections below the hero. The footer carries the one-line privacy promise and the support links.
- The landing preview (touch devices and the reference animation) uses motion to explain that contract. It should type once when the writing surface enters view, pause long enough to show the real 5-second danger threshold, recover before deletion, and then remain static. Activating the paper stops playback permanently for the visit.
- Never turn the landing preview into an ambient loop. Pause its timeline while offscreen or while the document is hidden, finish it when entering the trial, and render the completed static draft under `prefers-reduced-motion`. A live inline session never pauses: silence danger and deletion keep running while offscreen or hidden.

## Web architecture boundary

Runtime on the landing/trial surface: Datastar Pro v1.0.2 (`datastar-pro.js`, loaded as `type="module"`). v1 colon syntax only (`data-signals`, `data-computed`, `data-text`, `data-show`, `data-class`, `data-attr`, `data-on:*`, `data-on-interval`, `data-effect`, `data-ignore`). Pure frontend: no backend, no SSE, no `@get/@post`, no `data-persist`, no `data-query-string`.

- Signals are the ONLY UI-state truth. The session state lives in the `_session.*` signal object declared on `<body>` via `data-signals` (context, active, failed, complete, text, startedAt, duration, lastInputAt, remaining, dangerSeconds, dangerActive, resultText, resultWords, promptOpen, promptIndex, promptText, toastVisible, toastText, morphing). `_session.clock` is `data-computed`. There is NO parallel JS state object.
- The runtime also exports `root`, `mergePatch`, `mergePaths`, and `getPath`. `root` IS the same page signal store the bindings read, and writing it from JavaScript does update bindings. Those exports are a thinly documented, version-sensitive programmatic surface, not an officially preferred application API. The project deliberately does NOT write signals through them. Its single JS-to-signal policy is the custom-event bridge: JavaScript dispatches custom `fl*` DOM events and `data-on:fl*` expressions write the signals. This is a project-chosen boundary, not a runtime limitation. Do not switch to `root`/`mergePaths` writes and do not mix the two write policies.
- `window.FirstLineLandingDemo` is a stateless browser-bridge module. It holds no UI state (only genuinely non-UI plumbing: the IME composition flag, timers and observers, demo animation timeline counters, focus return references, and WAAPI/geometry state). Bridge contract:
  - READ UI state from the DOM (element text, the `body.trial-mode` / `.demo-writing-surface.is-live` / `body.trial-morphing` classes (all declarative `data-class`, mirroring `_session.context`/`_session.morphing`), and contenteditable state) or from values passed in by expressions; never from the signal store directly.
  - WRITE UI state by dispatching custom `fl*` DOM events on `document.body` (e.g. `flinput`, `flactivate`, `flentertrial`, `flexittrial`, `flcomplete`, `flfail`, `fldanger`, `fltoast`, `flprompt*`, `flreset`, `flmorphing`, `flroutecheck`). The matching `data-on:fl*` expressions on `<body>` translate each event's `evt.detail` into signal patches.
- The session ticker is a `data-on-interval__duration.250ms` expression that reads signals and calls the pure `FirstLineLandingDemo.tickDispatch(...)` helper, which dispatches `flcomplete` / `flfail` / `fldanger`. Pure helpers called from expressions are allowed; they must be stateless.
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

## Kami visual system

All current web-facing pages use Kami by default:

- parchment canvas `#f5f4ed`
- ivory surface `#faf9f5` and warm-sand control surface `#e8e6dc`
- ink-blue accent `#1B365D`, with lighter interactive blue `#2D5A8A`; blue should occupy no more than roughly 5% of the page
- near-black `#141413`, dark warm `#3D3D3A`, olive `#504e49`, and stone `#6b6a64`; never introduce cool gray
- serif-led hierarchy and warm neutrals; body uses weight 400 and headings use weight 500 rather than synthetic bold
- title line-height 1.1-1.3 and reading line-height 1.5-1.55 unless the writing surface needs more room
- ring or whisper shadows only
- control radius `8px` and paper radius `16px`
- restrained, document-like sections

Do not introduce unrelated SaaS or Mole-style cards, pill buttons, cool gray palettes, or decorative component systems. Footer, FAQ, help, privacy, and release sections must serve a real support, legal, or release need and remain visually consistent with Kami.

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
- capture screenshots of every changed state (landing, demo animation stages, inline typed/danger/failure/complete, trial empty/typed/danger/failure/complete) and inspect them before reporting completion

For native macOS work, follow the deeper instructions under `apps/macos/AGENTS.md` and `apps/macos/FirstLine/AGENTS.md`. From `apps/macos/FirstLine/`, run:

```bash
swift build
swift test
```
