# SYNC.md - Mac to Windows parity ledger

Every Mac room behaviour, token and string, and what the Windows prototype does about it. Status is one of
**done**, **different** (deliberately, with the reason) or **n/a** (not in the prototype's scope, with why).
The Mac sources are the source of truth: `apps/macos/FirstLine/Sources/FirstLine` in this repository, read at their real
paths. The ledger was written against `0c3fa26` and re-synced to `d4e4687` (PR #80, D-076) when the Windows module moved
here; rows 63 to 67 record what that Mac change did and did not carry over. Tokens and strings are generated, never typed
(run from `apps/windows/`):

```
python3 scripts/gen_tokens.py | gofmt > tokens/tokens_gen.go   # regenerate
sh scripts/check_tokens.sh                                      # drift gate: fails when stale; CI runs it on every PR
```

The drift gate fails when a Mac token changes and `tokens/tokens_gen.go` was not regenerated, when a copied Mac sentence
changed or moved (the generator exits instead of emitting), and when a shipped font differs from the Mac app's copy.
When it fails: regenerate, run `go test ./...`, then add or update the parity row here in the same PR.

Evidence names in the Reason column (`150-15-home-licensed.png`, `evidence/e2e150/...`) point at the vivobook-1 run that
proved the row. Those captures were not committed; `scripts/e2e.sh`, `scripts/capture.sh` and `scripts/ime-suite.sh`
regenerate them (see `README.md`).

`gen_tokens.py` reads `Colors.swift` (every role, light and dark, alpha included), the D-069 history ladder,
`Spacing.swift`, the anchor/exit-window/session/silence/size/measure constants, the failure and kept
composition constants, the paper generator constants (`PaperSheetView.swift`) and the verbatim room strings
(`SessionViewController.swift`, `RoomPresentation.swift`, `SessionKeptView.swift`).

| # | Mac source | Windows | Status | Reason / assertion |
|---|---|---|---|---|
| 1 | SessionEngine: first input starts the clock; deadline and wipe race as absolute deadlines; tie goes to the wipe | `session/engine.go` | done | `session/engine_test.go` (4.999/5.000/7.999/8.000, tie, blank draft at the deadline, preedit counts as activity) |
| 2 | Silence limit 5 / 8 / 12 s | home picker, `app/prefs.go` | done (slice) | picker labels generated (`tokens.SilenceLabels`); persisted in `%AppData%\WriteItDown\settings.json`; `WID_SILENCE_SECONDS` still wins for tests |
| 3 | Session durations 1/5/10/20/30 min | home picker (`tokens.DurationChoices`) | done (slice) | `TestPickersPersist`; `WID_SESSION_SECONDS` still wins for tests |
| 4 | Word count: Han characters one each, NLTokenizer for the rest | `session/words.go` | different | NLTokenizer is Apple-only. Same stated rule (CountRule string): Han one each, letter/digit runs one word, `don't` and `1,000` one word, punctuation and emoji none. Kana runs count as one word per run. `TestWordCount` |
| 5 | Warn after silence-3 s, numeral = ceil(silence - idle) | `room/room.go` step, `session.SecondsUntilDeletion` | done | `TestNumeral`; real window: warn begins 5.004 s, wipe 8.068 s after the last key (`measure.py`) |
| 6 | Wash ramp over the 3 warn seconds; colours `paperWash` / `paperWashDeep` | `room/draw.go` wash, `WashFraction` | done | `TestWashRampsOverTheThreeSecondsBeforeTheWipe`; real window: blue channel 204 -> 196 across the numerals |
| 7 | Cut: deep wash step for 200 ms, then the 120 ms linear fade; one keystroke returns the wash on the 120 ms fade | `wash()` | done | timing is in the code and the unit tests; the 200 ms/120 ms frames are not captured on hardware (pending) |
| 8 | Wipe clears the draft; an open preedit does not survive it | fresh `ime.Editor` at the wipe | done | `wipe_during_preedit` in the IME suite (a known-broken build fails it: `WID_BREAK=keepeditor`) |
| 9 | Stopped screen (D-070): one group, midpoint at the anchor, 9/24 gaps, base 32-48 from 5% of the window, headline Newsreader 500 on a 1.1 box, 15/48 note, outlined pill, clock and bar off | `stoppedGeo`, `FailureFor` | done | `TestFailureCompositionKeepsTheLockedRatios`; real window: midpoint within 3 px of 33 percent at 100% and 150%, pill height, label optical centre |
| 10 | Return, the pill, or any typing restarts in place; the first IME key starts the new session | `key()`, `gate()`, pill | done | `TestReturnRestartsTheStoppedRoom`, `wipe_restart` in the IME suite |
| 11 | Kept sheet: heading, receipt `N MINUTES. M WORDS.`, COPY TEXT / COPIED / TRY COPY AGAIN, RUN IT AGAIN, draft below, scrollable | `keptGeo`, `pills` | done | the copy pill keeps the widest label's width so the swap never moves the row (web Q-24; the Mac re-centres the row, a small improvement we took) |
| 12 | Two-act exit: first Esc / EXIT arms the inline confirmation for 2 s, second leaves, typing disarms; Esc is the IME's while composing | `requestExit`, `c.Shortcut(Esc)` | done | `TestExitNeedsTwoActsInsideTwoSeconds`, `TestEscapeWorksOnTheKeptSheetAndTheStoppedSheet`; Q-29 measurements |
| 13 | Leaving the room goes back to Home | the second Esc returns to Home, or to the activation card when nothing allows another session (`App.leaveRoom`) | done (slice) | `TestHomeAndTheThreeFreeSessions`; e2e `LEAVE surface=0` lines in `evidence/e2e150/app.log` |
| 14 | Deny feedback: 0.2 s paper shake (3, 2.5, -1), 0.22 s red hairline, announcement; reduce motion keeps only the hairline | `onDeny`, `shakeOffset`, `drawDenyOutline` | done | `TestBackspaceIsDeniedAndFlashes`; the animation curves are the Mac's keyframes with one ease-out over the whole run (CA applies it per segment) |
| 15 | Forward-only input policy (`AppendOnlyInputPolicy`): undo, redo, paste, cut, word/line deletes, movement, selection denied, preedit editable | `ime/editor.go` | done | `ime/editor_test.go` + the real-keystroke suite `scripts/ime-suite.sh` |
| 16 | Wheat paper `#e9e2ce` / `#342e24`, grain 70/100 at size 1.00, two mottle scales, fibres, flecks, locked mean | `paper/paper.go` (port of `PaperField`) | done | same PRNG and seeds; `paper_test.go` mean within 6 (light) / 10 (dark); real window mean `[233.6, 226.1, 206.0]` against `#e9e2ce` |
| 17 | The sheet is rendered once per size, never while typing; first frame carries it | `ensureSheet` (sync first render, async resize) | different | resampling is bilinear in Go where Core Graphics uses its own filter, so the field is statistically identical, not bit-identical. First render 350-390 ms on the i5; the window is visible about 80 ms before the sheet is painted (pending: hide the window until then) |
| 18 | D-073 ink spread: a hair of blur-shadow under the glyphs | not ported | different | mygo has no text shadow; DirectWrite's greyscale/ClearType AA already thickens. Revisit after the captain's eyes on it |
| 19 | History ladder (D-069): current 1, then .847 .769 light / .902 .772 dark, older lines gone, per visual line | `HistoryAlpha`, band-clipped redraws | done | `TestHistoryLadder`; real window: depth 230 -> 200 between the lines |
| 20 | Anchor 33 percent of the paper for the writing line and the stopped group (D-070) | `AnchorY` | done | the brief said 35 percent: that is the web trial's own line; D-070 moved the Mac to 33. Windows follows the Mac. Real window: ink centre 349.5 px vs 351 px at 150% |
| 21 | One-pitch history shift, 0.18 s ease-out, snaps on a jump > 2.5 pitches and under reduce motion | `drawWriting` scroll | done | |
| 22 | Typography: Newsreader (writing, headings), Zhuque Fangsong (CJK), system sans for chrome | `fonts` stack, `Segoe UI Variable` for chrome | different | the Mac's system font is SF; Segoe UI Variable is the Windows system face. Family-list fallback does the CJK cascade (the probe's per-script splitting is gone) |
| 23 | Writing size 28 pt, measure 62 ch of the writing face, line pitch 1.6 x size, one pitch for every script | `Measure`, `Font.LineHeight` | done | real window: pitch 67.0 px vs 67.2 px at 150% |
| 24 | Footer row: ESC - EXIT 13/500 +4% tracking, count 13/400 on one 1.6 box, 22 pt insets; clock 15/600 top right | `drawChrome` | done | Q-05, Q-06: baselines equal, insets within 3 px, chrome does not move between states |
| 25 | Session bar: 2 pt, ink, one continuous linear drain, off on the stopped sheet | `drawContent` | done | drawn from the clock every frame (continuous); reduced-motion stepping at 0.5 s is not implemented |
| 26 | Warning numeral (Newsreader italic, min(18% window, 170) pt) and caption placed by ink: numeral ink top 44 under the baseline, caption 20 under the numeral | `drawWarning`, `ink.go` | done | glyph bounds come from the font file; real window: 44.0 DIP |
| 27 | Pills: ink primary 48, outlined secondary, press scale .97, ink focus ring | CrychicUI `button.Pill` / `button.Outline` + `roomTheme` | different | mygo's own focus ring and its hover colour step; the Mac's inset-3 ring and 1 pt hover lift are not copied (hover lift is decorative motion, Q-10) |
| 28 | Dark appearance | `roomTheme(dark)`, `Theme.Dark` | done | follows the system; rendered in the headless tester (`TestSnapshotsDark`); not captured on the hardware (pending) |
| 29 | Reduced motion (system setting) | `Preferences().ReduceMotion` | done | wash steps at once, no shake, scroll snaps; not exercised on hardware |
| 30 | VoiceOver announcements (danger, stopped, kept, blocked, exit hint, copied) | `Context.Announce` with the Mac strings | done | UIA/Narrator output not verified (pending) |
| 31 | Settings, Home, rules screen, trial counter, licence, Buy, Sparkle updates | rows 34-62 below | see rows | split into one row per behaviour in this slice |
| 32 | Window: min 980 wide, default 1040 x 720 | 1040 x 620 default, min 760 x 480 | different | vivobook-1's screen is 1280 x 720 DIP at 150%: the Mac default would not fit |
| 33 | Draft text stays in memory only | same | done | nothing is written to disk except the optional `WID_LOG` test log |

## The product around the room (slice 2)

The generator now also reads `Info.plist` (service URL, product id, public key,
price, purchase page), `HomeViewController`, `RulesViewController`, `UpgradeViewController`, `SettingsViewController`,
`AppState` (status and trial sentences), `LicenseModels` (every activation error), `SessionEngine` (durations) and
`RoomPresentation` (the blocked-restart sentences). **Every Mac literal is searched for verbatim before it is emitted**, so a
changed Mac sentence fails `gen_tokens.py` instead of drifting. Mac wording becomes Windows wording only through the two
tables at the top of that section of the script (`WIN_SUBS`: "this Mac" -> "this PC", "2 Macs" -> "2 PCs", "2-Mac" -> "2-PC",
"On the Mac: " dropped, "Waffo order number" -> "order number"; `WIN_OVERRIDES`: the storage-failure sentence names the
Credential Manager, not "disk permissions"). A string that still says "Mac" after substitution aborts the script.

| # | Mac source | Windows | Status | Reason / assertion |
|---|---|---|---|---|
| 34 | Home: white card 560 wide, lockup, "How long?", minutes picker, silence picker, Begin, access line, "?" | `app/view.go homeView` | done | card width, centring, 48 DIP Begin, 40 DIP tracks measured on the real window: `scripts/measure_screens.py` (51 PASS at 100% and 150%) |
| 35 | Home access line: trial count for the unlicensed, hidden when licensed | `homeView`, `Manager.AccessStatusText` | done | `TestActivationFlow` ("a licensed Home shows no access line"), `150-15-home-licensed.png` |
| 36 | Settings reached from the menu bar (Cmd+,) | a quiet "Settings" link under the access line and Ctrl+, | different | Windows has no application menu bar; the link is the visible entry, the shortcut is the Windows convention |
| 37 | Rules sheet over Home (`?`, Done, Esc/Return) | `rulesView`, a full surface with the same card | different | mygo has no sheet presentation; same copy (generated), same dismissal keys |
| 38 | Trial: 3 free sessions; the first nonempty input spends one before it is accepted; empty room, blocked input, wipe, exit and quit spend or return nothing; the last trial completes and copies | `Manager.ChargeTrial` through `room.Config.Admit` | done | `TestTrialLikeTheMac`, `TestHomeAndTheThreeFreeSessions`; real window: `ADMIT ... trialLeft=2/1/0` in `evidence/e2e150/app.log` |
| 39 | After exhaustion, restarting or leaving opens the activation card; a wipe itself never routes to checkout | `Config.Restartable/Blocked`, `App.leaveRoom` | done | e2e `150-06-room-stopped-3.png` (still the stopped sheet) then `150-09-upgrade-exhausted.png` after Return |
| 40 | The stopped sheet names the real reason a restart is blocked | `room.Obstacle`, `StrAnnounce...` (generated) | done | announcement only; the Mac also sets the pill's accessibility help, mygo has no per-control help text |
| 41 | Unreadable or malformed trial counter exhausts only the trial, with a visible error; a licence record is never a trial | `ParseState`, `NewManager` | done | `TestTrialLikeTheMac`, `TestLicenceResidueNeverFallsBackToTrial` |
| 42 | Trial counter location: `settings.json` in Application Support (resettable by deleting it) | a Credential Manager entry (`TrefoilStudio.WriteItDown/state`) | different | one durable place for the counter and the licence, which survives an MSIX uninstall (AppData is removed with the package). Still not a tamper-proof boundary, as on the Mac |
| 43 | Activation card: title, subtitle, field with `WID-XXXX-XXXX`, Activate (Activating), Buy a license $4.99 once, "One payment. 2 Macs. 14-day refund.", web trial link | `upgradeView` | done | PC wording through `WIN_SUBS`; field 464 x 44 DIP, Activate/Buy pair centred: `measure_screens.py` |
| 44 | Licensed card: "This Mac is licensed." and Start writing | `upgradeView` (licensed branch) | done | `150-14-upgrade-licensed.png` |
| 45 | Field input trimmed of leading/trailing ASCII space, tab, CR, LF only; empty is refused before any request | `licence.TrimKey`, `Manager.Activate` | done | `TestActivateWireContractAndAccess`, `TestActivationErrorStates` (0 requests for an empty key) |
| 46 | Wire contract: POST JSON `activate {orderId, installLabel, platform}`, `validate {token}`, `deactivate {token}`; no Authorization header; redirects refused | `licence/client.go` | done | request shape asserted in `TestActivateWireContractAndAccess`; against the real service `TestRealServiceTestMode` and the e2e |
| 47 | `platform: "macos"` | `platform: "windows"` | different (required) | the service accepts exactly `macos` and `windows` (`service.go:252`); nothing in the service changes |
| 48 | Token: base64url(JSON).base64url(sig), Ed25519 over the encoded payload text, pinned public key, product, installLabel, <=60 s ahead, exactly 7 days, not expired | `licence/token.go` | done | `TestTokenContract` |
| 49 | Activation errors and their sentences: invalid (403/404), the 2-Mac limit (409 "device limit reached" only), network (429/5xx/transport), empty, storage, not configured, wrong product, invalid token, cleanup | `licence/errors.go`, `client.go` | done | sentences generated from `LicenseModels.swift`; every state hit in `TestActivationErrorStates`; limit and invalid-key against the real service in the e2e (`150-13-upgrade-limit.png`) |
| 50 | The "Waffo order number" sentence for an empty key | "Enter your order number or activation code." | different | the Mac copy still names Waffo, retired by D-011; flagged to the captain, not carried over |
| 51 | Two installations per licence | enforced by the service; the client shows its 409 | done | real service: third PC refused, a slot released, the same entry then succeeds (`TestRealServiceTestMode`, e2e 13 and 14) |
| 52 | Offline grace: 7 days from the last validation, never extended by the network; 429/5xx/transport keep access; only 403 revokes | `Manager.withinGrace`, `validate` | done | `TestOfflineGraceNeverExtendsTheSevenDays` (boundary at 7 days), `TestRenewalReplacesTheToken` |
| 53 | Revoked or refunded licence: next validation revokes, status text, no fallback to free sessions, survives relaunch | `Manager.validate` | done | `TestRevocationLikeTheMac`; real window: refund webhook, relaunch, `150-20-upgrade-revoked.png` ("License revoked...") |
| 54 | Launch revalidation runs behind the screen; stored valid access opens Home at once | `App.Start`, `afterValidation` | done | `TestRefundedLicenceIsEnforcedAtLaunch`; `VALIDATED surface=0 full=true` then `surface=3 ... revoked` in the e2e log |
| 55 | Renewal replaces the token only after signature, product, install and activation checks; stale results are dropped (activation/validation revision counters) | `Manager.validate` | done | revision counters ported; exercised by the unit tests, not by a concurrent real-window race |
| 56 | Activation persistence failure restores the previous state and releases only the new allocation | `Manager.Activate`, `rejectActivation` | done | `TestStorageFailureReleasesTheNewAllocation` |
| 57 | In-app Buy: POST `/api/v1/checkout` (Accept json, no body, no cookies, redirects refused), only an https `checkout.stripe.com` URL is opened, anything else opens the public page | `licence/checkout.go` | done | `TestCheckoutContract`; real service in e2e; real Edge opened the hosted URL (`150-11a-browser-checkout.png`) and, with Stripe down, the public page (`150-21-browser-fallback-page.png`) |
| 58 | The fallback page is `mac.html` | the same URL (generated from `WIDCheckoutURL`) | different, open decision | a Windows buyer lands on a page titled "Write It Down for Mac". The wording and a Windows page are a captain decision |
| 59 | Install id: random UUID in `install-id.json` | random UUID in a Credential Manager entry | different | the licence token is bound to it; keeping both in the vault means a reinstall keeps its slot |
| 60 | Licence token, order number and status in `settings.json` (plain file) | Credential Manager only | different (stricter) | brief: never plain files. `mygo.Secrets` = Windows Credential Manager, encrypted for the user; the entry is 0.6 KB of the 2.5 KB limit |
| 61 | Settings: licence status, activated and validated dates, entry, About | `settingsView` | done (subset) | appearance, motion, focus, alignment, font size and updates are n/a in this slice |
| 62 | Deactivate this Mac / deep link / Sparkle updates | - | n/a | the Mac app has none of the first two in the UI (Mac `deactivate` is only used to undo a failed save); updates: Store updates for the MSIX, `mygo.Updater` for a direct build is a later decision |
| 63 | D-076 item 1: kept block spans the sheet's inner width, so its centre is the paper's centre | `keptGeo` | to verify | the Windows kept sheet was measured against the paper axis in row 11; not re-measured against D-076's 1040x720 and 1600x1000 cases. Re-run `scripts/capture.sh` before claiming parity |
| 64 | D-076 item 3: no Buy when checkout is unavailable; Buy disabled and "Checking your key..." while a key check runs | `upgradeView` | open | the Windows card still shows Buy disabled when checkout is unavailable and has no "Checking your key..." line. Not ported in the move; one bounded follow-up |
| 65 | D-076 item 3: the free route is a 48 pt outlined button "Try the free web room" | `upgradeView` | different (copy only) | the sentence is generated from the Mac; the control is still the prior link-shaped one. Follow-up with row 64 |
| 66 | D-076 item 4: Settings on one grid, switches named once | `settingsView` | n/a | the Windows Settings holds the licence only (row 61); no boolean rows to align |
| 67 | D-076 items 5 and 6: rules sheet on the 15 pt scale over a 60-character measure; picker line "Free trial: N of 3 sessions left, counted at the first character." and card subtitle "A license is required to keep writing on this PC." | `rulesView`, `homeView`, `upgradeView` | done (copy), open (rules type scale) | the sentences are generated and asserted through `tokens.TrialLeftFormat`; the rules sheet sizes were not re-measured. The longer trial line was not re-measured on the card either |

Regression assertions added for defects found while building this slice: `TestHomeAndTheThreeFreeSessions` (a repeated room
session id charged only once: the app now salts it per room), `TestActivationFlow` (stale layout after external state change),
the `measure_screens.py` rules (Begin/Activate heights, track heights, centring, field width).
