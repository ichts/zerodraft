# Project instructions

These repository-specific rules extend the global `~/.pi/agent/AGENTS.md`. Do not duplicate global rules here. The sections below add the discipline and product contracts that are specific to Zero Draft; the global file still owns the universal rules (no em dash, no unrequested co-authored trailer, no editing generated files, no exposed secrets, and no commit/push/deploy without authorization). `VISION.md` is the acceptance policy that governs whether a change may land; it does not override `design/DESIGN.md` (the visual constitution) or this file (process).

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
- Web visuals: reuse the `design/DESIGN.md` tokens (CSS custom properties) and danger choreography (wash, snap, step numeral) before inventing a variant.
- macOS: follow the existing deadline adjudication, navigation routing, persistence, deny-feedback, and reduced-motion patterns; extend the existing types instead of adding a parallel one. New top-level modals must join the existing pending-modal routing, not each go their own way.

The goal is that code from ten contributors reads as one design language.

Design authority: the web surface answers to `design/DESIGN.md` (constitution v2); the macOS app answers to Apple HIG first (see `apps/macos/FirstLine/AGENTS.md`). Generic design and motion skills are transferable methodology only and never override the platform constitution.

## Current product and scope

- Zero Draft is the current product and its outward-facing name; the First Line name is retired for outward use. The root web surface is its public landing site and browser trial.
- `writeitdown/` is the separate writeitdown.app static deployment. Its approved LAMPLIGHT/DAYLIGHT and vanilla-browser contracts are scoped in `writeitdown/AGENTS.md`; they do not change the root landing's Datastar or bone-only rules.
- writeitdown.app releases stay bundle installs, never a deploy from this repository: the source lives here, but a release still means transferring a tested bundle to the Hetzner host and running `sh writeitdown/install.sh` there (it copies exactly the twelve production files into `/var/www/writeitdown.app`). Nothing in this repository - no workflow, hook, or credential - deploys anything.
- `apps/macos/FirstLine/` is the native macOS implementation. It is a separate Swift-native track and does not share a Datastar runtime with the web surface.
- The historical Zero Draft prototype (see "Historical material") is the product origin; historical files are not requirements for current work unless the task explicitly targets them.
- Current code and tests override historical PRDs, plans, screenshots, and prototypes when they disagree.

## Root web surface

- `index.html` is the canonical landing page and deployment source of truth. It implements visual constitution v2 (`design/DESIGN.md`): interrogation-room minimal - one paper, one clock, one door; the graveyard (fossils, siege, narrator) is closed.
- `kami-landing.html` is a visual reference copy. Do not assume it is synchronized with `index.html`.
- `download.html`, `checkout-success.html`, `help.html`, `privacy.html`, `refund.html`, `terms.html`, and `release-notes.html` are supporting public pages.
- The supporting public pages are self-contained static HTML with inline vanilla CSS and JavaScript and no framework.
- `index.html` (the landing and trial surface) is Datastar-native: it loads `datastar-pro.js` as an ES module and keeps inline CSS plus an inline browser-bridge module. Do not add any other build framework. Do not regress the landing back to a parallel vanilla state machine.
- The landing holds four objects: logotype (the `MAC RELEASE ->` link rides with it as one nav unit), headline, door (the CTA `Give it sixty seconds.`), demo paper. No second entrance: the demo paper is watch-only theater, and pointer or keystrokes on the landing do nothing. The CTA is the only way in; the `#trial` route is preserved.
- The demo paper runs a scripted loop at real speed (types ~7s, 5s of nothing, warn wash + 3-2-1, wipe at 8, machine report holds 2s, rearms at 1:00) with absolute carry+origin clocks so timer drift never cheats the numbers. It pauses offscreen/hidden and is fully static (sample typed, clock at 1:00) under `prefers-reduced-motion`.
- Preserve the forward-only writing contract: input appends at the end; deletion, paste, cut, drop, undo, and selection replacement stay blocked; IME composition remains usable and counts as activity; danger begins after 5 seconds of silence and failure clears the current draft at 8 seconds. A blocked action fires the deny body (2px shake, 90ms red hairline, SR line); warn itself never moves the paper.
- A trial session completes only when the 60s deadline lands. Session-end adjudication is explicit (`design/DESIGN.md` section 5): the deadline and the wipe line race as absolute deadlines, whichever comes first wins, and a tie goes to the wipe.
- The trial is the cleaner room: paper-white room, chrome in the corners (rules TL, timer TR, ESC - EXIT BL, words BR), the full draft visible in Newsreader 21/1.6 on a 62ch measure. Warn ramps the wash (seconds 5-8) and lands the step numeral 3-2-1; one keystroke during warn returns the wash and numeral on the 120ms snap; at the eighth second the wash steps one step deeper for the <=200ms cut, then exits. The wipe report (`DRAFT WIPED - M:SS UNUSED. TYPE TO RESTART.`) is literal - the editor stays armed and the next keystroke starts a fresh session. The kept surface returns the paper to the bone wall with the words, the receipt `0:00 - N WORDS KEPT.`, one action COPY TEXT (completed state COPIED), one mono link RUN IT AGAIN, and the caption NOTHING HERE IS SAVED.
- ESC and EXIT are the same act: leave the room immediately, back to the landing; the session (active, paused, kept, or wiped) ends without ceremony and nothing is saved. Focus returns to the door.
- The trial does not persist writing statistics, session history, streaks, or any localStorage data.
- The footer carries the one-line privacy promise and the support links.

## Web architecture boundary

Runtime on the landing/trial surface: Datastar Pro v1.0.2 (`datastar-pro.js`, loaded as `type="module"`). v1 colon syntax only (`data-signals`, `data-computed`, `data-text`, `data-show`, `data-class`, `data-attr`, `data-on:*`, `data-on-interval`, `data-effect`, `data-ignore`). Pure frontend: no backend, no SSE, no `@get/@post`, no `data-persist`, no `data-query-string`.
Attribute-name gotcha: HTML lowercases attribute names, so any signal key declared through an attribute name (`data-computed:_session.xxx`, `data-signals:_session.xxx`) must be all-lowercase. A camelCase key silently registers lowercased while camelCase reads in attribute VALUES keep their case and miss (this killed `_session.liveWords`). Keys inside `data-signals` JSON and expression values are unaffected.

- Signals are the ONLY UI-state truth. The session state lives in the `_session.*` signal object declared on `<body>` via `data-signals` (context, active, failed, complete, text, startedAt, duration, lastInputAt, remaining, dangerSeconds, dangerActive, wiping, resultText, resultWordCount, wipeReport, copied, srStatus, denyActive, denyHair). `_session.clock` and `_session.livewords` are `data-computed`. There is NO parallel JS state object.
- The runtime also exports `root`, `mergePatch`, `mergePaths`, and `getPath`. `root` IS the same page signal store the bindings read, and writing it from JavaScript does update bindings. Those exports are a thinly documented, version-sensitive programmatic surface, not an officially preferred application API. The project deliberately does NOT write signals through them. Its single JS-to-signal policy is the custom-event bridge: JavaScript dispatches custom `fl*` DOM events and `data-on:fl*` expressions write the signals. This is a project-chosen boundary, not a runtime limitation. Do not switch to `root`/`mergePaths` writes and do not mix the two write policies.
- `window.FirstLineLandingDemo` is a stateless browser-bridge module. It holds no UI state (only genuinely non-UI plumbing: the IME composition flag, timers and observers, demo theater clocks, the deny staleness token, and focus return references). Bridge contract:
  - READ UI state from the DOM (element text, the `body.trial-mode` class (declarative `data-class` mirroring `_session.context`), the `.sr-only` live region's text, and contenteditable state) or from values passed in by expressions; never from the signal store directly.
  - WRITE UI state by dispatching custom `fl*` DOM events on `document.body` (`flinput`, `flentertrial`, `flexittrial`, `flreset`, `flcomplete`, `flfail`, `fldanger`, `flwipe`, `flcopied`, `flsrstatus`, `fldeny`, `fldenyhair`, `fldenyclear`, `flroutecheck`). The matching `data-on:fl*` expressions on `<body>` translate each event's `evt.detail` into signal patches.
- The session ticker is a `data-on-interval__duration.100ms` expression that reads signals and calls the pure `FirstLineLandingDemo.tickDispatch(...)` helper, which dispatches `fldanger` / `flwipe`+`flfail` / `flcomplete`. Pure helpers called from expressions are allowed; they must be stateless.
- DOM side-effects of state transitions (blur, contenteditable toggle, focus move) run in `FirstLineLandingDemo.onComplete` / `onFail`, invoked from a `data-effect` expression that watches `_session.complete` / `_session.failed`. Because a `data-effect` re-executes on every signal change, these handlers must never emit an `fl*` event whose signal patch differs on re-run (identical writes are deduped; different writes loop until the stack blows). The deny bridge guards with an in-flight flag and every SR write is value-guarded against the `.sr-only` region's current text.
- Custom JavaScript remains only for browser-only capabilities: contenteditable selection and forward-only guards, IME composition, clipboard copy, the route (`#trial`) push/pop plumbing, and the demo theater sequencer. The trial editor subtree carries `data-ignore` so Datastar does not fight the contenteditable DOM; its `is-composing` class is therefore applied imperatively by the bridge.
- `datastar-inspector.js` is a dev-only tool. It is loaded and the `<datastar-inspector>` element is mounted only when the page is opened with `?debug`; it is never present in production markup.
- Do not maintain duplicate truth in signals and JavaScript. Durable business truth would belong to the server; the landing has no server, so the transient UI signals on `<body>` are the whole truth.
- The supporting public pages remain vanilla static HTML with no framework. Do not migrate them without explicit authorization.

## Product voice

- Explain the mechanism and consequence in short, plain sentences.
- Position Zero Draft as an opinionated forced-output writing tool: the user writes forward, cannot edit the first draft, and loses it after eight seconds of silence.
- Take inspiration from the uninterrupted-output idea behind 750 Words, but do not imply an affiliation or claim features such as streaks, history, accounts, or analytics.
- Avoid therapeutic, ceremonial, or self-help language such as "honest sentence", "long practice", or "begin when you are ready". Prefer direct labels such as "Start typing", "Keep writing", and "Draft deleted".

## Visual system: constitution v2 (all public pages)

The landing page implements visual constitution v2, defined in `design/DESIGN.md` - that document is the visual constitution for all landing work (tokens as CSS custom properties, the four-objects landing, corner chrome, the wash, the step numeral, machine-voice captions, motion law, anti-patterns). Read it before changing landing markup or CSS. Its short form:

- interrogation-room minimal: one paper, one clock, one door; the trial is the cleaner room, not a different product
- canvas: bone `#f1f0eb`; the paper `#ffffff` is the only white object; radius 0; one shadow (the paper's lift)
- Newsreader (the human) + IBM Plex Mono (the machine); red `#c8392f` is spent only on the warn numeral and the wipe cut; blue usage is zero; the logotype underscore is ink
- danger appears only while the writer pauses: the wash ramps bone/paper to 88% color-mix danger over seconds 5-8, steps one step deeper at the eighth second, and exits on the 120ms snap; the numeral 3-2-1 never tweens
- the wall stays blank: no fossil text, no eulogies, no ambient loops; `prefers-reduced-motion` renders everything static (the wash steps once per second, the warn still lands on time)
- dark mode is forbidden; repeated pauses never escalate

The supporting public pages (`download.html`, `checkout-success.html`, `help.html`, `privacy.html`, `refund.html`, `terms.html`, `release-notes.html`) are self-contained vanilla static pages styled with the same bone canvas and Newsreader + IBM Plex Mono faces. Keep them framework-free: do not migrate them to a framework.

Do not introduce unrelated SaaS or Mole-style cards, pill buttons, cool gray palettes, or decorative component systems on any page. Footer, FAQ, help, privacy, and release sections must serve a real support, legal, or release need.

## Historical material

- `prototype.html`, `src/styles/`, `design-demos/` (including `flood-v2.html`, the reference implementation of the retired Flood system), `datastar-inspector.js`, and `datastar-pro.js` belong to the legacy Zero Draft web app, except that `datastar-pro.js` and `datastar-inspector.js` are now ALSO the live runtime/dev-tool for the Zero Draft landing (see "Web architecture boundary"); treat them as active there.
- `zerodraft-prd.md` and `docs/design-system.md` describe the historical product and design system. The Flood system (fossils, the siege, the narrator, zen rendering, the morph handoff) is retired; `design/siege-motion-model.md` is its retirement notice and points to the last live commit.
- Do not restore the fossil layer, siege, zen rendering, morph, prompts, or legacy signals into the current landing unless explicitly requested.

## Testing gate

- Regression is proven only by deterministic commands: for the web surface, the repository-root `npm test` (the minimal landing/trial Playwright harness; it is not full root coverage) and `cd writeitdown && npm test` (the acceptance suite for the writeitdown.app sibling site, not for the root page); `swift build` and `swift test` (from `apps/macos/FirstLine/`) for the macOS app.
- Agents write and modify tests, scripts, and fixtures; never use Sol, Fable, Grok, or any model-driven MCP clicking as a regression run.
- Exploration may use real clicking (AXe, Jev, a human); once the same path is stable twice, it must be scripted.
- Reporting done requires the acceptance command and its result; without a command, the work is not done.

## Development and validation

Preview the web surface over HTTP:

```bash
python3 -m http.server 8000
# Open http://localhost:8000/index.html
```

The root-web acceptance command is the repository-root `npm test`: the minimal Playwright harness added by https://github.com/ichts/zerodraft/pull/12, which drives the trial focus flow. The root page has no fuller suite yet - do not claim root coverage it does not have. The writeitdown suite (`cd writeitdown && npm test`) accepts only the writeitdown.app sibling site. The checks below are exploration support, not the exit condition. For web changes:

- inspect affected pages at desktop and mobile widths
- exercise the browser trial's typing, danger recovery, failure, completion, keyboard restrictions, and IME behavior when relevant
- verify focus visibility and `prefers-reduced-motion` behavior for interaction or motion changes
- verify visual layout consistency: hero content width and left edge must align with the footer; centered elements must be centered; text must not be clipped or orphaned; interactive elements must have consistent radius, color, and spacing
- capture screenshots of every changed state (landing hero, demo typing/warn/wipe/report stages, trial at rest/typed/warn/recovery/wipe/kept, COPY TEXT completed state, ESC and EXIT outcomes) and inspect them

For native macOS work, follow the deeper instructions under `apps/macos/AGENTS.md` and `apps/macos/FirstLine/AGENTS.md`. From `apps/macos/FirstLine/`, run:

```bash
swift build
swift test
```

UI, editor, or motion changes on the macOS app must also be exercised in a real debug window (typing, danger, failure, aftermath, deny feedback, success, reduced motion, and the fossil gutter at the minimum window width) as exploration alongside `swift test`, with the result recorded in `apps/macos/FirstLine/docs/MANUAL_QA.md`.

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

The web surface is a single `index.html`, so its durable truth lives in `design/DESIGN.md` (visual constitution v2; `design/siege-motion-model.md` is the retired Flood-era motion contract, kept as a notice), the "Web architecture boundary" section above, and the `_session` signals - not in an L2/L3 hierarchy. Apply L3 headers only to hand-written, structured source with a real responsibility; do not spray them onto generated or vendored files (`datastar-pro.js`, `datastar-inspector.js`) or the supporting static pages.

Workflow after a code change: code -> nearest header and L2 check -> L1 check -> validation -> done. Before entering a module: nearest `AGENTS.md` -> module `AGENTS.md` -> relevant L3 header -> code.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
