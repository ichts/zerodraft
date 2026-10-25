# Write It Down: captain decision log

Status: durable, append-only record of product decisions for Write It Down / Zero Draft. Chat and PR
text are not the source of truth; this file is. An entry is never edited. A later decision adds a new
entry and names the entry it supersedes. The behaviour contract that implements these decisions is
`docs/wid-mac-behavior.md`; visual tokens remain owned by `design/DESIGN.md` (web) and
`apps/macos/FirstLine/AGENTS.md` (Mac).

## D-001: One design language across web and Mac

- Date: 2026-10-24
- Decision: The web trial and the Mac app are one product with one design language. Every user-visible
  state must be consistent across the two surfaces. A difference is allowed only when it is written
  down with its reason.
- Reason: Two surfaces that drift teach the user two products; consistency is the product promise.
- Supersedes: none.

## D-002: No unnecessary secondary labels or sub-labels

- Date: 2026-10-24
- Decision: Do not add secondary labels, explanatory sub-labels, helper sentences or status captions
  that do not carry a decision the user needs. The primary action and the mechanism carry the screen.
- Reason: Extra labels dilute the forced-output room and invite drift between web and Mac.
- Supersedes: any earlier pattern that added explanatory chrome to the writing room.

## D-003: Centered zen writing

- Date: 2026-10-24
- Decision: The current writing line is centered horizontally and anchored at the live trial's zen
  position (39% of the sheet); earlier lines move up under the live gradient fade.
- Reason: The live trial is the parity reference; the writing should feel like one room.
- Supersedes: the fixed left writing origin used by earlier Mac builds.

## D-004: The paper sheet fills the window

- Date: 2026-10-24
- Decision: Keep the sheet, but the sheet fills the window with the live web trial's small margin,
  corner radius and shadow at every window size, including full screen. The fixed 720/880 sheet is
  retired. The writing text stays a centered readable column of about 60-70 characters. The Alignment
  setting maps to that column measure (Narrow 62ch, Wide 70ch), not to a paper width.
- Reason: The captain's product call: "it can be paper, but it has to fill like the web trial."
- Supersedes: D-003's implied fixed paper geometry only where the sheet size is concerned; the
  centered zen placement remains. Also supersedes the earlier "do not change the sheet yet" hold.

## D-005: Top session bar and bottom silence bar

- Date: 2026-10-24
- Decision: The room has two thin bars on web and Mac, with no labels. The top bar is 2 px, ink,
  pinned to the paper top, anchored left, full at session start and empty at session end. The bottom
  bar is 3 px, pinned to the paper bottom, full while typing, draining as silence accumulates, ink
  until the warning window, red from the warning on, and empty exactly at the wipe. Reduce Motion gets
  stepped updates, never an animated drain.
- Reason: The writer should see session progress and the silence deadline without reading numbers.
- Supersedes: the earlier "no progress bar or silence meter" room decision.

## D-006: Exit needs two acts

- Date: 2026-10-24
- Decision: The first Escape or EXIT click shows the hint `Press Esc again to leave. The draft is
  deleted.` A second Escape or click within about 2 seconds leaves the room. Typing dismisses the
  hint; after the window the next act arms it again.
- Reason: Accident protection; the draft is unrecoverable.
- Supersedes: the live web trial's single-act immediate exit for the Mac room only.

## D-007: COPIED persists until the next session

- Date: 2026-10-24
- Decision: After COPY TEXT succeeds, the action reads COPIED and stays COPIED for the rest of the
  kept state, across refreshes. A new session resets it.
- Reason: The user needs to know the copy happened; a transient flash is not proof.
- Supersedes: transient copied feedback.

## D-008: No "License active." line

- Date: 2026-10-24
- Decision: The licensed picker does not show a `License active.` line or its leading dot. The
  unlicensed picker keeps its trial-sessions line.
- Reason: The licensed state is already visible from the controls; the line is noise (D-002).
- Supersedes: the licensed access-status line.

## D-009: No blue system focus ring

- Date: 2026-10-24
- Decision: Every button, link, segmented control, popup and checkbox in every card uses the
  design-system ink focus ring. The system accent-blue ring never appears.
- Reason: The blue halo breaks the bone/ink/red palette and looks like an unstyled control.
- Supersedes: AppKit's default focus ring on app controls.

## D-010: In-app Buy opens Stripe checkout directly

- Date: 2026-10-24
- Decision: The in-app Buy action opens the hosted Stripe checkout in the user's default browser; it
  does not route through an intermediate page or an in-app mock.
- Reason: One click from the app to the real purchase page.
- Supersedes: the earlier fallback-only Buy behavior.

## D-011: Stripe with a restricted live key

- Date: 2026-10-24
- Decision: Payments run on Stripe using a restricted live key. Waffo and Polar are retired.
- Reason: One payment provider, one contract, one reconciliation path.
- Supersedes: Waffo and Polar payment integrations and their keys.

## D-012: Pasted licence keys are trimmed

- Date: 2026-10-24
- Decision: A pasted licence key is trimmed of surrounding whitespace before activation. The key's
  internal bytes are preserved.
- Reason: Clipboard padding is common and must not turn a valid key into a failed activation.
- Supersedes: the untrimmed key path.

## D-013: Trial counter lives in local settings; reset hardening undecided

- Date: 2026-10-24
- Decision: The three-session trial counter lives in the local settings file. Hardening against a
  user resetting that file is not decided; no stronger store or server counter is implied.
- Reason: Record the current mechanism and keep the open question explicit instead of inventing a
  hidden policy.
- Supersedes: none. This entry records an open boundary.

## D-014: One session bar, no bottom silence meter

- Date: 2026-10-24
- Decision: The Mac room keeps the 2 pt top session bar and removes the 3 pt bottom silence
  meter. The silence deadline is carried by the warning numeral and its line under the writing
  line, not by a second bar. The web trial has no bottom bar either; the unmerged web branch
  `fm/wid-web-room-bars` is out of scope and would revisit this entry.
- Reason: The captain's hands-on feedback: the bottom bar pulls too much attention and is not
  needed. One bar and one warning line keep the room quieter and the eye on the draft.
- Supersedes: D-005's bottom-bar half; the top session bar in D-005 stands.

## D-015: Basic UI polish is the implementing agent's job

- Date: 2026-10-24
- Decision: Basic design, UI and UX polish is the implementing agent's responsibility, not a
  review finding to be forwarded. Every defect a person or reviewer finds becomes a rule in
  `docs/ui-quality.md` and a regression assertion in the owning suite. Every checklist rule names
  the measurement or capture that decides it. A different model family reviews the captures and
  measurements against that file after the implementing agent reports done, before hands-on
  testing.
- Reason: The captain's follow-up: these are basic points and should not need to be pointed out
  every time; a standing constraint with measured checks prevents the recurrence.
- Supersedes: none.

## D-016: The empty caret, the placeholder and the first glyph share the centred insertion origin

- Date: 2026-10-24
- Decision: In the Mac room the empty caret sits at the centred text origin, not at the first
  glyph of the placeholder. The placeholder is centred on that same x and placed on the writing
  line's baseline, so the first typed character (and an IME composition) is drawn exactly where
  the caret was, with no jump. The caret is one fixed band in every state: 1.5 pt wide, one font
  size tall, its bottom 0.12 em below the line baseline (the house `.caret` rule in
  `writeitdown/site.css`). This matches Apple's centred
  `NSTextView`/`NSTextField` (measured on macOS 15: the empty insertion point is at the line
  centre and the first glyph is centred on it) and the web trial's centred textarea (the empty
  caret is at the content centre). The caret therefore sits inside the centred placeholder words
  while the room is empty, exactly as those controls do.
- Reason: The captain's point 3: the caret was drawn at the placeholder's first glyph while the
  first typed character appeared at the centre, which looked unprofessional. The convention
  above removes the jump and keeps one product language across web and Mac.
- Supersedes: the empty-caret-at-placeholder-first-glyph placement introduced for case 18 in PR
  #58; no earlier D entry recorded it.

## D-017: Mac status text sits under the writing line, not at the paper edge

- Date: 2026-10-24
- Decision: On the Mac, the warning numeral and its line, and the wipe receipt, sit directly under
  the writing line: the numeral top is the writing anchor plus half a line plus 24 pt, and the
  receipt takes the same top. This is an intended Mac difference from the web trial, whose
  `.room-danger` band starts at 68 % of the sheet and whose wipe receipt sits 76 px above the
  paper bottom. Everything else about those strings (copy, colour, timing) stays aligned with the
  web.
- Reason: The captain's point 2: the countdown text appears too low and should move up. The same
  reason applies to the wipe receipt, which is the result the writer must read.
- Supersedes: none.

## D-018: The written line is centred in the rendered output at every window size

- Date: 2026-10-24
- Decision: The writing column is the text view's width minus both text-container insets, and the
  rendered line must be centred in the sheet at the default window and at any wide or full-screen
  size. A layout-manager-only centre check is not enough evidence: the rendered frame is checked.
- Reason: A frame reassignment reset the text container to the full view width, so the drawn line
  sat one inset to the right (7-8 pt at the default window, up to ~250 pt at a wide window) while
  the layout data looked centred. The captain's full-screen screenshots show the shifted line.
- Supersedes: none. This is a correction of the earlier column implementation, recorded because it
  changes the full-screen look and binds the regression test.

## D-019: The exit confirmation says delete the draft

- Date: 2026-10-24
- Decision: The Mac inline confirmation reads `Press Esc again to leave and delete
  the draft.` in sentence case with no caps letterspacing. `ESC - EXIT` keeps its caps tracking, and
  the two runs share the footer row and baseline; the word count shares that baseline too.
- Reason: `The draft is deleted.` read as already done while the first Escape changed nothing.
  Sentence case is not a caps label, so the caps tracking made the lowercase run look wrong.
- Supersedes: D-006's hint copy only; the two-act exit rule stands.

## D-020: The warning is grouped and placed by ink

- Date: 2026-10-24
- Decision: The warning numeral's ink top sits 44 pt under the writing baseline (assertion band
  40-48 pt), its caption's ink top 20 pt under the numeral ink (band 16-24 pt), and the wipe receipt's
  ink top 44 pt under the writing baseline. The placement is computed from the drawn glyph ink and the
  line baseline, not from the label's line-box frame, and holds at the default and tall window sizes.
- Reason: The label frame top carried about 33 pt of empty descent, so the numeral read 26 pt under the
  line and 65 pt above its own caption; a frame-based formula also drifted at tall sizes. Ink-based
  placement keeps the numeral and its line together under the writing line.
- Supersedes: D-017's geometry sentence; the under-the-writing-line placement decision stands.

## D-021: The empty room shows the caret alone; the hint is a status caption

- Date: 2026-10-24
- Decision: On an empty Mac room the writing line holds only the caret at the centred
  insertion point. `Start typing.` moves to the status slot under the line (the same slot the wipe
  receipt uses: ink top 44 pt under the writing baseline), in the caption's machine type. It disappears
  on the first keystroke; nothing on the line moves. A no-hint variant (caret alone) was captured for
  comparison but is not the default. This supersedes the caret-through-the-placeholder treatment.
- Reason: The captain rejected the caret inside `Start typing.` as ugly. Keeping the writing line empty
  and putting the instruction under it preserves the single insertion origin (the first glyph appears at
  the caret) without overlaying two texts. It also keeps the hint near the eye, with the warning and
  wipe receipt.
- Supersedes: D-016's empty-caret/placeholder placement; the shared insertion origin and the first
  glyph at the caret stand. The web trial still overlays the native caret on its centred placeholder;
  that is a separate web follow-up.

## D-022: Continuous bar motion and a short interruptible refusal

- Date: 2026-10-24
- Decision: The top session bar is one linear Core Animation over the remaining session time,
  re-anchored only on real state changes (first input, new session, resize, window key, Reduce Motion
  change). Ticks never step it. A blocked edit plays a 200 ms paper shake and a 220 ms red-hairline
  flash: transform and opacity only, display-synced, interruptible by the next blocked key, and under
  Reduce Motion the translation is omitted and only the hairline flash remains. No layout runs per
  frame. The principles followed are Emil Kowalski's *Great Animations* (fast, ease-out, purposeful,
  transform/opacity for compositing, interruptible, accessible):
  https://emilkowal.ski/ui/great-animations.
- Reason: The captain found both the progress bar and the Backspace refusal choppy. Per-tick view
  updates and a two-step timer shake were the cause; Core Animation moves both off the main thread.
- Supersedes: the per-tick bar fill and the timer-driven two-step deny shake. The web's "repeated keys
  do not restart the feedback" rule remains web-only; the Mac refusal is deliberately interruptible.

## D-023: Kept screen actions first, and the receipt names the duration

- Date: 2026-10-24
- Decision: On the Mac kept screen the heading, the receipt and the COPY TEXT / RUN IT AGAIN
  actions form a fixed block at the top; the draft scrolls below, so the actions never require
  scrolling. The receipt is `N WORDS WRITTEN DOWN IN M MINUTES.` using the session's real configured
  duration; the old `0:00 - N WORDS KEPT.` is retired on Mac. The count rule is stated in the receipt
  and count tooltips and accessibility help: each Chinese character counts as one, punctuation and
  emoji do not count (the engine already splits Han characters individually). The web kept screen keeps
  its 0:00 receipt and bottom actions; this is an intended Mac difference.
- Reason: The captain's screenshot showed a long draft hiding the copy action at the bottom and a
  meaningless `0:00`; the receipt should say what happened and for how long, and the count needs its
  CJK rule stated.
- Supersedes: the Mac kept layout with the actions below the draft and the wall-clock `0:00` receipt.

## D-024: Ink pills focus with one inner light ring (fourth round: the ring sits on the pill edge)

- Date: 2026-10-24
- Decision: A primary ink-filled pill (Begin, Activate, COPY TEXT) shows keyboard focus as a
  single 2 pt light (on-ink) ring just inside the pill. Outline, quiet and other controls keep the
  outer 2 pt ink focus ring at a 3 pt offset. No control draws both an outer and an inner ring.
- Reason: The captain's kept screenshot showed the COPIED pill with a doubled outline: the ink pill
  plus an outer ink ring separated by a light gap. The light inner ring keeps the focus visible without
  the duplicate.
- Supersedes: D-009's "one outer ink ring for every control" for ink-filled primary pills only; the
  system accent-blue ring remains forbidden everywhere.

## D-025: The active line sits at 35% of the paper

- Date: 2026-10-24
- Decision: The Mac room anchors the active writing line at 35% of the paper from the top (the web
  trial uses 39%). The status slot stays under the line, so the warning, receipt and count follow the
  line at every window size, including full screen and the empty, typing, warning and wiped states.
- Research: monitor ergonomics place the comfortable gaze below the top of the screen (the top of the
  monitor at or slightly below eye level and the screen centre 15-20 degrees below eye level; OSHA
  computer-workstations eTool, https://www.osha.gov/etools/computer-workstations/components/monitors),
  and typewriter-style writing modes keep the active line in the middle band: iA Writer's Typewriter
  option keeps "the cursor ... vertically centered in the Editor"
  (https://ia.net/writer/support/editor/focus-mode); Ulysses and Typora's Typewriter modes keep the
  active line in the middle. The live web trial anchors at `--write-anchor:39%`
  (`writeitdown/tokens.css`). The captain asked for the line higher than the vertical middle; 35% is a
  little higher than the web's 39%, in the upper comfortable gaze band.
- Reason: Ergonomics and the captain's "not in the middle" feedback; the previous 39% read as too close
  to the middle on the tested window.
- Supersedes: the 39% anchor from the live-trial parity work; the centred zen line and the status slot
  under it stand. This is an intended Mac difference from the web's 39%.

## D-026: One fixed line pitch for every script

- Date: 2026-10-24
- Decision: Writing lines use a fixed 1.6 x font-size pitch: paragraph `minimumLineHeight` and
  `maximumLineHeight` both 44.8 at 28 pt, `lineHeightMultiple` 1, font leading disabled, and one
  baseline derived from the tallest ascender plus half the spare space. The kept draft uses the same
  fixed line height. Chinese, English and mixed lines share the pitch.
- Cause: `lineHeightMultiple` scales each font's own natural line height. The Zhuque CJK fallback's
  natural height plus leading produced a 58.4 pt Chinese line next to the 44.8 pt Latin line (and its
  5.6 pt leading added to every CJK line); mixed lines alternated between the two. That is the line
  spacing the captain saw, not a paragraph-constant change.
- Comparison: the previous signed DMG 506f759f shares the same 1.6 constant and fallback, so it has
  the same inflated CJK pitch; the live web trial's `--lh-write` is a fixed 44.8 pt; the older 45 pt
  behaviour in the captain's screenshot matches the fixed pitch. The measured rendered pitches after
  the fix are 44.8 pt for Chinese, English and mixed text.
- Reason: One grid for every script, matching the web line height and the older behaviour.
- Supersedes: the per-font line-height behaviour. The measured room pitch is asserted by
  `EditorFocusTests.linePitchIsFixedForChineseEnglishAndMixed`.

## D-027: Stepped per-line history opacity and a one-pitch animated shift

- Date: 2026-10-24
- Decision: Each completed line gets one uniform opacity: the current line 100%, one line up 22%, two
  lines up 7%, older lines 0 (the live trial's intent). The continuous gradient mask is retired. A
  completed line does not move or change when characters are added on the line below; only a new line
  shifts the history, exactly one line pitch, animated over 0.18 s ease-out (instant under Reduce
  Motion).
- Reason: The gradient cut through a line's top and bottom halves, and the CJK line-height inflation
  changed the scroll target while typing on the same line, pushing completed lines up.
- Supersedes: the continuous `lineFadeMask` and the instant line jumps. The web trial keeps its own
  mask until that surface follows; this is an intended Mac refinement of the same 100/22/7 intent.

## D-028: The empty room carries the instruction in the count slot

- Date: 2026-10-24
- Decision: The empty writing line shows only the caret. The bottom-right count slot reads
  `Type to start` in the count's own style until the first keystroke, then shows the word count. After
  a wipe the red receipt carries `TYPE TO START AGAIN.`, the count shows `0 words`, and no hint is
  added near the line. Option C was chosen by the captain after A (under-line hint) and B (caret alone)
  were captured side by side.
- Reason: The captain rejected any caret-plus-"Start typing" pairing near the line; existing chrome
  carries the instruction without adding a second text near the writing.
- Supersedes: D-021's under-line hint caption. The caret-only line and the shared insertion origin
  stand.

## D-029: The wiped screen is the kept screen's counterpart

- Date: 2026-10-24
- Decision: After a wipe the room shows the calm headline `You stopped.`, a real 48 pt outlined
  `Begin again` secondary (Return triggers it, the editor stays first responder for typing), and the
  red `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` receipt below the empty line. The button starts a
  fresh session; typing still restarts. No alternative headline ships.
- Reason: The fifth round's machine-only failure state had no counterpart to "You wrote it down." and no
  pointer-friendly restart. The captain's final copy chose the calm headline and the button, and
  dropped the alternative captures.
- Supersedes: the plain caret-and-receipt failure screen; the alternative headlines. The receipt
  position and empty-caret rule from D-028 stand.

## D-030: The kept screen's final restrained feedback and controls

- Date: 2026-10-24
- Decision: The kept screen returns to the headline `You wrote it down.` and one quiet small-caps
  receipt below it: `5 MINUTES. 63 WORDS.` with the real session duration and count (singular
  `1 MINUTE. 1 WORD.`), no `KEPT`. It mirrors the failure receipt's format. COPY TEXT hugs its label
  (24 pt padding; 141 pt for the label), COPIED is narrower, RUN IT AGAIN is a 48 pt quiet outlined
  secondary, both labels sit on the row's optical centre, and the copy pill's focus ring is one light
  ring on its edge.
- Reason: The captain found the machine receipt and the fixed-width pill odd, asked for restrained
  positive feedback, then chose the small-caps duration/count line and removed `KEPT`. The receipt is
  the failure receipt's quiet counterpart.
- Supersedes: D-023's fixed-width copy pill and `N WORDS WRITTEN DOWN IN M MINUTES.` receipt; the fifth
  round's three candidate acknowledgement variants (quiet line, count-in-headline, ink settle). The
  empty room's D-028 count prompt is unchanged.

## D-031: The picker's rules live behind one quiet question mark

- Date: 2026-10-24
- Decision: The picker has no subtitle. A small quiet `?` control at the card's top-right is keyboard
  reachable and opens a dedicated rules sheet that reuses the landing page's How it works wording and
  order: No way back; Eight seconds of silence; Reach zero, keep it. Done or Return dismisses it,
  Escape cancels it, and it renders in light and dark. The start screen keeps the merged A split-W
  lockup above the "How long?" card.
- Reason: The captain said the `Forward only. Nothing is saved.` subtitle was unnecessary, and asked
  for the rules behind a question mark explained the same way as the landing. The landing's order keeps
  web and Mac saying the same thing.
- Supersedes: the picker subtitle; any separate rules copy on the picker.

## D-032: A wipe resets the input context's composition

- Date: 2026-10-24
- Decision: When a wipe clears the editor while an input method owns a marked composition, the editor
  discards the input context's marked text in addition to unmarking its storage. A stale replacement
  range outside the current text is ignored, and an already-empty wiped room is not cleared again
  while the first marked key is being delivered.
- Reason: The captain reported that the first Pinyin key after a wipe was swallowed while English
  letters were fine. The input context kept the cleared composition's marked range; the restart clear
  then interfered with the first new composition. The real input-context regression test drives the
  Apple Pinyin source through `NSTextInputContext`.
- Supersedes: the wipe's storage-only unmark. The append-only guards are unchanged.


## D-033: An unmarked composition does not license deletion

- Date: 2026-10-24
- Decision: Delete, forward-delete or replace after the IME has cleared its marked range but before it
  commits is a user edit and fires the deny treatment; a commit that belongs to the composition still
  passes through. A denied edit clears the pending range so a later replacement cannot target stale text.
- Reason: The earlier tolerance kept the unmarked range live for the rest of the view, so deleting
  visible `ni` bypassed append-only without the engine ever receiving it.
- Supersedes: case 13's post-unmark deletion tolerance. D-032's wipe context reset stands.

## D-034: A composition replacement updates the engine draft

- Date: 2026-10-24
- Decision: When an IME commits a replacement over a range the editor already committed (the
  unmark-then-replace path), the engine replaces that range in its draft; a marked commit whose range
  is not yet in the engine appends. Engine text, copy text and word count stay identical to the editor.
- Reason: The unmark step committed the romanization to the engine, then the replacement commit
  appended the final text, so a WeType-style commit kept `nihao` beside `你好` and inflated the count.
- Supersedes: the append-only commit callback for composition replacements. The append-only user guard
  stands.

## D-035: A live composition keeps its range through denied edits

- Date: 2026-10-24
- Decision: A denied selection or blocked command while marked text is live preserves the composition
  range; the next IME commit still passes. Delete/forward refresh the range after candidate edits, and
  `setMarkedText` falls back to the selection when the stored range is outside the current text. Only
  an unmarked stale range is cleared.
- Reason: Clearing the live range turned the IME's next unmark-replace commit into a denied edit, so
  the Chinese character never reached the editor or engine.
- Supersedes: D-033's blanket clear on a denied edit for the live-marked case; D-033's unmarked-stale
  rule and D-034's replacement accounting stand.

## D-036: The picker lockup sits inside the "How long?" card

- Date: 2026-10-25
- Decision: The start screen's merged A split-W lockup is the first item in the "How long?" card's
  content block, centred above the heading. No lockup sits outside the card.
- Reason: The After card layout moved the lockup into the card. Case 55 of
  `docs/wid-mac-behavior.md` and section 6 of
  `apps/macos/FirstLine/docs/WRITEITDOWN_PLAN.md` carry the accepted placement.
- Supersedes: D-031's "above the 'How long?' card" placement only; its rules-page copy, question-mark
  control and dismissal rules stand.

## D-037: The web room and the landing demo follow the shipped Mac room

- Date: 2026-10-25
- Decision: writeitdown.app's `#room` trial and its landing demo (`#demo`) carry the Mac room's
  settled behaviour, not the pre-PR-58 web variant. The active line sits at 35% of the sheet; the
  empty room shows only the caret with `Type to start` in the count slot and `0 words` after a wipe;
  the history fade is stepped per rendered line (100/22/7/gone) with a one-pitch, 180 ms ease-out
  shift on a new line; the warning numeral and `KEEP TYPING OR THE DRAFT IS DELETED.` are one group
  placed by ink 44 px under the writing baseline; the wipe receipt takes the same status slot; one
  2 pt bar runs as a single linear animation over the remaining session and there is no bottom meter;
  the wipe screen is `You stopped.` with a 48 pt outlined `Begin again` and the red receipt; the kept
  screen puts `You wrote it down.`, `1 MINUTE. N WORDS.` and COPY TEXT / RUN IT AGAIN in a fixed top
  block above a scrollable draft; exit takes two acts with an inline confirmation on the footer row;
  and a blocked edit is a 200 ms transform-only shake with a 220 ms red-hairline flash. The parity
  table for the pass lives in the task record; the Mac cases are `docs/wid-mac-behavior.md` 18-57 and
  the web assertions are `writeitdown/qa/phase4.spec.mjs`.
- Reason: D-001 says both surfaces are one product. After PR https://github.com/ichts/zerodraft/pull/58
  the Mac moved (35% anchor, `Type to start`, stepped fade, grouped warning, one bar, the stopped
  screen, the kept top block, the two-step exit) and the web room did not, so the same product showed
  two different rooms.
- Supersedes: the web-only room values that D-014, D-020, D-021, D-025 to D-030 and D-031 set for the
  trial where they differ from the list above. It does not change any Mac decision.

## D-038: The landing demo shows the result screens without their controls

- Date: 2026-10-25
- Decision: The landing demo is watch-only theatre, so its wipe stage shows the room's failure screen
  (`You stopped.` plus the red `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` receipt) but no
  `Begin again` button, and its loop rearms by itself. The trial's control is real; the demo gets no
  control that does nothing.
- Reason: Q-13 forbids dead zones, and a second button inside the hero would compete with the one
  entrance under the sheet. The copy and the result screen still match the app.
- Supersedes: none.

## D-039: The web keeps its nav row, and a phone wraps the exit confirmation

- Date: 2026-10-25
- Decision: The browser room keeps its nav row (brand, `Download for Mac`, theme toggle): dark mode
  and the app link stay reachable without leaving the writing, and the Mac has no nav row at all. On a
  phone (<=767 px) the inline exit confirmation takes its own line above `ESC - EXIT` and the count
  instead of being truncated the way the Mac truncates it. Every other block, copy string and motion
  timing follows the Mac exactly.
- Reason: The Mac can truncate because it has a window menu and no nav; a phone cannot, and a clipped
  destructive confirmation hides the part that matters. Both deviations are platform-forced and are
  the only ones in the parity pass besides the missing picker, settings and licence surfaces (the web
  trial is 60 seconds, free and unlimited, and stores nothing).
- Supersedes: none.

## D-040: The refusal is visual only on both surfaces

- Date: 2026-10-25
- Decision: A blocked edit is announced visually and to assistive technology only: the 200 ms shake
  with the 220 ms red hairline, plus the live-region line. The web's short browser tone is removed;
  the Mac has no sound for a refusal either.
- Reason: One product, one answer to a blocked key. The tone was web-only, undocumented, and forced
  nothing about the browser.
- Supersedes: none.
