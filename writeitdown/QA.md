# Current acceptance

Current user-visible behavior is documented in [README.md](README.md); shared writing geometry is owned by `tokens.css` and `site.css`. Run the browser acceptance command in the README for this revision. The records below describe earlier revisions, not evidence that the current change passed.

`qa/mac.spec.mjs` covers removed demo labels and caption and header theme controls. `qa/phase4.spec.mjs` covers shared demo/trial start-line placement, the blocked demo Backspace, the reduced-height mobile trial footer, short-sheet warning/failure/kept placement, the demo reset and loop, and room interactions; `qa/motion-regression.spec.mjs` covers the animated history shift, bar re-anchoring and refusal continuity. Use the current run's results and screenshots for release acceptance.

Real OS IME, iOS Safari/virtual keyboard and human audio evaluation remain unverified. Chrome viewport checks do not replace those checks.

# 2026-10-26: The room, the fold and the download head hold their numbers (web audit round)

The captain's site audit (sections 9.3 to 9.5) and the design review named eleven basic defects on
the writeitdown.app surfaces; each one now carries an assertion that fails on the pre-fix tree. The
kept screen's primary reserves its own label width and `.home :focus-visible` is a ring only
(D-059); the kept screen prints one count in the red receipt and one caption (D-062); the wiped room
keeps the caret on the empty line and holds the clock at the minute the draft died (D-063, D-065);
EXIT and the brand arm the same two-act confirmation for a thumb and both Mac links open in a new tab
(D-061, D-067); the landing's first screen is one flex column whose sheet follows a fraction floor
instead of a width or height breakpoint (D-068); the watch-only demo carries no caret and no typing
prompt (D-064); seconds read one way and both clocks use tabular numerals (D-066); and `/download/`'s
head, deck, hash and install command are fixed shapes with no scroll container (D-060, including the
two distinct copy labels). In the same round the landing header began spanning the page container
(`.home .first-screen > .wrap{width:100%}`), so the brand sits on the left gutter and the theme button
on the right like the room, the download page and the rest of the site.

## Commands and results

- `cd writeitdown && npx playwright test` (8 projects) on the head rebased onto `origin/main` after
  the sheet lane (#71) and the shared type set (#72): 960 tests, 887 passed, 0 failed, 73 skipped
  (9.2 min). The two merges kept main's paper, type and grain rules and put this round's room, fold
  and download rules on top; this round's decision numbers are D-058 to D-068 and its quality rows
  Q-24 to Q-29, so `D-056`/`Q-22` (the sheet) and `D-057`/`Q-23` (the type set) stay theirs.
- `cd writeitdown && npx playwright test --project=... --grep "kept screen: headline"` with the copy
  floor removed: `the pill keeps one width across labels` fails (137.33 -> 107.64 px), so the gate is
  still sensitive to a jumping pill.
- The merge with the sheet lane exposed one real conflict the suite did not cover: the new not-saved
  caption was still `--mute` (4.25:1 light, 4.34:1 dark on the Note paper, under the sheet's 7:1
  floor). It now uses `--paper-quiet` (7.35 / 7.38), and `qa/paper.spec.mjs` measures `#kept-note`
  with the draft and the receipt at the same floor. The paper specs plus the kept test pass on all
  eight projects (64 passed).
- Afterwards CI failed twice on a machine whose system sans is wider than the one this round was
  tuned on: the pill's `6.25em` floor was measured on this Mac's face, so `COPY TEXT` (146.5 px) and
  `COPIED` at the floor (141.75 px) differed by 4.77 px. The floor is now measured from the widest of
  the three labels in the face the device renders (`room.js` `sizeCopyFloor`, re-run on
  `document.fonts.ready` and on resize), so the rule no longer depends on a hand-measured constant;
  the `em` value stays as the no-script fallback. The probe measures on `<body>` because the room is
  hidden until the writer opens it, and a hidden descendant reports width 0: that is why the first
  measurement silently fell back to the `em` constant on CI, where `document.fonts.ready` resolved
  while the room was still closed. The kept test now asserts the floor exists before the room opens. The two failing tests now load and assert the
  page's faces (`document.fonts.status` plus a loaded `Newsreader` and `Reenie Beanie`) before any
  width is measured, and the fold's 61% check allows one rendering pixel of `vh` rounding instead of
  an exact ratio. Locally: those two tests 16 passed on the eight Chromium projects, the fold test
  passed on WebKit at 1440 and 390, and with the floor removed the pill jumps 137.33 -> 107.64 px and
  `the pill keeps one width across labels` fails, while a face 1 px wider per character still holds
  one width because the floor is measured.
- `node journey/journey.mjs --base http://127.0.0.1:8035 --expect-sha 5b8483bd... --dmg-file
  Write-It-Down-1.0.dmg`: 80 pass, 0 fail, 2 waived (sign-in, test-payment), on the phone's WebKit
  with the iPhone 14 profile and on desktop Chromium, one continuous video per viewport under
  `/Users/ichts/firstmate-homes/wid/data/wid-room-fixes/journey-r10/{phone,desktop}/`.
- `node writeitdown/release-check.mjs --download`: STATIC CHECK PASSED.
- Root `npm test` (Zero Draft landing and trial): the root `index.html` is not in this diff and was
  not re-run.

## Measured (what each assertion now holds)

| Item | Surface | Measured | Assertion |
| Q-24 copy press | kept screen, 1440 and 390 | COPY TEXT -> COPIED keeps the pill's width and left edge, deltas 0.00 px; RUN IT AGAIN left, top and width deltas 0.00 px; the pointer is still over the copy control after the relabel and a second press at the same point leaves the phase `kept` with the draft intact; the row does not wrap at 390 (`stacked: false`). The label's floor is the widest of `COPY TEXT`, `COPIED` and `TRY AGAIN` measured in the rendered face, so a wider system face changes the pill's size but never its stability | `phase4.spec.mjs` "kept screen: headline, quiet receipt, action row above a scrollable draft" |
| Q-24 focus shape | kept pill, focus ring, 1440 and 390 | focused pill 141.75x48 px with radius 999 px and a 2 px ink outline, width and height deltas 0; the Tab-reached EXIT keeps radius 0 px with the same ring | `phase4.spec.mjs` "focus is a ring, never a re-cut of the control it lands on" |
| Q-25 wipe caret | room, wipe phase | `caret-color` `rgb(28, 25, 23)` at alpha 1, no ancestor below opacity 1 (writing area opacity 1), editor focused with a collapsed `Caret` selection, editor text colour transparent | `phase4.spec.mjs` "empty room shows only the caret and the count prompt; after a wipe the receipt carries it" |
| Q-25 wipe clock | room, wipe phase | corner clock `0:52` equals the receipt's `DRAFT DELETED AT 0:52.`, still `0:52` after 1.5 s, back to `1:00` only on the next keystroke | same test |
| Q-25 phone exit | room at 390 with touch | one tap on EXIT or on the brand keeps phase `typing` with the draft and reads `Tap EXIT again to leave and delete the draft.`; two taps leave; both Mac links are `_blank` with `noopener` and the draft survives them | `phase4.spec.mjs` "nothing in the room can throw a live draft away in one act" and "a thumb gets the same two acts as a keyboard" |
| Q-25 kept count and caption | room, kept phase | corner count empty, receipt `1 MINUTE. 44 WORDS.`, caption `Nothing here is saved. Copy it before you leave.` under the actions, both controls on one line at 390 | `phase4.spec.mjs` "kept screen: headline, quiet receipt, action row above a scrollable draft" |
| Q-28 fold | landing first screen | nav, hero, door and sheet are one flex column with `min-height:100vh` / `100svh` (vh first, svh second), `.stagewrap` floors the sheet at `max(300px, 61vh)` / `max(300px, 61svh)` and `.home .paper` fills it (`flex:1;min-height:300px`), with no width or height breakpoint; measured 390x844 530.9 px = 0.629 of the viewport, 375x667 406.9 px = 0.610, 320x700 427 px = 0.610, 375x812 495.3 px = 0.610, 320x568 346.5 px at the 300 px floor with the page scrolling; the door and its note sit fully inside the fold at every size and the sheet ends on the first-screen edge (0 px); no horizontal overflow | `phase4.spec.mjs` "the door and the sheet it opens share one first screen on a short phone" |
| Q-26 demo | landing demo | 0 caret elements, no `contenteditable` and no input, the count slot empty at load then `1 word` / `17 words`, the report frame holds clock `0:39` with `DRAFT DELETED AT 0:39.` for its two seconds and re-arms at the loop's `1:00` | `phase4.spec.mjs` "the watch-only demo advertises no input, and its count speaks like the room" and "demo loop: warning group, cut, and the failure screen in the status slot" |
| Q-27 seconds | landing copy and schema | moments `0:47 · writing` / `3 s left · warning` / `8 s · deleted`, card markers `5 s · warning` / `8 s · deleted`, FAQ states the three-second lead-in and matches the JSON-LD answer word for word | `phase4.spec.mjs` "the landing states the warning lead-in and never labels a moment with another moment" |
| Q-27 tabular clock | room and demo | clock width constant at 33.625 px across `1:00`, `0:58` and `0:11`; `font-variant-numeric: tabular-nums` on the room clock, the demo clock and both counts | `phase4.spec.mjs` "the clock does not breathe: tabular numerals on the room and the demo" |
| Q-28 download head, hash and command | `/download/` at 1440, 390, 375, 320 | H1 `Write It Down` / `for Mac` as two two-word lines on phones (one centred line at 1440); deck ink left 20.00 px on the H1's ink left 20.00 px at 390/375/320, 34ch cap; the hash's two 32-character halves share one 13 px line at 1440 and wrap as two unbroken lines at 390/375 (13 px) and 320 (12 px); the install command splits at its argument with `Write-It-Down-1.0.dmg` whole; 0 scroll containers, no fade; COPY returns the joined 64-hex value and the one-line command; the two controls carry distinct names (`Copy the SHA-256`, `Copy the install command`) | `mac.spec.mjs` "the download head breaks without an orphan and its checksum block reads" |
| Header | landing at 320, 375, 390, 768, 1024, 1440 | the nav box equals the page container at every width (1120 px centred at 160-1280 on 1440, full width below); the brand sits on the container's left padding (192 px from the viewport edge at 1440, 32 px at 1024, 20 px at 390) and the theme button's right edge on the right padding (1248 of 1440, 370 of 390, 355 of 375, 300 of 320); no horizontal overflow | `mac.spec.mjs` "the landing header spans the page container at every width" |

## Known-broken proofs for the new gates

Each assertion was run against the pre-fix tree; the recorded failure text is the item's own.

- Copy press: with the label floor removed the pill shrinks, `the pill keeps the COPY TEXT width` fails.
- Focus shape: `a square control stays square` fails while the room-wide focus rule still sets `border-radius`.
- Wipe caret: the caret-state deep equality fails while the writing area keeps `opacity: 0`.
- Wipe clock: `toHaveText` fails with `1:00` against the receipt's `0:52`.
- Phone exit: two `toBeVisible` failures while one tap leaves the room.
- Kept count: `the corner count is silent on the kept screen` fails while both counts print.
- Fold: `375x667: the sheet it opens ends on the first screen` fails on the breakpoint rule.
- Demo: `toHaveCount` fails on the caret element and on the empty count slot.
- Seconds: `the warning panel is labelled with its own numeral: 5 s · warning` fails.
- Tabular clock: the width equality fails with two different clock widths.
- Download: ``the line `Mac` holds more than one word`` fails on the phone head, and the pre-change
  release gate reads a truncated install card (`Install command: the card does not name the DMG file
  to hash`) and a card whose command hashes `Write-It-Down-0.9.dmg` while the page links 1.0 is
  refused.
- Header: removing `.home .first-screen > .wrap{width:100%}` shrinks the lockup and the new test fails
  with `expected difference < 0.5, received 58.265625`; restoring the rule makes it pass.

## Captures

- This round's suite run wrote one directory per touched test at 1440 and 390 in both themes under
  `/Users/ichts/firstmate-homes/wid/data/wid-room-fixes/qa-r10/artifacts2/`, covering the kept,
  copied and focused room, the wipe, the phone exit confirmation, the armed brand, the demo
  typing/warn/report, the fold, the download head and hash, and the landing header.
- The live Chrome drive behind the measured table is
  `/Users/ichts/.no-mistakes/evidence/01M5WCJ7JM97Y38TNTSA45D0KH/live-r9/` (`room-report.json`,
  `fold-report.json`, `header-report.json`, `report.json`, `demo-report.json`, `phone-report.json`,
  and `room-copied-1440.png`, `room-kept-primary-focus-1440.png`, `room-wipe-1440.png`,
  `phone-room-brand-armed.png`, `demo-report-1440.png`, `download-hash-1440.png`, `download-390.png`,
  `fold2-375x667.png`, `fold2-320x700.png`, `header-1440.png`, `header-390.png`).

## UI quality checklist (docs/ui-quality.md)

| Rule | Result | Basis |
| Q-01 | PASS | No chrome was added on any state; `phase4.spec.mjs` "the session bar is one continuous linear animation" and the one-bar assertion inside `assertRoom` are green. |
| Q-02 | PASS | "warning numeral, caption and wipe receipt are placed by ink under the writing line" is green; the receipt's slot did not move when the count left the corner. |
| Q-03 | PASS | The wipe now holds the same caret state as the first-entry room: `caret-color` painted, editor focused and collapsed, writing area at opacity 1 (the deep-equality assertion). |
| Q-04 | PASS | "demo and trial active-line placement: 35% of the sheet" is green on both surfaces. |
| Q-05 | PASS | The kept row shares one baseline and one optical centre at 1440 and 390, and both controls stay on one line at 390 (`stacked: false`). |
| Q-06 | PASS | The copy press and the focus ring move nothing: copy width, left and the restart rect all measure 0.00 px delta. |
| Q-07 | PASS | One caption was added on the kept screen by the captain's decision (D-062); no other label or helper sentence was introduced. |
| Q-08 | PASS | The web room and the landing demo now share the caret rule, the clock rule and the seconds vocabulary; the Mac differences are scoped and named in D-062, D-063 and D-065. |
| Q-09 | PASS | Every touched state is captured at 1440 and 390 in light and dark in this round's evidence directory. |
| Q-10 | PASS | Nothing new moves while typing: the clock keeps its width (tabular), the caret is static, and the demo's report holds still for its two seconds. |
| Q-11 | PASS | No motion was added or changed; the reduced-motion projects of the touched tests are green in the full run. |
| Q-12 | PASS | The room keeps `Type to start` and the wipe receipt keeps `TYPE TO START AGAIN.`; the watch-only demo no longer prints either (D-064). |
| Q-13 | PASS | Every control keeps the ink ring; the ring no longer re-cuts the control's shape (radius 999 px pill, 0 px square). |
| Q-14 | PASS | The kept row sits on one line at both widths, the deck starts on the headline's ink edge (20.00 / 20.00), and the header keeps the container's gutters at 320 to 1440. |
| Q-15 | PASS | The two-act exit follows the platform's destructive-action confirmation; the copy controls follow the site's own ghost pill and a live-region status. |
| Q-16 | PASS | These eleven defects were found by the audit and the design review, not by a tester; each now has an assertion. |
| Q-17 | PASS | No type metric changed except the hash's 12 px step below 365 px, which is recorded in D-060. |
| Q-18 | N/A | Mac launch state; no web surface. |
| Q-19 | PASS | The landing header now spans the container at 320 to 1440 with no overflow, and `/download/` keeps its gutter sweep. |
| Q-20 | PASS | One caption was added (D-062); the price string is unchanged and `shell.spec.mjs` still enforces `$4.99 once`. |
| Q-21 | PASS | The twelve shipped pages keep one header, canvas and body family; `shell.spec.mjs` is green. |
| Q-24 | PASS | Copy press and focus shape: see the measured table. |
| Q-25 | PASS | Kept count and caption, wipe clock hold, wipe caret, and the two-act exit: see the measured table. |
| Q-26 | PASS | The demo draws no caret, prints no typing prompt, and its count and receipt stay truthful. |
| Q-27 | PASS | Seconds read one way and both clocks are tabular. |
| Q-28 | PASS | The fold, the download head, the deck edge, the hash and the install command: see the measured table. |
| Q-29 | PASS | Escape, EXIT and the brand arm one two-act confirmation, a single tap on a phone keeps the draft, typing cancels it, both Mac links open in a new tab, and the wording follows the input (D-061, D-067). |
| Q-28 | PASS | The sheet's text roles clear 7:1 on the Note paper, including the not-saved caption (7.35 light, 7.38 dark) that the merge with the sheet lane found at 4.25; `qa/paper.spec.mjs` measures it with the draft and the receipt. |

## Remaining limits

- 320x568 still scrolls: the sheet keeps its 300 px floor and the door and note are inside the first
  screen, but the demo's lower half is below the fold. That is D-068's decided outcome, not a defect.
- Headless Chrome does not composite the native text caret, so the wiped room's caret is pinned by
  its painted `caret-color`, the focused editor with a collapsed selection, the writing area at
  opacity 1 and a frame burst over the writing line, not by a screenshot pixel.
- Real OS IME, iOS Safari with the virtual keyboard, and human audio evaluation remain unverified;
  Chrome viewport checks do not replace them.
- Mac parity is not claimed for D-062, D-063 and D-065: the Mac kept screen still prints the count
  twice and the Mac deleted screen still shows the re-armed clock. The Mac lane applies the same
  rules under `docs/wid-mac-behavior.md` before the two surfaces are called one design.
- The release journey needs Playwright WebKit and a real DMG; the run recorded above served the local
  1.0 DMG, so a live-site journey is still the pre-release step on the host.
- No deployment. writeitdown.app still serves the previous bundle until `sh writeitdown/install.sh`
  runs on the host.


# 2026-10-26: One shared type set with the Mac app, served by the site itself

Every shipped page now draws text with the same faces the Mac app does (D-057): Newsreader for what
the writer writes and for every heading, Zhuque Fangsong for the same roles in Chinese, the system
sans for everything the tool says, and the system monospace for literal code strings only. The
landing's Reenie Beanie hand accent stays as the one declared exception. All faces are served from
`fonts/`; no page requests a font host, and the ten pages that still carried the retired IBM Plex
Mono identity now use the shared set. Evidence: `fonts/` (the build step and its OFL texts),
`qa/typography.spec.mjs`, `qa/shared-type-baseline.json`, `design/DESIGN.md` section 12.

## Commands and results

- `npx playwright test` (whole writeitdown suite, 8 projects, private port 8117 because another
  lane held 8015): 751 passed, 0 failed, 73 skipped (16.0 min).
- `npx playwright test qa/typography.spec.mjs`: 56 passed, 0 failed.
- `npm test` at the repository root (the landing/trial harness): 2 passed, 0 failed.
- `python3 -m http.server 8017`: `index.html` requests `fonts.css`, `fonts-cjk.css`,
  `fonts/newsreader-latin.woff2`, `fonts/reenie-beanie.woff2` and nothing from another origin.

## Measured (browser-computed, light and dark agree)

| Role | Family as computed | Size / weight / tracking |
| Writing text and kept text | `Newsreader, "Zhuque Fangsong", Georgia, ...` | 28 px / 400 / normal, 1.6 pitch |
| Kept heading, failure headline | the same stack | 48 px / 500 / **normal** (was `-.02em`) |
| Chinese draft (platform face) | `Zhuque Fangsong (technical preview)` -> `ZhuqueFangsong-Regular`, 6 glyphs | 28 px / 400 |
| Clock | system sans | 15 px / 600 / normal, `font-variant-numeric: tabular-nums` |
| Count | system sans | 13 px / 400 / normal |
| Kept receipt, wipe report | system sans | 13 px / 500 / `0.26px` (.02em) |
| Warning caption, quiet link | system sans | 13 px / 500 / `0.52px` (.04em) |
| Room pills | system sans | 15 px / 600 / `0.6px` (.04em) |
| Hand accent (landing only) | `"Reenie Beanie", "Segoe Print", cursive` | 108.36 px / 400 |
| With `fonts.googleapis.com` and `fonts.gstatic.com` refused | writing face is still `Newsreader 16pt` (bundled), the editor stack unchanged | 28 px / 400 |

Face payload: Newsreader upright 137,436 B, italic 154,240 B, the hand accent 17,936 B, and 13
Zhuque Fangsong slices 2,726,540 B in total (48,668-358,692 B each). A page that renders no Chinese
fetches 309,612 B of faces plus `fonts.css` (1,127 B); `fonts-cjk.css` (47,824 B) is linked by
`index.html` alone and a Chinese slice downloads only when a character in it reaches the screen.

## Captures

60 PNGs at `/Users/ichts/firstmate-homes/wid/data/wid-font-fix/captures/`: the landing, `mac.html`,
`download/`, support, privacy, terms and the price page at 1440x900 and 390x844 in light and dark;
the room empty, typing, warning, wiped, kept and exit-confirmation in both themes and sizes; the room
with a mixed Chinese draft; and the landing and room with both font hosts refused. Face measurement
JSON sits beside them (`measurements.json`, `cjk-face.json`).

## Known-broken proofs for the new gates

- **Chinese falls back to the system CJK face again.** Removing `var(--cjk)` from `--serif` (the
  pre-change stack exactly) makes `qa/typography.spec.mjs` `chinese in the room draws in the Mac
  room's fangsong` fail with `Received string: "Newsreader, Georgia, \"Times New Roman\", serif"`;
the plant was removed and the committed tree passes.
- **The mono identity comes back.** Adding `font-family:ui-monospace,...` to `.home .doc h2` makes
  `every text role on every shipped page stays in the shared type set` fail with
  `mac.html: monospace is reserved for code, found h2,h2,h2,h2,h2,h2`; the plant was removed and the
  committed tree passes.
- The same guard was shown failing in the pre-change values the inventory measured: headings at
  `-.02em` (`kept h1` advance 378.594 vs the Mac's 395.869) and a proportional clock
  (`1:00` 31.391 px, `0:59` 33.859 px on a 15 px face).

## UI quality checklist (docs/ui-quality.md)

| Rule | Result | Basis |
| Q-17 | PASS | The writing pitch is unchanged on both surfaces: 28 px / 1.6 = 44.8; only the face behind the glyph changed. `EditorFocusTests.linePitchIsFixedForChineseEnglishAndMixed` and the shipping 28/1.6 room both hold, and the subset build refuses a subset that moved the em box. |
| Q-19 | PASS | No horizontal overflow at 320-1440 px after the face changes; `qa/shell.spec.mjs`'s width sweep stays green. |
| Q-23 | PASS | The shared type set is measured, not eyeballed: the role census on twelve pages, the self-hosted proof with the font hosts refused, the Chinese platform face, clock width stability, the untracked headings, the receipt's 13 px medium and tracking, and the shared advances against the Mac's own numbers (`shared-type-baseline.json`, tolerance 0.05 %); in the current run 56 of 56 typography assertions pass. |

# 2026-10-26: Document content sits on the header grid (PR 70 review round)

The captain read the PR 70 preview of `mac.html#buy` and saw the page as a narrow column stuck to the
logo with an empty band on the right. The measurement matched the eye: the ten document pages put a
62ch measure inside a 1120 px container that was itself flush with the header, so every paragraph
started on the header's left edge and stopped 392 px short of its right edge at 1440. `main.doc` now
owns the measure and is centred in the header container, and the per-block `max-width`s of `h1`,
`h2`, `p`, `.qa`, `.doc-buy` and `.license-card` are gone, so the H1, the lede, the questions, the
purchase card and the licence card share two edges that are equidistant from the header's own. This
is the landing's composition (a centred object inside the header container, like the 760 px sheet
under the 1120 px header), not a new one. D-055 records the decision.

## Commands and results

- `npx playwright test qa/shell.spec.mjs qa/mac.spec.mjs` (8 projects): 258 passed, 0 failed,
  46 skipped.
- `npx playwright test` (whole writeitdown suite, 8 projects): 695 passed, 0 failed, 73 skipped
  (6.7 min).

## Measured (content edges inset from the header container)

| Surface | 1440 | 1024 | 390 |
| Ten document pages, all text blocks | 196 / 196.1 px | 148 / 148.1 px | 0 / 0 px |
| `mac.html` buy card (border box) | column-wide, 196 px inset | 148 px inset | gutter-width, 0 inset |
| `mac.html` buy card (text inside its padding) | 236 / 236.1 px | 188 / 188.1 px | 24 / 24 px |
| `/download/` and the landing | unchanged, container-flush (0 / 0) | 0 / 0 | 0 / 0 |

The header container spans 192-1248 at 1440, 32-992 at 1024 and 20-370 at 390, so the document
column sits symmetrically inside it at every width and never narrower than one gutter at 390.

## Known-broken proof for the new gate

With the pre-fix `site.css` restored (the tree at `21565be`), `qa/shell.spec.mjs` `every page puts
its content on the header grid at 1440, 1024 and 390` failed with:

```
mac.html @1440 h1 starts 0 px and ends 211 px from the header's edges: flush with the header container or centred in it
Expected: <= 1   Received: 211
```

and the paragraph blocks reported the same 0 / 392.1 px split at 1440 and 0 / 296.1 px at 1024. With
the fix the same test passes on all twelve pages at all three widths. The failing run's artifacts
are in the task evidence directory (`known-broken-grid/`).

## Captures

`captures/mac-buy-{before,after}-{1440,1024,390}-{light,dark}.png`: `mac.html#buy` before and after at
the three widths in both themes. `captures/{landing,support,download,mac}-grid-*` and
`*-grid-before-*`: full pages at 1440 and 390 in both themes, landing beside a migrated page.

## UI quality checklist

| Rule | Result | Basis |
| Q-14 | PASS | Content edges are 196 / 196.1 px inside the header container at 1440, 148 / 148.1 at 1024 and 0 / 0 at 390 on all ten document pages; the landing and `/download/` stay container-flush. Pinned by the shell geometry test (D-055), which fails at 211 px asymmetry on the pre-fix tree. |
| Q-16 | PASS | The misalignment was found by the captain on the preview; the measurement now ships as an assertion so a reviewer is not the first to see it. |
| Q-19 | PASS | No horizontal overflow at 390: the column keeps both gutters (20 / 370 in a 390 viewport). |

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
| Q-19 | PASS | The 360 px point samples now run over every shipped page and the room, and the width sweep still covers `/download/`; no overflow, 6 px+ gutter, one plate token. |
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
