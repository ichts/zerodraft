# writeitdown site + Playwright suite

**Status: on the default branch.** The writeitdown site (`writeitdown/index.html`, `demo.js`, `room.js`, `theme.js`, `session.mjs`, `site.css`, `support.html`, `privacy.html`, `terms.html`) and its harness (`package.json`, `playwright.config.mjs`, `qa/phase4.spec.mjs`) are tracked in this repository. The historical QA screenshot binaries were stripped when the history landed; `QA.md` records what they showed.

**What it is:** the writeitdown browser app - the same forward-only, 8-second-wipe writing room as the root trial, shipped as its own static site with dark/light themes, plus its executable acceptance suite.

**How to reach it:** on a branch that contains it, serve the repo root and open `/writeitdown/`; the Playwright config serves it at `http://127.0.0.1:8015/writeitdown/` itself.

**How to drive it:**

```bash
cd writeitdown && npm install   # once per checkout
npm test                        # qa/phase4.spec.mjs, 8 projects: {1440,390} x {dark,light} x {no-preference,reduce}
npx playwright test --project=1440-light-no-preference   # single project while iterating
```

The suite enters through `#landing .door`, drives the editor (`#editor`), and asserts the zen geometry, forward-only denial, warn/wipe/recovery, the kept state with copy, ESC/EXIT, theme, and reduced-motion behavior, capturing per-state screenshots into `writeitdown/test-results/`.

**Observable end state that proves it works:** `npm test` exits 0 across all 8 projects (32 tests). Evidence (screenshots, traces on failure) lands under `writeitdown/test-results/` (override with `WID_QA_OUTPUT`).
