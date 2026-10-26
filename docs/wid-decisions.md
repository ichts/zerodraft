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

## D-037: A stored license opens the picker; revalidation never holds access

- Date: 2026-10-25
- Decision: Entitlement at launch is decided by the stored token alone: an active status, a present
  order key and install id, the configured product, and a token whose signature, product, install
  label and seven-day lifetime verify locally, with the last validation inside the seven-day offline
  grace. The online revalidation runs in the background and may not withhold access; only a definitive
  revocation (service refusal) or an invalid/renewed token marks the license revoked or invalid, and
  only then does the picker yield to the license card. Trial and unlicensed launch paths are unchanged.
- Reason: The captain reported that every launch of the shipped app showed the license card first and
  only then said the Mac was already active. `hasFullAccess` included "no validation in flight", so
  the launch window presented the activation card until the network round trip finished.
  Case 58 of `docs/wid-mac-behavior.md` carries the behaviour; the binding test opens a Mac with a
  stored signed fixture license and asserts the picker is the first presented surface.
- Supersedes: the "cached key is blocked until validation" launch behaviour; it stands only as the
  local-verification requirement, not as a network hold.

## D-038: The web header opens with the A mark chip

- Date: 2026-10-25
- Decision: The writeitdown.app header and footer lockup is the A mark as a chip (the app icon's squircle plate
  with the split W painted on it) followed by the wordmark on the same baseline. Two aligned alpha masks share
  one viewBox: `writeitdown/logo/write-it-down-lockup.svg` supplies the W and wordmark in `currentColor`;
  `writeitdown/logo/write-it-down-lockup-plate.svg` supplies the plate in the existing paper-surface token
  (`--sheet`, falling back to `--paper`). Light appearance has a paper plate with ink W; dark has an ink plate
  with bone W. The Mac start screen and the social card keep the wordmark-only lockup. The mobile header trades
  gap for it (12 px between the brand and the page action, 6 px inside the action group) so the theme button
  stays on the 390 px right gutter.
- Reason: The captain read the live header as plain words: the shipped lockup was the wordmark alone and its
  split W is invisible at 21 px, so the product had no logo in the corner. A mark set beside the wordmark as a
  bare letter reads as a repeated W; the paper-surface plate makes the small mark an object against the wall. Details are
  in `design/DESIGN.md` section 11.6.
- Supersedes: section 11.1/11.4 of the split-W logo decision shipped in
  https://github.com/ichts/zerodraft/pull/59, which made the wordmark the whole lockup and forbade setting the
  mark beside it. The favicon set, the app icon, the volume icon, the Mac start screen, the og card, the palette
  and the "no red in the logo" rule stand.

## D-039: The narrow-phone header steps the lockup to 16 px type

- Date: 2026-10-25
- Decision: At 380 px wide and below the writeitdown.app header lockup is 16 px type (the chip is 16.7 px)
  instead of 19 px, on every page that uses `.brand`: the landing, the trial room, `/download/` and `mac.html`.
  It is one rule, so those pages never diverge. Nothing changes above 380 px: 19 px up to 820 px, 21 px above.
- Reason: `/download/` carries the widest header (the brand, `Try it in your browser` and the theme button), and
  the chip widened the lockup by 1.384 em, so at 360 px a 19 px lockup pushed the theme button 12.3 px past the
  right edge and the page scrolled 15 px sideways. The mark and every control stay; only the lockup size gives.
  17 px still leaves 2.6 px of the 20 px page gutter at 360 px, so 16 px is the largest whole-pixel step that
  clears the 6 px bar: 10.0 px of gutter at 360, 17.6 at 375, 20 at 390. The chip carries the small-size notch
  widening (DESIGN 11.6), so the split still reads as a plate with a W at 16.7 px on a 3x phone render.
- Supersedes: D-038's mobile gap trade ("the mobile header trades gap for it ... so the theme button stays on the
  390 px right gutter") only, in that the 12 px/6 px gap trade now stops at 380 px and the lockup itself steps
  down below it. The chip, the single mask file, the palette and the rest of D-038 stand.

### Correction to D-039: mask layers and mobile gaps

- Date: 2026-10-25
- Decision: D-039 changes only the lockup size at 380 px and below. The mobile gaps remain in effect there;
  the implementation uses two aligned masks, as defined in `design/DESIGN.md` section 11.6.
- Reason: D-039's closing sentence retained the earlier single-mask description and incorrectly said the mobile
  gap trade stopped at 380 px. Neither describes the shipped CSS.
- Supersedes: D-039's "single mask file" and "12 px/6 px gap trade now stops at 380 px" wording only.

### Correction to D-039: narrow-phone spacing across system fonts

- Date: 2026-10-25
- Decision: At 380 px and below, keep the 16 px lockup and use the existing 8 px spacing token between the
  brand and action group. The internal action gap stays 6 px. All shared headers use the same rule.
- Reason: Linux system-font metrics made the download action wider than on macOS, leaving only 3.125 px of
  right gutter at 360 px in CI. The 8 px gap restores the 6 px minimum without shrinking the mark or changing
  the action. Browser acceptance covers native metrics and a 164 px action width on both platforms.
- Supersedes: The earlier D-039 correction's claim that the 12 px mobile header gap remains at 380 px and below.
  The 16 px lockup, two mask layers, theme polarity and 6 px action-group gap stand.

### Correction to D-038: one plate token for every page

- Date: 2026-10-25
- Decision: The chip plate is the single `--brand-plate` token, one value per theme, owned with the other root
  colour roles in `writeitdown/tokens.css` (`#ffffff` light, `#26231c` dark). `.brand` consumes the token
  directly; the `var(--sheet, var(--paper))` fallback chain is gone, so the landing, the trial room,
  `/download/` and `mac.html` paint one plate.
- Reason: The fallback resolved `--sheet` on the landing and `/download/` but fell through to `--paper` on
  `mac.html`, whose page colour is `#f7f4ea` light and `#211f18` dark. The same lockup was a chip on two pages
  and a bare mark on the third, which the "one rule for every page" contract forbids.
  `writeitdown/qa/mac.spec.mjs` "the header chip paints one plate colour on every page" failed on the
  `mac.html` plate before the token and passes after it.
- Supersedes: D-038's "`--sheet`, falling back to `--paper`" plate source only. The chip drawing, the two aligned
  masks, the light-plate/ink-W and dark-plate/bone-W polarity, the responsive sizes and D-039 stand.

### Correction to D-038: the plate carries the header hairline

- Date: 2026-10-25
- Decision: The header chip keeps the paper plate `#ffffff` with the ink W in light and the ink plate `#26231c`
  with the bone W in dark, and `.brand::before` adds the existing `--hair-2` hairline as a 1 px border on the
  chip square, with a corner radius matching the squircle. It is the same boundary `.theme-btn` draws, with no
  new token, shadow, or second colour, and it is one shared rule in `writeitdown/site.css`, so the landing, the
  trial room, `/download/` and `mac.html` agree.
- Reason: The paper plate `#ffffff` against the `#f7f7f5` page wall is 1.07:1, so in the default light theme the
  chip collapsed into a bare split W beside the wordmark's own W - the repeated-letter reading D-038 exists to
  prevent. A hairline is the boundary the header controls already use, and it makes the 21 px chip an object
  without inventing a surface treatment. `writeitdown/qa/mac.spec.mjs` "the header chip paints one plate colour
  on every page" now reads the rendered plate border and requires the 1 px solid `--hair-2` edge to equal the
  theme button's boundary on every page.
- Supersedes: D-038's reason and DESIGN 11.6 "Each plate sits one step off its wall" claim, in that the paper
  plate alone does not separate from the wall and the edge does. The plate-token correction above, the chip
  drawing, the two aligned masks, the theme polarity, the responsive sizes and D-039 stand.

### Correction to D-039: the header holds its gutter at every width

- Date: 2026-10-25
- Decision: The 16 px narrow-phone lockup covers 390 px and below, the 19 px step runs from 391 to 820 px, and
  above 820 px keeps 21 px. Below 360 px the widest header cannot hold one row under the wider-font action
  model, so `.home-nav` stacks into two rows with the action group right-aligned; the mark stays at 16 px and
  the action stays. The room paper fills the stage as a flex child instead of subtracting `--nav-h`,
  so the taller stacked header cannot clip it at 320 px. The gate is a sweep of `/download/` from 320 to 1440 px
  in 1 px steps under the 164 px wider-font action model, requiring no horizontal overflow, at least 6 px of
  right gutter, the page action visible, and the 36 px theme button at every width; the 360/375/390 px point
  samples stay for the visual checks.
- Reason: the old 380 px step left 381-390 px on the 19 px lockup while the wider-font action needs the 16 px
  step; at 381 px the theme button had 1.1 px of gutter, under the 6 px bar. The gate sampled only 360, 375 and
  390 px, so it stepped over the band. Below 360 px the one-row header cannot hold the wider-font
  action plus the 36 px button (the landing already overflowed at 320 px), and stacking preserves the mark,
  the action and the button instead of shrinking any of them.
- Supersedes: D-039's "at 380 px and below" step and the D-039 corrections' band wording down to 380 px, plus
  the D-039 reason's sampled gutter figures; the 16 px lockup, the two aligned masks, the theme polarity, the
  `--brand-plate` token, the plate hairline, the 6 px action-group gap and D-038 stand.

### Correction to the D-039 correction: the room keeps main's dvh sizing

- Date: 2026-10-25
- Decision: The trial room's vertical sizing is main's again: `.room{...min-height:0}`, the `.room-paper`
  `100vh`/`100dvh` calc pair, `.room.home{min-height:0}` and the `.room-nav` padding shorthand are restored
  verbatim. The stacked header at 360 px and below carries `--nav-h: 77px`, its min-height, so the unchanged
  paper calc still pins the sheet to `100dvh`. The header work (the 390 px narrow-phone step, the two-row
  header and the 320-1440 px sweep) stands.
- Reason: The flex-filled paper removed the room's `dvh` minimum, so an expanded mobile toolbar let `100vh` win
  and pushed EXIT and the word count out of the un-scrollable trial. The paper calc takes `--nav-h` as its
  header input, so the header tier must carry the actual stacked header height.
- Supersedes: The previous D-039 correction's "room paper fills the stage as a flex child" sentence only. The
  header step, the two-row header, the sweep, the plate hairline and the rest of D-039/D-038 stand.

### Correction to D-039: below 380 px the header keeps the mark and the theme button

- Date: 2026-10-25
- Decision: Below 380 px one shared rule hides the nav page action on every page (`nav[aria-label="Main"]
  .btn-quiet`): the landing, the trial room and `/download/` show the brand lockup and the 36 px theme button,
  and `mac.html`, which has no nav action, is unchanged. Each page keeps its call to action in the body. The
  16 px lockup step still covers 390 px and below; the narrow header stays one 56 px row at and below 820 px,
  and the `--nav-h: 77px` stacked tier is gone. The 320-1440 px sweep runs 1 px steps from 320 to 420 and 8 px steps
  from 420 to 1440 under the wider-font action model, with the page action expected at 380 px and above and
  absent below 380 px, and carries its own 120 s timeout.
- Reason: The two-row header was a compromise that changed the header height and needed a room token. The nav
  action is redundant because every page already carries its call to action in the body, so dropping it is one
  uniform rule that keeps the mark at 16 px and the theme button without touching the room's sizing. The
  short-viewport gate now asserts the room's `min-height: 0` boundary and the paper's
  `calc(100dvh - var(--nav-h) - var(--room-gut))` minimum, which fails if the room returns to the flex-only
  paper.
- Supersedes: The previous D-039 corrections' stacked tier, their `--nav-h: 77px` sentence and their
  "stacking preserves..." reason only. The room's restored dynamic-viewport sizing, the 390 px step, the two
  aligned masks, the theme polarity, the `--brand-plate` token, the plate hairline and D-038 stand.

## D-040: The landing states the rule, the promise and the privacy line

- Date: 2026-10-25
- Decision: The landing carries the captain's copy verbatim, and no other words on the page change. The
  headline stays `We force you to write it down`. A subheadline sits directly under it: `Forward only.
  Pause and the draft disappears. Keep going and you get to keep it.` One small line sits under the
  `Give it 60 seconds` door: `No account. Nothing is saved. Just the timer.` Three one-sentence points sit
  below the first viewport, one per column, as one plain list on a hairline (not cards, not a new
  section): the forward-only rule, the situation the tool is for, and the no-save promise on web and Mac.
  The door and its line stay fully on the first screen at both target sizes, 390x844 and 1440x900, and
  that is measured, not assumed: `qa/mac.spec.mjs` and `journey/journey.mjs` assert the line's bottom ends
  at or above the fold beside the door, with the sans stack pinned to one face so the host's system font
  cannot decide the result. The phone keeps the 61% sheet and the line by tightening the hero and CTA
  gaps, not by shrinking type or dropping the sheet.
- Reason: A visitor who reads only the first screen learns what the tool does to them, what it costs them
  and when to reach for it, before scrolling into the mechanics. The captain supplied and approved these
  words directly. D-002's no-extra-labels rule was aimed at the writing room, whose chrome stays bare.
- Supersedes: none. D-002 continues to govern the room; this entry is the landing's exception and names
  its exact words.

## D-041: Updates are opt-in, and never enter the writing room

- Date: 2026-10-25
- Decision: Write It Down 1.1 ships Sparkle 2.10.0 with automatic checks OFF by default.
  `SUEnableAutomaticChecks` is false, so the app never prompts and never schedules a check; the only
  two triggers are `Settings > Updates > Check for updates automatically` and `Check for Updates…`
  in the app menu. The standard Sparkle UI is used, and no update window may appear while the
  Session room is shown: the empty room, writing, warning, failure and kept states all count. A
  scheduled update found while the room is shown is remembered, a check or update window started
  before the room opens is ended through Sparkle's own cancellation or reply path, and every
  deferred update returns once the room is left; the menu command is disabled in the room. Update
  archives are EdDSA-signed ZIP payloads served from
  `https://writeitdown.app/download/updates/` with the feed at
  `https://writeitdown.app/download/appcast.xml`; the DMG stays the public installer. The captain
  creates and holds the signing key (`apps/macos/FirstLine/docs/RELEASE_KEY.md`); the tracked
  `Info.plist` carries the captain's real public key, and the release gate refuses the pre-key
  placeholder. The privacy promise in `WRITEITDOWN_PLAN.md` and `writeitdown/privacy.html` is
  amended to state exactly this: no check runs unless the writer turns it on or asks. 1.0 users
  learn about 1.1 from a release-notes line on the download page; the first automatic delivery
  lands with 1.2.
- Reason: 1.0 shipped with no update channel, so IME and room fixes could never reach installed
  copies, and "free updates included" stayed an empty promise. The captain chose the least invasive
  version of it: no network traffic the writer did not ask for, no window that can steal focus from
  an eight-second silence deadline, and no key material in the repository.
- Supersedes: the 2026-10-24 privacy sentence "no update checks are added" in
  `apps/macos/FirstLine/docs/WRITEITDOWN_PLAN.md` section 7, and the download page's single-version
  release-notes absence. All other room decisions stand: update UI is never part of the room and the
  room's strings, geometry, and motion are unchanged.
  room's strings, geometry, and motion are unchanged.

## D-042: An update waits while a writing session is live, whichever surface is shown

- Date: 2026-10-25
- Decision: The update gate tests whether a writing session is still live, not which surface happens
  to be on screen. A session counts as live on the whole Session room (empty, writing, warning,
  failure, kept) and also after the writer opens Settings, because the silence clock keeps running
  there and the draft can still be lost when Settings is closed. Every presentation entry point
  (menu command, scheduled check, standard Sparkle driver hooks, deferred return on activation or
  surface change) uses that one predicate; an update found while the session is live is deferred and
  presented at most once after the session ends. The menu command is disabled for the same reason.
- Reason: D-040's surface-only wording left a real path to losing a draft: open Settings while
  writing, and a deferred update could appear over Settings and take focus while the silence clock
  ran. The captain's rule is that an update never interrupts writing, so the gate must follow what
  is still running, not one enum that can drift.
- Supersedes: D-041's "while the Session room is shown" gate wording only. Its opt-in default, its
  signed-feed and key rules, and every room string, geometry and motion rule stand.

## D-043: The web room and the landing demo follow the shipped Mac room

- Date: 2026-10-25
- Decision: writeitdown.app's `#trial` room and its landing demo (`#demo`) carry the Mac room's
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
- Supersedes: the web-only room values that D-014, D-020, D-021 and D-025 to D-030 set for the
  trial where they differ from the list above, and the web clauses of D-006 (one act left the room),
  D-017 (the 68% danger band and the receipt 76 px above the paper bottom), D-022 (a repeated blocked
  key does not restart the web refusal) and D-023 (the web kept screen keeps its `0:00` receipt with
  the actions under the draft). It does not change any Mac decision.

## D-044: The landing demo shows the result screens without their controls

- Date: 2026-10-25
- Decision: The landing demo is watch-only theatre, so its wipe stage shows the room's failure screen
  (`You stopped.` plus the red `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` receipt) but no
  `Begin again` button, and its loop rearms by itself. The trial's control is real; the demo gets no
  control that does nothing.
- Reason: Q-13 forbids dead zones, and a second button inside the hero would compete with the one
  entrance under the sheet. The copy and the result screen still match the app.
- Supersedes: none.

## D-045: The web keeps its nav row, and a phone wraps the exit confirmation

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

## D-046: The refusal is visual only on both surfaces

- Date: 2026-10-25
- Decision: A blocked edit is announced visually and to assistive technology only: the 200 ms shake
  with the 220 ms red hairline, plus the live-region line. The web's short browser tone is removed;
  the Mac has no sound for a refusal either.
- Reason: One product, one answer to a blocked key. The tone was web-only, undocumented, and forced
  nothing about the browser.
- Supersedes: none.

## D-047: The landing keeps the door, the demo and the facts a reader needs

- Date: 2026-10-25
- Decision: The landing drops five blocks and moves one. The `Give it 60 seconds` door stands between
  the subheadline and the demo sheet in one vertical rhythm (24 px under the subheadline, 48 px above
  the sheet on the desktop; 16 px and 24 px on a phone, both read from the page's own spacing scale),
  so the reader meets the way in before the preview. Deleted: the reassurance line under the old door,
  the three below-the-fold points, the `The facts` / `Real rules, real numbers` table, the Mac block's
  native-room paragraph and its `macOS 14 ... 14-day refund` meta line, and the closing block with its
  repeated headline, italic line and second door. The page now ends with the FAQ and the footer, and
  the header's `Download for Mac` is the way to the Mac surface. The copy rule behind those cuts is
  recorded as Q-20 in `docs/ui-quality.md`: copy states a mechanism, a number, a price or a
  requirement, and never explains, announces or vouches for the page carrying it.
- Reason: The captain read the page as too long and too eager - the reassurance line, the points band
  and the closing block repeat what the headline, the cards and the FAQ already say, and the facts
  table and the Mac paragraph duplicate what `mac.html` and `/download/` own. The door belongs above
  the demo because the reader decides whether to type before watching a preview. Nothing factual left
  the site: the price, refund, trial and requirement facts stay on `mac.html`, `/download/` and the
  landing's Mac card, and the eight-second rule, the blocked edits and the 60-second length stay in
  the cards and the FAQ.
- Supersedes: D-040 for the reassurance line, the three points and the 390x844/1440x900 fold assertion
  on the door and its line; D-044's "one entrance under the sheet" wording, since the one entrance is
  now above the sheet. The wordmark, subheadline, cards, FAQ and Mac facts are unchanged.
## D-048: The six-lens review is the last stage of an acceptance run, and a declared defect is never a pass

- Date: 2026-10-25
- Decision: `scripts/vm-journey.sh` invokes `scripts/design-panel.sh` on its own evidence bundle as the
  run's last stage and records every lens result in `acceptance.txt`. Sign-off asserts the six named lenses
  (Rams, Norman, Spiekermann, Kare, Matas, Vignelli) by name, so a shorter or renamed lens list cannot
  satisfy it. A lens counts only when its model turn ended normally, its answer is a review of that shape,
  and it declares the lens that was asked: one review repeated across six prompts counts once. A run whose
  six lenses did not all complete writes an explicit "panel not run: <reason>" block with the exact re-run
  command into `acceptance.txt` and `notes.md` and exits 79; the recorded reason is the observed lens
  failure, never a route probe. It never signs off. A run accepted with the declared known defect exits 78
  and marks the sign-off as not accepted. Only a clean, fully reviewed run exits 0. The declaration stays
  keyed to one artifact checksum and one assertion id, and that id is emitted only for the licensed
  relaunch streams, so the same surface in another launch stream fails under its own id.
- Reason: The recorded acceptance must end with the six-lens review inside the same evidence bundle, and no
  exit status may read as a pass when a lens is missing or a declared defect reproduced.
- Supersedes: the separate-command panel procedure and the exit-0 `accepted-with-declared-defect` verdict;
  the declared-defect key and the strict launch assertion stand.

## D-049: A standalone review re-run refreshes the acceptance record with provenance

- Date: 2026-10-25
- Decision: `design-panel.sh` owns the derived lines of a bundle's `acceptance.txt` (the `analysis:` line,
  the panel state and counts, the per-lens results and `sign_off`) and rewrites them from the single status
  it derives at the end of every run; its declared-gap re-run text is the same quoted, absolute command the
  record carries. `vm-journey.sh` keeps the run's own assertion and verdict lines, and reads that record for
  its panel gate, log line and notes summary instead of deriving the panel state a second time. If the panel
  wrote no record at all, the journey writes that record once from the same derivation. A run that replaces
  an earlier review adds `review:` with the UTC timestamp and `review_lenses:` with the lens results, and
  appends the same fact to `notes.md`, stating that this repairs the review artifact only and does not
  re-validate the product.
- Reason: the documented remedy for a blocked panel is a standalone re-run, and before this decision that
  re-run left `acceptance.txt` saying "panel: not run" beside a completed review, so the one record a
  reviewer reads contradicted the artifact it sat next to.
- Supersedes: D-048's ownership of those lines by the journey; its six-named-lens gate, its exit codes and
  its declared-defect keying stand.
## D-050: A frozen screen fails the run, and no recorded step excuses it

- Date: 2026-10-25
- Decision: the analyser's `recording-stall` assertion fails any window in which the screen does not change at
  all for 20 s or more. Nothing in the bundle can excuse that window: a `steps.tsv` stamp inside it is itself a
  capture of the frozen screen, and the guest stamps steps on its own schedule whether or not the screen moved.
  The finding names the stamp as no proof of progress instead of downgrading to informational. Frozen windows
  under 20 s stay informational, so a settled dialog or a paused step does not fail an otherwise live run.
- Reason: the previous rule excused a frozen window whenever a step stamp fell inside it, and a recorded
  run whose every frame delta was 0.000 was therefore accepted as a working run - the capture the rig exists
  to distrust. A dead screen is either a hung app or a stalled recorder, and both must fail the run, so no
  evidence inside the bundle may downgrade them.
- Supersedes: the step-based excuse for `recording-stall` in `scripts/vm/analyse-recording.py` (an
  implementation shortcut, never a recorded decision). D-048's assertion ownership, its six-lens gate and its
  exit codes stand.

## D-051: A launch stream is judged only against the surfaces its own contract forbids, and nothing signs off by default

- Date: 2026-10-25
- Decision: the analyser's forbidden-surface rule is keyed to the launch stream, not to the text alone. The
  fixture launch is started to show the activation page before activation, so `launch-fixture-first.jsonl`
  is judged only for the transience of its states and never against the forbidden list; the trial and the
  licensed relaunch streams keep failing on it under their own assertion ids, and no PASS line is printed
  for a stream the rule does not judge. `panel-lib.py gate` reports the review state as the command's own
  exit status (0 complete, 79 not) so `vm-journey.sh` cannot turn an unparseable printed value into a pass.
  A sign-off is `accepted` only for the recorded `accepted` verdict; an unknown, renamed or absent verdict
  line is written as not accepted and names the verdict the record states.
- Reason: the fixture stream's contract requires the surface the forbidden list names, so a clean DMG run
  was rejected for showing exactly the screen the rig demands, while a non-numeric gate value silently
  skipped the 79 exit, and a renamed verdict line could sign off with no criterion at all.
- Supersedes: D-048's "the same surface in another launch stream fails under its own id" only for a stream
  whose own contract requires that surface, and D-049's read of the gate as a number. D-048's six named
  lenses, its exit codes and its declared-defect keying stand.

## D-052: A panel that could not run is a declared capability gap, and the release record states the run that happened

- Date: 2026-10-25
- Decision: on this host the six-lens panel is a declared capability gap, not a panel failure and never a pass: it
  is implemented and wired as the run's last stage, it did not run for the 1.0 bundle because no reviewer route
  answers, the bundle carries `panel_not_run` with the exact re-run command and `sign_off: blocked`, and a
  released build still needs a real six-lens run in its own bundle. The evidence bundle is the only authority for
  the recorded run: the 1.0 bundle recorded 367 captured frames, an 892 ms largest frame gap, 125.52 s of
  recording, 31 deterministic findings, verdict `accepted-with-declared-defect`, panel not run, `sign_off`
  blocked, and exit 79. `writeitdown/README.md` states the exit-code contract once - 0 clean pass, 78 the
  declared known defect reproduced with the deterministic analysis and the panel complete, 79 blocked including
  a panel that could not run, 1 rejected - and the QA record points at it instead of restating a per-run code.
- Reason: the record claimed that same run exited 78 with a signed-off declared defect and carried the six-lens
  review, while the bundle it described recorded a blocked panel and exit 79, and the QA record carried two
  different frame counts and frame gaps for one recording. A release record that disagrees with its own bundle
  cannot be used to decide a release.
- Supersedes: D-048's exit-78 sentence only as it applies to a run whose panel did not complete. Its six named
  lenses, its assertion ownership and its declared-defect keying stand.

## D-053: Every shipped page is one design system, and the phone room nav yields to the clock

- Date: 2026-10-25
- Decision: the landing's design system governs all twelve writeitdown.app pages. The nine
  help/legal/answer pages and `mac.html` move onto the shared document shell: the A mark lockup on its
  paper plate, the theme button, the same footer, 17 px system-face body copy at the 62ch measure,
  Newsreader headings, token-only colours, and the v2 pill and underlined-link treatments. There is no
  reading-mode exception. `mac.html#buy` becomes a section with the heading and the `$4.99 once` price
  row in view, the buy form's pending and error states, and a licence card for the ready, copied and
  unpaid states; the `session_id` credential is cleared from the address bar and history on success and
  failure alike, with `Check again` as the in-page retry. One price string, `$4.99 once`, appears
  wherever the Mac page names the price. On a phone the room nav keeps only the lockup and the theme
  icon, and the Mac link moves into the exit row. The download page carries no 1.1 note until 1.1
  ships; the note returns with that release.
- Reason: the captain read the live site and found the colours wrong on `support.html` and the design
  system wrong on the page buyers reach before paying. The nine support, legal and answer pages were
  still a retired beige/mono document style, and `mac.html` was a third system: a 48 px left-aligned
  serif heading, 21 px serif body, square mono buttons and a transparent theme button, while
  `/download/` two links away was 60 px centred, 17 px sans and pill-shaped. A buyer paid from the page
  that matched the least. On a phone, the room nav's filled pill was louder than the clock above it, and
  D-045's reachability reason survives without it because the Mac link stays in the exit row.
- Supersedes: D-045's room-nav clause (the nav row is still kept on the landing room at every width,
  but a phone shows only the lockup and the theme icon; the Mac link moves into the exit row). It also
  supersedes the canvas-only adoption recorded for `mac.html` in the `tokens.css` header.

## D-054: The download card may carry a release note only for the artifact it links

- Date: 2026-10-25
- Decision: `download/index.html` carries no hidden release-note placeholder. A release note in
  `#release-notes` is optional; when present it declares the artifact version it links in
  `data-release-note`, and that version must equal the linked DMG's version. The release gate
  refuses a note that runs ahead of or behind the linked DMG, a note without a valid declared
  version, and any `data-launch-pending` mark. Publishing a version adds the visible note naming
  that version. The DMG link name, the Install command's filename and the SHA-256 slot stay always
  gated, so a version bump cannot ship half-flipped.
- Reason: the design migration removed the 1.1 note from the card and relaxed the gate to accept a
  page with no note, which reversed D-041's recorded commitment that 1.0 users learn about 1.1 from
  the download page without recording a supersession. The note is product content the captain owns:
  a published version carries a visible note naming it, and a page without one claims nothing newer
  than the artifact it links.
- Supersedes: D-041's download-page release-note clause and the `data-launch-pending` gate. D-041's
  opt-in update rules stand.

## D-055: Page content sits on the header's grid, centred or flush, never flush on one side

- Date: 2026-10-26
- Decision: On every shipped page each block of page content starts and ends at the same distance
  inside the header container. Two compositions are allowed and no third: a block flush with the
  container's edges (the landing's full-bleed bands and `/download/`) or a block centred in it (a
  document's 62ch measure). A document page centres its measure inside the header container instead
  of running it from the header's left edge, so the H1, the lede, the questions, the purchase card
  and the licence card share those two edges. `qa/shell.spec.mjs` pins the geometry at 1440, 1024
  and 390 on all twelve pages, and document blocks may not reach past the container at all.
- Reason: the captain read the PR 70 preview of `mac.html#buy` and described the page as a narrow
  block stuck to the logo with an empty band on the right. The measurement agreed with his eye: the
  column was inset 0 px on the left and 392 px on the right at 1440, 0 and 296 at 1024 - a 62ch
  text measure inside a 1120 px container, left-aligned, under a header that spans the container.
  The landing itself never does that: its objects are either container-wide bands or the centred
  760 px sheet.
- Supersedes: the 2026-10-25 QA row Q-14 wording "one left edge shared with the footer on every
  document page", which read the flush-left column as the deliberate alignment. The one measure in
  the 17 px face is unchanged.

## D-056: The Note paper and its ink are locked for every writing sheet

- Date: 2026-10-26
- Decision: The writing sheet is the **Note** paper on every surface, and the page around it keeps its
  white identity. Light: the sheet is `#dbe6ec`; dark: `#21272a` (the lamp version of the same paper,
  not an inversion of the light values). Ink is `#1c1917` in light at full strength (weight 100) with
  the tuner's imperfection on - measured 13.78:1 on the sheet - and `#ece7d9` in dark. Grain is **70 of
  100** at size **1.00**, generated per sheet size from integer-stable seeds, two scales (device-pixel
  tooth plus a coarser pulp cloud), with pulp fibres and pigment flecks; it is drawn once per size and
  theme and never while typing. The sheet's other roles are measured against the paper rather than
  against white, because the paper is no longer white: quiet chrome (clock, count, exit link, receipt,
  hint) `#464746` / `#b8b5ac` at 7.35:1, the per-line history ladder at 9.2:1 then 7.2:1, and the pen red
  (numeral, wipe receipt, exit hint) `#63140b` / `#ffb4a2`, which clears 7:1 on the sheet *and* on the
  warn wash the numeral actually sits on. Considered alternative: **Wheat** `#e0d5b8` (dark `#342e24`),
  the runner-up the captain liked; it was not chosen. Platen's paper was the earlier round's favourite
  and is what prompted this round.
- Reason: The captain locked these values from the live tuner at
  `http://100.110.226.112:8099/?tone=note#trial` (theme light, warm 0, depth 0, sheet as rendered
  `#dbe6ec`, grain 70 at size 1.00, ink weight 100 with imperfection on, 13.78:1, sound all off), after
  saying of the earlier round `我觉得 platen 的很好看 你可以试试`. A paper that reads as paper cannot
  be the plain white sheet the constitution was written around, so the sheet's text roles had to be
  re-derived from measurement: on `#dbe6ec` the old quiet grey sits at 4.5:1, the old pen red at 5.2:1,
  and the old 100/22/7 opacity ladder put the faded history lines at 1.2:1 - all below the 7:1 floor
  the captain set. The fade therefore steps by *contrast* (13.78 -> 9.2 -> 7.2) instead of by opacity,
  which keeps the depth cue and the readable floor at once.
- Mac: the same tone, grain and ink, rendered by `PaperSheetView`/`PaperField` with the web renderer's
  seeds and amplitudes. The one technique that does not transfer is the web's 2 px glyph displacement:
  a live `NSTextView` cannot be re-rasterised per keystroke without moving the caret with the glyphs, so
  the Mac keeps the transferable half (a 0.35 pt ink spread) and leaves the hand to its own writing
  face. Both surfaces are asserted on the measured result: tone, contrast ladder, grain presence and
  grain stillness.
- The warn wash is the sheet's, not the wall's: `color-mix(in oklab, paper 88%, #c8392f)` resolved as
  `#ddd3d5` light / `#352c2c` dark, and the eighth second's deeper step at 76% as `#ddc0be` / `#49302e`.
  All three writing surfaces paint that mix, so the alarm tints the same paper the same way. The pale
  tint the product used before (`#f6e2dc` / `#4a2318`) was tuned for a white sheet: over the Note paper
  its mid-ramp lands on neutral grey, and the Mac's rendered warning frame measured 0.017 of warmth - no
  tint at all - which is why the Mac now takes the paper mix instead of its own pale overlay. Captured:
  `site-warn-*`, `root-trial-warn-*`, `mac-snapshot-room-warning-light`.
- The texture cannot arrive late: the landing's renderer mounts a sheet's canvas in the same task the
  sheet enters the document (a `MutationObserver` in the document head, not a `DOMContentLoaded`
  handler). A per-frame probe proves no rendered frame ever showed the sheet plain
  (`tests/paper.spec.mjs`, `the demo sheet at rest`); deferring the mount to `DOMContentLoaded` fails
  that assertion, and did before this change.
- Tests: `tests/paper.spec.mjs` (landing demo sheet, trial sheet, kept sheet, wash),
  `writeitdown/qa/paper.spec.mjs` (site demo sheet and room, light and dark, 1440 and 390, plus the
  warn wash and the numeral on its deepest step), `FirstLineTests/PaperContrastTests` (tones, roles,
  ladder, the wash mix, determinism) and `SnapshotTests.paperStaysStillWhileTyping` plus the
  `paperPoint` region checks on every room state.
- Supersedes: the white writing sheet (`--sheet #ffffff` / `#26231c`, `--paper #ffffff` on the landing),
  the landing's `--ink #17150f`, and D-027's 100/22/7 *opacity* numbers (its stepped-per-line intent and
  the one-pitch shift stand unchanged).
