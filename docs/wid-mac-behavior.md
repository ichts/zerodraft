# Write It Down (Mac): outside-in behaviour contract

Status: acceptance spec for PR #58, branch `fm/wid-mac-consistency`. This file is the contract the
independent audit reads against the code. A case is done only when the code implements it, the bound
test drives the real path, and the signed DMG has a real-window recording of the same behaviour.
Case numbers are stable; cite them in review.

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

## 2. Caret and placeholder

| # | Case | Bound test | Recording |
| 18 | In the empty room the caret sits at the first glyph origin and baseline of the centred placeholder; it is never drawn inside the words "Start typing." | `RoundThreeTests.emptyCaretSitsOnThePlaceholderFirstGlyphAndMarkedTextHidesIt` | signed-build recording |
| 19 | The placeholder disappears as soon as real or marked text exists. | same test | signed-build recording |

## 3. Paper and window

| # | Case | Bound test | Recording |
| 20 | The paper fills the window the way the live web trial does: 32 pt margin, 16 pt radius, the sheet shadow, at 1040x720 and at a larger window. | `RoundThreeTests.sheetFillsTheWindowAndKeepsTheReadableColumn` | signed-build recording |
| 21 | Full screen keeps the same paper, margin, radius, shadow, and a centred readable column. | same geometry plus the full-screen recording | signed-build recording |
| 22 | The writing column stays a centred 62-70 character measure; the Alignment setting maps to that measure (Narrow column 62ch, Wide column 70ch), not to a fixed 720/880 paper. | `RoundThreeTests.sheetFillsTheWindowAndKeepsTheReadableColumn`; `RoundThreeTests.writingAlignmentNamesTheColumnMeasure` | signed-build recording |

## 4. Room bars

| # | Case | Bound test | Recording |
| 23 | Top bar: 2 pt, ink, pinned to the paper top, anchored left, full at session start and empty at session end. No label. | `RoundThreeTests.roomBarsFollowLiveTrialSemantics` | signed-build recording |
| 24 | Bottom bar: 3 pt, pinned to the paper bottom; full while typing, drains as silence accumulates, ink before the warning, red from the warning on, empty exactly at the wipe. No label. | same test | signed-build recording |
| 25 | Reduce Motion: the bars change in steps on the 100 ms tick; no animated drain. | same test (no animation exists); real-window Reduce Motion recording | signed-build recording |

## 5. Exit, copy, cards

| # | Case | Bound test | Recording |
| 26 | Exit requires two acts: the first Escape or click shows `Press Esc again to leave. The draft is deleted.`; a second within 2 s leaves; typing cancels; after the window it re-arms. | `RoomTests.firstEscapeShowsHintAndSecondEscapeLeaves`, `exitConfirmationRequiresTwoRequestsInsideTheWindow`, `typingDismissesTheExitHint`, `exitHintExpiresAfterTheConfirmationWindow`, `clickExitAlsoNeedsConfirmation` | signed-build recording |
| 27 | COPY TEXT shows COPIED and stays COPIED until the next session. | `RoomTests.copyButtonSwitchesToCopied` (includes the next-session reset); `SnapshotTests` copied state | signed-build recording |
| 28 | With Buy hidden on the licensed Upgrade card, Start writing is centred in the card content; the pre-licence Activate+Buy group is centred as a group. | `RoundThreeTests.licensedCardCentresStartWritingAndPreLicenceGroup` | signed-build recording |
| 29 | A licensed picker does not show `License active.`; an unlicensed picker still shows its trial sessions line. | `RoundThreeTests.licensedPickerHidesAccessLineAndTrialPickerKeepsIt` | signed-build recording |
| 30 | Every button, link, segmented control, popup and checkbox in every card uses the ink focus ring in light and dark. The system accent-blue ring never appears. | `RoundThreeTests.everyCardControlUsesTheInkFocusRingInLightAndDark`; `RoomTests.keptStateFocusesCopyText` | signed-build tab-through recording |
| 31 | Buy opens the LIVE hosted checkout in the default browser. | `CheckoutClientTests.appStateOpensHostedCheckoutAndUsesFallbackOnlyOnError`, `successPostsToTheServiceAndReturnsTheHostedURL`, `checkoutAvailabilityRequiresTheServiceAndTheFallback`; `LicenseFlowTests.checkoutURLComesFromInfoPlist` | signed-build recording |

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
