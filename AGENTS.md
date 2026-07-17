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
- The web pages are self-contained static HTML with inline vanilla CSS and JavaScript. Do not add Datastar or a build framework to the current landing unless the user explicitly requests an architecture change.
- The trial/demo API is `window.FirstLineLandingDemo`. Preserve `.demo-writing-surface`, `.live-demo-editor`, `.demo-session-bar`, `.demo-result`, `.demo-failure`, `.demo-toast`, `.demo-prompt`, `.trial-overlay`, `.trial-writing-surface`, `.trial-editor`, `[data-trial-launch]`, and the `#trial` route.
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

- Name the runtime before implementing a web interaction. Do not mix a vanilla state machine and Datastar signals on the same surface.
- The current landing and trial are vanilla by design. Do not describe their imperative JavaScript as Datastar-native or sprinkle `data-*` expressions over the existing state machine.
- A Datastar adoption is a deliberate whole-surface migration that requires explicit user authorization and an updated architecture contract in this file.
- If the root surface migrates to Datastar, signals and `data-on:*` expressions own ordinary UI state and actions. Keep custom JavaScript only for browser-only capabilities such as contenteditable selection, IME composition, clipboard access, and necessary animation APIs.
- In a Datastar implementation, do not maintain duplicate truth in signals and JavaScript. Durable business truth belongs to the server; browser signals are transient UI state.

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

- `prototype.html`, `src/styles/`, `datastar-inspector.js`, and `datastar-pro.js` belong to the legacy Zero Draft web app.
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
