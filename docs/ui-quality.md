# UI quality checklist

Status: standing acceptance checklist for every user-visible surface of Write It Down / Zero Draft:
the web landing and trial, the writeitdown.app site, the native Mac app, and later iOS. It turns the
captain's basic design, UI and UX expectations into rules an implementing agent applies without being
asked. It is not a taste brief; taste decisions still belong to the captain.

`design/DESIGN.md` owns the visual constitution, `docs/wid-decisions.md` owns product decisions, and
`docs/wid-mac-behavior.md` owns per-case Mac behaviour. This file owns the cross-surface quality bar.

## How to use it

- Before the first `done:` of any task that changes something a person can see or touch, capture every
  affected state at real size and record pass/fail for each rule below. The build under test must never
  be the first place a basic defect appears.
- A rule is checked only by its named measurement or its named capture. Layout, rendering and
  accessibility numbers decide; screenshots are evidence that the numbers describe what a person sees.
  A change that cannot name a check is not finished.
- A defect found by anyone - captain, reviewer, or a different model family - becomes a rule here (or
  an entry on an existing rule) and a regression assertion in the owning test suite. See D-015.
- The builder does not grade its own captures for acceptance. After the implementing agent reports
  done, a different model family reviews the captures and measurements against this file and may fail
  the build. Its review is the gate before hands-on testing.

## Rules

| ID | Rule | Decided by |
| --- | --- | --- |
| Q-01 | Chrome carries only what the writer needs. No decorative, ambient or always-moving element competes with the writing line; a bar, meter or counter that repeats information already on screen is removed, not restyled. | `RoundThreeTests.roomBarsFollowLiveTrialSemantics`: exactly one 2 pt session bar, pinned to the paper top; no second bar. Evidence: `window-light-{empty,typing,warning}`, `full-light-{empty,typing,warning}`. |
| Q-02 | Status and warning text sits where the eye already is: on the writing line's side of the paper, never on the window's lower edge, and never below the footer row. The group is placed by ink, not by label frames, so it stays together at tall sizes. | `RoundThreeTests.warningInkSitsUnderTheWritingLine` (numeral ink top 40-48 pt under the writing baseline; caption ink top 16-24 pt under the numeral ink, at 1040x720 and 1600x1000); `RoundThreeTests.wipeReceiptSitsUnderTheWritingLine` (receipt ink top 40-48 pt under the baseline). Evidence: `*-warning`, `*-deleted`. |
| Q-03 | Caret, placeholder and first typed character share one insertion origin. The placeholder never implies a different insertion point, the first character (or IME composition) is drawn at the caret, and nothing jumps on the first keystroke. | `RoundThreeTests.emptyCaretAndPlaceholderShareTheInsertionOriginWithTheFirstGlyphAndComposition`: empty caret = measure centre, placeholder centre = caret, placeholder baseline = line baseline, first glyph box centred on the caret, caret band identical before/after. `compositionRendersOnTheWritingLineAndHidesThePlaceholder`: composition line centred, same baseline, placeholder hidden. Evidence: `*-empty`, `*-first-char`, `*-typing`. |
| Q-04 | The written line is centred in the *rendered* output at every window size, and the writing column is the view width minus both insets. Measuring the layout manager alone is not enough. | `EditorFocusTests.currentLineSitsAtTheSheetAnchorAndIsCentered` (39 % anchor, centre, column width invariant) and `EditorFocusTests.drawnWritingLineStaysCentredInWideWindows` (rendered ink centre within 2 pt at 1040x720 and 1600x1000). Evidence: `window-light-*` and `full-light-*`. |
| Q-05 | One row shares one baseline; same-role text shares one type style (face, size, weight, tracking, line height). Sentence-case text does not inherit caps tracking. Equal frame centres are not enough if the line boxes differ. | `RoundThreeTests.exitHintSharesTheExitRowBaselineAndTypeStyle` (confirmation, `ESC - EXIT` and the count on one baseline within 1 pt; sentence-case confirmation has zero tracking, the caps link keeps its tracking); `ReviewRoundTests.keptActionsShareOneBaselineAndCopyKeepsItsWidth` (COPY TEXT and RUN IT AGAIN ink baselines within 1 pt). Evidence: `*-exit-hint`, `*-kept`. |
| Q-06 | Changing state never shifts unrelated elements: the clock, count, footer row and writing anchor stay fixed through rest, typing, warning, wipe and kept. | `RoundThreeTests.stateChangesDoNotMoveTheRoomChromeOrTheWritingAnchor`: element frames and the line baseline equal within 1 pt across rest/typed/warning. Evidence: all `window-light-*` states. |
| Q-07 | No extra labels, subtitles, helper sentences or status captions (D-002). The primary action and the mechanism carry the screen. | `RoundThreeTests.licensedPickerHidesAccessLineAndTrialPickerKeepsIt`; `docs/wid-mac-behavior.md` cases 27-29; review of every `*-light` capture for secondary copy. |
| Q-08 | Every surface matches in look, behaviour, copy and timing (D-001). An intended difference is written down with its reason before it ships. | Parity table in the task report plus one `docs/wid-decisions.md` entry per difference (D-005, D-014, D-016, D-017, D-019, D-020 for the current Mac room and exit row). |
| Q-09 | Light theme first. Dark is a stored choice that gets equal treatment, never an afterthought; every state is captured in both at the default window size. | `SnapshotTests.everySurfaceRendersInLightAndDark`, `SnapshotTests.keptCopyFocusRendersInLightAndDark`; evidence `window-light-*` and `window-dark-*`. |
| Q-10 | During writing nothing moves or changes except what the writer needs: the clock, count, caret and, while paused, the warning. No ambient loop, no decorative motion. | `RoundThreeTests.stateChangesDoNotMoveTheRoomChromeOrTheWritingAnchor`; `RoomTests` warn/cut/reduced-motion timings; evidence `*-typing` vs `*-warning`. |
| Q-11 | Motion answers the writer's action or marks a deadline, and honours the platform's reduced-motion setting (steps, never a tween). | `RoomTests.washRecoveryFadesOnceAndWarningInterruptsImmediately` (the 120 ms snap and the reduced-motion step), `RoomTests.cutCleanupUsesTheSameWashFade`, `RoomTests.reducedMotionDenyHasNoShake`; `RoundThreeTests.roomBarsFollowLiveTrialSemantics` (the bar sets a fraction, it is never animated); web `npm test` reduced-motion project. |
| Q-12 | Placeholders signal emptiness, never contradict the caret, and disappear as soon as real or marked text exists. | Q-03 tests; `compositionRendersOnTheWritingLineAndHidesThePlaceholder`; evidence `*-empty` and `*-first-char`. Follows the Vercel "Placeholders signal emptiness" rule. |
| Q-13 | Every visible control is interactive; there are no dead zones. Every focusable element shows the ink focus ring, never the system blue, and the focus target is not covered. A purchase action is a control, not body text. | `RoundThreeTests.everyCardControlUsesTheInkFocusRingInLightAndDark`; `RoomTests.keptStateFocusesCopyText`; `ReviewRoundTests.settingsLicenseBlockIsOneAlignedBlockWithRealControls` (Buy is an enabled 48 pt outline control on the Activate row); `docs/wid-mac-behavior.md` case 30; the tab-through recording. |
| Q-14 | Alignment is deliberate: every element aligns to a grid, a baseline, an edge or an optical centre, and a ±1 pt optical adjustment is allowed only when it is recorded. | Every geometry test above (1 pt tolerances); the capture review. Follows the Vercel "Deliberate alignment" and "Optical alignment" rules. |
| Q-15 | A new interaction detail follows the platform's own controls and at least two well-regarded products in the same class; the comparison is kept with the evidence. | `docs/wid-decisions.md` entry for the choice, plus the comparison captures or sources under the task evidence directory. Example: D-016 for the empty caret and placeholder. |
| Q-16 | Basic design/UI/UX polish is the implementing agent's job. A reviewer must never be the first to point out a caret, baseline, alignment, attention or consistency defect. The contract, the assertions and the measurement dump use one coordinate convention. | `docs/wid-decisions.md` D-015; this checklist is applied and recorded before every `done:`; the independent review gate below; the measured table in `docs/wid-mac-behavior.md` and the regenerated `after-raw-v2` dump agree on room-top and paper-top labels. |

## Evidence sets

- Web: the acceptance command is the repository-root `npm test` for the landing/trial and
  `cd writeitdown && npm test` for writeitdown.app; capture names follow the Playwright spec names.
- Mac: `swift test` from `apps/macos/FirstLine/`, with `WID_SNAPSHOT_DIR` set for PNG evidence. The
  geometry assertions are the truth; the PNGs are the record a second family reads.
- Real window: `apps/macos/FirstLine/scripts/qa-window.sh` writes per-stage screenshots, AX snapshots
  and a `geometry.jsonl` frame record. It is evidence for the shipped build, not a substitute for the
  deterministic assertions; it must run on a permitted GUI machine without taking over the user's
  screen. AX has no insertion-point frame, so caret/placeholder/first-glyph equality stays bound to
  `RoundThreeTests`.
- Every task keeps its own capture set (`window-light-*`, `window-dark-*`, `full-light-*` for the Mac
  room) and the before/after measurement table next to its report.

## Review gate

After the implementing agent's first `done:`, a different model family reads this file, the captures
and the measurement table before the build goes to hands-on testing. It may fail the build on any
rule it cannot tie to a measurement or a capture, or on any capture that contradicts a rule. A taste
question with two defensible options is escalated with a capture of each option; basic polish is not.
