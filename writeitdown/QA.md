# Current acceptance

Current user-visible behavior is documented in [README.md](README.md); shared writing geometry is owned by `tokens.css` and `site.css`. Run the browser acceptance command in the README for this revision. The records below describe earlier revisions, not evidence that the current change passed.

`qa/mac.spec.mjs` covers removed demo labels and caption and header theme controls. `qa/phase4.spec.mjs` covers shared demo/trial start-line placement, the blocked demo Backspace, the reduced-height mobile trial footer, short-sheet warning/failure/kept placement, the demo reset and loop, and room interactions; `qa/motion-regression.spec.mjs` covers the animated history shift, bar re-anchoring and refusal continuity. Use the current run's results and screenshots for release acceptance.

Real OS IME, iOS Safari/virtual keyboard and human audio evaluation remain unverified. Chrome viewport checks do not replace those checks.

# 2026-10-25: One design system across the site, and a purchase page a buyer can trust

Every shipped page moved onto the landing's design system (D-053): the nine help/legal/answer pages
and `mac.html` now carry the A mark lockup with its plate, the theme button, the shared footer, 17 px
system-face body copy at the 62ch measure, the v2 pill and underlined-link treatments, and the same
canvas. `mac.html#buy` is a section with its heading and `$4.99 once` price row in view, pending and
error states, and a licence card for ready/copied/unpaid; `session_id` is cleared from the URL and
history when the licence response arrives, on success and failure, with `Check again` as the in-page
retry. The 1.1 note left the download card, and the page no longer requests IBM Plex Mono; every
shipped page now loads only Newsreader and Reenie Beanie. Evidence: `/Users/ichts/firstmate-homes/wid/data/wid-web-shell/`.

## Commands and results

- `node --test buy.test.mjs session.test.mjs`: 22 pass, 0 fail.
- `npx playwright test` (writeitdown suite, 8 projects, run on a private port because another lane
  held 8015): 670 passed, 0 failed, 66 skipped.
- `node release-check.mjs`: STATIC CHECK PASSED.
- `npm test` at the repository root (Zero Draft landing/trial harness): unchanged by this work; see
  that run's result in the delivery report.

## Measured (captures/measurements.json)

| Surface | Measure | Value |
| --- | --- | --- |
| All 10 document pages, both sizes and themes | brand top / height | 21 / 22 px (1440), 19.6 / 16.7 px (390) |
| All 10 document pages | theme plate | `rgb(255,255,255)` light, `rgb(38,35,28)` dark; 1 px edge |
| All 12 shipped pages | body family | one system-UI stack; 17 px |
| All 10 document pages | body measure | 664 px at 1440 (62ch), 350 px at 390 |
| All 10 document pages | legacy shell classes | 0 |
| All 12 shipped pages | horizontal overflow | 0 |
| `#buy` at 1440 / 390 | heading box | 57.2-87.2 / 41.3-71.3 px (viewport 900 / 844) |
| `#buy` at 1440 / 390 | price row box | 173.6-208.8 / 212.1-300.3 px |
| `#buy` | scroll margin | 16 px |
| pending | button label / opacity / cursor / aria-busy | `Opening checkout...` / 0.6 / progress / true |
| error | button / status role | `Try again` / `alert` |
| ready | URL | credential removed when the response arrives (`.../mac.html`) |
| unpaid | URL / retry | credential removed on response / visible, key hidden |
| phone room nav | visible controls | lockup + theme icon only |
| phone room exit row | Mac link box | inside the footer row (772-816 px in a 751-816 px row) |

## Captures

`captures/`: 12 pages x 1440/390 x light/dark full-page PNGs (48), purchase states (default, `#buy`,
pending, error, ready, copied, unpaid) at both sizes and themes (28), room empty and exit-confirmation
at 390 in both themes (4), and `measurements.json`. Compared against the landing page at the same size
and theme.

## UI quality checklist (docs/ui-quality.md)

| Rule | Result | Basis |
| --- | --- | --- |
| Q-01 | PASS | Room phone nav shows the lockup and theme icon only; the Mac link sits in the exit row (`shell.spec.mjs`, `measurements.json`). |
| Q-02 | PASS | Warning numeral, caption and receipt placement assertions in `phase4.spec.mjs` are green; no change to the ink slot. |
| Q-03 | PASS | Empty caret/count prompt assertions in `phase4.spec.mjs` are green; the room was not restyled. |
| Q-04 | PASS | 35% anchor and centring assertions in `phase4.spec.mjs` are green. |
| Q-05 | PASS | Exit-hint baseline and type-style assertion in `phase4.spec.mjs` is green; the buy row shares one baseline (captures). |
| Q-06 | PASS | State-change geometry assertions are green; `status-slot.js` now reserves the whole wrapped exit row (see below). |
| Q-07 | PASS | The migrated pages carry no new labels or helper sentences; the download badge that repeated the facts is gone. |
| Q-08 | PASS | `shell.spec.mjs` compares brand y, plate, family, canvas and footer across all twelve pages; D-053 records the change. |
| Q-09 | PASS | Every page and every purchase state captured in light and dark; the plate and canvas are the same per theme. |
| Q-10 | PASS | No room motion changed; the landing's write-on reveal is unchanged, and the hover lift is pointer-gated. |
| Q-11 | PASS | Hover lift is gated to `(hover:hover) and (pointer:fine)`; `:active` stays; `motion-regression.spec.mjs` and `phase4.spec.mjs` are green. |
| Q-12 | PASS | `Type to start` / `0 words` assertions in `phase4.spec.mjs` are green. |
| Q-13 | PASS | Ink focus ring (2 px) on the lockup of all twelve pages; every buy/licence control is a real button. |
| Q-14 | PASS | Brand y 21, measure 664 px, one left edge shared with the footer on every document page. |
| Q-15 | PASS | The purchase states follow the platform convention for a working submit (disabled + `aria-busy`) and a failed one (`Try again` + `role=alert`); no novel interaction was invented. |
| Q-16 | PASS | Basic polish fixed in this pass: the wrapped exit row had eaten a line of the kept draft, and the error status now reads at ink weight. |
| Q-17 | PASS | 17 px / 1.6 body with the serif reserved for headings; no rendered pitch changed. |
| Q-18 | N/A | Mac launch state; no web surface. |
| Q-19 | PASS | Header sweep and 360 px point samples now run over all twelve pages; no overflow, 6 px+ gutter, one plate token. |
| Q-20 | PASS | No copy was added to describe a page. Every price mention on all twelve pages and in the six buy states is exactly `$4.99 once`; `shell.spec.mjs` enforces it. The 1.1 note left the 1.0 card. |
| Q-21 | PASS | `shell.spec.mjs` enforces one price string, `$4.99 once`, on every shipped page and every buy state; the shell rule is green on all twelve pages. |

## Known-broken proofs for the new gates

- Old shell (`known-broken-old-shell.txt`): on `support.html` there is no A mark lockup, the
  `WRITE_IT_DOWN` logotype sits at y 48, the theme button is transparent, body copy is 21 px
  Newsreader on `rgb(216,210,195)`, and the footer is absent. The new `shell.spec.mjs` fails on the old
  tree (`known-broken-shell-spec.txt`), including `support.html: "Give it 60 seconds" is 3.57:1 on
  rgb(216,210,195)`.
- Old purchase page: `mac.html#buy` landed on the button with no `#buy-heading` and no price row
  (`heading: null`, `price: null`), and the three actions were 308.7 / 261.9 / 159 px square mono
  buttons.
- Price guard: planting `USD $4.99` in the `mac.html` buy-card paragraph made `shell.spec.mjs`
  `the purchase path states one price string` fail with `mac.html: price mention "USD $4.99"`; the
  plant was removed and the committed tree passes.
- Old failure path: `mac.html?session_id=...` with a 404 licence response kept `session_id` in the URL
  and offered no retry.
- Old route server: `journey/serve-local.mjs` answered a missing page with the landing page and
  HTTP 200; it now answers 404, and `shell.spec.mjs`'s release server test pins that.

## Remaining limits

- The release journey (`npm run journey`) was not run: it needs Playwright WebKit and the real DMG;
  its purchase block was updated for the new labels, credential cleanup and retry control but is not
  claimed as run here.
- No deployment. The live site still serves the old files until the bundle is installed on the host.
- The room's `Download for Mac` link in the exit row still discards an open draft in one click, as the
  nav pill did before it; the two-act exit guard covers `ESC - EXIT` only. That is audit item 13, not
  in this migration's scope.

# 2026-10-25: Download-page release-note version gate (local)

The download card keeps its 1.0 facts and now says the 1.1 update check is not released yet. The note
declares the version it describes in `data-release-note` and carries `data-launch-pending` while that
version is not the linked download. `release-check.mjs` refuses a note newer than the linked DMG
without that mark, a pending mark once its version is the linked download, and a note without a
version.

- `node writeitdown/release-check.mjs --download`: STATIC CHECK PASSED on the current page.
- Known-broken proof: the pre-fix page at `7932fe0` passes the pre-fix checker (exit 0) and is refused
  by the new one with `the note announces 1.1 but the download is 1.0`.
- `qa/mac.spec.mjs` gained four rejection cases (pending mark removed, DMG advanced to 1.1 while the
  note stays pending, missing `data-release-note`, current-tense 2.0 note). Those exact inputs were
  executed against `release-check.mjs` and each was blocked with its expected message. The full
  Playwright suite was not run in this round (`writeitdown/node_modules` is not installed here).
- Follow-up: the version comparison no longer falls through when the DMG file name carries no version.
  A page whose link is renamed to `Write-It-Down.dmg` passed the previous checker and is refused by
  this one with `DMG URL: the file name does not carry the version`; `qa/mac.spec.mjs` gained that
  rejection case and the current page still reports STATIC CHECK PASSED.

# 2026-10-25: Web room parity with the shipped Mac app (local, branch `fm/wid-parity-mini`)

- Scope: `writeitdown/index.html`'s landing demo and `#trial` room brought to the Mac room's settled
  behaviour (D-043 to D-046): 35% anchor, caret-only empty room with `Type to start`/`0 words`, stepped  per-line history with a one-pitch 180 ms shift, ink-placed warning group and wipe receipt, one 2 pt
  linear session bar and no bottom meter, `You stopped.` / `Begin again` failure screen, kept top block
  with `1 MINUTE. N WORDS.`, two-step exit with an inline confirmation, 200 ms/220 ms refusal. The root
  Zero Draft landing (`/index.html`) is out of scope: it is the separate outward brand.
- The delivered spec now includes `short sheets keep the warning and result slots inside the paper`,
  `kept screens keep the controls and draft clear of the paper foot`, `the demo danger group clears when a new
  loop reaches typing`, `short demo sheets keep the status slot inside the paper`, and the 5-test
  `qa/motion-regression.spec.mjs`. The full eight-project `npx playwright test` gate for this revision
  is the repository acceptance command and runs in the pipeline test step; focused review runs of the
  touched tests passed on 1440-light, 390-dark and 390-dark-reduce. The earlier 108-pass figure
  belongs to the initial parity pass, not this revision. `qa/mac.spec.mjs` and `qa/seo.spec.mjs` pass
  (26 tests, 1440-light).
- Release journey, room scenarios only against a local server (`journey/serve-local.mjs --root .`):
  `full-session` and `silence-wipe` PASS on WebKit (iPhone 14 profile, 390x844) and Chromium 1440x900,
  one continuous video each. `journey/verify-room.mjs`: `no-finish`, `no-wipe` and `no-copy` fail on
  both viewports at the named step and the intact build passes.
- Measurements (task evidence, both sizes, light and dark): active line 0.390 -> 0.350 of the sheet;
  warning numeral ink 218/221 pt under the writing baseline -> 44/43 pt; caption 67/46 pt under the
  numeral ink -> 21/22 pt; trial session bars none -> one 2 pt bar; demo bars 2 pt + 3 pt meter -> one
  2 pt bar; demo history 0.36/0.22 -> 0.22/0.07; count `0 WORDS` -> `Type to start` / `0 words`; kept
  receipt `0:00 - N WORDS KEPT.` -> `1 MINUTE. N WORDS.`; exit row baselines equal within 0 pt on
  desktop (a phone wraps the confirmation onto its own line instead of truncating it).
- Short-sheet follow-up: at the compact sizes 1440x350 and 844x390 the warning group, failure block
  and kept layout clamp above the paper foot, the kept actions stay clear of the footer, and at least
  one kept draft line remains visible. The exit confirmation row's measured height (one or two
  lines at the current width) is reserved permanently by a hidden probe: the kept bottom derives
  from the measured footer plus that row in the compact and tall layouts alike, so arming the
  confirmation neither reflows nor overlaps the kept screen. The kept test forces a two-line
  confirmation at 320, 390 and 767 px widths with a filled box, and asserts the last kept line
  stays above the confirmation on the tall desktop sheets too. Tall desktop kept screens
  keep the Mac 72 px offset and the token title size. The compact
  threshold is a 480 px paper; 667x375, 390x844 and 1440x620 cover the boundary. The Mac 44 px ink
  offsets are unchanged.
- Kept draft line, metric-independent: the kept screen owes the writer one full line of the returned
  draft, so `status-slot.js` measures the rendered line box against the measured scroll box and, only
  when the title, receipt, controls or the reserved confirmation row squeeze it, gives way through the
  screen's own gaps (draft gap, then actions gap, then receipt gap) until a line fits. The guarantee is
  therefore not a font constant: the Linux runner wraps the phone confirmation row one line taller and
  left 30.4 px of a 33.6 px draft line, which this test now reproduces deterministically on every
  platform by adding one receipt line above the draft at 320 px.
- Not re-run here: the whole suite in a single final pass, the pre-deploy journey against a real DMG
  (`npm run journey --expect-sha`, needs the artifact), and real-device IME/iOS checks.

# 2026-10-25: Aligned-room build and split-W logo (local)

- Source `1446b4a` (the merged writing-room/After alignment and split-W logo PRs). The download page and the `journey:live` expectation publish the rebuilt DMG's SHA-256 `5b8483bd210e5f4c697265fad0c447b4bc88b9265a1999bd9a7566be74bf4bc4`.
- `cd writeitdown && npm test`: exit 0, 460 passed and 36 expected skips across desktop/mobile, both themes and both motion preferences. Inspected the download-page captures at 1440x900 light and 390x844 dark: the new hash stays on one line on desktop and wraps without clipping or overflow on mobile.
- Pre-deploy journey against the real artifact (`node journey/serve-local.mjs --root . --dmg-file <dmg> --port 8025`, then `npm run journey -- --base http://127.0.0.1:8025 --expect-sha 5b8483bd210e5f4c697265fad0c447b4bc88b9265a1999bd9a7566be74bf4bc4`): 82 passed, 0 failed, 2 WAIVED (sign-in absent; installed-DMG TEST acceptance pending). Both viewports (WebKit iPhone 14 profile, Chromium 1440x900) recorded one continuous video each, and the served DMG matched its published size and SHA-256.
- `npm run release-check` and `npm run release-check -- --download`: static checks passed before the deploy.
- Live deploy: the bundle built from merged commit `fa136cd` was installed on the host and the ten sampled production files match the tested tree byte for byte; the previous site copy and the previous DMG (SHA-256 `714822ee...`) are kept as backups. `npm run release-check -- --download --live` and `npm run release-check -- --live` both reported `LIVE CHECK PASSED`. `npm run journey:live`: 82 passed, 0 failed, 2 WAIVED, with one continuous video per viewport; live captures of the landing, download and Mac pages at 1440x900 and 390x844 show the split-W headers, the room, and the published `5b8483bd...` hash on one line on desktop and wrapped without clipping on mobile. The hosted DMG answers `application/x-apple-diskimage`, 8117026 bytes, and hashes to the published value; `/llms.txt` answers `text/plain; charset=utf-8`.

# 2026-10-25: Download-page release note and update-feed hosting (local only)

The Mac 1.1 release adds Sparkle auto-update (see `../docs/wid-decisions.md` D-041). The site change
is small: one `#release-notes` line inside the download card, one scoped spacing rule in
`site.css`, and the Mac section of `privacy.html` gains the opt-in update paragraph with `UPDATED`
moved to October 25, 2026. No page was added to the sitemap; no other surface changed.

- `cd writeitdown && npm ci && npx playwright test`: 460 passed, 36 skipped across the eight
  viewport/theme/motion projects. The Install/Activate/Refunds structure, the single DMG link, the
  published SHA-256 slot and the canonical/og metadata the journey asserts are unchanged. The
  legal-page check now also asserts the opt-in update disclosure in `privacy.html` (`Updates are
  opt-in.`, `Check for updates automatically`, `Check for Updates…`); the page is still in the
  shipped-file list and the sitemap/SEO checks still see it.
- `npm run release-check -- --download`: passes locally. The published SHA-256 still names the live
  1.0 DMG, so the DMG link name, the Install card's `shasum` filename, the note and the checksum
  must flip together in the deploy that uploads 1.1 (see `README.md`, "Mac download release"). The
  release gate now refuses an Install command that names a different DMG than the link;
  `qa/mac.spec.mjs` covers the rendered Install command and that rejection.
- Captures: `download-desk.png` (1440x900, full page) and `download-mobile.png` (390x844, full page),
  plus a crop of the card footer. Inspected: the note sits 16 px under the last requirement row, wraps
  to three lines on desktop and four on mobile, stays inside the card, and neither eats the card's
  bottom padding nor pushes the three step cards down. Light theme only; the note inherits the chrome
  colour, so the dark theme needs no separate capture.
- Not verified here: the live host's new Caddy handlers, the appcast content type, and the 404 for a
  missing update file. Those are release-day checks in `README.md`; nothing in this repository
  deploys.

# GEO acceptance (historical)

GEO pass, October 23, 2026. The discovery and answer-page contracts are owned by [README.md](README.md#discovery-files-and-answer-pages). Landing, trial and Mac visuals were untouched.

The recorded run of `cd writeitdown && npm ci && npx playwright test` passed 222 tests with 18 expected skips across the eight viewport/theme/motion projects, including `qa/seo.spec.mjs`. `node --test session.test.mjs` passed 10 tests. `npm run release-check -- --download` reported STATIC CHECK PASSED. A local static serve of `writeitdown/` returned `Content-type: text/plain` for `/llms.txt`. `qa/test-install.py` installed the production files listed in `install.sh`, including `llms.txt` and the answer pages.

Screenshots of all six answer pages at 1440x900 in light and dark and at 390x844 in light, plus `support.html` at 390x844 in light and dark, were inspected: no horizontal overflow, the breadcrumb wraps inline, and the FAQ headings separate cleanly from body copy.

Analytics records were not independently verified. The live deploy and the real `curl -I https://writeitdown.app/llms.txt` remained unverified pending the operator's bundle installation.

# 2026-10-23: Mac purchase and license delivery (local only)

- `cd writeitdown && npm ci && npx playwright test`: exit 0, 395 passed and 29 expected skips across desktop/mobile, both themes and both motion preferences. Skips are duplicate filesystem checks and existing reduced-motion demo cases. Checkout HTTP is intercepted: the suite proves POST/navigation, paid key/copy including a service-padded key displayed and copied trimmed, pending/unknown/error neutrality, no key before a successful response and no return-page analytics/referrer leak. It does not charge a card.
- Before implementation, `npx playwright test qa/checkout.spec.mjs --project=1440-light-no-preference --grep 'Buy posts once'` exited 1 because the existing waitlist page had no Buy button. The same journey now passes. Installer acceptance also runs a deliberately broken installer without its symlink guard and requires rejection.
- `npm run release-check -- --download`, `npm run release-check`, `node --test session.test.mjs`, `python3 qa/test-install.py`, shell syntax, ShellCheck and `git diff --check`: exit 0. Installer acceptance covers the production-file list in `install.sh`, preserved backup, repeat installation and refusal to follow destination symlinks. A pre-existing ShellCheck warning on the empty CDPATH assignment was corrected without changing its behavior.
- Inspected desktop and mobile screenshots for Buy, paid/COPIED, neutral pending and the download page in the existing light/dark system. The paid key appears above the sales copy on return and is asserted to be in the viewport. No CSS, tokens, room input rules, demo timing or motion were changed.
- The real paid TEST response exposed a contract bug missed by the original fixtures: the service returns `licenseKey`, not `license_key`. A deterministic paid-session test using the actual field failed with an empty key before the fix. The page and fixtures now use the deployed camelCase field without a second compatibility path.
- The corrected page was checked at 1440 and 390 against the real deployed buyer-key route with an authorized paid TEST session: HTTP 200, visible key, exact clipboard copy, activation sentence, no overflow and zero console/page errors. Only static page assets were intercepted under the real apex origin; service traffic was not stubbed. Unpaid and unknown sessions were also verified against the real route: HTTP 404, neutral notice and no key. No payment was placed by this worker, and no real session/key value is stored in source or reports.
- The configured DMG is signed/notarized; native acceptance and pending installation/window checks are recorded in `../apps/macos/FirstLine/docs/MANUAL_QA.md`. Clean-user installation and real-window activation remain unobserved here. The current purchase journey coverage and installed-DMG release boundary are owned by the release-order section in `README.md`.

# Centered-aperture acceptance (historical)

This pass centers the trial writing aperture on the paper instead of pinning it to the upper third. The active-line center is y=450 at 1440x900 and y=422 at 390x844, matching the paper center at both widths. The editor's computed mask keeps mirrored alpha stops around the 40%-60% clear band in both themes.

The landing demo now loads its module graph from the deploy bundle, including `demo-timeline.mjs`; a hard-load browser regression proves that `#cur` receives the first typed character. The shortened timeline completes in about 12.7 seconds, uses two quick backspaces for the correction, and holds the wipe report for one second before looping. Deny feedback is a lighter 280ms beat and reduced motion still removes spatial movement.

`cd writeitdown && npm ci && npx playwright test` passes 44 tests and skips the four expected reduced-motion correction snapshots across eight viewport/theme/motion projects. The suite checks center geometry, mirrored mask stops, hard-load demo typing, correction pacing, shortened deny feedback, warning, recovery, wipe, kept, copy, Escape, console errors and failed assets. `node --test writeitdown/session.test.mjs`, `sh -n writeitdown/install.sh`, and `git diff --check` also pass.

Real OS IME, iOS Safari/virtual keyboard and human audio evaluation remain unverified. This is a local-only handoff, not a deployment.

# Phase-four acceptance (historical)

Phase four is a local-only tested bundle, not a live deployment. Final acceptance is executable: from `writeitdown/`, run `npx playwright test`. All 24 specs pass across eight viewport/theme/motion projects in 20.8 seconds; 108 screenshots are captured by the specs and inspected in contact sheets. The suite asserts the native input paths, no writing scrollbar/page overflow, three visible text lines, opaque active band, writing line near 39% of viewport height, historical sample, absent subtitles, centered report, 600ms deny with its final still hold, and reduced-motion behavior. Eight mocked sixty-second sessions reach kept and verify clipboard contents and Escape. Script exceptions, failed application assets, and non-GET requests fail acceptance. Google Chrome and `npm ci` are the prerequisites; there is no runtime dependency change.

The phase-four handoff includes `REPORT.html`, executable specs, contact sheets, individual screenshots, and command logs. Earlier real-time browser runs below remain supporting reproduction evidence, not the final acceptance workflow.

- Reproduced the textarea scrollbar with native insertion of 378 multilingual writing units: 342px client height versus 765px content. Short drafts hid the overflow. Fixed-height masked text and symmetric padding replace content-driven growth, keeping the active line centered and two previous lines faded.
- Restored the sample verbatim from `4bef933:writeitdown/demo.js`; removed all key subtitles and centered the demo report.
- Deny feedback lasts 600ms (420ms shake, 180ms still hold). Input and deadline clocks are never paused. Repeats do not restart the shake; reduced motion retains the hairline without movement.
- Eight session unit tests pass. Run `qa/input-regression.js` and `qa/zen-regression.js` as browser evaluation functions while in `#trial`: 15 input-path and 14 zen checks pass across 1440x900/390x844, both themes, normal/reduced motion.
- Browser matrix covers empty, focused, long Latin/CJK/emoji text, denied deletion/cut, warn, real recovery, wipe, exit, and kept. Four real full-minute sessions cover both widths and motion preferences; each kept result is captured in both themes. Copy and Escape pass. Demo typing/warn/cut/report frames are captured in both sizes and themes.
- Presentation frames freeze an observed clock or animation to survive CLI screenshot latency. Real wipe/recovery and full-minute checks use unchanged session clocks. Initial stale typing/recovery captures were replaced after visual inspection caught CLI delays.
- Real OS IME, iOS Safari/virtual keyboard, and human audio evaluation remain unverified. Synthetic composition and Chrome viewport tests are not substitutes for those checks.

# Phase-three acceptance (historical)

Phase three was validated locally on September 16, 2026. See [`data/zd-writeitdown-polish-s2/REPORT.md`](../data/zd-writeitdown-polish-s2/REPORT.md) for the multilingual counting rule, all eight requested changes, checks, screenshots and limits. There are now 8 deterministic tests and 10 installed production files. Browser evidence covers 1440x900 and 390x844, both themes and reduced motion, with real full-minute kept runs. The deployment handoff is `writeitdown-phase3-deploy-bundle.tar.gz`; local validation does not claim a live release.

# Phase-two acceptance (historical)

Validated locally on September 16, 2026. Deployment and HTTPS acceptance remain the supervisor's responsibility.

## Automated checks

- `node --test writeitdown/session.test.mjs`: 7 passing tests. Covers idle, 5s warning, recovery, 8s wipe/restart, real 60s deadline, delayed ticks, wipe-winning ties, late input, whitespace-only drafts, and labels.
- `node --check` on all browser JavaScript: passed.
- `sh -n writeitdown/install.sh` and `git diff --check`: passed.
- Installer exercised in a temporary sandbox with its target path substituted. All nine production files copied; original index backed up; repeat installation preserved the backup; a destination symlink was rejected without writing its target.
- All four public HTML pages and five assets returned HTTP 200 from the local server.

## Browser acceptance

Used separate headless Chrome profiles through `chrome-devtools-axi`, never the desktop browser. Exact viewports were 1440x900 and 390x844. The latter used mobile/touch emulation, not window resize: Chrome's minimum ordinary window width is 500px.

- CTA enters the actual `#trial` room and focuses its editor. Direct `#trial` entry also works.
- Native browser text insertion starts the independent clock. Multiple full 60-second runs at both widths reached `kept`, with no clock overrides or shortened deadlines.
- `You wrote it down.`, the full draft, the receipt, and COPY TEXT appear. Clipboard writes received the exact full draft and resolved; the button became COPIED. Forcing the Clipboard API to reject exercised successful `execCommand('copy')` fallback with the same full text.
- Warning starts at five seconds. Typing during warning preserves the original text and removes the warning. Eight seconds of silence clears the editor and displays the real unused-time report. Typing restarts with a new minute.
- Actual Backspace was blocked. Browser event checks covered Delete, undo/redo, cut, paste, drop, replacement text, and selection replacement. Selection typing appended rather than replacing prior text.
- Synthetic composition events retained Chinese text and reset silence through a warning. This is not a claim of physical OS IME testing.
- ESC and EXIT discard the active/kept text and return focus to the CTA.
- Both modes were inspected on landing, room, warning, wipe, and kept/copied surfaces. Stored preference survived page navigation. With empty storage, system appearance selected the default and subsequent system changes were followed. The only storage key was `writeitdown-theme`.
- Privacy, Terms, and Support opened. Legal-page theme switching worked. Measured document width equaled viewport width at 1440 and 390.
- A second isolated Chrome instance with reduced motion forced on showed a static preview and a full, non-transitioning warning wash at five seconds.
- Final product-page console had no errors. Network requests were limited to static site assets and the disclosed Google Fonts resources; no writing requests were made.

Screenshots in `qa/` covered both widths and themes, plus warning recovery, reduced motion, legal pages, exit, and composition; images were inspected individually and in contact sheets at QA time. The PNG binaries were stripped before this history entered the repository, so they survive only in the pre-transplant local commits. Paper stays brighter than wall; the mobile nav fits; the warning numeral does not overprint the editor. A wrapping mobile word count found during review was fixed with `white-space: nowrap`.

The CLI's `wait` and script `run` APIs failed in this environment. Approval was obtained to use shell timing and `eval` promises instead. Browser insertion at two-second intervals kept the real sixty-second sessions alive; the model clock was never patched.

## Remaining limits

- No deployment was attempted: the supplied brief states SSH credentials are unavailable. The install bundle is the handoff, not proof of a live release.
- Real iOS Safari, its virtual keyboard, and physical IME candidate selection were not exercised. Mobile evidence is isolated Chrome emulation.
- Clipboard read permission was denied by headless Chrome. Validation checked the actual write call's complete payload and success, and the fallback's selected full text and successful copy result.
- The public contact address remains explicitly unconfigured, as requested. Hosting log retention has not been independently audited; Privacy does not claim otherwise.
