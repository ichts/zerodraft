# Current acceptance

Current user-visible behavior is documented in [README.md](README.md); shared writing geometry is owned by `tokens.css` and `site.css`. Run the browser acceptance command in the README for this revision. The records below describe earlier revisions, not evidence that the current change passed.

`qa/mac.spec.mjs` covers removed demo labels and caption and header theme controls. `qa/phase4.spec.mjs` covers shared demo/trial start-line placement, the blocked demo Backspace, the reduced-height mobile trial footer, short-sheet warning/failure/kept placement, the demo reset and loop, and room interactions; `qa/motion-regression.spec.mjs` covers the animated history shift, bar re-anchoring and refusal continuity. Use the current run's results and screenshots for release acceptance.

Real OS IME, iOS Safari/virtual keyboard and human audio evaluation remain unverified. Chrome viewport checks do not replace those checks.

# 2026-11-11: Buy moves to the header's top-right corner (D-115)

The landing's `Buy` link under the door is gone; every header carries a lighter quiet `Buy` pill left of the page
action, and below 460 px it is the only header pill. Proof: `qa/shell.spec.mjs` `the header carries Buy on every
page...`, the 320-480 px header sweep in `qa/mac.spec.mjs`, the `buy-page` journey block on WebKit iPhone 14 and
Chromium 1440x900 (header Buy to `/buy` to hosted checkout), and before/after captures of the landing at 1440 and 390 in
both themes, `/buy` and `mac.html` in `data/wid-buy-top-right/`.

# 2026-11-10: The buy line opens a purchase page, not the manual

`writeitdown.app/buy` is the sale (D-113). One screen at every width, holding the price `$4.99 once`
as the page's largest text, the licence in three lines - `One license for 2 computers.`,
`No subscription.`, `Free updates included.` - the primary `Buy for $4.99 once` form, and
`Download free trial`. Nothing below the actions, no footer, and no refund, guarantee, trust badge or
payment-provider line beside the button. The landing's buy line and every footer `Buy for Mac` point
here; `mac.html` stays the manual and the checkout's return page, its `#buy` card carries the same
price and the same three lines word for word and links to `/buy`; the refund left that card for
`#refund`, `/terms.html` and the checkout. `/buy` is out of `sitemap.xml` until LIVE sales pass the
real TEST loop, as `mac.html` is.

## Commands and results

- `npm run release-check`: `STATIC CHECK PASSED: inputs present. Not verified live; run with --live.`
  The gate now reads the checkout slot from `buy.html`; `qa/mac.spec.mjs` carries the refusal cases
  for a missing slot, a GET form, a wrong action and a wrong price on either page.
- `python3 qa/test-install.py`: `PASS: 52 exact production files, preserved backup, repeat
  installation, rejected symlinks.` `buy.html` is in `install.sh` and in the test's own list, and the
  reference crawl now walks the purchase page's assets too.
- `npm test` (8 projects, 1536 tests): 1433 passed, 2 failed, 1 real. The real failure was this
  change's own drift: `installer installs the complete purchase bundle` failed until `buy.html`
  joined `qa/test-install.py`; it passes now, and the installer's two negative controls still pass.
  The other failure was `history-fade.spec.mjs` "the aperture clips a partial line at its edge and
  never fades it" at 14.9 s under parallel load, which then passed 3/3 alone in 1.3 to 2.3 s. The
  full-session journey step also flaked 1 of 2 runs on this machine against a clean HEAD worktree as
  well; it passed in both full journey runs recorded below.
- `npm run journey -- --base http://127.0.0.1:8127 --expect-sha b5796ac1…` (real 1.1 DMG served,
  matching its published SHA-256): 86 passed, 0 failed, 2 WAIVED (sign-in absent; installed-DMG TEST
  acceptance pending), both viewports, one continuous video each. The new `buy-page` block walks
  landing -> buy line -> `/buy` -> hosted checkout on WebKit iPhone 14 and Chromium 1440x900 and
  fails if the walk ever passes through `mac.html`.
- The same journey against a server without the artifact: 84 passed, 2 failed, both the DMG step
  answering 404, which is the documented `--dmg-file` requirement rather than a page defect.

## Measured (what the new assertion holds)

`scripts/core-tasks/measure-web.mjs --tasks 3 --runs 3` now also records the destination's own cost,
so `--root` can measure a baseline worktree with the same instrument. Before this change the buy
link landed on `mac.html#buy`; after, on `/buy`:

| Item | Before (HEAD tree) | After (this branch) |
| --- | --- | --- |
| T3 steps | 2 clicks + 0.33 screens to the landing buy line | same |
| Purchase page, desktop | 2.14 screens | 1 screen |
| Purchase page, phone | 2.99 screens | 1 screen |
| Buy control on the first screen | yes (inside the card, above Requirements/Install/Activate/Refunds) | yes |
| T3 machine time | 350 to 390 ms desktop, 340 to 375 ms phone | 271 to 445 ms desktop, 302 to 495 ms phone (within noise, load 11 to 36) |

- `qa/shell.spec.mjs` holds the purchase page's own contract: the landing shell (brand y, plate,
  canvas, body family), an exact reading of `main` that is those five strings and nothing else, no
  footer, no refund/guarantee/secure/stripe wording under the actions, exactly one link in `main`,
  the clean canonical `https://writeitdown.app/buy`, one screen at 320, 390 and 1440 with the price
  as the largest text on the page, and the licence sentence equal to `mac.html`'s word for word.
- Measured at 320, 390 and 1440, light and dark: `overflowX: 0`, document height equal to the
  viewport at all three widths, price 116 px Newsreader at 1440 and 52 px at 390/320, facts block
  84.5 px, actions 48 px tall and 104 px stacked on a phone, the stacked pair sharing one 192 px
  width.
- `qa/typography.spec.mjs` now censuses the purchase page too: its roles resolve to Newsreader and
  the system sans, and no face is fetched from another host.

## Captures

`data/wid-buy-page-c/captures/`: `{before,after}-destination-{1440,390}-{light,dark}.png` (the page
the buy line opens, at the anchor as it resolves), `before-destination-390-light-full.png` (the 2.99
screens of manual the buyer used to land in), and `{before,after}-landing-{1440,390}-light.png`
(the door and its buy line). `data/wid-buy-page-c/core-{before2,after}/shots/` carries the meter's own
captures of the landing, the purchase page and the hand-off.

## Known-broken proof for the new gates

The `buy-page` journey block fails on the old href: with `index.html`'s buy line pointing at
`mac.html#buy`, `waitForURL(/\/buy/)` never resolves and the block records
`the landing buy line opens the price, not the documentation` as FAIL - observed while the working
tree was mid-edit, before the link was repointed. The one-screen gate fails on the pre-change
destination by construction: `mac.html#buy` measures 2.14 screens at 1440 and 2.99 at 390.

## Quality checklist rows this change touches

- Q-07 pass: the purchase page adds no label, subtitle or helper sentence. It holds the price, the
  licence and two actions, and nothing else.
- Q-09 pass: both themes captured at 1440 and 390; the dark page is the same composition with the
  site's dark tokens.
- Q-14 pass: one centred column on the page's own axis; the price, the three lines and the action
  pair share it within 1 px at 320, 390 and 1440.
- Q-19 pass: the purchase page joins the header gutter, chip-plate, focus-ring and grid sweeps.
- Q-24 pass: the two controls keep one width with the stacked phone row (192 / 192 px) and stay
  distinct by surface and colour, not by width.
- Q-28 pass: no wrapped unit, no clipped string, no horizontal overflow at 320, 390 or 1440; the
  refund window's `14-day` guard moved to the `/download/` requirement card with the sale.
- Q-30 pass: nothing beside the Buy button reassures; the refund, the licence terms and the payment
  processor are stated on the checkout and the legal pages, where a buyer already expects them.

## Limits

- This is the web surface only. The purchase page hands off to the same Stripe checkout; no payment,
  licence or checkout code changed, and no real card was used.
- The journey recorded here is a local pre-deploy run against the real 1.1 DMG. Installed-DMG TEST
  acceptance and LIVE sales remain the maintainer's next step, and the waiver is unchanged.
- `mac.html#buy` keeps its section and its `scroll-margin` for old bookmarks and emails; nothing on
  the site links to it any more.

# 2026-11-05: The download page keeps 1.1 current and archives 1.0

`/download/` links `Write-It-Down-1.1.dmg` and publishes that artifact's SHA-256, as it has since
2026-11-04. What changed is what the page says about the version before it: one quiet line under the
requirements, `#previous-version`, reads `Previous version: 1.0.` / `A 1.0 installation cannot update
itself.` / `The archived Write-It-Down-1.0.dmg is a fresh install of 1.0 only.` and links
`releases/Write-It-Down-1.0.dmg` (D-081). The archive is a host file: until firstmate places it on
the host and applies the Caddy delta, that address answers 404, so the link is correct and dead.

## Commands and results

- `node writeitdown/release-check.mjs --download`: `STATIC CHECK PASSED` and `Download page ready: the
DMG link, the Install command and its published SHA-256 agree.` The gate now also refuses an archive
note that is not `releases/Write-It-Down-<version>.dmg` or not older than the linked download; the
fixture table in `qa/mac.spec.mjs` carries 25 refusal cases, four of them new.
- `cd writeitdown && npx playwright test qa/mac.spec.mjs -g "the download page offers 1.1 as current
and 1.0 as the archived previous version"`: 8 passed (1440/390, light/dark, both motion settings).
- `cd writeitdown && npx playwright test qa/mac.spec.mjs`: 211 passed, 1 failed. The failure was
`the header keeps its right gutter and a legible chip at 360 px with wider system-font metrics`
timing out at 35.7 s against Playwright's 30 s default budget, the known parallel-load timeout this
file already records for 2026-11-04, not an assertion. That sweep and `the landing header spans the
page container at every width` now declare `test.slow()` (a 90 s budget for 6 to 39 navigations);
both pass alone in 4.2 s, 11.2 s and 7.6 s.
- `python3 qa/test-install.py`: `PASS: 62 exact production files, preserved backup, repeat
installation, rejected symlinks.` It now exempts the archive path, which no deploy bundle contains,
instead of failing on a link its reference crawl cannot install.
- `cd writeitdown && npx playwright test` (8 projects): 1152 passed, 27 failed, 1.4 h on a machine
running four other agent lanes. All 27 were timeouts or disposed browser contexts in specs this
change does not touch (`history-fade`, `checkout`, `impressum`, `motion-regression`, `phase4`,
`shape-text`, `shell`) plus the two header sweeps above; twelve of the failing titles re-run alone
passed, and so did the remaining two. This is a load result, not a clean run: the changed specs are
`qa/mac.spec.mjs` (211/212, the one failure fixed by the budget above) and `qa/test-install.py`
(green). No other suite run was clean on this machine today.

## Measured (what the new assertion holds)

| Item | Surface | Measured | Assertion |
| Q-14 alignment | `/download/` at 1440, 390, 320 | the note's left edge 373.00 / 43.00 / 33.00 px equals the requirements' 373.00 / 43.00 / 33.00 px and the card's content edge, at both themes; 24 px below the requirements' last rule; page never scrolls sideways (overflow 0) | `the download page offers 1.1 as current and 1.0 as the archived previous version` |
| Q-28 copyable filename | the archive link at 1440, 390, 320 | one client rect at every width, 139.3 px, text `Write-It-Down-1.0.dmg`; `white-space: nowrap` keeps it whole, so a reader can match it against a file on disk | same test |
| Link set | `/download/` | exactly two `.dmg` links: `https://writeitdown.app/download/Write-It-Down-1.1.dmg` from `data-launch="dmg"`, and `releases/Write-It-Down-1.0.dmg` inside `#previous-version`; the Install command and `#release-notes` still name 1.1 | same test |
| Not a second download | `#previous-version` | no `data-launch` mark, not a `.btn`, `display: inline` link, 13 px muted line below the requirements and below the download action's bottom edge (872.16 vs 848.16 and 447.38 px at 1440) | same test |
| Text floor | the note at both themes | 5.77:1 light and 5.80:1 dark against the card, above the 4.5:1 floor for 13 px text; the link keeps the same colour and adds an underline | same test |

Captures: `test-results/mac-the-download-page-*/download-archive-note-{1440,390,320}.png`, the
download card only, and the existing full-page `download.png` per project.

## Quality checklist rows this change touches

- Q-07 (no extra labels or helper lines) - PASS: the note is one line that states a version, a
limitation and what the archive is; no heading, kicker, badge or second card.
- Q-14 (deliberate alignment) - PASS: measured left edges above.
- Q-20 (copy states a fact, never sells) - PASS: three subject-verb-object sentences, no benefit,
no changelog; `$4.99 once` and the requirements list are untouched.
- Q-28 (nothing a reader must copy is broken or clipped) - PASS: the archived filename stays one
139.3 px run at 320 px and the two hash halves, the `shasum` call and the 1.1 filename keep their
shapes in the existing head test.
- Text floors - PASS: 5.77:1 and 5.80:1, both above 4.5:1.

## Not exercised

- The 301s and the archive directory are written as a Caddy delta and measured against a real
  Caddy v2.6.2 binary in a loopback lab (see `data/wid-dmg-10-retire/report.md`); nothing was
  applied to the host, so the live `/download/Write-It-Down-1.0.dmg` still answers 200 today.
- The archive link is unvisited in a browser against the real host: the file is not there yet, and
  the suite's link crawl deliberately skips it as a host artifact.
- No independent cross-vendor review of the note's copy and placement yet; the wording is proposed
  for approval in the task report before it goes live.

# 2026-11-04: The download and Mac pages name 1.1

`/download/` offered `Write-It-Down-1.0.dmg` while the Sparkle feed already offered 1.1 (build 2), so
the site contradicted itself: a visitor downloaded an older app than the updater would give them.
The page now links `Write-It-Down-1.1.dmg` (9,229,162 bytes, SHA-256
`b5796ac123419f69ec758c3d671e3d90fcd119ae8e932136adee0484616818a6`), and the two 32-character hash
spans, the Install command's filename and the note all name that artifact. `#release-notes` returns
with `data-release-note="1.1"` and reads `Version 1.1. A free update for the app you already own.`;
`mac.html` carries the same line in its `doc-note` shape under Requirements. No style, layout,
analytics, copy about features or other page changed.

## Commands and results

- `node writeitdown/release-check.mjs --download`: `STATIC CHECK PASSED` and `Download page ready: the
  DMG link, the Install command and its published SHA-256 agree.`
- `node writeitdown/release-check.mjs --download --live`: `LIVE CHECK PASSED`, so the served DMG
  hashes to the published value. `curl -sSI https://writeitdown.app/download/Write-It-Down-1.1.dmg`
  reports `content-length: 9229162`, and an independent `shasum -a 256` of the download returns
  `b5796ac123419f69ec758c3d671e3d90fcd119ae8e932136adee0484616818a6`. The feed at
  `https://writeitdown.app/download/appcast.xml` carries `sparkle:shortVersionString` 1.1 and
  `sparkle:version` 2, so page and feed now name one version.
- `cd writeitdown && npx playwright test qa/mac.spec.mjs -g "download page states the trial, the DMG"`:
  8 passed. `-g "Mac page offers the free trial and real Buy"`: 8 passed. `-g "the download head
  breaks without an orphan"`: 6 passed and 2 timed out at the 30 s per-test budget under parallel
  load; both projects pass alone (16.0 s and 17.4 s), so the gate is unchanged, not regressed.
  `-g "release gate rejects missing or invalid"`: 8 passed after the note fixtures began deriving
  the linked version and version ahead of it from the page instead of a hardcoded pair.
- Placement, measured rather than eyeballed: on `/download/` the note's left edge is 373 px against
  the card's 373 px content edge at 1440 and 43 px against 43 px at 390, with no overflow; on
  `mac.html` its left edge equals the Requirements paragraph's (388.05 px at 1440, 20 px at 390).
  The note's contrast is 5.15:1 light and 5.28:1 dark on the download panel, 5.38:1 and 6.82:1 on the
  Mac page, all above the 4.5:1 floor for its 13 px and 15 px sizes.
- Captures at `/Users/ichts/firstmate-homes/wid/data/wid-download-11/captures/`:
  `{download,mac}-{1440,390}-{light,dark}.png`, full page.

Limits: this round only makes the pages describe the artifact the release pipeline already hosts.
Installing the site is a separate deploy step, and the page served from writeitdown.app until then
still shows 1.0.

## Quality checklist rows this change touches

- Q-07 (no extra labels or helper lines) - PASS: the download note is one line with the version and
the free-update fact; `mac.html` carries the same line and no new section, kicker or subtitle.
- Q-14 (deliberate alignment) - PASS: measured left edges above (373/373 and 388.05/388.05, 43/43 and
20/20 px) at 1440 and 390.
- Q-20 (copy states a fact, never sells) - PASS: `Version 1.1.` plus `A free update for the app you
already own.`; no feature, changelog or benefit claim, and the price string `$4.99 once` is untouched
(`qa/shell.spec.mjs` `the purchase path states one price string` still reads one string).
- Q-28 (nothing a reader must copy is broken or clipped) - PASS: the two 32-character spans, the
`shasum -a 256 ` call span and the `Write-It-Down-1.1.dmg` filename span keep their shape; the head
and command test passes on both phone widths and both desktop widths.
- Text floors - PASS: 5.15:1 and 5.28:1 on the download panel, 5.38:1 and 6.82:1 on `mac.html`, all
above 4.5:1 for 13 px and 15 px text.

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
| Kept receipt | system sans | 13 px / 500 / `0.26px` (.02em) |
| Stopped-screen line `Draft deleted.` | system sans | 15 px / 400 / normal |
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
| Q-02 | PASS | Warning numeral and caption placement assertions in `phase4.spec.mjs` are green, and the stopped screen is one group whose midpoint sits at 33% of the sheet (`the stopped screen is one group anchored at 33% of the sheet`, both widths); the wipe receipt is retired (D-070). |
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
  behaviour (D-043 to D-046): 35% anchor, caret-only empty room with `Type to start`/`0 words`, stepped  per-line history with a one-pitch 180 ms shift, ink-placed warning group, one 2 pt
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
- The public contact address remains explicitly unconfigured, as requested. Privacy states the 2026-11-04 access-log policy (IPv4 truncated to /24, IPv6 to /48, referrer cut to its origin, raw logs kept at most 14 days); the hosting configuration has not been independently audited.

# 2026-10-26: The stopped screen is one composition (web + Mac, D-070)

- Scope: the failure screen on the browser trial, the landing demo and the Mac room. The trial and
  the Mac carry the `Begin again` pill; the watch-only demo shows only `You stopped.` and
  `Draft deleted.`. The captain rejected the paused candidate-C screen (frozen clock and bar as a
  receipt, `Begin again` as a text link, block pinned 72 px under the sheet's top edge) and locked a
  composition in the live tuner: one group whose midpoint sits at 33% of the paper height, with a 9
  px gap under the headline and, where the pill is present, the line above it and 24 px above the
  pill, the session chrome off. Values and reasoning: `docs/wid-decisions.md` D-070.
- Composition before the change, measured with the same probe the new test uses (1440: group top 72,
  height 128.8, midpoint 16.97% of the 804 px sheet, 8 px and 20 px gaps, a 24 px / 15 px / 400 text
  link, no pill, clock and bar visible; 390: midpoint 16.44%). The new assertions failed on 8 of 8
  Playwright projects before the change, the first with
  `group midpoint at 16.44% of the 776 px sheet`.
- Web assertions (`qa/phase4.spec.mjs`): "the stopped screen is one group anchored at 33% of the
  sheet" measures the anchor, both gaps, the order, the headline size for the width (48 px at 1440,
  the role's own 32 px at 390), the line's 15 px / 400 in the sheet's quiet role (`--paper-quiet`, 7:1 or better on the sheet in both themes), the pill's 48 px height, 15 px / 600,
  20 px padding and full radius, the chrome-off rule, and that neither the group nor its parts move
  as time passes; "the stopped pill carries the keyboard and shows the room ink ring" holds the
  visible focus ring and the `aria-keyshortcuts`; "Return and the pill start a fresh session and
  bring the chrome back" holds the restart path; the demo test holds the 33% anchor, the 9 px gap and
  the chrome-off rule on the landing preview, and the new "the demo takes its chrome off while the
  stopped block shows" holds the rearm.
- Mac assertions: `RoundThreeTests.stoppedScreenIsOneGroupAnchoredAtThirtyThreePercent` (light and
  dark, at 1040x720 and at a smaller 760x560 sheet: order, the group midpoint on the room's one
  anchor `RoomPresentation.paperAnchorFraction` (0.33 of the paper, the same constant that places the
  active writing line, so the two cannot disagree), the two gaps as 9/48 and 24/48 of the pill-height
  base, the headline's 1.1 line box, the line's 24/48 box (the web's 15/1.6), the line and pill label
  as 15/48 of that base from the typography tokens with the size applied to the token, the group's
  3.2875 base ratio sum, the pill at the base height with 20/48 sides, centred label, clock and bar
  off, and a transparent writing layer with `alphaValue` 0 so no caret is drawn in the group) and
  `RoundThreeTests.restartBringsTheChromeBackWithTheNewSession`.
  `TrialReleaseTests.wipedSessionRestartSpendsAnotherButLastWipeDoesNotSellImmediately` holds the
  pill's help at both wipe kinds (begin again, then activation), and
  `RoomTests.stoppedScreenAnnouncementNamesOnlyTheReasonThatIsTrue` holds the reason branch: an
  exhausted trial says the three free sessions are used, while licence residue, a trial-access error
  or a cleanup failure only say a licence is needed. Before the change the same test
  reported 10 pt and 18 pt gaps, a 21.4% midpoint, a 44 pt link at weight 400 and a missing timer.
- Evidence: web `stopped-1440` / `stopped-390` in light and dark from the suite's own `page.screenshot`
  (inspected individually); Mac content snapshots `room-deleted-light.png` and `room-deleted-dark.png`
  from `WID_SNAPSHOT_DIR=... swift test --filter SnapshotTests`. These are real AppKit renders of the
  room, not live window captures; a real-window recording is still pending.
- Suite state: the eight-project `writeitdown` Playwright suite is green (800 tests, 77 skipped).
  `swift test` is green except `EditorFocusTests.imeMovementStaysWithinMarkedRange` and
  `EditorFocusTests.movementCommandsDenyAndKeepCaretAtEnd`, which fail identically on the unchanged
  baseline in this environment (the test host cannot activate a window, so `lastDenyAt` stays nil);
  case 53 records the same host limitation as a known issue.
- The window QA script (`apps/macos/FirstLine/scripts/qa-window.sh`), the shipped-DMG journey
  (`scripts/dmg-journey.sh`) and the VM guest journey (`scripts/vm/guest-journey.sh`) now wait for
  and assert the stopped group - `You stopped.`, `Draft deleted.`, `Begin again`, `0 words`, no
  receipt sentence and no clock - instead of the retired `DRAFT DELETED AT …` receipt.

# 2026-11-05: The kept screen offers one quiet route to the app (web, D-083)

- Scope: the browser trial's kept screen only. Nothing on the landing, the download page, the demo or the
  Mac app changed. The new control is `#kept a.kept-app`, `Mac app`, `download/?from=kept`, `_blank` plus
  `noopener`, styled by one rule in `site.css` in the room's quiet role.
- Geometry, measured on the real kept path (real Chrome, the sixty-second deadline played through, the
  suite's own clock acceleration only in the assertions): the action row is the same box before and after
  the change at both widths - 1440x900 top 241.59 / left 564.28 / 311.44x48, 390x844 top 215.98 / left
  43.28 / 303.44x48 - and the same box again with the link taken out of flow in the same page. The row
  adds 50 px (6 px gap, 44 px tap row, 13 px ink) under the pair and keeps the returned draft's line: the
  kept scroll measures 413.2 px at 1440 and 370.4 px at 390 against a 33.6-44.8 px line.
- The row yields to the draft. `status-slot.js` decides it from the layout it already measures: a sheet
  whose kept scroll would be shorter than one draft line drops the row (`data-kept-app="false"`) and keeps
  the block's rhythm and the line. Measured: 320x568 (line 33.6, scroll 33.6), 667x375 (33.6), 844x390
  (67 against a 44.8 line) and 1440x350 (44.8) all keep their line; without the rule 320x568 fell to
  23.6 px and 844x390 to 41 px, and the suite's "kept screens keep the controls and draft clear of the
  paper foot" failed. The header pill (above 767 px) or the phone exit-row `Download for Mac` still offers
  the app on those sheets.
- Web assertions: `qa/phase4.spec.mjs` "the kept screen offers one route to the app, and the writing
  screen none" (one visible link on the kept screen, none on the writing, wipe and 844x390 sheets; text,
  target and rel; the quiet role's colour equal to the caption's, 13 px, underlined, a 44 px row below the
  pair and above the caption; the pair's four edges unchanged with the link out of flow; the Tab-reached
  link wearing the shared 2 px ink ring on its square shape). The kept and phase specs that already
  govern this screen stay green: "kept screens keep the controls and draft clear of the paper foot" (seven
  sheets, the compact and the 320 px squeeze stress), "the kept screen draws the draft once", "kept
  screen: headline, quiet receipt, action row above a scrollable draft" (COPY TEXT / COPIED / TRY AGAIN
  keep one pill and RUN IT AGAIN does not move), `qa/paper.spec.mjs` "the kept screen stays on the same
  paper", `qa/typography.spec.mjs` "the kept receipt and the machine-voice labels keep the Mac's 13 px
  medium and its tracking", and `qa/mac.spec.mjs` "every shipped link resolves and every fragment exists".
- Evidence: `data/wid-kept-app-link/after/` - `kept-1440x900.png`, `kept-390x844.png`,
  `kept-link-focused-{1440x900,390x844}.png`, `kept-no-app-row-844x390.png` and the two link close-ups.
  Inspected: the row reads as a quiet editorial link under the pill pair in both widths, its underline is
  the only one on the block, the focus ring clears the pill row above it, and the caption below is
  unchanged.
- Limits: the 390 px capture is Chrome desktop with a fine pointer, not a real phone; touch was not
  exercised on hardware. On the kept screen a second route to the same page exists in the room's own
  chrome (the header pill above 767 px, the exit-row link below it); that is D-061/D-067 wayfinding, not
  this row, and it was left alone. The href is relative like every other Mac link on the page, so the
  suite's site-wide link gate can resolve it under `/writeitdown/`; an absolute `/download/` would 404
  there and only resolve on the deployed root.
- UI quality checklist (`../docs/ui-quality.md`), the rows this change touches: Q-05 pass (the link is its
  own role with its own line box, so the pair keeps one optical centre; the kept actions still sit above a
  long draft at 1440, 390 and 320x568). Q-06 pass (nothing outside the kept block moves: the exit row reads
  top 830 at 1440 and 772 at 390 before and after the session). Q-07 pass (a route, not a label: the spec's
  two words, no caption, arrow or helper). Q-08 pass (the Mac kept screen keeps its own composition; D-083
  records the difference). Q-09 pass (light and dark kept captures at both default sizes). Q-13 pass (the
  link is Tab-reachable from RUN IT AGAIN and wears the 2 px ink ring on its own shape). Q-14 pass (centred
  on the sheet axis, 6 px optical gap under the pair, no ±1 px nudge). Q-21 pass (the site's underlined-link
  treatment, tokens only, no page-local colour). Q-22 pass (the link uses the caption's `--paper-quiet`,
  which `qa/paper.spec.mjs` holds at 7:1 or better on the kept sheet in both themes). Q-24 pass (focus
  changes the ring and nothing else; the control keeps its square shape). Q-25 pass (the receipt, the silent
  corner count and the caption are untouched; the row adds no number). Q-29 pass (a new tab with
  `noopener`, so the link cannot throw the live draft away). Q-33 pass (the block still centres on the sheet
  axis). Q-36 pass (the new row, asserted by the new phase4 test).

# 2026-11-09: The Mac purchase card states its facts once and neither control resizes (web, A3)

`mac.html#buy` opened with a paragraph that gave the price, the two computers, the free updates and the
14-day refund, and the price line's note gave the same four facts again, the Activate section a third
time and the Refunds section a fourth. The paragraph is deleted with no replacement copy, the price row
is unchanged, the note's words are unchanged, its `14-day` hyphen became a non-breaking hyphen while
the meta description keeps its plain hyphen, `#buy-form button` and `#copy-license` take the width
of their widest label measured in the face the device renders (`buy.js` writes `--copy-floor`, the
floor `room.js` already gives the kept pill's copy control), and the licence key panel loses its ring,
fill and radius for one hairline above it. No checkout behaviour, price, Stripe call, key delivery,
clipboard logic or Windows sentence changed.

## Commands and results

- `npx playwright test` (writeitdown suite, 8 projects, two full runs): the second run reported
  1326 passed / 81 skipped and one failure, a 30 s test timeout in `qa/phase4.spec.mjs` "empty room
  shows only the caret..." under the eight-project load; the same test on the same project passes 3/3
  when run alone (3.5-4.6 s). The first run reported 1325 passed and two failures: the same class of
  room-timing flake in `qa/history-fade.spec.mjs` (3/3 green alone) and a race in this change's own new
  checkout test, which aborted the pending request and could read `Try again` before `Opening
  checkout...`; it now hangs the request instead, and `qa/checkout.spec.mjs` across all eight projects
  is 232 passed, including the wider-sans case. No file this change touches is loaded by the room.
- `npx playwright test qa/checkout.spec.mjs` on the pre-fix tree: the new tests fail with the
  measured numbers below (`known-broken-buy-card.txt` in `data/wid-design-a3-buy-card/`).
- `node --test buy.test.mjs session.test.mjs`: 26 passed.
- `node release-check.mjs`: STATIC CHECK PASSED.

## Measured (`data/wid-design-a3-buy-card/`)

| Surface | Measure | Before | After |
| --- | --- | --- | --- |
| `#buy-form button` at 1440 and 390 | width in idle / pending / error | 183.9 / 191.2 / 114.3 px | 192 / 192 / 192 px |
| `#copy-license` at 1440 and 390 | width in ready / copied | 167.7 / 99.8 px | 168 / 168 px |
| both controls | widest label as rendered (15 px) | `Opening checkout...` 191.2, `Copy license key` 167.7 | `min-width` measured from it: 192 and 168 px here |
| both controls, `--sans:Verdana` | width in every state | `Opening checkout...` 201.5 px would outgrow the old 200 px floor | 202 / 202 and 177 / 177 px, one width per control |
| price-row note, `14-day` | line rects at 15 widths, 320 to 1440 | 2 rects at 480, 450 (`doc-note`) and at 600, 420 (deleted paragraph) | 1 rect at every width |
| `.license-key` | border / background / radius | 1 px on all four sides, `--tag-bg`, 4 px | 1 px top only, transparent, 0 |
| `#buy` | card height at 1440 / 390 | 348.1 / 501.9 px | 277.7 / 377.2 px |
| `#buy` | height idle / error at 1440 and 390 | 277.7 / 298.5, 377.2 / 418.8 px | unchanged: the inline error still opens one line at 1440 and two at 390 |
| `#buy .doc-actions` | top edge in idle / pending / error | 484.4 at 1440, 529.5 at 390 | unchanged, so the controls never move under the pointer |
| `#buy .doc-actions` stacked at 390 and 320 | ghost / primary width | 182.2 / 183.9 px before A3, 182.2 / 192 px after the measured floor | 192 / 192 px |
| `#buy .doc-actions` side by side at 1440 | ghost / primary width | 182.2 / 183.9 px | 182.2 / 192 px, the inline composition and its hierarchy unchanged |
| whole page | horizontal overflow at 320 / 360 / 390 | 0 | 0 |

## Captures

`buy-{idle,pending,error,unavailable,ready,copied}-{1440,390}-{light,dark}.png` in
`data/wid-design-a3-buy-card/before/` and `after/`, full page at real size.

## UI quality checklist (`../docs/ui-quality.md`), the rows this change touches

Q-06 pass (the rows above: the control row's top edge and the card's top edge are identical in all three
buy states; the inline status legitimately opens its own line below the controls). Q-07 pass (one helper
paragraph removed, nothing added). Q-08 pass (the Mac app's own purchase strings are untouched; the note
keeps its exact words). Q-09 pass (every state captured in light and dark at both sizes). Q-13 pass (both
controls stay real 48 px buttons with the 2 px ink ring). Q-14 pass (price, note, buttons and key all share
the card's one content edge). Q-17 pass (no size, weight or leading changed; only the hyphen's character).
Q-19 pass (no sideways scroll at 320, 360 or 390). Q-20 pass (no copy written; the deleted paragraph was a
repeat and the 3-session fact stays in Activate and the meta description). Q-21 pass (one price string;
one shell). Q-24 pass, and this is the row the work moves forward: a control that swaps its label keeps
the width of its widest label, now asserted on the purchase surface by `qa/checkout.spec.mjs`, under
the default face and under a deliberately wider one. Q-28 pass
(the refund window no longer breaks; the key still wraps whole at 320).

## Follow-up: the stacked buy row shares one width

The independent review of this batch's captures found the one thing this pass had recorded as "not
changed" and was wrong about: on a phone the row stacks, and the measured floor left the ghost at
182.2 px under a 192 px primary, where the pre-A3 page had them 1.7 px apart. The width lock itself
created that ragged pair, so closing it is basic polish rather than a new visual choice: equal widths
now come from the primary's own measured floor, so the ghost carries no second number: `buy.js`
writes the same `--copy-floor` on the row, and the phone step in `site.css` gives `.home #buy
.doc-actions>.btn-ghost` that `min-width`. The ghost keeps its own surface (`rgb(255,255,255)` light,
the sheet fill in dark) and the 500 weight `.home .btn` gives both controls, so it still reads as the
secondary action; side by side at 1440 px it keeps its natural 182.2 px. `qa/checkout.spec.mjs` "the
stacked buy row keeps one width and stays secondary" fails on the pre-fix tree (Expected 192, Received
182.2) at 390 and 320, asserts the row is stacked there, and pins that the ghost keeps a different fill
and the same weight and family.
`after/buy-idle-390-light.png`, `after/buy-idle-390-dark.png` and `after/buy-error-390-light.png`
were re-shot; the other captures still describe the shipped layout. Two filled primaries in the ready
state, the 44 vs 48 px button heights, the duplicated `Opening checkout...` line and the 390 px error
wrapping `a moment.` stay out of scope and were recorded as pre-existing by that review.

# 2026-11-09: The download page states its terms once and holds no card inside a card (D-107)

`/download/` carried `3 free sessions`, `$4.99 once`, `2 computers` and `14 days` twice, in the four
requirement rows and again in the Activate and Refunds cards, and it nested three filled, rounded
panels inside its bordered cards: the published SHA-256, the release note and the Install card's
`shasum` command. The Refunds card is deleted, the Activate card keeps only the activation step the
requirement rows do not state, and those three blocks now open on one 1 px `--hair` rule with no fill,
radius or closed border. No copy is added. The steps row carries two cards, each at its own height, on
the same 760 px grid as the download card above it.

## Commands and results

- `cd writeitdown && npx playwright test`: exit 0, 1303 passed across the eight viewport, theme and
  motion projects (14.2 min).
- `npm run release-check -- --download`: `STATIC CHECK PASSED` and `Download page ready: the DMG link,
  the Install command and its published SHA-256 agree`. The `data-launch` slots and the SHA node are
  byte-for-byte untouched: `git diff` shows no line inside them.
- Known-broken proof for the new gates: with only `download/index.html` and `site.css` restored from
  `HEAD` and every test file kept, `npx playwright test qa/mac.spec.mjs qa/shape-text.spec.mjs -g
  "download page states the trial|copyable blocks stay hairlines|the download head breaks without an
  orphan"` fails 5 of 5 (`#refunds` count 1 against 0, nested panels 3 against 0, and the three
  hairline rows reporting radius 4 px, a `--tag-bg` fill and four borders). On the fixed tree the same
  selection passes 10 of 10 across 1440 and 390.

## Measured

- Card-in-card panels on `/download/`: 3 before, 0 after, at 1440x900 and 390x844 in both themes.
  Full-page height 1908 to 1718 px at 1440 and 2612 to 2324 px at 390.
- The hash, the release note and the install command: `background rgba(0, 0, 0, 0)`, `border-radius
  0`, `border-top 1px solid` the same `--hair` value in both themes
  (`rgba(28, 25, 23, 0.1)` light, `rgba(236, 231, 217, 0.1)` dark), and their text edges equal the
  card's content edges (373 and 1067 px at 1440, 43 and 347 px at 390, 33 and 287 px at 320).
- Text on the card, measured: the quiet role 5.77:1 light and 5.8:1 dark, the ink mono 17.49:1 light
  and 12.69:1 dark. Nothing on the page reads below 4.5:1 at 1440, 1024, 390 or 320.
- Two step cards: equal widths (372 px at 1440, 350 px at 390), one shared top edge, heights 363.9 and
  128.5 px, no document overflow at any of the four widths.

## Capture index

`/Users/ichts/firstmate-homes/wid/data/wid-design-a4-download/captures/{before,after}/`: full-page
`page-download-{1440,390}-{light,dark}.png` at deviceScaleFactor 1, plus `census.json` with the panel
list, the computed borders and backgrounds, and the page height for each capture.

## Standing UI review (emil passes over the changed page)

- emil-ui-review: ship it. One visible primary action (the ink Download pill) and one ghost buy; the two
  COPY controls keep their 36 px height and their labels. No motion was added, nothing shifts, and the
  screen has no dynamic number to stabilise.
- emil-design-foundations: pass. Token colours only (`--hair` replaces a `--tag-bg` fill), one hairline
  weight, text and rules on the card's content edges, and the 62-character release note stays on one
  line, so no reading measure is exceeded.
- emil-surfaces: pass. No nested radius is left to derive; the one border kept is separation, not
  elevation, which that skill keeps as the divider case. Its 0.5 px retina hairline advice is not
  taken: this project holds one 1 px line weight site-wide (design rulebook 14.4 e), and a page-local
  half-pixel rule would be the only one on the site.
- emil-typography: pass. Monospace stays inside `code` for the two literal machine strings, line
  heights are unitless, no orphaned word appears in the release note or the Activate sentence at 320,
  390 or 1440, and all four text roles clear 4.5:1.
- Not fixed here, both pre-existing and site-wide (bounded follow-ups, not caused by this change):
  the shared `.btn` is 36 px tall, under the 44 px touch floor, and the download page still carries six
  font sizes (13, 14, 15, 17, 20, 60), which A6 owns.

## Quality checklist rows this change touches

- Q-07 pass: three panels and one card lose their labels and their duplicate sentences; no label,
  helper line or caption is added.
- Q-09 pass: captured in light and dark at 1440x900 and 390x844, and the hairline flips with the theme
  rather than staying a light-mode colour.
- Q-14 pass: the hash, the release note and the install command start and end on their card's content
  edges to the half pixel (measured above), and the two step cards share one top edge and one width.
- Q-20 pass: the four facts appear once each, in the requirement rows; the Activate card states the
  activation step and nothing else; `$4.99 once` is still one string site-wide (`qa/shell.spec.mjs`).
- Q-21 pass: token colours only; a fill reference (`--tag-bg`) is removed, one hairline token is used.
- Q-23 pass: both copyable strings stay in the system monospace inside `code`, and
  `qa/typography.spec.mjs` passes at every project.
- Q-28 pass: the 64-character hash's two unbroken halves and the install command's argument-boundary
  break still fit and copy exactly at 1440, 1024, 390, 375 and 320 px, with no scroll container, fade
  or clipping; the new hairline takes no width from either string.
- Design rulebook 14.4 d pass: 3 card-in-card panels before, 0 after, asserted by
  `qa/mac.spec.mjs` (`nestedPanels`) and `qa/shape-text.spec.mjs`.

# 2026-11-09: The room's Chinese is one blocking face (D-108)

The captain typed Chinese in `https://writeitdown.app/#trial` and watched characters change shape after
they were already on screen. The cause was the face pipeline, not the input path: 13 GB2312 slices
declared `font-display:swap`, so any character whose slice was not resident was painted by the platform
serif and repainted in Zhuque when the slice landed. `fonts-cjk.css` now declares that face once with
`font-display:block`, `room.js` asks for it while the door opens, and the composing span still carries
no face of its own.

## Commands and results

- The specs this change touches, all eight projects: `npx playwright test qa/chinese-face.spec.mjs
  qa/typography.spec.mjs qa/door-grow.spec.mjs qa/door-instant.spec.mjs` -> 112 passed, 0 failed. The
  new file is `qa/chinese-face.spec.mjs`, four tests.
- `cd writeitdown && npm test`, the full site suite, was run twice on this box and is not the gate for
  this change (fast tier). Run one reached 1,382 passed and one failure (`qa/door-grow.spec.mjs`, a 7 px
  frame-to-frame shrink at 390 px while the box sat at load average 90; that spec then passed 48/48 in
  isolation on this branch and on its parent). Run two reached 1,371 passed and one failure
  (`qa/shell.spec.mjs`, the purchase-price test timing out at 31 s, which this change does not touch)
  when it was stopped under the fast-tier instruction.
- `python3 qa/test-install.py` -> `PASS: 51 exact production files, preserved backup, repeat
  installation, rejected symlinks.` The installed set now carries `fonts/zhuque-fangsong-gb2312.woff2`
  and no slice.
- `npm run cache-headers` -> `all 32 assertions match the policy in README.md`, including the new single
  face at `no-cache` with an ETag.
- `npm test` at the repository root -> 22 passed. The root landing links no CJK stylesheet (D-057) and
  is untouched by this change; the run is here because the writeitdown README and decision log are part
  of the same change.
- Measurement rig, outside the repository: a Chrome 157 screencast (`Page.startScreencast`, 20 fps) plus
  an injected probe recording `document.fonts` loading, `loadingdone` and per-frame ink spans, in a
  macOS 26.6 VM driving the built-in Pinyin input with synthetic hardware keys. Sources and the raw
  frames are in `data/wid-ime-font-swap/` (`cdp.mjs`, `probe.js`, `analyze.py`).

## Measured (the live site, before)

`wo jintian kaishi xiezuo`, Space commits, seven new Chinese characters. Five changed face after being
drawn; the two whose slice was already resident did not.

| character | painted | face it used | slice | slice status at paint | slice landed | repainted |
|---|---|---|---|---|---|---|
| 我 | 14.421 s | platform serif | `-08` | `loading` | 14.610 s | 14.682 s, 439 px |
| 今 | 18.103 s | platform serif | `-04` | `loading` | 18.229 s | 18.265 s, 700 px |
| 天 | 18.103 s | platform serif | `-07` | `loading` | 18.229 s | 18.265 s |
| 始 | 21.440 s | Zhuque | `-07` | `loaded` | already resident | none |
| 开 | 21.440 s | platform serif | `-05` | `loading` | 21.510 s | 21.499 s, 1,922 px + 21.549 s, 744 px |
| 作 | 24.785 s | platform serif | `-09` | `loading` | 24.847 s | 24.832 s, 2,532 px + 24.932 s, 935 px |
| 写 | 24.785 s | Zhuque | `-08` | `loaded` | already resident | none |

The lag between the keystroke that commits a character and its repaint is 60-360 ms, and a repaint is
not one frame: 开 and 作 repainted twice, 35-45 ms apart, because two slices arrived in sequence.

## Measured (after)

Same VM, same Pinyin input, same sentence, the built room served from a local origin: seven new Chinese
characters, 0 changed face, 0 font requests during the draft. The face request opens when the door
opens (167 ms after the click, 1,726 ms to a complete 2,589,548 B face on the VM's link) instead of
waiting for the first character that needs it.

`evidence/chinese-face-before-after.png` is the same character at the two moments, both builds, four
panels: 我 in the platform serif and then in Zhuque (before), 我 in Zhuque at both moments (after).

## Why one blocking file, with the numbers

| arrangement | bytes | requests | behaviour on a cold cache |
|---|---|---|---|
| 13 slices, preloaded or warmed after first paint | 2,726,540 | 13 | still wrong: a slice that lands mid-draft repaints the characters already drawn in it. Preloading all 13 defers 2.7 MB to the room's first seconds, which is the same bytes but a heavier start. |
| one slice set, `font-display:swap` | 2,589,548 | 1 | no invisible window, but a guaranteed fallback repaint on a cold cache: the reported bug, reproduced. |
| **one file, `font-display:block`, asked for at the door (taken)** | **2,589,548** | **1** | a glyph is either not drawn yet or drawn in the face the room means; on the measured link the face is resident 1.7 s after the click, before a writer can type. |

One file is also 136,992 B smaller than the 13 slices, because the table overhead is paid once.

## Known-broken proofs for the new gates

The same spec run against the sliced arrangement (`git checkout <parent> -- writeitdown`, spec copied
in) fails three of its four tests:

- `the Chinese face is one file that blocks instead of swapping`: `Expected length: 1, Received length:
  13`.
- `the room asks for the face when its door opens, before any character needs it`: `Expected: 1,
  Received: 0`, after a 5 s poll: no face is requested while the room is open and empty.
- `a drawn character is never repainted in another face`: fails at the frame taken while the face is
  held open, because the character was already drawn in the platform face.

The fourth test, `composition text carries no face of its own`, passes on both: it is a guard against a
future regression, and the composing span was never the cause.

## Captures

All in `data/wid-ime-font-swap/evidence/`, all captured in a disposable macOS 26.6 VM (`tart`), which is
deleted afterwards:

- `chrome-before/`: 800 screencast frames (40 s) of the live site with `frames.json` and `probe.json`.
- `chrome-after/`: 687 frames of the built room, same typing.
- `videos/before-slowmo.mp4`, `videos/after-slowmo.mp4`: the writing line, 2x slow motion, Chinese
  labels naming each moment, the red box marking the line while it is being repainted.
- `chinese-face-before-after.png`: the four-panel still described above.
- `safari-before.mov`, `safari-after.mov`, `safari-before-cold.mov`: Safari, same VM, same input.

## Not reproduced, and limits

- Safari on the same VM did not show the swap: with a cold cache the first committed 我 was drawn once
  in Zhuque and never repainted (frames 88, 100, 170 and 190 of `safari-before-cold.mov` are the same
  glyph, same advance). WebKit appears to hold the glyph until the face is ready rather than painting a
  fallback first, so Safari's evidence here is "no visible change after the fix", not a before/after.
- `font-display:block` has a bounded invisible window (Chrome: ~3 s). The warm request measured 167 ms
  to start and 1,726 ms to finish on the VM's link, so a writer normally never sees it; on a link slower
  than about 0.9 MB/s a character typed in the first second could stay invisible until the window ends,
  then appear in the platform face and change once when the file lands. Still one change on a slow link,
  never a change on a normal one.
- Characters outside GB2312 still fall back to the platform face. That is unchanged by this decision and
  was true of the slices too.
- The room still cannot be tested against a real iOS keyboard from this repository; the VM drives the
  built-in macOS Pinyin input, which is the input path the captain used.

## Quality checklist rows this change touches

- Q-07 pass: no label, helper line or caption is added; the room's copy is untouched.
- Q-09 pass: the face, the sheet and the room are unchanged in light and dark; the eight-project suite
  covers both.
- Q-21 pass: no token value changes; the only edit in `tokens.css` is the sentence that says how the
  Chinese face is delivered.
- Q-23 pass: `qa/typography.spec.mjs` still passes on all eight projects, including the shared advances
  from `qa/shared-type-baseline.json` (the GB2312 glyph advances are the same face, so nothing moved).
- Q-14 pass: no geometry change; the room's measure, anchor and line height are untouched.

# 2026-11-09: The room's Chinese arrives early and is never held invisible (D-109)

D-108 stopped a character changing face after it was drawn and left a worse defect in the same place: a
writer who clicks the door and types at once sees nothing while `font-display:block` waits for 2.5 MB.
`fonts-cjk.css` now declares the face `font-display:swap`; `room.js` fixes the face at each draft's first
Chinese character (Zhuque when its bytes are loaded, the platform serif when they are not) and holds that
choice until the sheet is empty again, and it prefetches the file on an idle main thread after intent on a
trial link, at low priority, so the next draft draws Zhuque. The room's own request at door-open stays as
the backstop.

## Commands and results

- `npx playwright test qa/chinese-face.spec.mjs qa/door-instant.spec.mjs qa/door-grow.spec.mjs
  qa/typography.spec.mjs` -> 136 passed, 0 failed, eight projects, and the same suite again 136/136 after
  the last edit; `qa/door-instant.spec.mjs` alone 16/16 and `qa/door-grow.spec.mjs` alone 8/8 four times
  in a row. `qa/chinese-face.spec.mjs` is now seven tests: one file with a visible-text display policy,
  the composing span still carrying no face, the door asking for the face, a character typed while the
  file is in flight painted at once and never repainted, a room that finds the file resident drawing
  Zhuque, the draft after a wipe drawing the face that has landed by then, and a bounce that fetches no
  Chinese while intent starts exactly one low-priority request. Two of them fail on `9b818ad` (the
  display policy and the painted-at-once assertion), which is the red proof for the new gate.
- One intermediate run (before the font engine's ask was held behind the door's grow) failed both
  `qa/door-instant.spec.mjs` projects while the door was compositing during a 2.5 MB font decode. The
  decode now waits for `growUntil`, and the four runs above are clean; the spec's own history of a
  frame-to-frame shrink under a loaded host is unchanged by this batch.
- `node .pi/skills/verify-writing-deadlines/verify.mjs` -> `27,000 checks, 0 failures` (the room's
  session module is unchanged by this batch).
- The full site suite was not run: fast tier, and this change touches one generated stylesheet, one
  builder, `room.js`, `tokens.css`, `site.css` and two specs.

## Measured (a disposable macOS 26.6 VM, the VM's own Chrome 157, real CDP throttling)

The built site served inside the guest; the door clicked with a real HID click; three Chinese characters
committed through the browser's IME entry point within 200 ms of the click; pixels from a
`Page.screencast` at a 17 ms median frame interval, each frame timestamped on the same wall clock as the
commit.

| | Fast 3G | Slow 4G | `9b818ad`, Fast 3G |
| --- | --- | --- | --- |
| first frame showing the character | +5 ms | +10 ms | +12 ms, then nothing |
| frames showing nothing in the 3.5 s after the commit | 0 of 210 | 0 of 177 | **59 of 209 (about 1.0 s)** |
| ink at +100 ms / +1 s / +3 s | 59 / 57 / 57 px | 59 / 57 / 57 px | 1 / 0 / 57 px |
| face the room drew | platform serif for the draft | platform serif for the draft | platform serif, then a repaint |
| second draft after the wipe | Zhuque Fangsong | Zhuque Fangsong | Zhuque Fangsong |

Page weight, cold cache: a bounce pays 514,588 B and none of the face; intent on the trial link adds
2,589,738 B as one `Low` request, starting 4.6 s (Fast 3G) and 13.9 s (Slow 4G) after first contentful
paint. FCP and LCP are unmoved by it (1,428-1,444 ms on Fast 3G with and without a hover, 4,972 ms on
Slow 4G). The door is unmoved too: click to room visible 8-21 ms, click to editor focused 7-20 ms across
five runs, with the 2.5 MB fetch already in flight in three of them. The frame-by-frame tables, the raw
CDP reports and the harness are in `data/wid-ime-block-budget/` (`README.md` first).

## Not reproduced, and limits

- The VM cannot enable the macOS Pinyin input source (`TISSelectInputSource` -50,
  `TISEnableInputSource` leaves it disabled, and the login agent drops it again). The composed sequence
  therefore comes from Chrome's own IME entry point, and one run repeats the measurement with the
  characters typed as real HID key events to show the result does not depend on that harness.
- A cold slow session writes its first draft in the platform serif. That is the stated trade: on Slow 4G
  the file lands at 65 s, long after the first draft's own silence deadline, and the draft that follows
  draws Zhuque.
- Characters outside GB2312 still fall back to the platform face, unchanged by this decision.

## Quality checklist rows this change touches

- Q-07 pass: no label, helper line or caption is added; the composer keeps its rule and the room's copy
  is untouched.
- Q-09 pass: the face, the sheet and the room are unchanged in light and dark at both widths.
- Q-21 pass: no token value changes; `tokens.css` gains one derived stack (`--serif-platform`) built from
  the same family names.
- Q-23 pass: `qa/typography.spec.mjs` passes on all eight projects, including the shared advances.
- Q-14 pass: no geometry change; the room's measure, anchor, line height and wrapped advances are
  untouched.
