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
- `mac.html`, `waitlist.js`: the paid Mac app's sale page. The free web room is its working CTA (the landing's secondary link points to `mac.html#waitlist`). Checkout, DMG download, and license delivery steps are each a verified live element (`data-launch`) or a visible pending notice (`data-launch-pending`), never a placeholder link; the waitlist form posts to `/api/waitlist` (`services/waitlist/`) and works without JS via `:target`. The collector's deployment and public POST routing require independent verification; health alone is insufficient. Name no payment provider or license-delivery mechanism until a real test order confirms it. Kept out of the sitemap until sales open. See `README.md` "Mac page release order".
- `release-check.mjs`: `npm run release-check` (add `-- --live` to fetch the URLs), the pre-publish gate. It requires live checkout and download slots to be links with real destinations and fails on missing or placeholder launch inputs, a missing support address, or a mismatch with the app's `Info.plist` price and checkout URL. A pass is not proof of a working sale; opening still needs a real test order and an explicit go. Not shipped.
- `session.test.mjs`: deterministic timing and multilingual-count regressions.
- `qa/input-regression.js`: browser event-path checks, including synthetic IME composition; not an OS input-method test.
- `qa/zen-regression.js`: long multilingual text, fixed zen geometry, scroll containment, and deny-feedback regressions.
- `qa/mac.spec.mjs`: sale-page CTA honesty, site-wide link and fragment resolution, release gate CLI fixtures, the waitlist form's JS/no-JS outcomes against both a mocked collector and the real Go collector, and the installer's collector guard.
- `qa/phase4.spec.mjs`, `playwright.config.mjs`: executable eight-project browser acceptance, accelerated clocks, screenshots, and console/network checks. Playwright is test-only; the deployed site has no package runtime.
- `og.png`: 1200×630 light-theme social share card referenced by landing metadata.
- `robots.txt`, `sitemap.xml`, and the Google/Bing verification files: crawl discovery and ownership for the apex site. Keep the sitemap aligned with the indexed canonical pages.
- `install.sh`: fixed-target, backed-up deployment inside `/var/www/writeitdown.app/` only. Refuses to install until the waitlist collector's health URL answers `ok`.
- `QA.md`: browser acceptance and remaining limits.

The design references are the phase-two Landing/Room deliverables, not their `.dc.html` preview scaffolding. `site.css` is the production token contract. No frameworks, rounded UI, or design-board runtime. The only analytics is the cookieless Cloudflare Web Analytics beacon, once before `</body>` on each shipped HTML page.

Validate with `node --test writeitdown/session.test.mjs` and `cd writeitdown && npm ci && npx playwright test` (installed Chrome required). The browser suite serves HTTP and covers both themes at 1440x900 and 390x844, normal and reduced motion, with accelerated clocks. The room starts on first input, not entry. Kept text is visible only until exit/reload. Never store or submit writing. The public contact is contact@trefoilstudio.com; do not add other addresses without confirmation.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this module. Point to authoritative files and commands instead of repeating implementation details. Prefer pruning or rewriting existing entries over appending new ones. Preserve this bar when updating the file.
