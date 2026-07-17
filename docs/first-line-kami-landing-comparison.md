# First Line Landing Comparison: Current vs Kami Variant

Date: 2026-06-14
Status: historical decision; updated by trial-only support requirements

## Artifacts

- Current landing: `index.html` uses the Kami visual system with trial-only support/privacy/release sections.
- Variant reference: `kami-landing.html` keeps the same structure for comparison.
- Web/native repair backlog: `docs/first-line-web-native-alignment.md`

## Kami rules used

- Parchment canvas: `#f5f4ed`, never pure white.
- One accent only: ink blue `#1B365D`.
- Serif-led hierarchy for headline, body, and product argument.
- Warm neutrals only; avoid cool gray SaaS palette.
- Ring / whisper shadows only; no hard drop shadows.
- Same structure and copy as the previous `index.html`; Kami only changes the visual system.
- No unrelated SaaS cards, pill-button systems, cool gray palettes, or decorative component systems.
- Extra sections are allowed only for real trial, legal, support, privacy, or release needs, and must stay document-like in Kami.

## Why not the full official Kami landing template

The real `tw93/Kami` landing module is screen-first and production-ready, but its default structure is `Hero -> Gallery -> Features -> Principles -> Pricing -> FAQ -> Footer`.

That conflicts with the product direction for this release:

- current product is trial-only, not direct download;
- support/privacy/release sections are needed before paid access;
- keep the existing `#trial` morph/demo behavior;
- no footer unless there is a legal, support, or release requirement.

## Decision

Promote the Kami-skinned replica to `index.html`.

Short judgment: use Kami's visual system and production restraint, not Mole/SaaS components. The page may explain trial, privacy, FAQ, help, and release state, but those sections should read like a restrained document system, not a marketing card grid.
