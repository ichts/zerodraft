# WRITE_IT_DOWN static site

This directory is the independent writeitdown.app deployment, not the root Zero Draft site. Its approved phase-two brief explicitly chooses vanilla browser JavaScript and both LAMPLIGHT (dark) and DAYLIGHT (light). Do not migrate the root site's Datastar runtime or bone-only palette here.

## Map

- `index.html`: landing and directly addressable `#trial` room.
- `site.css`: shared geometry and semantic tokens. Both themes keep paper brighter than wall, including wash and cut.
- `theme.js`: appearance preference only. System appearance is the default; `writeitdown-theme` is the only localStorage key.
- `demo.js`: watch-only private messy-draft preview replaying `demo-timeline.mjs` - human-rhythm typing with a visible self-correction and a centered wipe report. Never owns the actual trial; deny feedback fires only in the trial.
- `demo-timeline.mjs`: deterministic seeded typing script (lines, correction beat, pacing) shared by `demo.js` and the qa specs.
- `feedback.js`: shared deny shake and gesture-gated sound; reduced motion suppresses spatial movement.
- `session.mjs`: pure deadline adjudication and Unicode writing-unit count. Earlier deadline wins; ties wipe. See `README.md` for counting semantics.
- `room.js`: transient session owner, native textarea/IME enforcement, upper-third three-visible-line zen viewport, routing, clipboard. Writing never exposes a scrollbar; kept text remains readable. No draft persistence or network transport.
- `privacy.html`, `terms.html`, `support.html`: honest static help/legal pages with the shared theme.
- `session.test.mjs`: deterministic timing and multilingual-count regressions.
- `qa/input-regression.js`: browser event-path checks, including synthetic IME composition; not an OS input-method test.
- `qa/zen-regression.js`: long multilingual text, fixed zen geometry, scroll containment, and deny-feedback regressions.
- `qa/phase4.spec.mjs`, `playwright.config.mjs`: executable eight-project browser acceptance, accelerated clocks, screenshots, and console/network checks. Playwright is test-only; the deployed site has no package runtime.
- `og.png`: 1200×630 light-theme social share card referenced by landing metadata.
- `install.sh`: fixed-target, backed-up deployment inside `/var/www/writeitdown.app/` only.
- `QA.md`: browser acceptance and remaining limits.

The design references are the phase-two Landing/Room deliverables, not their `.dc.html` preview scaffolding. `site.css` is the production token contract. No frameworks, analytics, rounded UI, or design-board runtime.

Validate with `node --test writeitdown/session.test.mjs` and `cd writeitdown && npm ci && npx playwright test` (installed Chrome required). The browser suite serves HTTP and covers both themes at 1440x900 and 390x844, normal and reduced motion, with accelerated clocks. The room starts on first input, not entry. Kept text is visible only until exit/reload. Never store or submit writing. New support contact details require a confirmed address; do not invent one.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this module. Point to authoritative files and commands instead of repeating implementation details. Prefer pruning or rewriting existing entries over appending new ones. Preserve this bar when updating the file.
