# Write It Down (Mac): outside-in behaviour contract

Status: acceptance spec for PR #58, branch `fm/wid-mac-consistency`. This file is the contract the
independent audit reads against the code. A case is done only when the code implements it, the bound
test drives the real path, and the signed DMG has a real-window recording of the same behaviour.
Case numbers are stable; cite them in review. Every case must also keep the cross-surface bar in
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
| 13 | Delete/forward/setMarkedText while the IME has cleared its marked range but the composition is still live must pass through, not deny. | `PinyinInputTests.clearedMarkedRangeDeletionIsComposition` | signed-build recording |
| 14 | `setMarkedText` with `.notFound` while a composition exists replaces the current composition, not the committed draft. | `PinyinInputTests.notFoundMarkedReplacementStaysInComposition` | signed-build recording |
| 15 | Internal `replaceCharacters` during a composition is composition bookkeeping, not a denied user edit. | `PinyinInputTests.replaceCharactersDuringCompositionIsAllowed` | signed-build recording |
| 16 | A commit that targets a range inside the composing text after the marked range was cleared is a commit, not a deletion. | `PinyinInputTests.commitAfterUnmarkInsideCompositionIsAllowed` | signed-build recording |
| 17 | Pinyin candidacy under Shuangpin follows the same rules. | `PinyinInputTests.shuangpinSequenceStaysCompositionSafe` | signed-build recording |

## 2. Caret, placeholder and the writing line

| # | Case | Bound test | Recording |
| 18 | The empty room has one insertion origin: the caret sits at the centred text origin (the measure centre), the placeholder is centred on that same x and on the writing line's baseline, and the first typed character is drawn centred on that point with no jump on the first key. The caret is one fixed band whether the room is empty or has text, so it never bobs between glyphs. | `RoundThreeTests.emptyCaretAndPlaceholderShareTheInsertionOriginWithTheFirstGlyphAndComposition` | signed-build recording |
| 19 | The placeholder disappears as soon as real or marked text exists. | same test | signed-build recording |
| 32 | An IME composition is laid into the writing line: the composed run is centred in the measure, on the same baseline, and the placeholder is hidden while the input method owns it. | `RoundThreeTests.compositionRendersOnTheWritingLineAndHidesThePlaceholder` | signed-build recording |
| 33 | The written line is centred in the rendered output at every window size, not only in layout data: at 1040x720 and at a wide window the drawn ink centre equals the sheet centre. The writing column is the view width minus both text-container insets. | `EditorFocusTests.currentLineSitsAtTheSheetAnchorAndIsCentered`; `EditorFocusTests.drawnWritingLineStaysCentredInWideWindows` | signed-build recording |

## 3. Paper and window

| # | Case | Bound test | Recording |
| 20 | The paper fills the window the way the live web trial does: 32 pt margin, 16 pt radius, the sheet shadow, at 1040x720 and at a larger window. | `RoundThreeTests.sheetFillsTheWindowAndKeepsTheReadableColumn` | signed-build recording |
| 21 | Full screen keeps the same paper, margin, radius, shadow, and a centred readable column. | same geometry plus the full-screen recording | signed-build recording |
| 22 | The writing column stays a centred 62-70 character measure; the Alignment setting maps to that measure (Narrow column 62ch, Wide column 70ch), not to a fixed 720/880 paper. | `RoundThreeTests.sheetFillsTheWindowAndKeepsTheReadableColumn`; `RoundThreeTests.writingAlignmentNamesTheColumnMeasure` | signed-build recording |

## 4. Room bar

| # | Case | Bound test | Recording |
| 23 | Top bar: 2 pt, ink, pinned to the paper top, full width, full at session start and empty at session end. No label, no tooltip. | `RoundThreeTests.roomBarsFollowLiveTrialSemantics` | signed-build recording |
| 24 | The room carries no second bar: the 3 pt bottom silence meter is removed because it pulled the eye away from the writing line. The deadline is carried by the numeral and its line (case 34) instead. | same test (`bars.count == 1`) | signed-build recording |
| 25 | Reduce Motion: the remaining bar changes in steps, with no animated drain. | `RoundThreeTests.roomBarsFollowLiveTrialSemantics` (fraction is set, never animated); `RoomTests.washRecoveryFadesOnceAndWarningInterruptsImmediately`; real-window Reduce Motion recording | signed-build recording |

## 5. Status, warning and the exit row

| # | Case | Bound test | Recording |
| 34 | The warning is grouped and placed by ink, not by label frames: the numeral's ink top is 40-48 pt under the writing baseline and the caption's ink top is 16-24 pt under the numeral's ink, at 1040x720 and at a tall (1600x1000) window. The offset holds under the writing line at tall sizes instead of drifting down the sheet. | `RoundThreeTests.warningInkSitsUnderTheWritingLine` | signed-build recording |
| 35 | The wipe receipt is the result the writer must see, so `DRAFT DELETED AT … TYPE TO START AGAIN.` has its ink top 40-48 pt under the writing baseline, in the same status slot, not at the paper's bottom edge. | `RoundThreeTests.wipeReceiptSitsUnderTheWritingLine` | signed-build recording |
| 36 | A state change never moves unrelated elements: the clock's right edge, the count's right edge, the ESC - EXIT frame and the writing line baseline are unchanged from rest to typing to warning. | `RoundThreeTests.stateChangesDoNotMoveTheRoomChromeOrTheWritingAnchor` | signed-build recording |
| 37 | `Press Esc again to leave and delete the draft.` shares one baseline with `ESC - EXIT` and the word count. The sentence-case confirmation carries no caps tracking; `ESC - EXIT` keeps its caps tracking; both use the same face, size, weight and line height. The rendered first-ink rows are equal within 1 pt for all three runs. | `RoundThreeTests.exitHintSharesTheExitRowBaselineAndTypeStyle` | signed-build recording |
| 38 | The wiped state keeps the editor first responder with the caret at the insertion point, exactly as the empty room does, so `TYPE TO START AGAIN.` has a visible place to start. | `ReviewRoundTests.wipedStateKeepsTheEditorFocusedForTheNextDraft` | signed-build recording |
| 43 | The warning wash is in the rendered paper: at about 6.5 s of silence the paper pixel is tinted, not pure white, at the same phase the numeral shows. | `ReviewRoundTests.warningWashTintsTheRenderedPaper`; real-window recording pending | signed-build recording |

## 6. Exit, copy, cards

| # | Case | Bound test | Recording |
| 26 | Exit requires two acts: the first Escape or click shows `Press Esc again to leave and delete the draft.`; a second within 2 s leaves; typing cancels; after the window it re-arms. | `RoomTests.firstEscapeShowsHintAndSecondEscapeLeaves`, `exitConfirmationRequiresTwoRequestsInsideTheWindow`, `typingDismissesTheExitHint`, `exitHintExpiresAfterTheConfirmationWindow`, `clickExitAlsoNeedsConfirmation` | signed-build recording |
| 27 | COPY TEXT shows COPIED and stays COPIED until the next session. | `RoomTests.copyButtonSwitchesToCopied` (includes the next-session reset); `SnapshotTests` copied state | signed-build recording |
| 28 | With Buy hidden on the licensed Upgrade card, Start writing is centred in the card content; the pre-licence Activate+Buy group is centred as a group. | `RoundThreeTests.licensedCardCentresStartWritingAndPreLicenceGroup` | signed-build recording |
| 29 | A licensed picker does not show `License active.`; an unlicensed picker still shows its trial sessions line. | `RoundThreeTests.licensedPickerHidesAccessLineAndTrialPickerKeepsIt` | signed-build recording |
| 30 | Every button, link, segmented control, popup and checkbox in every card uses the ink focus ring in light and dark. The system accent-blue ring never appears. | `RoundThreeTests.everyCardControlUsesTheInkFocusRingInLightAndDark`; `RoomTests.keptStateFocusesCopyText` | signed-build tab-through recording |
| 31 | Buy opens the LIVE hosted checkout in the default browser. | `CheckoutClientTests.appStateOpensHostedCheckoutAndUsesFallbackOnlyOnError`, `successPostsToTheServiceAndReturnsTheHostedURL`, `checkoutAvailabilityRequiresTheServiceAndTheFallback`; `LicenseFlowTests.checkoutURLComesFromInfoPlist` | signed-build recording |
| 39 | COPY TEXT and RUN IT AGAIN share one baseline; the copy pill keeps one fixed width across COPY TEXT and COPIED, so nothing on the kept row moves. | `ReviewRoundTests.keptActionsShareOneBaselineAndCopyKeepsItsWidth`; `RoomTests.copyButtonSwitchesToCopied` | signed-build recording |
| 40 | The Settings license block is one left-aligned block with no per-line hairlines and no stray bullet; the instance id is gone, the activation dates remain. In the unlicensed state the Buy action is a real 48 pt outline control on the Activate row, and the license controls reach the card content edge with Done. | `ReviewRoundTests.settingsLicenseBlockIsOneAlignedBlockWithRealControls`; `ReviewRoundTests.licensedSettingsShowDatesWithoutImplementationDetails` | signed-build recording |
| 41 | On the activation card Activate and Buy share one 48 pt height on one row. | `ReviewRoundTests.activationActionsShareOneHeightOnOneRow`; `RoundThreeTests.licensedCardCentresStartWritingAndPreLicenceGroup` | signed-build recording |
| 42 | In the picker, the two control-group labels ("Minutes" and "Delete after silence") share one type style and one placement above their controls. | `ReviewRoundTests.pickerControlLabelsShareOneStyleAndPlacement` | signed-build recording |

## Measured changes

Numbers below are frames/baselines from the layout or from the rendered frame, in points. "Paper top"
means distance below the paper's top edge; "room top" means distance below the window content's top.
The post-review dump (`after-raw-v2`) uses the room-top convention for ink rows and prints the
paper-top equivalents; this table uses the same labels. The before ink values marked "pixel review"
come from the reviewers' measurements of the previous capture set, because the original before dump
recorded frames only.

| What | Before (`e792ac98`) | After | Bound by |
| --- | --- | --- | --- |
| Room bars at 1040x720 | 2 pt top bar + 3 pt bottom bar at y=0 | one 2 pt top bar only | case 24 |
| Warning numeral frame top from the paper top, 1040x720 / 1600x1000 | 426 / 641 | 322 / 431 | case 34 |
| Warning numeral ink top under the writing baseline | 26 (pixel review of the old captures) | 46 (band 40-48) | case 34 |
| Warning caption ink top under the numeral ink | 65 (pixel review) | 19 (band 16-24) | case 34 |
| Empty caret x, 1040x720 | 452.9 (67.1 left of centre) | 520.75 | case 18 |
| Placeholder baseline vs first glyph baseline, 1040x720 | 295 vs 310 (15 apart) | 310 vs 310 | case 18 |
| Rendered writing-line centre, 1040x720 | +7.25 | within 1 of centre | case 33 |
| Rendered writing-line centre, 1600x1000 | +249.25 | within 1 of centre | case 33 |
| Wipe receipt ink top from the paper top, 1040x720 | 554 (frame top) | 322.5 | case 35 |
| Exit confirmation baseline vs ESC - EXIT title baseline | 33.0 vs 28.4 | 28.4 vs 28.4 | case 37 |
| Exit confirmation copy and tracking | `Press Esc again to leave. The draft is deleted.` with caps tracking | `Press Esc again to leave and delete the draft.` with zero tracking | cases 26, 37 |
| Kept COPY vs RUN IT AGAIN ink-top difference | 4 (pixel review) | 0.5 | case 39 |
| Kept COPY pill width, COPY TEXT vs COPIED | 19 pt narrower on COPIED (pixel review) | 184 pt in both | case 39 |
| Deleted-state caret | none in the still set | editor first responder, caret at the insertion point | case 38 |

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
