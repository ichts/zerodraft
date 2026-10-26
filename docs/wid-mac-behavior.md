# Write It Down (Mac): outside-in behaviour contract

Status: acceptance spec for the Mac batches from PR #58 onward; each batch appends its own cases.
This file is the contract the independent audit reads against the code. A case is done only when the
code implements it, the bound test drives the real path, and the signed DMG has a real-window
recording of the same behaviour. Case numbers are stable; cite them in review. Every case must also
keep the cross-surface bar in
`docs/ui-quality.md`, which names the measurement each rule is decided by.

The room is the native AppKit writing surface (`SessionViewController`, `AppendOnlyTextView`). Input
methods installed on this machine: Apple Pinyin (`com.apple.inputmethod.SCIM.ITABC`, simplified and
shuangpin) and WeChat WeType (`com.tencent.inputmethod.wetype.pinyin`). 水杉输入法 is installed but is
not a contract target. Sogou is not installed on this machine. Sogou coverage is never claimed; case 11
stays blocked until it can be exercised on a machine that has it. This is a coverage fact, not a pass.

## 1. Input method composition (Pinyin)

The room must never show the deny treatment (2 px paper shake, 90 ms red hairline, live-region line)
while an input method owns the composition. Moving the caret inside the candidate window must never
move the viewport either: the paper is fixed geometry, and only a commit may re-anchor the caret.

| # | Case (user-visible) | Input path | Bound test | Recording |
| 1 | Type pinyin; marked text grows and the committed Han text appends. No paper shake, no scroll jump. | Apple Pinyin simplified: `setMarkedText` sequence then `insertText` commit | `PinyinInputTests.applePinyinTypeCommitsWithoutDenyOrScroll` | signed-build recording |
| 2 | Backspace while composing edits the candidate. No paper shake, no scroll jump, no deletion of committed text. | Apple Pinyin: `setMarkedText`, `deleteBackward` with live marked text | `PinyinInputTests.applePinyinBackspaceWhileComposingIsNotADeny` | signed-build recording |
| 3 | Space picks the highlighted candidate. No deny. | Apple Pinyin: `insertText(" ", replacementRange: markedRange)` | `PinyinInputTests.applePinyinSpaceCandidateCommitsWithoutDeny` | signed-build recording |
| 4 | A digit picks the numbered candidate. No deny. | Apple Pinyin: `insertText("1", replacementRange: markedRange)` | `PinyinInputTests.applePinyinDigitCandidateCommitsWithoutDeny` | signed-build recording |
| 5 | Escape dismisses the candidate window and leaves the committed draft unchanged. No deny. | Apple Pinyin: `unmarkText` / empty `setMarkedText` | `PinyinInputTests.applePinyinEscapeCancelsWithoutDeny` | signed-build recording |
| 6 | Type pinyin through WeChat WeType; the committed Han text appends. No paper shake, no scroll jump. | WeType: `setMarkedText` sequence then `insertText` commit | `PinyinInputTests.weTypeTypeCommitsWithoutDenyOrScroll` | signed-build recording |
| 7 | Backspace while composing under WeType edits the candidate. No shake. | WeType: `setMarkedText`, `deleteBackward` | `PinyinInputTests.weTypeBackspaceWhileComposingIsNotADeny` | signed-build recording |
| 8 | Space picks the WeType candidate. No deny. | WeType: `insertText(" ", replacementRange: markedRange)` | `PinyinInputTests.weTypeSpaceCandidateCommitsWithoutDeny` | signed-build recording |
| 9 | A digit picks the WeType candidate. No deny. | WeType: `insertText("1", replacementRange: markedRange)` | `PinyinInputTests.weTypeDigitCandidateCommitsWithoutDeny` | signed-build recording |
| 10 | Escape dismisses the WeType candidate window; the draft is unchanged. No deny. | WeType: `unmarkText` / empty `setMarkedText` | `PinyinInputTests.weTypeEscapeCancelsWithoutDeny` | signed-build recording |
| 11 | Sogou Pinyin: the same five behaviours. | Sogou not installed on this machine | BLOCKED: no bound test, no recording, no claim | none |

The two failure modes are distinct and both must stay absent: (a) `onDeny` producing the paper shake,
and (b) the scroll view's `contentView.bounds.origin` changing while the composition is live. The tests
count both. `RoomTests.inputClientCompositionNeverDenies` remains the broader NSTextInputClient table
(commit/replace/cancel/backspace/selection across CJK and emoji candidates).

| # | Case | Bound test | Recording |
| 12 | Committed text stays append-only: deleting it still fires the deny treatment. | `PinyinInputTests.committedTextDeletionStillDenies`; `RoomTests.committedText...` | signed-build recording |
| 13 | Delete/forward after the IME has cleared its marked range but before it commits is a user edit and must deny without moving the draft; a commit that belongs to the composition still passes through. | `PinyinInputTests.clearedMarkedRangeDeletionDenies` | signed-build recording |
| 14 | `setMarkedText` with `.notFound` while a composition exists replaces the current composition, not the committed draft. | `PinyinInputTests.notFoundMarkedReplacementStaysInComposition` | signed-build recording |
| 15 | Internal `replaceCharacters` during a composition is composition bookkeeping, not a denied user edit. | `PinyinInputTests.replaceCharactersDuringCompositionIsAllowed` | signed-build recording |
| 16 | A commit that targets a range inside the composing text after the marked range was cleared is a commit, not a deletion, and the engine records only the final committed text rather than the intermediate romanization. | `PinyinInputTests.commitAfterUnmarkInsideCompositionIsAllowed` | signed-build recording |
| 17 | Pinyin candidacy under Shuangpin follows the same rules. | `PinyinInputTests.shuangpinSequenceStaysCompositionSafe` | signed-build recording |

## 2. Caret and the writing line

| # | Case | Bound test | Recording |
| 18 | The empty writing line holds only the caret at the centred insertion point; there is no hint near the line. The bottom-right count slot reads `Type to start` in the count style until the first keystroke, then shows the word count. The first typed character is drawn at the caret; the line baseline does not move. A fresh start and a start after a wipe place the caret at the same point; after a wipe the red receipt carries `TYPE TO START AGAIN.`, the count shows `0 words`, and no hint is added. The caret is one fixed band whether the room is empty or has text. | `RoundThreeTests.emptyCaretAndCountPromptShareTheInsertionColumnWithTheFirstGlyph`; `ReviewRoundTests.emptyCaretAndCountPromptMatchAfterAWipe` | signed-build recording |
| 19 | The count prompt becomes the word count as soon as real or marked text exists. | same tests; `RoundThreeTests.compositionRendersOnTheWritingLineAndReplacesTheCountPrompt` | signed-build recording |
| 32 | An IME composition is laid into the writing line: the composed run is centred in the measure, on the same baseline, and the count prompt is replaced by the word count while the input method owns it. | `RoundThreeTests.compositionRendersOnTheWritingLineAndReplacesTheCountPrompt` | signed-build recording |
| 33 | The written line is centred in the rendered output at every window size, not only in layout data: at 1040x720 and at a wide window the drawn ink centre equals the sheet centre. The writing column is the view width minus both text-container insets. | `EditorFocusTests.currentLineSitsAtTheSheetAnchorAndIsCentered`; `EditorFocusTests.drawnWritingLineStaysCentredInWideWindows` | signed-build recording |

## 3. Paper and window

| # | Case | Bound test | Recording |
| 20 | The paper fills the window the way the live web trial does: 32 pt margin, 16 pt radius, the sheet shadow, at 1040x720 and at a larger window. | `RoundThreeTests.sheetFillsTheWindowAndKeepsTheReadableColumn` | signed-build recording |
| 21 | Full screen keeps the same paper, margin, radius, shadow, and a centred readable column. | same geometry plus the full-screen recording | signed-build recording |
| 22 | The writing column stays a centred 62-70 character measure; the Alignment setting maps to that measure (Narrow column 62ch, Wide column 70ch), not to a fixed 720/880 paper. | `RoundThreeTests.sheetFillsTheWindowAndKeepsTheReadableColumn`; `RoundThreeTests.writingAlignmentNamesTheColumnMeasure` | signed-build recording |

## 4. Room bar

| # | Case | Bound test | Recording |
| 23 | Top bar: 2 pt, ink, pinned to the paper top, full width, full at session start and empty at session end. No label, no tooltip. It runs as one continuous linear animation over the remaining session time, started on the first input and re-anchored only on a real state change (new session, resize, window key, Reduce Motion); ticks never step it. | `RoundThreeTests.roomBarRunsOneContinuousLinearAnimation`; `RoundThreeTests.newSessionBarRestartsFromFullAfterAWipe` (a wipe-then-restart session starts its animation from the full bar) | signed-build recording |
| 24 | The room carries no second bar: the 3 pt bottom silence meter is removed because it pulled the eye away from the writing line. The deadline is carried by the numeral and its line (case 34) instead. | `RoundThreeTests.roomBarRunsOneContinuousLinearAnimation` (`bars.count == 1`) | signed-build recording |
| 25 | Reduce Motion: the remaining bar changes in steps (0.5 s cadence), with no animated drain. | `RoundThreeTests.reducedMotionBarStepsWithoutAnimation`; `RoomTests.washRecoveryFadesOnceAndWarningInterruptsImmediately`; real-window Reduce Motion recording | signed-build recording |
| 44 | A blocked edit plays a 200 ms transform-only paper shake and a 220 ms opacity-only red-hairline flash. A repeated blocked key restarts it (interruptible); the model transform stays identity; no layout runs per frame. Reduce Motion omits the translation and keeps only the hairline flash. | `RoomTests.denyAnimationIsAShortTransformAndOpacityAnimation`; `RoomTests.reducedMotionDenyKeepsOnlyTheHairlineFlash`; `RoomTests.denyFeedbackIsInterruptible` | signed-build recording |

## 5. Status, warning and the exit row

| # | Case | Bound test | Recording |
| 34 | The warning is grouped and placed by ink, not by label frames: the numeral's ink top is 40-48 pt under the writing baseline and the caption's ink top is 16-24 pt under the numeral's ink, at 1040x720 and at a tall (1600x1000) window. The offset holds under the writing line at tall sizes instead of drifting down the sheet. | `RoundThreeTests.warningInkSitsUnderTheWritingLine` | signed-build recording |
| 35 | The wipe receipt is the result the writer must see: `DRAFT DELETED AT … TYPE TO START AGAIN.` takes the first status slot under the writing line (ink top 40-48 pt under the writing baseline), not under a hint and not at the paper's bottom edge. | `RoundThreeTests.wipeReceiptSitsUnderTheWritingLine` | signed-build recording |
| 36 | A state change never moves unrelated elements: the clock's right edge, the count's right edge, the ESC - EXIT frame and the writing line baseline are unchanged from rest to typing to warning. | `RoundThreeTests.stateChangesDoNotMoveTheRoomChromeOrTheWritingAnchor` | signed-build recording |
| 37 | `Press Esc again to leave and delete the draft.` shares one baseline with `ESC - EXIT` and the word count. The sentence-case confirmation carries no caps tracking; `ESC - EXIT` keeps its caps tracking; both use the same face, size, weight and line height. The rendered first-ink rows are equal within 1 pt for all three runs. | `RoundThreeTests.exitHintSharesTheExitRowBaselineAndTypeStyle` | signed-build recording |
| 38 | The wiped state keeps the editor first responder with the caret at the insertion point, exactly as the empty room does, so `TYPE TO START AGAIN.` has a visible place to start. | `ReviewRoundTests.wipedStateKeepsTheEditorFocusedForTheNextDraft` | signed-build recording |
| 43 | The warning wash is in the rendered paper: at about 6.5 s of silence the paper pixel is tinted, not pure white, at the same phase the numeral shows. | `ReviewRoundTests.warningWashTintsTheRenderedPaper`; real-window recording pending | signed-build recording |

## 6. Exit, copy, cards

| # | Case | Bound test | Recording |
| 26 | Exit requires two acts: the first Escape or click shows `Press Esc again to leave and delete the draft.`; a second within 2 s leaves; typing cancels; after the window it re-arms. | `RoomTests.firstEscapeShowsHintAndSecondEscapeLeaves`, `exitConfirmationRequiresTwoRequestsInsideTheWindow`, `typingDismissesTheExitHint`, `exitHintExpiresAfterTheConfirmationWindow`, `clickExitAlsoNeedsConfirmation` | signed-build recording |
| 27 | COPY TEXT shows COPIED and stays COPIED until the next session, including after a Settings round trip recreates the room. | `RoomTests.copyButtonSwitchesToCopied` (includes the next-session reset); `RoomTests.copiedStateSurvivesRoomRecreation`; `SnapshotTests` copied state | signed-build recording |
| 28 | With Buy hidden on the licensed Upgrade card, Start writing is centred in the card content; the pre-licence Activate+Buy group is centred as a group. | `RoundThreeTests.licensedCardCentresStartWritingAndPreLicenceGroup` | signed-build recording |
| 29 | A licensed picker does not show `License active.`; an unlicensed picker still shows its trial sessions line. | `RoundThreeTests.licensedPickerHidesAccessLineAndTrialPickerKeepsIt` | signed-build recording |
| 30 | Every button, link, segmented control, popup and checkbox in every card uses the ink focus ring in light and dark. The system accent-blue ring never appears. | `RoundThreeTests.everyCardControlUsesTheInkFocusRingInLightAndDark`; `RoomTests.keptStateFocusesCopyText` | signed-build tab-through recording |
| 31 | Buy opens the LIVE hosted checkout in the default browser. | `CheckoutClientTests.appStateOpensHostedCheckoutAndUsesFallbackOnlyOnError`, `successPostsToTheServiceAndReturnsTheHostedURL`, `checkoutAvailabilityRequiresTheServiceAndTheFallback`; `LicenseFlowTests.checkoutURLComesFromInfoPlist` | signed-build recording |
| 39 | The kept screen puts "You wrote it down.", one quiet small-caps receipt `5 MINUTES. 63 WORDS.` (the real session duration and count; singular `1 MINUTE. 1 WORD.`; no KEPT) and the COPY TEXT / RUN IT AGAIN controls in a fixed top block; a long draft scrolls below and never hides the actions. COPY TEXT hugs its label (24 pt padding each side; 141 pt for COPY TEXT), COPIED is narrower and the row re-centres. RUN IT AGAIN is a 48 pt quiet outlined secondary, both labels sit on the row's optical centre, and COPY TEXT focus is one light ring on the pill edge. The count rule is in the count tooltip and accessibility help. | `ReviewRoundTests.keptActionsShareOneOpticalCentreAndThePillFitsItsLabel`; `ReviewRoundTests.keptActionsStayAboveALongDraftWithTheDefaultAcknowledgement`; `RoomTests.keptReceiptMirrorsTheFailureReceipt`; `RoomTests.copyButtonSwitchesToCopied` | `captures/sixth/kept-final.png` |
| 45 | A primary ink-filled pill (Begin, Activate, COPY TEXT) shows focus as one light ring on its edge; no dark margin sits outside the ring, so it cannot read as a doubled outline. Other controls keep the outer ink ring. | `RoomTests.keptStateFocusesCopyText`; `RoundThreeTests.everyCardControlUsesTheInkFocusRingInLightAndDark` | `captures/sixth/kept-final.png` |
| 40 | The Settings license block is one left-aligned block with no per-line hairlines and no stray bullet; the instance id is gone, the activation dates remain. In the unlicensed state the Buy action is a real 48 pt outline control on the Activate row, and the license controls reach the card content edge with Done. | `ReviewRoundTests.settingsLicenseBlockIsOneAlignedBlockWithRealControls`; `ReviewRoundTests.licensedSettingsShowDatesWithoutImplementationDetails` | signed-build recording |
| 41 | On the activation card Activate and Buy share one 48 pt height on one row. | `ReviewRoundTests.activationActionsShareOneHeightOnOneRow`; `RoundThreeTests.licensedCardCentresStartWritingAndPreLicenceGroup` | signed-build recording |
| 42 | In the picker, the two control-group labels ("Minutes" and "Delete after silence") share one type style and one placement above their controls. | `ReviewRoundTests.pickerControlLabelsShareOneStyleAndPlacement` | signed-build recording |

## 7. Layout grid

| # | Case | Bound test | Recording |
| --- | --- | --- | --- |
| 46 | The active writing line sits at 35% of the paper from the top at 1040x720 and 1440x900 (both alignment settings), a little above the vertical middle (the live web trial and its landing demo now use the same 35%, D-043). The anchor is a fraction of the paper, so the same formula applies at full screen; that real-window check is pending. The warning, receipt and count follow the line at every size. | `EditorFocusTests.currentLineSitsAtTheSheetAnchorAndIsCentered` | signed-build recording; full-screen check pending |
| 47 | Chinese, English and mixed lines share one rendered line pitch: 1.6 x the font size (44.8 pt at 28 pt). CJK fallback height and leading cannot inflate a line; the kept draft uses the same fixed line height. | `EditorFocusTests.linePitchIsFixedForChineseEnglishAndMixed` | measured, `measurements/after-raw-v4.txt` |
| 48 | Each completed line carries one uniform opacity (current 100%, one up 22%, two up 7%, older 0). Adding characters on the current line does not move or change a completed line; a new line shifts the history exactly one pitch, animated 0.18 s ease-out, instant under Reduce Motion. | `EditorFocusTests.completedLineOpacityIsUniformAndStepped`; `EditorFocusTests.completedLinesDoNotMoveWhenTheCurrentLineGrows` | measured, `measurements/after-raw-v4.txt` |
| 49 | The empty room was captured as A (under-line hint), B (caret alone) and C (count slot prompt) at the 35% anchor; C is the default. | `captures/empty-state-options.png`; cases 18-19 | A/B/C capture |

## 8. Wipe, kept controls and the rules page (fourth to sixth hands-on rounds)

| # | Case | Bound test | Recording |
| --- | --- | --- | --- |
| 50 | After a wipe the screen is the kept screen's counterpart: the headline `You stopped.`, a real 48 pt outlined `Begin again` secondary focused by Return, and the red `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` receipt below the empty line. Typing still restarts; clicking the button or pressing Return starts a fresh session while the trial or license allows it, and otherwise opens activation. No alternative headline is shipped. | `RoomTests.deletedStateShowsUnusedSentenceAndCountWithoutAHint`; `RoomTests.failureRestartWorksFromReturn`; `TrialReleaseTests.exhaustedFailureRestartOpensActivation` | `captures/sixth/failure-final.png` |
| 51 | The top countdown bar is visible and shrinking in the render tree, not only in the model: the first animation starts at the full bar width, ends at zero, and the presentation is non-zero shortly after the first input. | `RoundThreeTests.roomBarRunsOneContinuousLinearAnimation` | `captures/fourth/running-bar.png` |
| 52 | The kept draft re-centres on every window resize (maximised, half, maximised) without the room's viewDidLayout; its body centre is the sheet centre within 1 pt after each change. | `ReviewRoundTests.keptDraftRecentersAfterEveryWindowResize` | `captures/fourth/kept-after-resize.png` |
| 53 | The first Pinyin key after a wipe is not swallowed: with the Apple Pinyin input source selected, a real marked composition before the wipe, the wipe, and the next key through the input context leave the first marked letter in the editor and start a fresh session. The wipe discards the input context's marked text; a stale replacement range outside the current text is ignored; an already-empty wiped room is not cleared again during the key. | `RoomTests.firstPinyinKeyAfterAWipeThroughTheInputContext`; `RoomTests.markedFirstKeyAfterAWipeKeepsTheSameRoom` | real input-context test when the host window is active; headless runs record case 53 as a known unverified issue; signed-build recording pending |
| 54 | The picker has no subtitle. A small quiet `?` control at the card's top-right is keyboard reachable and accepts the mouse, and opens a dedicated rules sheet that reuses the landing page's How it works wording and order (No way back; Eight seconds of silence; Reach zero, keep it). Done or Return dismisses it, Escape cancels it, and it renders in light and dark. | `BrandTests.rulesViewReusesTheLandingExplanationAndDismisses`; `BrandTests.rulesViewCancelOperationDismisses`; `BrandTests.startScreenAndMenusShowWriteItDown`; `ReviewRoundTests.homeRulesButtonIsMouseReachable` | `captures/sixth/picker-final.png`, `rules-light.png`, `rules-dark.png` |
| 55 | The start screen carries the merged A split-W lockup in the card's top block, above the "How long?" heading; the icon and lockup use the logo contract from `design/DESIGN.md` section 11. | `BrandTests.startScreenAndMenusShowWriteItDown` | `captures/sixth/picker-final.png` |
| 56 | A denied selection or blocked command during a live marked composition preserves the composition range; the IME's following unmark-replace commit still reaches the editor and the engine. | `PinyinInputTests.deniedCommandDuringCompositionKeepsTheCommit` | signed-build recording |
| 57 | RUN IT AGAIN on the kept screen starts a new session in the same room: the writing surface and editor focus return before the next tick, and the first keystroke lands in the draft. | `ReviewRoundTests.keptRestartEntersTheWritingRoomWithoutATick` | signed-build recording pending |
| 58 | Launch on a Mac whose stored license verifies locally (signature, product, install label, seven-day lifetime, inside the offline grace) presents the picker as the first surface. The activation card never appears, neither while the launch revalidation is still in flight nor when it cannot reach the service; the check runs silently behind the picker. Only a definitive revocation or an invalid token replaces the picker with the license card. The trial and unlicensed launch paths are unchanged. | `LicenseEntitlementTests.launchWithAStoredSignedLicensePresentsThePickerFirst` (fails on the pre-fix build: activation card first, `.upgrade`, `hasFullAccess == false`); the restart expectations in `WaffoLicenseClientTests.activationRequiredAfterTrialAndAfterRefundOrExpiry`, `LicenseEntitlementTests.activatedLicenseUnlocksHomeAndRestartsWithoutTrialBudget`, `TrialReleaseTests.corruptTrialCountPreservesOfflineSignedLicense` | launch frame captures before/after, task evidence `capture-before/`, `capture-after/` |

## 9. Updates (1.1)

The update gate follows a live writing session, not the visible surface (D-041, D-042). A case passes
only when its bound tests drive the policy and the driver hooks; the real-window recordings are listed
in `apps/macos/FirstLine/docs/RELEASE_CHECKLIST.md` (Updates) and stay pending until a signed DMG can
be exercised on the release Mac.

| # | Case | Bound test | Recording |
| 59 | No update window appears while writing may be live: the Session room in any phase, or a session still running after the writer opens Settings. A scheduled update is deferred and returned at most once after the session ends; a check or status window not yet shown is cancelled, a result is acknowledged without an alert, and a window already on screen is ended when the room opens. | `UpdatePolicyTests.noUpdateUIIsEverPresentedWhileWritingMayBeLive`, `deferredUpdateWaitsForTheRoomToClose`; `UpdateWritingSessionGateTests.theRoomSurfaceAloneHoldsTheGate`, `settingsDoesNotOpenTheGateWhileTheSessionRuns`, `theRoomCancelsACheckBeforeItsWindowAppears`, `theRoomCancelsADownloadBeforeItsStatusWindowAppears`, `theRoomAcknowledgesResultsWithoutAnAlert` | signed-build recording pending |
| 60 | Checks are opt-in: `SUEnableAutomaticChecks` is false, so no check runs until the writer turns on `Check for updates automatically` or chooses `Check for Updates…`. The toggle writes through to Sparkle, reflects a previously enabled setting, and the row is absent where no updater exists. | `UpdatePolicyTests.infoPlistKeepsChecksOffUntilTheWriterOptsIn`; `SettingsUpdateTests.automaticChecksStartOffAndTheSwitchWritesThrough`, `theSwitchReflectsAPreviouslyTurnedOnSetting`, `noUpdateSwitchWhereThereIsNoUpdater` | `settings-updates-light.png`, `settings-updates-dark.png` content snapshots |
| 61 | `Check for Updates…` sits directly under About and exists only when the app really has an updater; its enablement uses the same policy call, so it is unavailable inside a live writing session and without an updater. | `UpdateMenuTests.updateItemSitsUnderAboutWhenPresent`, `updateItemIsAbsentWithoutAnUpdater`, `checkForUpdatesIsDisabledWithoutAnUpdater`; `UpdatePolicyTests.theMenuCommandIsOnlyAvailableOutsideAWritingSession` | signed-build recording pending |
| 62 | The writing sheet is the Note paper (D-056) and the grain is texture, not decoration: the room, its failure screen and the kept sheet sit on the same paper, the paper's mean tone stays inside the locked band, and typing never regenerates the field under the writer. The ink and every role on the paper clear 7:1 against the paper, and the two faded history lines keep 9.2:1 and 7.2:1. | `PaperContrastTests.lockedTonesAreThePaperAndTheInk`, `everyTextRoleClearsSevenToOneOnTheSheet`, `thePenRedAlsoClearsSevenOnItsWarnWash`, `theFieldIsDeterministic`; `SnapshotTests.paperStaysStillWhileTyping` plus the `paperPoint` region check on every room state (`room-rest`, `room-typing`, `room-exit-hint`, `room-warning`, `room-deleted`, `room-kept`, `room-copied`, light and dark) | `room-*-{light,dark}.png` content snapshots (the `WID_SNAPSHOT_DIR` run); live-window recording pending |

## Measured changes

Numbers below are frames/baselines from the layout or from the rendered frame, in points. "Paper top"
means distance below the paper's top edge; "room top" means distance below the window content's top.
The post-review dumps (`after-raw-v2` for the review round, `after-raw-v3` for the second hands-on
round) use the room-top convention for ink rows and print the paper-top equivalents; this table uses
the same labels. The before ink values marked "pixel review"
come from the reviewers' measurements of the previous capture set, because the original before dump
recorded frames only.

| What | Before (`e792ac98`) | After | Bound by |
| --- | --- | --- | --- |
| Room bars at 1040x720 | 2 pt top bar + 3 pt bottom bar at y=0 | one 2 pt top bar only | case 24 |
| Active writing line anchor from the paper top | 39% | 35% | cases 33, 46 |
| Warning numeral ink top under the writing baseline | 26 (pixel review of the old captures) | 46 (band 40-48) | case 34 |
| Warning caption ink top under the numeral ink | 65 (pixel review) | 19 (band 16-24) | case 34 |
| Empty caret x, 1040x720 | 452.9 (67.1 left of centre) | 520.75 | case 18 |
| Empty room instruction | 28 pt italic on the writing line, caret inside it, then a `Start typing.` caption in the status slot | count slot `Type to start` in the count style until the first keystroke; no hint near the line | cases 18-19 |
| Empty caret after a wipe vs a fresh start | 512 pt away from the fresh position (old build) | 0 pt difference | case 18 |
| Rendered writing-line centre, 1040x720 | +7.25 | within 1 of centre | case 33 |
| Rendered writing-line centre, 1600x1000 | +249.25 | within 1 of centre | case 33 |
| Wipe receipt position | bottom of the paper (554 pt from the paper top) | first status slot under the line (ink top 44 pt under the baseline) | case 35 |
| Rendered line pitch, Chinese / English / mixed at 28 pt | 58.4 / 44.8 / alternating (CJK height plus leading) | 44.8 / 44.8 / 44.8 | case 47 |
| Completed-line fade and scroll | continuous gradient mask through each line; the scroll target moved while typing on one line | one uniform opacity per line (100/22/7/0); same-line typing moves nothing; a new line shifts 44.5 pt, animated 0.18 s | case 48 |
| Exit confirmation baseline vs ESC - EXIT title baseline | 33.0 vs 28.4 | 28.4 vs 28.4 | case 37 |
| Exit confirmation copy and tracking | `Press Esc again to leave. The draft is deleted.` with caps tracking | `Press Esc again to leave and delete the draft.` with zero tracking | cases 26, 37 |
| Kept COPY vs RUN IT AGAIN ink centres | 4 pt (pixel review) | within 1 pt on the row's optical centre | case 39 |
| Kept COPY pill width, COPY TEXT / COPIED | 184 pt fixed for the longest state | 141 pt for COPY TEXT (label 92.5 + 48.5 padding); COPIED narrower; row re-centres | case 39 |
| Kept restart control | 13 pt plain text link | 48 x 150 pt quiet outlined secondary, 1 pt hairline | case 39 |
| Deleted-state caret | none in the still set | editor first responder, caret at the insertion point | case 38 |
| Top session bar | fraction updated from the 100 ms tick (10 steps/s) | one continuous linear CA over the remaining time; no per-tick writes | case 23 |
| Deny feedback | two timer steps (0/0.14/0.28 s) with a static outline | 200 ms transform keyframe + 220 ms opacity flash; interruptible | case 44 |
| Kept actions / receipt | actions below a scrolling draft; `0:00 - N WORDS KEPT.` | actions in a fixed top block; `5 MINUTES. 63 WORDS.` in the small-caps receipt style | case 39 |
| Kept copy focus ring | outer ink ring + ink pill (doubled outline) | one light ring on the pill edge | case 45 |
| Failure screen | no headline or restart control; caret and red receipt only | `You stopped.`; `Begin again` (Return); red receipt below | case 50 |
| Top bar after the CA rewrite | 0 -> 0 first animation (invisible in the running window) | full -> empty; presentation non-zero and shrinking | case 51 |
| Kept draft after a resize | stayed 344-414 pt left when viewDidLayout did not run | own layout re-centres; sheet centre within 1 pt | case 52 |
| First Pinyin key after a wipe | first marked key lost with a live input context | first marked key survives; fresh session | case 53 |
| Picker | `Forward only. Nothing is saved.` subtitle | no subtitle; quiet `?` opens the landing's rules page | case 54 |
| Writing line pitch | 1.6 x font size in e792ac9 (`sessionParagraphStyle`) | 1.6 x font size, unchanged; measured 44.8 pt at 28 pt | type-metrics check |
| Kept draft CJK face | kept body used the system CJK fallback while the room used Zhuque Fangsong | both use the room's `fontWithCJKFallback` cascade; line pitch stays 1.6 | case 39 |

The caret band is now one geometry for every state: 1.5 pt wide, one font size tall, its bottom
0.12 em below the line baseline (the house `.caret` geometry). Before, the empty caret used the
placeholder's first glyph and the placeholder's own font ascender, and the typed caret changed height
per glyph.

## Method boundaries

- Tests drive the actual `AppendOnlyTextView` `NSTextInputClient` entry points (`setMarkedText`,
  `insertText`, `unmarkText`, `deleteBackward`, `doCommandBySelector`) in the order an input method
  sends them. No test re-implements the editor's guards.
- The recording is made on the notarized DMG build with the real input sources selected through
  `TISEnableInputSource`/`TISSelectInputSource`, the original enabled set restored afterwards. Keys and
  license tokens stay out of recordings, logs and source.
- A snapshot is layout evidence, not a substitute for a bound test or the real-window recording.

## Open evidence

The signed-DMG recordings are produced after the DMG is built; this file is updated with their paths in
the same change. Case 11 remains blocked and is not claimed as passed.
