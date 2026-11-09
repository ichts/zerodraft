# Write It Down: captain decision log

Status: durable, append-only record of product decisions for Write It Down / Zero Draft. Chat and PR
text are not the source of truth; this file is. An entry is never edited. A later decision adds a new
entry and names the entry it supersedes. The behaviour contract that implements these decisions is
`docs/wid-mac-behavior.md`; visual tokens remain owned by `design/DESIGN.md` (web) and
`apps/macos/FirstLine/AGENTS.md` (Mac). The per-surface world table
is `docs/wid-world-table.md`.

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

## D-057: One shared type set, served by the site itself, with the hand accent as the one declared exception

- Date: 2026-10-26
- Decision: writeitdown.app and the Mac app draw text with one shared set, and the Mac is the
  reference. **Newsreader** (the bundled variable upright and italic, `wght` 200-800, `opsz` 6-72)
  is what the writer writes and what every heading is set in, on both surfaces. **Zhuque Fangsong**
  is the same roles in Chinese: the Mac through its bundled CoreText cascade, the web through
  GB2312-subset woff2 slices declared with `unicode-range` in `fonts-cjk.css`, which `index.html`
  alone links, so a visitor fetches a Chinese slice only when Chinese characters reach the screen.
  **The system sans** is everything the tool says - labels, nav, buttons, eyebrow copy, the clock,
  the count, the warning caption, the receipts, the quiet links - and the kept heading, the failure
  headline and the warning numeral carry no tracking, matching the Mac, whose kept and failure
  headings are set with no kern attribute. The clock keeps tabular digits at 15 px semibold as the
  Mac's `monospacedDigitSystemFont` does. **No monospace face sets text**: the retired IBM Plex Mono
  chrome layer is gone from the web and its 135,580 B font file no longer ships inside the Mac app;
  the system monospace (`ui-monospace`) draws literal machine strings only (a shell command, a
  SHA-256), and the licence key moved to the system sans because it is product chrome, not code.
  **Every face is served from the site itself** (`writeitdown/fonts/`, generated by
  `writeitdown/fonts/build-fonts.py`): no page requests a font host, and the Latin subset is
  byte-for-byte equivalent in advance to the face Google used to serve. **The one exception, and it
  is a recorded exception, not an oversight: the hand-lettered accent (Reenie Beanie) stays on the
  landing and its existing marketing uses - the `write it down` hero word and the two section
  headings - and nowhere else.** It never appears in the room, it is not added to any new surface,
  and it never ships on the Mac, which must not gain a hand face: Reenie Beanie has one weight, no
  CJK, and a script face at 13 px would fight the native control look. It is a marketing voice for
  the page that sells the product, not a type role of the product. The guard is
  `writeitdown/qa/typography.spec.mjs` (a census of every text role on the twelve shipped pages, the
  self-hosted-face proof with the font hosts refused, the Chinese platform-face check, clock width
  stability, and the shared advances) plus
  `apps/macos/FirstLine/Tests/FirstLineTests/TypographyParityTests.swift` (resolved faces, the CJK
  cascade, tabular clock digits, untracked kept heading, the receipt's 0.02em); both read
  `writeitdown/qa/shared-type-baseline.json`, where one committed advance per shared role binds the
  two surfaces at 0.05 %.
- Reason: the captain reported that the web fonts differ from the Mac app's, and the inventory
  behind this decision found the divergences were not the Latin writing face (web 264.500 px and Mac
  264.486 pt for the same 28 pt string, 0.005 %) but the four things a visitor actually meets:
  Chinese fell through to PingFang SC instead of the Mac's fangsong; ten shipped pages still carried
  a machine-mono identity the app had retired; the web's serif came from Google and silently became
  Georgia when that host was refused, which is the normal state on the captain's own network; and
  the clock's digits were proportional while the Mac's are tabular, so the corner moved on every
  tick. The inventory also showed the landing's hand accent has no counterpart in the app. The
  captain chose, for that one taste call, to keep it on the web as a marketing-only voice (option B),
  which is why it is recorded here as an exception with its boundary instead of being retired or
  quietly extended. Self-hosting also removes a third-party call from a product that sells privacy,
  so `privacy.html` now states that the site serves its own fonts. The root Zero Draft landing
  (`index.html`, `design/DESIGN.md` sections 1-11) is a separate surface, answers to its own type
  pairing, and is untouched by this decision.
- Payload: Latin upright 137,436 B and italic 154,240 B, the hand accent 17,936 B, and the 13
  Zhuque Fangsong slices 2,726,540 B in total (48,668-358,692 B each). A page that renders no Chinese
  fetches 309,612 B of faces; the CJK stylesheet itself is 47,824 B of `unicode-range` text and is
  linked by `index.html` alone.
- Supersedes: the `tokens.css` header's "Reenie Beanie (the pen) ... Newsreader loads with the site's
  existing font link" scope, and `writeitdown/AGENTS.md`'s landing `faces` clause now that the hand
  word is a recorded exception rather than one of three interchangeable faces. The retired mono
  identity itself was already superseded for `index.html` and `/download/` by D-053; this finishes it
  on the remaining ten pages and in the app bundle.

## D-058: A small phone shares its first screen between the door and the preview

- Date: 2026-10-26
- Decision: On a small phone the landing sheet takes the space left under the door instead of
  insisting on 61% of the viewport: at 380 px wide or narrower and 700 px tall or shorter its
  minimum height is `max(300px, min(61vh + 2px, 100svh - 340px))`. The door, its rhythm and the whole
  demo sheet then end inside the first screen at 375x667 and 320x700. At 320x568 the paper keeps its
  300 px floor and the page scrolls, which the captain allowed. The 390 px targets (390x844 and the
  toolbar-shrunk viewport the mobile gate simulates) keep the 61% sheet at every height.
- Reason: the audit measured the door below the fold at 375x667 and 320x700 before D-047 moved it
  above the demo, and the sheet still ended past the fold at both sizes (743.8 of 667 and 748 of
  700), so the first screen ended on a paper cut by the screen edge. The audit's own remedy was a
  height-aware sheet; scoping it to the widths the audit measured keeps the measured 390 px contract
  intact, which a blanket `max-height` rule broke in the mobile dynamic-viewport test.
- Supersedes: nothing. The 61% sheet contract stands for the sizes it was measured at.

## D-059: A press and a focus change the label and the ring, nothing else

- Date: 2026-10-26
- Decision: The kept screen's primary control reserves the width of its own `COPY TEXT` label in a
  single grid cell, so the press to `COPIED` cannot shrink the pill or re-centre the row; at 390 px
  the kept column narrows to 24 px insets with a 16 px gap, so both controls stay on one line and
  `RUN IT AGAIN` never lands under the pointer that pressed COPY. The shared focus rule is a ring
  only: `.home :focus-visible` keeps the 2 px ink outline and no longer carries `border-radius`, so a
  focused control keeps its own shape - the pill stays a pill, a text control stays square.
- Reason: the press moved `RUN IT AGAIN` 14.8 px left at 1440 and, at 390, from a second row into the
  first one directly under the tap point, so a second tap started a new session and threw the kept
  draft away; and the focused COPY pill rendered as an 8 px rounded rectangle beside a 999 px
  capsule the moment the kept screen took focus.
- Supersedes: nothing. The 48 pt pill, its single inner ring and its 24 px label padding are
  unchanged.

## D-060: The download head breaks without an orphan, and its copyable strings never break mid-token

- Date: 2026-10-26
- Decision: `/download/`'s H1 keeps `for Mac` unbroken, so a phone head reads `Write It Down` /
  `for Mac` instead of orphaning `Mac`. At 420 px and narrower the whole head is left-aligned, so
  the headline's ink and the 34ch deck's ink start on the page's own left edge; the desktop head
  keeps its centred line. The published SHA-256 sits in its own mono panel - `--tag-bg`, a hairline,
  13 px mono in the ink role, the label in the mute role - as two atomic 32-character halves that
  share one line when they fit and wrap into two unbroken lines when they do not (12 px and tighter
  panel padding below 365 px so one half fits at 320 px; 13 px wherever it fits). The Install card's
  `shasum` command breaks at its argument boundary: `shasum -a 256 ` stays on the first line and the
  DMG filename sits on a hanging continuation line, unbroken. Neither block is a scroll container,
  neither shows a fade, and every line is fully visible without interaction. Each block carries a
  `COPY` control (36 px ghost pill, `COPIED` for two seconds, sr-only live status) that writes the
  exact full value, and each control names its own value in its accessible label
  (`Copy the SHA-256`, `Copy the install command`) so the two buttons are distinguishable. The hash
  code's text stays the single 64-character value and the command's text the single one-line
  command, so `release-check.mjs` reads them unchanged.
- Reason: at 390 the head broke as `Write It Down for` / `Mac`, orphaning a 38 px word, the deck set
  seven centred lines with seven different left edges, the 64-character hash sat at 11.96 px and
  broke wherever the box ended, and the command a buyer must copy wrapped mid-token. A single
  scrolling line then hid most of the hash and the install card's narrow desktop column hid the
  filename, so the value a buyer must compare or copy could not be found.
- Supersedes: nothing. The `data-launch="sha256"` slot, its text and the command's filename stay
  exactly as `release-check.mjs` reads them.

## D-061: The exit asks twice for a pointer too, and the phone names the control it has

- Date: 2026-10-26
- Decision: In the room, nothing leaves in one act. Escape, `EXIT` and the brand all arm the same
  inline confirmation for two seconds and the second act leaves; the room's `Download for Mac` links
  (header and exit row) open in a new tab with `rel="noopener"`, so the draft survives them. The
  control is labelled `EXIT` at 767 px and below and its confirmation reads `Tap EXIT again to leave
  and delete the draft.`; above that width it stays `ESC - EXIT` with `Press Esc again to leave and
  delete the draft.` A tap on `EXIT` arms exactly as a click does.
- Reason: the phone carried only the label of a key it does not have and a confirmation that named
  that key, and the exit row itself held a one-tap link that navigated away from a live draft while
  the two-step exit was the only thing protecting it.
- Supersedes: D-053's phone nav arrangement only in that the Mac link in the exit row is now a new-tab
  link; the nav keeps the mark and the theme icon alone.

## D-062: The kept receipt owns the count, and one caption says the draft is not saved

- Date: 2026-10-26
- Decision: On the kept screen the red receipt prints the session's size (`1 MINUTE. 40 WORDS.`), the
  corner count slot is silent, and one caption sits under the actions: `Nothing here is saved. Copy
  it before you leave.` The caption's gap joins the kept screen's own space list, so a short sheet
  gives it up before it gives up the draft's last line.
- Reason: the count was printed twice, 598 px apart at 390, and nothing on the screen said the kept
  text existed only in this tab, so leaving or reloading lost it silently.
- Scope: the web surfaces (the trial room and the landing demo). The Mac kept screen still prints
  the count twice and the Mac lane carries the same change under `docs/wid-mac-behavior.md` before
  the two surfaces are claimed to match again.
- Supersedes: the "count in the corner on every state" reading of D-028 for the kept screen only;
  rest, typing, warning and wipe keep both the corner count and their instructions.

## D-063: The wipe clock holds the value the draft died with

- Date: 2026-10-26
- Decision: While the failure screen is up, the corner clock shows the same `M:SS` the red receipt
  names (`DRAFT DELETED AT 0:52.`), and holds it until `Begin again` or the next first keystroke
  starts a session. The landing demo's failure screen does the same.
- Reason: the clock re-armed to `1:00` under a receipt that named `0:52`, so the same corner meant
  "already used" on the kept screen and "reset" on the wiped one, and the receipt's value had no
  referent on screen.
- Scope: the web surfaces. The Mac deleted screen still shows the clock after it re-arms; the Mac
  lane takes the same change before the parity claim is restored.
- Supersedes: nothing. The receipt string itself is unchanged.

## D-064: The watch-only preview advertises no input

- Date: 2026-10-26
- Decision: The landing demo draws no caret, never writes `Type to start` in its count slot, and its
  failure receipt reads `DRAFT DELETED AT M:SS.` with no `TYPE TO START AGAIN.` instruction. The
  slot stays empty until the first scripted word appears, then prints the room's exact word string
  (`1 word`, `20 words`). Its clock and its receipt keep running, and its failure screen holds the
  clock at the deletion value like the room; the room keeps the trailing instruction because the
  room takes input.
- Reason: the preview painted a blinking insertion point and a typing instruction while a click, a
  key or an IME composition changed nothing, so the first thing a visitor tried was the one thing
  that could never work.
- Scope: the landing demo. The room keeps its `Type to start` prompt because the room takes input,
  and the Mac has no watch-only preview.
- Supersedes: the demo's `Type to start` reading of D-028.

## D-065: A wipe hides the draft, never the insertion point

- Date: 2026-10-26
- Decision: In the wipe phase the editor's text colour goes transparent and its caret keeps the ink
  colour; the writing area is no longer faded to zero opacity. The wiped room shows the caret on the
  empty line exactly as the first-entry room does.
- Reason: the failure screen orders `TYPE TO START AGAIN.` while an `opacity: 0` writing area had
  painted the caret away, so the one screen that tells the writer to type was the one screen with no
  insertion point.
- Scope: the web room. The Mac room's deleted screen is its own contract; the Mac lane applies the
  same rule there before the parity claim is restored.
- Supersedes: nothing.

## D-066: Seconds read one way, and the clock does not breathe

- Date: 2026-10-26
- Decision: On the landing `m:ss` names only the running clock, `N s` names a silence mark, and a
  duration is never a bare numeral: the warning panel reads `3 s left · warning` over its `3`, the
  card's marker row reads `5 s · warning` and `8 s · deleted`, and the three-second lead-in is
  stated once in the card and once in the answer the FAQ schema repeats word for word. The clock and
  the count on both the room and the demo use tabular numerals.
- Reason: the panel labelled `5 s · warning` sat over a numeral `3`, the Mac limits were listed as if
  they were warning times although the warning always starts three seconds before the limit, and the
  proportional clock crept sideways once a second.
- Supersedes: nothing. The silence limits themselves (`5 s`, `8 s`, `12 s`) are unchanged.

## D-067: The exit wording follows the input, not the window width

- Date: 2026-10-26
- Decision: The room chooses `EXIT` and `Tap EXIT again to leave and delete the draft.` whenever
  `(hover: none), (any-pointer: coarse)` matches, and `ESC - EXIT` and `Press Esc again to leave and
  delete the draft.` otherwise. Width only decides layout: the wrapped confirmation row and the
  hidden nav pill. The wording re-syncs when that query changes and on resize. The two-act exit and
  the new-tab Mac links are unchanged.
- Reason: the width rule left a landscape phone (844 px) naming a key it does not have, so the
  audit's phone-wording defect remained reachable on a wide touch screen.
- Supersedes: D-061's width rule for the label and hint; its two-act exit and new-tab links stand.

## D-068: The landing first screen is one flex column, not a breakpoint

- Date: 2026-10-26
- Decision: The landing's nav, hero, door and sheet sit in `.first-screen`, a flex column with
  `min-height:100vh` and `100svh`; `.stagewrap` takes the remaining space with a
  `max(300px, 61vh)` / `max(300px, 61svh)` floor (vh first, svh second), and `.home .paper` fills it
  (`flex:1;min-height:300px`, max-width 760 px). The sheet sizing carries no width or height
  breakpoint. When the content plus the floor exceeds the viewport, the first screen grows and the
  page scrolls; the door and its note stay inside the viewport. The sheet stays at or above 61% of
  the first viewport at 390x844, 375x667, 320x700 and 1440x900.
- Reason: the 380 px / 700 px scoped rule and its width-banded constant each moved the cut to the
  next size - 375x812 in the first, the 381-387 band in the second - so the sheet must follow the
  content instead of hard-coded chrome; the container-only sizing then let a wider phone face drop
  the sheet below the 60-61% contract, so the container now carries the fraction floor.
- Supersedes: D-058's width/height scoping rule and its 340 px constant; its intent (the door and the
  preview share the first screen) and the 300 px floor stand.

## D-069: The writing sheet is the Wheat paper, not the Note paper

- Date: 2026-10-27
- Decision: On the web (the landing demo, the trial, the writeitdown.app demo, room, failure and kept
  sheets) the writing sheet is the **Wheat** paper: light `#e9e2ce`, dark `#342e24` (the tuner's Wheat
  lamp version of the same paper, not an inversion). Grain stays **70 of 100 at size 1.00**; the ink stays
  `#1c1917` at weight 100 with the imperfection on in light and `#ece7d9` in dark. The page, the wall,
  the header and the chrome stay white. The warn wash is still the sheet's own mix: `#e8cfbb` (88%) and
  `#e6bca7` (76% at the cut) in light, `#453226` and `#573428` in dark.
- Measured (WCAG contrast, every text role against the sheet; the numeral and the pen also against the wash):

  | Role | Light on `#e9e2ce` | Dark on `#342e24` |
  |---|---|---|
  | Writing ink | 13.52 (`#1c1917`) | 10.88 (`#ece7d9`) |
  | Quiet chrome (clock, count, hint, receipt, exit, kept note) | 7.21 (`#464746`, unchanged) | 7.31 (`#c2bfb7`, was `#b8b5ac` = 6.56) |
  | Pen red (numeral, wipe report, exit hint) | 9.93 (`#63140b`, unchanged) | 8.74 (`#ffc2b4`, was `#ffb4a2` = 7.87) |
  | Pen on the 88% wash | 8.61 | 7.88 |
  | Pen on the 76% wash at the cut | 7.43 | 7.06 (was 6.37) |
  | History step one | 9.03 (alpha .847, unchanged) | 9.16 (alpha .902, was .846 = 8.26) |
  | History step two | 7.09 (alpha .769, unchanged) | 7.16 (alpha .772, was .727 = 6.54) |

  Every light role clears 7:1 untouched. In dark the quiet grey, the second history step and the pen on
  the deepest wash fell under 7:1 on the warmer, lighter lamp paper, so only those three lightness
  values moved; the first history step moved with them so the ladder keeps its roughly 9 then 7 shape
  (the room test pins step one at 9:1 or better).
- Reason: the captain was asked to choose between keeping the cool Note paper, a plain white sheet and
  the warm Wheat paper, and answered **3**. The value is the measured Wheat paper from the Platen
  garden, the tuner's runner-up (`data/wid-paper-tuner/site/tuner.js`, `wheat`: `#e9e2ce` / `#342e24`);
  it is warmer than the `#e0d5b8` D-056 recorded as the considered alternative.
- Tests: `tests/paper.spec.mjs` and `writeitdown/qa/paper.spec.mjs` now pin the Wheat values, the
  dark roles, the washes and the grain's rendered mean (the texture composited over the tone, read off
  the pixels: within 6 per channel in light, 10 in dark because the lamp moves it). They fail on the
  Note values (tone, wash, dark roles and the mean at 20 to 50 off the tone).
- Not changed here: the Mac app keeps D-056's Note paper (`PaperSheetView`, `PaperContrastTests`) until
  its own change mirrors this one; the web and the Mac disagree on the sheet tone until then.
- Supersedes: D-056's tone (`#dbe6ec` / `#21272a`), its measured role values for the web (13.78, 7.35,
  10.1 and the dark `#b8b5ac` / `#ffb4a2` / .846 / .727), and the wash values `#ddd3d5` / `#ddc0be` /
  `#352c2c` / `#49302e`. D-056's grain, ink, white page identity, contrast-ladder design and the
  one-canvas renderer stand unchanged.

## D-070: The stopped screen is one centred composition, and its chrome is off

- Date: 2026-10-26
- Decision: the stopped screen is one group - `You stopped.`, the single line `Draft deleted.`, and
  the `Begin again` pill - and the group, not the headline, is what the sheet places: its midpoint
  sits at 33% of the paper height. Under the headline the order is the line first, then the pill.
  The gaps are 9 px (headline to line) and 24 px (line to pill), box edge to box edge. The headline
  is Newsreader 48 px / 500 at line-height 1.1 at the desktop sheet and keeps the result role's own
  `clamp(32px, 5vw, 48px)` on a narrow sheet; the line is 15 px system sans / 400 in the sheet's
  quiet role, `--paper-quiet` on the web (7.21:1 light and 7.31:1 dark on the Wheat paper, D-069) and
  `FirstLineColors.paperQuietNSColor` on the Mac (measured at 7:1 or better against its rendered
  sheet), never `--mute`, which D-056 keeps off the paper; the pill is the room's outlined secondary at 48 px tall, 15 px / 600, 20 px side
  padding, full radius, and the room's ink focus ring. On the Mac the composition is the same
  mapping in the Mac's own units, not a copy of the web's pixels: the pill height is the base
  (5% of the window width, rounded, clamped to the result role's 32-48 pt), the headline is 1.0 of
  it on the locked 1.1 line box, the two gaps are 9/48 and 24/48 of that base, the line is 15/48 on
  its own 24/48 box (the web's 15/1.6, a fixed line height so the box is the ratio and the ink sits
  centred in it), the pill label is 15/48 at weight 600 from `FirstLineTypography.uiSemiboldNSFont`
  with the size applied to the token rather than replacing it, and the pill's sides are 20/48 of the
  base with a full radius and the room's ink focus ring. At the minimum window (980 pt content
  width) the base is 48, so the gaps are 9 and 24, the line and label 15 on a 24 pt box, and the
  pill 48 tall with 20 pt sides: the group is 3.2875 times the base, 157.8 pt, the same ratio sum as
  the web's. `RoundThreeTests` asserts the anchor, both gap ratios, the line's box ratio, each type
  size, the pill height and its side ratio, the group's ratio sum, and the invisible writing layer,
  at 1040x720 and at a smaller 760x560 sheet (base 38), so neither a copied constant nor a font's
  own metrics can pass. The group's midpoint sits on the room's one anchor,
  `RoomPresentation.paperAnchorFraction`: the active writing line is placed by that same constant,
  not by a second fraction, so the group replaces the line the writer was on and the two placements
  cannot disagree. That single anchor is 33% of the paper height, so the Mac's writing line moves up
  from D-025's 35% while the live web trial keeps its own 35% line, because the web's composition is
  a separate layer over the room rather than the editor's own placement; the two surfaces' stopped
  groups still sit at the same 33%. Session chrome is off on this screen: the clock and the 2 pt
  session bar do not show and are not frozen as a receipt, and the restart brings both back with the
  new session. Typing, Return and the pill all restart; the pill is the only restart control on the
  sheet, while leaving the room still uses `ESC - EXIT` in the footer. The stopped
  sheet's writing layer stays focused and editable but invisible (`alphaValue` 0, the same act as the
  web's `.room[data-phase="wipe"] .writing-area{opacity:0}`), so no caret is ever drawn inside the
  group while the next keystroke, including an IME composition, still restarts the room in place. A
  blocked restart names only the reason that is true: the announcement and the pill's help take the
  obstacle the app derives from its own state (the trial budget spent, or a licence needed), so an
  exhausted trial still hears that its three free sessions are used while licence residue, a
  trial-access error or a cleanup failure never claim they were, and the visible label stays
  `Begin again` in every case. The web and the Mac are asserted geometrically at 1440 and
  390 (`writeitdown/qa/phase4.spec.mjs` "the stopped screen is one group anchored at 33% of the
  sheet") and at 1040x720 and a 760x560 sheet in both appearances
  (`RoundThreeTests.stoppedScreenIsOneGroupAnchoredAtThirtyThreePercent`).
- Reason: the captain rejected the alternatives and the paused checkpoint's own screen. His words:
  搞错了 这些我都不喜欢 ... 那个 button 应该放中间 现在整个结构很怪异 you stopped 放在太上面了 其实是排版问题
  不是 button 的问题 - the block was pinned 72 px under the sheet's top edge, which read as a caption
  above a great emptiness rather than a screen; the pill was not the problem and the text-link
  restart was the wrong answer to it. He then locked the composition in the live tuner at 1440 light
  (sheet 1376x804, group 157.8 tall, top 186.1, midpoint 265) and turned the session chrome off.
  A share of the sheet, not a pixel offset, is what keeps the composition readable from a phone
  sheet to a desktop one.
- Supersedes: the paused candidate-C checkpoint (`fm/wid-failure-c-screen` at `96a3647`), whose
  stopped screen froze the clock and the 2 pt bar as its receipt and made `Begin again` a quiet
  text link with a `RETURN` caption; its block also stayed pinned at 72 px. This entry supersedes
  D-029's "the stopped screen is the kept screen's counterpart with a red deletion receipt" clause
  and D-030's receipt wording; it also supersedes D-017's wipe-receipt clause (the receipt taking
  the numeral's status slot under the writing line) and D-020's wipe-receipt ink-top clause, and it
  retires the `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` sentence and the frozen-instrument
  receipt on both surfaces. Its Mac-only clauses supersede D-025's "the active writing line sits at
  35% of the paper" anchor clause (the room now places the line on the same 33% anchor as the
  stopped group) and D-043's parity clause that makes the web room's 35% line follow the Mac's,
  which is why that figure now differs by surface; the web keeps its own 35% line as D-043 and D-025
  state it. Its wipe-screen clauses supersede D-043's "the wipe receipt
  takes the same status slot" and "the wipe screen is `You stopped.` with a 48 pt outlined
  `Begin again` and the red receipt", and D-044's "its wipe stage shows the room's failure screen
  (`You stopped.` plus the red `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` receipt)". On the web
  it also supersedes D-063 (the wipe clock held at the deletion value: the clock is off the stopped
  sheet instead), D-064's failure-receipt clause (the demo's stopped stage prints no receipt; its
  no-caret and silent-count clauses stand) and D-065 (the wiped room's caret: the stopped group sits
  where the writing line was, so the writing layer is transparent and no caret is drawn inside the
  group, while the editor keeps focus so typing still restarts). The spoken
  announcement keeps the deletion and the unused seconds, because the screen no longer prints them,
  and names the real obstacle to the next session.

## D-071: The landing's m3 moment card keeps its palette until the captain decides the contrast

- Date: 2026-10-26
- Decision: the landing keeps `--red-deep` as the `m3` moment card ground and `--mute` for its
  consequence line at 15 px / 400 until the captain makes a design decision; this change does not
  repaint the landing or alter any colour, CSS value or behaviour. The measured pair is 3.72:1, below
  the 4.5:1 normal-text floor, and the pair it replaced measured 4.23:1; the stopped screen's own line
  sits on the sheet in the paper's quiet role (D-070), so the card ground and ink are the question,
  not the room. Candidate
  remedies, all still open: paint the card's text with `--chrome` or `--ink`, choose a different
  ground, or keep the lines off the card.
- Reason: the `m3` card is visible copy in the default light theme at `#core`. Repainting the landing
  inside a Mac and stopped-screen change would widen the scope and pre-empt the captain's visual
  ruling, so the measured gap is recorded here as a bounded follow-up for that decision.
- Supersedes: none.

## D-072: The moment card's consequence line is ink; every moment-card text role is measured against its ground

- Date: 2026-10-27
- Decision: the landing's `Draft deleted.` line on the `m3` moment card paints in `--ink` instead of `--mute`.
  The measured pair moves from 3.72:1 to 11.27:1 in light and 5.03:1 to 11.00:1 in dark, both on `--red-deep`.
  The card ground, copy, size, weight and layout do not change. `writeitdown/qa/moments.spec.mjs` measures every
  text element on the three cards (writing, warning, deleted) against its own rendered ground at 1440 and 390,
  light and dark, with the WCAG floors: 4.5:1 for normal text, 3:1 for large text (24 px, or 18.66 px bold). The
  150 px warning numeral is large text, so its floor is 3:1; its dark-theme red on the warning ground measures
  4.47:1, which clears that floor but not 4.5:1, and is left for the captain to rule on rather than repainted here.
- Reason: the captain's standing rule is that basic polish is fixed without asking and no product text reads
  below its contrast floor. `--ink` is the token the card's headline already uses, and it clears the floor by a wide
  margin in both themes. `--chrome` would also pass (4.68:1 light) but leaves little margin and mixes a second text
  role into the card.
- Supersedes: D-071's colour clause (`--mute` for the consequence line) and its open list of candidate remedies. D-071
  held the colour until the captain decided; the captain's standing rule now decides it for this line.

## D-073: The Mac room carries D-069's Wheat paper, and the locked tone wins at the pixel on both surfaces

- Date: 2026-10-27
- Decision: The Mac room mirrors D-069, and both surfaces hold the locked tone at the pixel.
  1. **The Mac sheet is D-069's Wheat paper** with D-069's roles, read from the same values as the web's
     `tokens.css`: tone `#e9e2ce` / `#342e24`, quiet `#464746` / `#c2bfb7`, pen `#63140b` / `#ffc2b4`, wash
     `#e8cfbb` / `#e6bca7` and `#453226` / `#573428`, ink `#1c1917` / `#ece7d9`, grain 70 of 100 at size 1.00.
  2. **The history ladder is D-069's**, applied with D-027's stepping. Each completed line gets one opacity:
     the current line 1.0, one line up 0.847 (light) / 0.902 (dark), two lines up 0.769 / 0.772, older 0. The
     partial line at the aperture is clipped, not given its own alpha. The faded lines read at 9:1 and 7:1 or
     better on the paper. The ladder is solved per appearance, so the Mac editor re-steps every completed line
     when the appearance changes.
  3. **The locked tone wins over the renderer.** The lamp light and the dark settle are gone from the
     generator on both surfaces, and the texture's own mean is cancelled out of the base the sheet is drawn
     on. The pixels on screen therefore measure the locked tone, within two levels per channel, rather than
     the CSS or NSColor constant behind it. On the web the correction rides on the sheet's own tone token, so
     the wash still mixes from the corrected base.
  4. **The ink spread steps with the line.** The Mac's 0.35 pt ink spread is quantised to the line's ladder
     step (`inkSpread(step:)`, alpha 0.55 x step, never interpolated), so a faded line fades its whole
     rendered ink.
  5. **The alarm tints the same paper.** The Mac wash lays the sheet's whole texture in its own layer above a
     tint layer. A warn tick changes one layer colour and never repaints the texture. On exit the wash keeps
     its last tint while it fades over 120 ms. The Mac generator uses the web's seed string and pigments.
- Reason: The Mac had to become the same paper as the web once the captain chose Wheat (D-069). Measured on
  the rendered Mac field, the lamp light had lifted the dark sheet about 25 levels off the locked value.
- Tests: `PaperContrastTests` (Wheat tones and roles, the per-appearance ladder at 9:1 and 7:1 or better, the
  rendered field's mean against the locked tone, the wash mix), `EditorFocusTests`
  (`historyLadderFollowsTheAppearance`, `inkSpreadIsQuantisedToTheLineStep`),
  `RoomTests.warnTicksNeverRepaintThePaperTexture`, `SnapshotTests`, `tests/paper.spec.mjs` and
  `writeitdown/qa/paper.spec.mjs` (the sheet's tone measured as the rendered composite).
- Supersedes: D-069's note that the Mac keeps D-056's Note paper until its own change; the lamp light in the
  D-056 generator; the branch-only proposal to
  restore D-027's 100/22/7 values, which never shipped (D-027's stepping stands, D-069's values replace its
  alphas).

## D-074: The Mac kept screen takes D-062: the receipt owns the count and one caption says the draft is not saved

- Date: 2026-10-29
- Decision: On the Mac kept screen the receipt is the only owner of the count (`N MINUTES. M WORDS.`,
  singular `1 MINUTE. 1 WORD.`) and the corner count slot is hidden in that state; rest, typing, warning
  and wipe keep it. One caption, `Nothing here is saved. Copy it before you leave.`, sits under the
  action row in the kept block, centred on the block in the room's small caption type. The caption joins
  the fixed block above the draft and moves nothing else in it: the heading, receipt and action row
  keep their frames and only the flexible draft area gives way. The VoiceOver announcement on entering
  the kept state says the same sentence. The web room and the landing demo already did this under D-062,
  so the two surfaces match again.
- Reason: the captain's design review decided that the receipt keeps the count, the corner goes quiet
  and the caption ships on both surfaces with his copy. The Mac still printed the count twice and said
  nothing about the text living only in this window.
- Supersedes: the Mac half of case 39 in `docs/wid-mac-behavior.md`, which recorded the corner count
  beside the receipt, and D-062's scope sentence that the Mac still printed the count twice. D-030's
  receipt sentence, pill geometry and focus ring, and D-043's kept top block and draft scroll, stand.

## D-075: The Mac picker carries the web header's A mark chip

- Date: 2026-10-29
- Decision: The Mac picker's lockup is the chip-and-wordmark lockup the web header uses: the app icon's
  squircle plate around the split W, then the wordmark on the same baseline, in the header's 7.467 x
  1.046 em box at 21 px type (156.8 x 22 pt). The W and wordmark come from the web's own glyph layer
  (`writeitdown/logo/write-it-down-lockup.svg`, bundled byte for byte and asserted equal), so the
  two chips cannot drift. The plate is drawn natively in the page token with one 1 px hair-2 edge
  (22.33% corner radius); the W and wordmark are the ink token. The web header's sheet-token plate
  cannot carry over unchanged: it sits on the page wall, while the picker's lockup sits on the sheet
  card, where a sheet-token plate would vanish. The page token keeps the plate an object the writer
  can see in both appearances. The lockup stays the first item in the "How long?" card's content block,
  centred above the heading; the card's copy, controls and spacing do not change.
- Reason: the captain decided the Mac front door shows the mark the site shows. D-038 gave every shipped
  web page the mark in the corner but left the Mac picker with the wordmark alone, so the first surface
  a buyer sees carried no logo.
- Supersedes: D-038's clause that the Mac start screen keeps the wordmark-only lockup, and the
  `design/DESIGN.md` section 11 sentences that described the wordmark-only Mac lockup. D-036's
  placement inside the card, D-031's rules page and the social card's wordmark lockup stand.

## D-076: The Mac's review defects are fixed to measurement, and D-030's COPIED keeps the resting width

- Date: 2026-10-29
- Decision: seven Mac defects the full design review filed (`data/wid-design-review/report.md`, problems
  4, 5, 9, 10, 21, 24 and the D-030 note) are fixed as basic defects, each with an assertion that failed
  first (`DesignReviewFixesTests`):
  1. **The kept block sits on the sheet's axis.** The top block (headline, receipt, action row) spans the
     sheet's inner width, so its centre is the paper's centre at every window size; it used to size from its
     widest child and sat 43 pt right of the axis at 1040x720 and at 1600x1000 (the action pair 43.5 pt).
  2. **The writing line holds `RoomPresentation.paperAnchorFraction` for every draft length.** The caret's
     own line is scrolled onto the anchor after every layout, not only when a composition refresh was
     pending, and the top inset alone carries the first line to the anchor (the bottom inset that pinned the
     document is gone). A room laid out before its window exists - the kept and stopped captures - had left
     the line 89.5 pt (1040x720) and 90.1 pt (1600x1000) off the anchor. The anchor is D-070's 33%, not the
     35% the review quoted.
  3. **The licence card offers nothing it cannot complete.** With checkout unavailable no Buy is rendered;
     while a launch check or a key activation runs, Buy is disabled and the card says `Checking your key...`.
     The free route is the room's 48 pt outlined secondary, `Try the free web room`, with a hit area and the
     ink focus ring, not a 13 pt caption link.
  4. **Settings has one grid and names each control once.** Both boolean rows are label leading, switch
     trailing on the popups' right edge; the switch carries its row's name as its accessibility label, so
     `Fullscreen focus` and the updates row's duplicate title are gone.
  5. **The rules sheet follows the type scale.** Body is the scale's 15 pt on a 1.5 line box (22.5 pt) over a
     60-character measure; each rule title is 15 pt semibold, one step up in weight and never smaller than
     its paragraph (it was 13 pt over 15 pt body on a 480 pt measure).
  6. **The words follow the behaviour.** The picker line reads `Free trial: N of 3 sessions left, counted at
     the first character.` (the counter moves on the first nonempty input, not on opening the room), and the
     activation card reads `A license is required to keep writing on this Mac.` instead of claiming three
     sessions were used, which a licence-less state does not always mean. The free route is named for what it
     opens, the web room.
  7. **COPIED keeps COPY TEXT's width.** The copy pill hugs its label down to its resting width and never
     narrows, so RUN IT AGAIN stays where it was under the pointer (it moved 15 pt and the pill shrank 30 pt).
     This amends D-030's "COPIED is narrower" on the Mac the way the web already holds it (Q-24, D-060).
- Not done: the review's eighth Mac item, a caret on the wiped room, is superseded by D-070. The stopped
  group sits where the writing line was, the writing layer is transparent and no caret is drawn inside it;
  `RoundThreeTests` keeps asserting that. What stays asserted is that the insertion point a restart types at
  is the first-entry one (`wipedRoomRestartsOnTheFirstEntryInsertionPoint`).
- Reason: each was a measurable defect, not a taste call, and the review recorded the numbers.
- Tests: `DesignReviewFixesTests` (every case above, at 1040x720 and 1600x1000 where it is geometry),
  `SnapshotTests` (`rules-light/dark` joins the set), `RoomTests.copyButtonSwitchesToCopied`,
  `ReviewRoundTests.keptActionsShareOneOpticalCentreAndThePillFitsItsLabel`.
- Supersedes: D-030's COPIED-narrower clause on the Mac; the Mac's `Free trial: N of 3 sessions left.` and
  `After 3 free sessions, a license is required to keep writing.` strings.

## D-077: The history fades per logical line, and the first refused delete names the rule

- Date: 2026-10-29
- Decision: Two settled behaviours (captain, 2026-10-25), now identical on writeitdown.app and the Mac room.
  1. **The ladder's unit is the logical line.** A logical line is a sentence, or the text up to a hard line
     break (Unicode sentence rules: `Intl.Segmenter` on the web, `NSString` `.bySentences` on the Mac). Every
     visual row of one logical line carries one opacity: the live line 1.0, one back 0.847 light / 0.902 dark,
     two back 0.769 / 0.772, older 0. The values are D-069's and are unchanged; D-073 already applied them
     with D-027's stepping, and this decision only changes what a step is applied to. A trailing hard break
     puts the writer on a fresh empty line, so every written line sits one rung further back. The partial
     line at the aperture is clipped at its edge, never given an alpha of its own: the web aperture is one
     hard mask at the third pitch (no gradient), the Mac aperture is the scroll view's own clip. A sentence
     that ends mid-row keeps one rung on each side of its boundary. The rule reads the text only, so a width
     change never re-steps a line (the Mac's per-resize re-step is gone).
  2. **The first refused delete of a session names the rule.** The 200 ms shake stays on every refusal. The
     first refused delete of a session (Backspace or Delete, a word, line or paragraph delete, or the delete
     input types a touch keyboard sends) also shows `FORWARD ONLY. DELETING IS BLOCKED.` in the footer's
     status slot for two seconds, in the quiet role (`--paper-quiet`, 7:1 on the sheet, which clears the 4.5:1
     floor), then the slot returns to what it held. Later refusals in the same session shake only. A session
     that ends (wipe, kept, a new start) earns its own notice. Paste, cut, undo and caret moves only shake. An
     armed exit confirmation keeps the slot and the notice waits unspent, because the confirmation is the
     writer's pending decision. The slot is the exit confirmation's own footer slot, so nothing moves: the
     frames of the exit link, the count, the clock, the paper and the writing layer are unchanged while it
     shows and after it goes.
- Reason: A long sentence that wraps read as a staircase of greys, which says "different lines" about one
  thought. The refusal was silent beyond a shake, so a writer who did not know the rule had no sentence to
  read; once per session teaches it without nagging.
- Web mechanism: the textarea keeps the input, the caret and the IME and its glyphs are transparent; an
  `aria-hidden` ink layer above it repeats the draft with one span per logical line at its rung and draws the
  composition underline. Both share one box, font and wrap, and scroll together.
- Tests: `writeitdown/qa/history-fade.spec.mjs` (rows of one line share one measured opacity in the DOM and in
  the pixels; the ladder per theme and 7:1 per step; a mid-row sentence boundary; the hard-clip aperture;
  first-versus-later refusal, the 2 s duration, the reset, the colour and no layout shift at 1440 and 390,
  both themes, motion and Reduce Motion), `writeitdown/session.test.mjs`, `HistoryLinesTests`,
  `EditorFocusTests` (`restoredDraftKeepsOneOpacityPerSentenceAcrossResize`,
  `theAperturePartialLineIsClippedNotFaded`), `RoomTests` (first refused delete and its two seconds, the
  reset, delete-only, the exit confirmation), `SessionEngineTests`.
- Supersedes: D-027's per-visual-row unit (its stepping, one-pitch shift and the retired gradient stand) and
  D-046's "visual only" refusal (the shake, the hairline, the live-region line and the absence of sound
  stand). D-069's ladder values are cited, not changed.

## D-078: writeitdown.app carries an Impressum, linked from every footer

- Date: 2026-11-03. Captain approved the operator details ("ok 那 就用吧").
- Decision: the site ships `impressum.html` on the shared document shell with four labelled fields only:
  Operator `Ian Zhou (Trefoil Studio)`, Address `Balsahout 4, 2719 MJ Zoetermeer, Netherlands`, Email
  `contact@trefoilstudio.com`, and `Responsible for content (§ 18 MStV)` `Ian Zhou` at the same address. The
  Legal footer column on every page gains an `Impressum` link after Terms; the page is in the sitemap,
  `llms.txt` and `install.sh`.
- Reason: the licence checkout sells to Germany, where a provider must name itself and an address. No KvK
  number, VAT id or phone number exists, so none is written.
- Tests: `writeitdown/qa/impressum.spec.mjs` (exact fields, footer link on every page, measured footer
  geometry at 1440 and 390).
- Supersedes: nothing. The site is English only; a German or Italian page would use `Niederlande` or
  `Paesi Bassi` for the country word.

## D-079: The site's radii sit on a 4 px grid and nest as R - p, and headings, text and corners get shared CSS switches

- Date: 2026-11-02
- Decision: Web only (`writeitdown/site.css`, `tokens.css`; the Mac app is untouched). Every radius on a shipped
  page is on the 4 px grid and at least 4 px, or a pill or circle. `--r-card` is 24 px (was 22), the key caps use
  `--r-ctl` 8 px (were 10), and the phone demo sheet keeps `--r-sheet` 16 px like the room sheet (was 14 below
  768 px). A panel padded `p` inside a card of radius `R` takes `max(4, R - p)`: each card that owns panels
  declares its padding as `--pad` and derives `--r-panel` from it, so the SHA-256 panel, the install command and
  the license key are 4 px at their current paddings (were 8) and 12 px in the 12 px-padded download card on a
  phone below 365 px. Headings (`h1` to `h3`) use `text-wrap: balance`, paragraphs and list items
  `text-wrap: pretty`, button labels are `nowrap`, and the price and the price facts declare tabular figures.
  Continuous corners are progressive enhancement: under `@supports (corner-shape: superellipse(1.25))` every box
  takes `superellipse(1.25)` and every pill and circle `round`; browsers without it show the plain radius.
- Kept as they were: the two writing sheets keep their own text wrapping (`wrap`), so the anchor, the stopped
  group and the kept screen do not move (D-070, D-077); the download head keeps its `Write It Down` / `for Mac`
  break, so balance is off on it (D-060); the header chip keeps its drawn 22.33% squircle and `round` corners
  (D-038, D-075); the EXIT control stays square (D-059); the room sheet's 16 px radius value is D-004's, only its
  curve changes; the 2 px strike bar on the key caps is a stroke, not a box. Paddings off the 4 px grid
  (`.dlbox` at 22 px between 365 and 820 px, the 14 px and 12 px panel paddings) are left alone: moving them
  changes the width the hash halves and the command wrap against (D-060).
- Reason: the radii had drifted (22, 10 and 14 beside a 4 px scale), a small panel in a large card kept the same
  radius whatever its padding, and headings could end on one lonely word. The rule is one relation that a test
  can measure. Newsreader's default figures are already tabular, so the serif numbers only declare it; the
  system sans is proportional by default and carries it on the clock, count and numeral.
- Tests: `writeitdown/qa/shape-text.spec.mjs` (computed `text-wrap-style` on all twelve pages, the sheets and the
  download head excluded, radii on the grid and at least 4, pills `round`, nested `r = R - p` at 1440, 700 and
  360 px and on the license card, digit widths with a proportional negative control, `nowrap` and one-line labels
  at 320 px, no `line-break: anywhere` or `word-break: break-all`).
- Supersedes: no recorded decision. D-004's "corner radius" is cited, not changed.

## D-080: A Mac running Write It Down 1.0 has no updater, so 1.0 to 1.1 is a manual reinstall

- Date: 2026-11-04
- Decision: Write It Down 1.0 shipped with no updater of any kind, so 1.1 cannot and does not reach
  an installed 1.0. Read from the installed 1.0 bundle (8,117,026 bytes, SHA-256 `5b8483bd…`, the
  build the public page served, compiled from `de522b0`): `Contents/Frameworks` does not exist, so
  there is no Sparkle framework; the executable carries no `Sparkle`, `SUFeedURL`, `SUUpdater` or
  `appcast` string (`otool -L` and `strings -a`, zero matches); `Info.plist` holds 15 entries with
  no `SUFeedURL`, no `SUPublicEDKey` and no `SUEnableAutomaticChecks`; the app menu has no
  `Check for Updates…`; Settings has no Updates section. `Package.swift` at `de522b0` has no
  Sparkle dependency, which enters in `13f214e` for 1.1. With 1.0 running from `/Applications` for
  six minutes, the wire recorded 294 packets and every one was Apple system traffic;
  `writeitdown.app` (95.216.150.141) was never resolved and never contacted. So 1.0 -> 1.1 is a
  manual reinstall: a 1.0 user downloads `Write-It-Down-1.1.dmg` from
  `https://writeitdown.app/download/` and replaces the app, and nothing reaches a 1.0 installation
  automatically. The feed is healthy and 1.1 reads it correctly, so this is a fact about the 1.0
  client, not a feed fault: `https://writeitdown.app/download/appcast.xml` answers 200 signed with
  build 2 / 1.1, and 1.1's `Check for Updates…` fetched it over TLS and reported `You're up to
  date!`. D-041's sentence "the first automatic delivery lands with 1.2" is accurate as a
  statement about 1.2 and about nothing else: 1.2 is the first release that can install itself, and
  it can only install onto an installation already running 1.1. 1.1 is a build every existing user
  gets by hand. The half of D-041 that did ship is the release note: PR 101 merged as `9cb2827`
  repoints `/download/` to `Write-It-Down-1.1.dmg` and publishes `Version 1.1. A free update for
  the app you already own.` on `/download/` and `mac.html`, which is the mechanism D-041 promised.
  At the time of this entry the live URL still answered with the 1.0 page (`last-modified`
  2026-11-03), so the note reaches users with that site deploy bundle, not with the merge.
- Reason: the log described a delivery path the shipped app cannot take, so read in sequence it
  promised 1.0 users an automatic 1.1 that no code on their Mac could receive, while the download
  page was the only real path all along. Naming the two apart keeps the record usable: 1.0 is a
  manual reinstall, 1.2 is the first automatic delivery, and D-041's opt-in default, its
  signed-feed and key rules and its room rules were never the problem and do not change. Evidence:
  the 2026-11-04 upgrade run in `data/wid-upgrade-vm/report.md`, with captures 01 to 11 and
  `logs/net-1.0-six-minute-window.pcap`.
- Supersedes: D-041's delivery-path sentence ("1.0 users learn about 1.1 from a release-notes line
  on the download page; the first automatic delivery lands with 1.2") as a description of how 1.1
  reaches a 1.0 user. Its opt-in default, its signed-feed and key rules and every room string,
  geometry and motion rule stand.

## D-081: The 1.0 download stops being a current download without breaking the links that point at it

- Date: 2026-11-05
- Decision: `/download/` keeps 1.1 as its only current download (D-080's repoint, unchanged) and
  gains one quiet line under the requirements, `#previous-version`, that reads `Previous version:
  1.0.` `A 1.0 installation cannot update itself.` and links the archived copy at
  `/download/releases/Write-It-Down-1.0.dmg`, whose filename is the link text. The line is not a
  second download: it is 13 px muted text on the card's content edge, its link is an inline
  underlined filename that never breaks across lines, and it names no other version. The two
  retired host addresses `/download/Write-It-Down-1.0.dmg` and
  `/download/Write-It-Down-1.0.dmg.sha256` answer `301` to `/download/`, so an old link lands on
  the page that offers 1.1. `/download/releases/*` is served from the site directory as the archive;
  that directory is a host file, never committed and never in the deploy bundle, and `install.sh`
  neither creates nor prunes it. The archive note is not one of the page's version facts: a publish
  moves the DMG link, the Install command, the two SHA-256 halves and `#release-notes`, and leaves
  the archive note alone. `release-check.mjs --download` refuses an archive link that is not
  `releases/Write-It-Down-<version>.dmg` or not older than the linked download.
- Reason: measured on 2026-11-05, three weeks after 1.1 shipped, `https://writeitdown.app/download/
  Write-It-Down-1.0.dmg` still answered `200 application/x-apple-diskimage` with
  `content-length: 8117026`, while the page beside it had offered `Write-It-Down-1.1.dmg` since
  `9cb2827`. A 1.0 bundle has no updater at all (D-080), so every install that followed the old
  link is stranded on a build nothing can update. Deleting the file or letting the address 404
  breaks the pages, mail and forum posts that still link to it; a rewrite that keeps serving 1.0 as
  a download keeps producing stranded installs. The 301 sends the visitor to the page that offers
  1.1, and the archive keeps the exact build reachable for someone who needs to reproduce or match
  it, without the page presenting it as current. Evidence: the live probes, the Caddy v2.6.2 delta
  validation and the before/after route matrix in `data/wid-dmg-10-retire/report.md` and `lab/`, and
  the browser pass in `writeitdown/QA.md` ("2026-11-05: The download page keeps 1.1 current and
  archives 1.0"). The host rules are handed over as a delta and are not applied by this change.
- Supersedes: no recorded decision. It carries out the consequence D-080 records for the download
  address; D-080's reading of the 1.0 build, D-041's opt-in update rules and every room rule stand.

## D-082: The Mac carries the standard Edit menu, and ⌘C keeps both of its meanings

- Date: 2026-11-05
- Decision: The Mac app's main menu gains a standard Edit menu between the app menu and Navigate: Undo
  ⌘Z, Redo ⇧⌘Z, Cut ⌘X, Copy ⌘C, Paste ⌘V, Select All ⌘A. All six are nil-target items, so AppKit
  validates each one against the responder chain and only the responder that can perform the command
  lights it up. The window controller implements `undo:`/`redo:` by forwarding to the first responder's
  own undo manager, which is what makes the standard Undo item live in a text field. The Navigate item
  `Copy Kept Text` keeps ⌘C and its explicit target.
- Reason: 1.1 built only the app menu and Navigate. AppKit delivers every standard editing command
  through a menu item carrying that key equivalent, so on 1.1 the licence field accepted typing and the
  mouse but not the keyboard: ⌘V, ⌘A, ⌘C, ⌘X and ⌘Z were dead in the field the buyer types a key into,
  while right-click - Paste worked because that menu comes from the text system itself. The captain hit
  exactly that on the published 1.1 DMG. Reproducing it in a Tart VM with real HID keys (captures 02 to
  12 in `data/wid-cmdv-bug/captures`, report at `data/wid-cmdv-bug/report.md`) showed the same field
  taking a right-click paste and ignoring ⌘V, and a TextEdit control taking the same keys in the same
  guest, so the rig was sound and the app was the fault.
- Two meanings of ⌘C, resolved by the responder chain, not by a special case: in the writing room the
  append-only editor refuses cut, copy, paste, select-all, undo and redo, so the Edit menu's items are
  greyed and ⌘C does nothing while a draft is live; in the kept phase the same editor is not editable,
  so it forwards `copy:` up to the room, which runs Copy Kept Text. The Navigate item still serves the
  writers who reach for the menu bar. One key, two phases, no shadowing and no second code path.
- Rejected: fixed-target Edit items (a fixed target is never in the field editor's responder chain and
  so never receives `paste:`); a validation-only menu delegate (it cannot know which responder will have
  focus when the key is pressed, which is what nil targets exist for); fixing the licence field alone
  (the activation card carries the same field, and the next text field would inherit the bug).
- Supersedes: none. The room's keyboard contract (cases 1 to 70) is unchanged: typing appends, every
  editing command is refused, and the denial choreography still answers a blocked delete.
- Evidence: `apps/macos/FirstLine/docs/MANUAL_QA.md` (2026-11-05 entry) with the VM run against an
  ad-hoc build of this branch: `final-01-edit-menu.png` (Undo Paste enabled, Paste and Select All
  enabled, Cut and Copy greyed with no selection), `proof-02-selected.png` (⌘V pasted and ⌘A selected a
  key), `proof-03-activated.png` (the pasted key activated the Mac), `final-02-cmdz.png` and
  `final-03-redo.png` (⌘Z and ⇧⌘Z over a replaced key), `final-07-room-edit-menu.png` (all six items
  greyed in the live room) and `final-08-kept-copied.png` (⌘C in the kept room wrote the draft and the
  action read COPIED). Bound tests: `EditingCommandTests`.
## D-083: The payoff screen carries one quiet route to the app

- Date: 2026-11-05
- Decision: the web room's kept screen carries one link directly under the COPY TEXT / RUN IT AGAIN pair,
  its text exactly `Mac app`, its target `download/?from=kept` in a new tab with `rel="noopener"`. It sits
  in the quiet role (`--paper-quiet`, 13 px/500 sans, 1 px underline, a 44 px tap row), so it is clearly
  lighter than the ink pill above it and adds no component, colour, caption or arrow. It appears on the
  kept screen only, never on the writing, warning or wipe screens, and it costs the pair nothing: the
  action row's measured box is the same with the link in flow and taken out of it (`qa/phase4.spec.mjs`,
  "the kept screen offers one route to the app, and the writing screen none"). A sheet that cannot hold
  both the row and one line of the returned draft keeps the draft's line and drops the row
  (`data-kept-app="false"`, decided in `status-slot.js` from the layout it already measures), where the
  header pill or the phone exit-row Mac link still offers the app. The Mac kept screen does not gain the
  row; D-062's one-step-behind rule stands. The link text becomes `Mac and Windows app` when the Store
  listing is live; nothing else about the row changes.
- Reason: the kept screen is the one moment a stranger has felt the product work, and it offered no route
  to the app at all: COPY TEXT and RUN IT AGAIN were its only controls, so the moment of value ended in a
  dead patch of paper. The link is lighter than the pair because it is an offer, not the session's next
  act, and it is the first thing to yield when space is short because the writer earned the draft and
  nothing else on that screen. Measured (real Chrome, `data/wid-kept-app-link/`, kept through the real
  deadline): the pair's box is unchanged at both widths before and after the change (1440: top 241.59,
  left 564.28, 311.44x48; 390: top 215.98, left 43.28, 303.44x48); the row adds 50 px under it and keeps
  the draft's line at 1440 (413 px scroll), 390 (370 px) and every sheet down to 320x568 and 844x390,
  where the row itself steps out and the 44 px tap target would have crushed the draft to 23.6 px of a
  33.6 px line. The href is relative (`download/?from=kept`) like every other Mac link on the page: it
  resolves to `https://writeitdown.app/download/?from=kept` from the room's route and stays checkable by
  the suite's site-wide link gate, which cannot serve an absolute root path under `/writeitdown/`.
- Supersedes: no recorded decision. It adds to D-062's kept screen; D-062's receipt, silent corner count,
  not-saved caption and one-step-behind Mac rule stand.

## D-084: The Mac's light quiet grey on the sheet is warm

- Date: 2026-11-06
- Decision: on the Mac the light `paperQuiet` role (clock, count, exit link, receipt, kept note, notices)
  changes from `#464746` to `#48443E`. Nothing else changes: the dark role `#C2BFB7`, the ink, the pen
  red, the history ladder and the wash keep their values. The Windows tokens are generated from the Mac
  sources (`apps/windows/scripts/gen_tokens.py`), so Windows follows in the same change. The web
  (`tokens.css`, the landing demo, the trial) keeps `#464746` until the same change is decided there; the
  web parity of this one role is a follow-up.
- Reason: the Mac design audit (rule 6, warm greys only) found `#464746` the one cool grey on the Wheat
  paper. `#48443E` keeps the red-green-blue order of the paper's own tone, and it reads 7.47:1 on
  `#E9E2CE` (was 7.21:1), so the 7:1 floor of D-069 holds with more margin. Bound tests:
  `PaperContrastTests.theLightQuietGreyIsWarm`, `everyTextRoleClearsSevenToOneOnTheSheet`.
- Supersedes: D-069's light quiet value `#464746` on the Mac only; D-069's contrast floor stands.

## D-085: One verb for beginning a session, one noun for what the buyer types

- Date: 2026-11-06
- Decision: starting a writing session is `Begin`, and starting another one is `Begin again`, on the
  Mac, the web and Windows. `RUN IT AGAIN` becomes `BEGIN AGAIN` (the kept screen keeps its capitals),
  the Navigate menu's `New Piece` becomes `Begin`, the licensed card's `Start writing` becomes `Begin`,
  the web trial's `Run it again` link becomes `Begin again`, and the empty-room prompt `Type to start`
  becomes `Type to begin` (the wipe line's `Type to restart.` becomes `Type to begin again.`). What the
  buyer types into the activation field and Settings is a license key: the field label, the one placeholder,
  the empty-field and checking feedback and the access status lines all say `license key`. `Order number`
  stays on receipts and in support and is never the label of the input.
- Reason: the Mac design audit (rules 3 and 8, rows 2, 6, 24) counted six to eight verbs for one action
  and five nouns for one object. The ruling is a substitution of those words; no sentence is new. The
  accessible name `Begin writing` on the picker button already uses the one verb and stays.
- Supersedes: the wording (not the behaviour) of D-059, D-062, D-070 and D-076 where they name
  `RUN IT AGAIN`, `Type to start` or `Checking your key…`; their geometry and behaviour stand. Error
  prose, the trial line and the rules copy are not part of this decision.

## D-086: Errors, status lines, the trial line and the rules sheet say one plain thing each

- Date: 2026-11-06
- Decision: every license error and every license or trial status line is one plain sentence that says what
  happened and then what to do, with no HTTP code and no vendor name (for example `We could not connect, so
  check your internet connection and try again.`). The picker's trial line is `N free sessions left.`
  (`1 free session left.`), with no clause about when a session is counted. The rules sheet loses its lead
  line, and its three rules read `No way back` / `You can only add the next word.`, `Silence deletes it` /
  `Stop for N seconds and the draft is deleted.` (N is the picker's silence limit on the Mac and Windows,
  8 on the web) and `Reach zero, keep it` / `The text is yours to copy.` The activation card names its field
  with the label `License key` and drops the placeholder; Settings keeps its one placeholder. The revoked
  line is `This license is no longer valid, so enter a different license key.` The web's three How it works
  cards carry the same titles and bodies. The three helper lines on the activation card stay for now.
- Reason: product-design rules 2 and 3. The picker, the room and the kept screen already show what the
  removed sentences explained (the first typed character spends a session, blocked keys refuse themselves,
  the kept screen says nothing is saved), and the old rule titles hard-coded eight seconds while the picker
  offers 5, 8 and 12. The captain approved the sentences on 2026-11-06.
- Supersedes: the wording of D-085's exclusions and of D-076 items 5 and 6 (the trial line and the rules
  sheet) and the one-placeholder-on-both-surfaces rule of the Mac audit's activation fixes (#111: the card
  now has a label and no placeholder). Behaviour and geometry stand.

## D-087: The session bar is the paper's rounded top edge, not a straight bar inside the corners

- Date: 2026-11-07
- Decision: the 2 px session bar on web (room, demo) and Mac is the sheet's own top border: it follows the
  16 px corner arcs and tapers to the side edges, and the remaining time reveals it from the right with a
  clip (web `clip-path: inset(0 R% 0 0)`) or a width mask (Mac), so the curve never stretches. A full bar
  touches the card edge at both ends. Thickness, colour, linear timing, direction and the one-bar rule are
  unchanged.
- Reason: a straight 2 px bar clipped inside rounded corners starts and ends short of the card edge, so
  the bar looks like it never reaches the end (captain, 2026-11-07).
- Supersedes: the "straight 2 pt bar" shape in D-014; the bar's box is now the corner radius tall, only the
  top 2 px paint.

## D-088: The history fades per line ended by Return, never per sentence

- Date: 2026-11-07
- Decision: the history ladder's unit is the line the writer ended with Return, on writeitdown.app, the Mac
  room and the Windows room. A line is the text up to a hard break (LF, CRLF or a lone CR; the break belongs
  to the line it ends). A wrapped line is still one line, so every visual row of it carries one opacity. A
  full stop, a question mark or a CJK stop ends nothing: no sentence segmentation exists on any surface
  (the sentence cuts, `Intl.Segmenter` sentences and `NSString` `.bySentences`, are gone; the word count keeps its word segmenter). The ladder values are unchanged (live 1.0, one
  back 0.847 light / 0.902 dark, two back 0.769 / 0.772, older 0), as are the clip at the aperture, the one
  pitch shift, and a width change never re-stepping a line. A trailing hard break puts the writer on a fresh
  empty line, so pressing Return fades the line just written one rung and nothing fades before it. A blank
  line is a line. D-077's second item (the first refused delete names the rule) stands unchanged.
- Reason: the captain, 2026-11-07: the fade is per line and Return triggers it; nobody told the room to count
  sentences. Three sentences typed on one line read as one thought in the writer's hand, and a row that
  dimmed before the writer pressed Return said the room had decided where the line ended.
- Supersedes: D-077 item 1 (the logical line as "a sentence, or the text up to a hard break") and its
  mechanism note that the web cuts with `Intl.Segmenter`; D-073's per-sentence application. Case 48 of
  `docs/wid-mac-behavior.md`, Q-34 of `docs/ui-quality.md`, and row 19 of `apps/windows/SYNC.md` carry the new unit.
- Evidence: `writeitdown/session.test.mjs`, `writeitdown/qa/history-fade.spec.mjs`,
  `HistoryLinesTests`, `EditorFocusTests.returnFadesTheLineJustWrittenAndAFullStopDoesNot`,
  `apps/windows/session/lines_test.go`: the same cases on the three surfaces.

## D-089: The silence digits are placed from the live caret line each time they show

- Date: 2026-11-07
- Decision: on the Mac the 3-2-1 numeral and its caption are positioned from the caret's current line every
  time the warning phase draws them, not only from the last layout pass.
- Reason: on macOS 15.6.1 (the captain's Air, two recordings) no layout pass ran after the first warning
  second, so the digits kept the placement of an empty room at width 0, about 700 pt down and off the paper. The
  paper tinted and the draft was deleted with no digits on screen. macOS 26 happened to relayout and hid it.
- Supersedes: nothing; D-025's placement under the caret line is unchanged and now holds on both systems.
- Evidence: `RoomTests.silenceCountdownSitsOnThePaperUnderTheWritingLine` (fails on the old code), and a Tart
  macOS 15.7.7 run: numeral at y 812 before, 377 after, visible under the writing line.

## D-090: Glyphs are never filtered, and the web room's footer is one type style

- Date: 2026-11-07
- Decision: no element that carries words (the home demo, the trial room's input and ink layer, its headings,
  the kept text) takes a CSS filter, an SVG displacement or a text stroke on writeitdown.app or the Zero Draft
  landing. The ink is the colour and nothing else. The web room's footer is one style: the left label, the
  count and the phone's Mac link are 13 px / 400, no tracking, sentence case, one baseline. The left label
  reads `Esc to exit` (`Exit` on touch input).
- Reason: the captain, 2026-11-07, twice: the typed words warp on the paper, and the footer's two sides look like
  two sizes. Cause of the warp, measured by switching one property at a time in Chrome and Safari at 1x and 2x:
  the SVG `feTurbulence` + `feDisplacementMap` (2 px) that D-056 put on the writing layer bends every glyph
  outline; the 0.14 px stroke, the `translateY(-50%)` on the writing area and the aperture mask change nothing visible.
  The footer was 13 px / 500 / +4 % tracking in caps on the left and 11 px / 500 on the right.
- Supersedes: D-056's "ink imperfection on" (the 2 px displacement and the hair of stroke); the caps `ESC - EXIT`
  and `EXIT` labels and the 13/500 +4 % footer link on the web. The Mac and Windows rooms keep `ESC - EXIT` until
  their own change.
- Evidence: `writeitdown/qa/ink-footer.spec.mjs` (fails on the old code: a displacement filter on the writing
  layer, and two footer labels with different computed metrics); before/after 200 % crops in
  `data/wid-ink-warp/before-after.pdf`.

## D-091: The picker's help control is a quiet 32 pt circle on the logo row

- Date: 2026-11-07
- Decision: the `?` that opens the rules sheet is a 32 pt circle button with a 1 pt hairline outline (the
  secondary pill's), drawn in ink. Its centre sits on the logo lockup's centre line and its right edge sits
  flush with the card's inner padding. Hover fills it with 6% ink, press with 12%; keyboard focus draws the
  ink ring around the circle. The label stays `How it works` and no new copy exists. The Mac picker and the
  Windows picker carry the same control; the web trial has no picker.
- Reason: the captain, 2026-11-07: the `?` was not aligned and had no button mark, it just floated. Measured
  on a real window it sat 3 pt under the logo row's centre line and 11 pt inside the padding, with no outline,
  and its quiet chrome colour read 5.8:1 in dark. He chose this over an underlined "How it works" link in the
  card's last row (which would add 36 pt of card height) after the options round in PR 122.
- Supersedes: the placement and look of the control in D-031 (a small quiet `?` at the card's top-right);
  D-031's rules sheet, wording and order stand.
- Evidence: `PickerHelpButtonTests` (32 pt, 0 pt off the logo centre line and the padding, hit test, ink 7:1 in
  light and dark, focus ring), `TestHelpButtonSitsOnTheLogoRowAndTheCardPadding` on Windows, and Tart
  macOS 26.6.2 and 15.7.7 before/after captures in the PR.


## D-092: The history is dimmed to .22 and .07 and dissolves over 320 ms when Return lands

- Date: 2026-11-07
- Decision: option B of the zen-fade prototype (PR #119) on writeitdown.app, the Mac room and the Windows room.
  The unit stays D-088's: the line ended by Return, every visual row of a wrapped line one value. The values
  are the prototype's: the live line 1, one line back .22, two back .07, older lines 0, in light. Dark takes the
  same contrast on its own paper: .16 and .05 (ink `#ece7d9` on `#342e24`), which read 1.57:1 and 1.15:1 exactly
  as .22 and .07 read in light (`#1c1917` on `#e9e2ce`). When Return moves a line to its next step, the line
  dissolves there over 320 ms with CSS `ease-out` (`cubic-bezier(0, 0, .58, 1)`: the web transitions
  `opacity`, the Mac and Windows rooms step the same curve per frame), so the lines above melt into the
  paper; a line that is new, a restored or rebuilt draft, a theme change and Reduce Motion take the step at
  once. The live line, including every wrapped row and any marked IME text, stays full ink. The aperture
  keeps its hard clip and the one-pitch 180 ms shift.
- Footer parity (carried from D-090, same wording and style, not re-decided): the Mac and Windows rooms' left
  footer label reads `Esc to exit` (they have no touch variant) and the whole footer row, the label, the status
  slot and the count, is 13 pt regular, no tracking, sentence case, replacing `ESC - EXIT` at 13 / 500 +4 %.
- Contrast exception: the dimmed history lines are exempt from the 7:1 text-on-paper rule. Only the live line,
  the quiet chrome and the pen red answer to 7:1. The history exists to be passed, not read.
- Reason: the captain, 2026-11-07. First he picked C of the prototype (one flat dim, 120 ms), then
  changed to B (`会对 我感觉 专注模式 B 方案比 C 好`): the lines above should dissolve gradually into the paper
  with the older line fainter, not drop to one grey.
- Supersedes: D-088's "ladder values are unchanged" (0.847 / 0.902 and 0.769 / 0.772 are gone) and the
  instant step it described; D-077 and D-069 for the history values and the 9:1 / 7.1:1 floor on them (D-069's
  7:1 floor for every other role stands); D-027's 22% / 7% gave the first values and this puts them back, with
  the dissolve. The countdown bar (D-087) and D-089 are untouched.
- Evidence: `RoundThreeTests.exitHintSharesTheExitRowBaselineAndTypeStyle` and `RoomTests` (the footer parity); `writeitdown/qa/history-fade.spec.mjs` (Return starts a 320 ms opacity transition; each Return
  line measures exactly 1 / .22 / .07, .16 / .05 dark), `writeitdown/qa/paper.spec.mjs`,
  `EditorFocusTests.returnStartsTheDissolveOfTheLineJustWrittenAndAFullStopDoesNot`,
  `EditorFocusTests.everyReturnLineGetsExactlyItsStep`, `PaperContrastTests`,
  `apps/windows/room` `TestReturnStartsTheHistoryDissolve`.

## D-093: The dark sheet is flat warm charcoal with one fine grain

- Date: 2026-11-07
- Decision: the dark writing sheet is the flat `#342e24` with a single very fine per-pixel grain, peak +-3
  levels (luminance sigma about 1.1), and nothing else: no mottle, no pulp cloud, no fibres, no flecks. The
  light Wheat sheet is unchanged. The web, the Mac and the Windows renderers paint the same dark sheet.
  The ink and quiet roles clear 7:1 against the brightest pixel the grain paints (ink `#ece7d9` 10.4:1,
  quiet `#c2bfb7` 7.0:1), not only against the mean.
- Reason: the captain, 2026-11-07: the dark paper's texture looked strange. Measured on the shipped dark
  sheet, the mottle (9 and 4.5 levels at 34 px and 9 px cells) and the brown flecks read as blotchy brown
  stains (32 px blocks vary by 1.7 levels, grain sigma 4.8) and lifted single pixels to 5.2:1 for the ink and
  3.5:1 for the quiet role. He picked option A from three candidates (A fine grain, B flat, C the light recipe
  at a fifth of the contrast) in the evidence round, https://github.com/ichts/zerodraft/pull/121.
- Supersedes: D-056's and D-069's two-scale mottle, fibres and flecks on the dark sheet only (the dark "lift"
  that scaled them to 0.4, 0.32 and 0.22). The tone `#342e24`, D-073's locked mean and the light sheet stand.
- Evidence: `PaperContrastTests.theDarkSheetIsFineGrainWithNoBlotchesAndEveryPixelClearsSevenToOne`,
  `writeitdown/qa/paper.spec.mjs` (the dark-sheet test fails on the old code: a 22-level lift),
  `TestDarkSheetIsFineGrain` on Windows, and Chrome 1x/2x plus macOS 26.6.2 and 15.7.7 before/after
  captures in `data/wid-dark-paper/final-before-after.pdf`.
## D-094: `Esc to exit` in the room footer is a real quiet text button

- Date: 2026-11-07
- Decision: the label stays quiet text in the footer's one type style, but on the web, the Mac and the Windows
  room it is a real button named `Exit`. A click or press does what Esc does (the same two-act confirmation), the
  hover moves only its ink from the quiet role to the full ink, the keyboard focus draws the ink ring, and its hit
  area is at least 44 pt tall. Hover and focus never move the label.
- Windows detail: while a draft is being written, Tab stays swallowed (a stray Tab must never take the keyboard
  off the draft), so the button is reached by pointer or assistive technology there. On the kept screen, where no
  editor is live, Tab walks Copy, Begin again and Exit. The room's pointer handler now lets presses on any button
  through to it, which the stopped and kept pills also needed.
- Reason: the captain, 2026-11-07: the label should be a button, not a decoration. D-090 and D-092 fixed its
  words and style; this gives it the behaviour its look promised.
- Supersedes: nothing; D-090's footer style and D-092's footer parity stand.
- Evidence: `writeitdown/qa/ink-footer.spec.mjs` (hover ink, 2 px ink outline, 44 px target, click and Esc share the
  confirmation), `RoomTests.exitHasAQuietHoverInkFocusAndAFullHeightHitTarget`,
  `RoomTests.clickAndEscapeShareOneConfirmation`, `apps/windows/room` `TestExit*` and `TestTabNeverTakesTheDraftsKeyboardWhileWriting`.
## D-095: The result screen is sentence case, and a Chinese or Japanese draft counts in characters

- Date: 2026-11-07
- Decision: the kept screen's receipt, its two actions and the copy states read as sentences on the Mac,
  Windows and web room: `5 minutes. 63 words.`, `Copy text`, `Copied`, `Try copy again`, `Begin again`.
  One count rule holds on the Mac, Windows, the web room and the root landing trial. The number: each Han,
  Hiragana or Katakana character (and the prolonged sound mark) counts 1, every other script counts one per
  Unicode word run, punctuation and emoji count 0. The label: it says `characters` (`1 character`) only
  when CJK letters are at least half of the draft's letters and digits, otherwise the unchanged `words`
  (`1 word`). So `hello world 中文测试` stays `6 words`, an English essay with one quoted `你好` stays words,
  a Chinese or Japanese draft reads characters. Hangul is not CJK here: Korean separates words with spaces,
  so it counts and reads as words. The root trial changes only its count and the unit in its receipt and
  corner (`0:00 - 3 characters kept.`); its other copy is untouched. The count tooltip text is unchanged.
- Reason: the caps receipt and buttons shouted at the one quiet screen of the product, and a Chinese draft
  of 40 characters read as `6 words` or `14 words`, a number the writer cannot check against what they wrote.
  A contains-any rule would have turned one quoted `你好` in a long English draft into a letter count.
- Supersedes: the caps wording of D-059, D-074 and D-076 where they name `COPY TEXT`, `COPIED`,
  `BEGIN AGAIN` or `5 MINUTES. 63 WORDS.`, and D-023's Han-only count (kana now count one per character
  instead of one per run, so the label never sits on a word-run number). Their geometry and behaviour stand.


## D-096: The picker has no title, and Begin shows the paper before it builds it

- Date: 2026-11-07
- Decision: (1) The picker's `How long?` heading is deleted on the Mac and on Windows. The card opens with the
  lockup row, 32 pt (Windows 28 DIP) above the `Minutes` label, which now carries the meaning alone. The web
  trial has no picker. (2) Begin shows the room's paper within 100 ms of the click. The picker renders the room's
  sheet (its tone, mottle and grain) on a background queue as soon as it is on screen and again after a resize or
  theme change, into a three-entry `PaperSheetCache`; the room's first paint reads it. A miss (a click before
  the render ends, an unexpected size) still builds the sheet synchronously, so no frame ever shows a flat tone.
- Reason: the captain, 2026-11-07, from 120 fps recordings: `delete the HOW LONG? text it is not necessary`, and
  Begin `takes like half a second to go into the room`. The recording shows no fade: the room arrives as one
  frame after the main thread was busy. The ~5 M pixel paper texture was generated on the click's own turn
  (D-056's "built synchronously on first draw"); the picker already knows the room's paper size, so the work moves
  to idle time. Waiting for a wipe or countdown timing was never involved; D-077's 120 ms wash fade and the
  <=200 ms cut are untouched.
- Supersedes: D-031 and D-036's `How long?` heading (the lockup placement inside the card stands); D-056's
  "the image is built synchronously on first draw" as the only build path (it stays the fallback).
- Evidence: `BeginLatencyTests` (fails on the old code at 388 ms of main-thread CPU in a debug build; passes under
  100 ms with zero synchronous paper builds), the Windows `TestHomeAndTheThreeFreeSessions` and
  `TestHelpButtonSitsOnTheLogoRowAndTheCardPadding`, and the before/after recordings in
  `data/wid-picker-begin/picker-before-after.pdf`.


## D-097: The door opens - the paper grows out of the card, and the rules panel grows out of the `?`

- Date: 2026-11-07
- Decision: (1) Begin on the Mac and `Give it 60 seconds` on the web no longer cut to the room. The room's paper is on screen on the first frame in the rectangle of the thing that was clicked (the picker card on the Mac; the landing's demo paper on the web), then grows to its own place in 240 ms (the site's one `--ease-out`, `cubic-bezier(.22,1,.36,1)`, on both surfaces). The writing layer (editor, chrome, count) fades in over the last 70% of the grow behind a veil of the same paper; only transforms and opacity run, the layout is final from the first frame, so the editor is live and focused at once. On the web the brand row and the nav end slide from their landing positions to the room's, so nothing jumps 160 px at desktop width; a landing scrolled out of view cuts instead. Reduce Motion is one change with no in-between frame. Esc and exit stay a cut back. (2) The Mac's how-it-works panel is a transient popover anchored on the `?` that opened it (system grow-from-anchor animation, Esc, Return, Done or a click outside closes it back into the button), not a window-wide sheet that slides from the title bar. Its content sits clear on the system popover surface.
- Reason: the captain, 2026-11-07: Begin must not cut from picker to room, the paper should grow out of the card; the motion audit (`wid-motion-audit`, tables B1 and B2) found every state change a hard cut and these two as the ones that lose the eye (the clicked card or CTA vanishes; the sheet slides in from the top edge unrelated to the `?`). Rulebook v3 14.4 f: the acted-on element must be tied between consecutive frames, with no blink and no full crossfade.
- Supersedes: D-096's implicit cut at Begin (the 100 ms budget to first paper stands and is now the first frame of the grow); D-091's "?" opening a system sheet (the 32 pt quiet circle itself stands); D-076's sheet chrome for the rules (type scale, measure and wording stand).
- Evidence: `BeginLatencyTests.beginGrowsThePaperOutOfThePickerCard` (the first frame sits on the card's centre and size, Reduce Motion has no animation), `BrandTests.rulesPopoverIsAnchoredOnTheQuestionMark`, `writeitdown/qa/door-grow.spec.mjs` (first frame equals the demo paper's box and the brand row has not moved, widths only grow, 240 ms, no blank frame, editor focused, Reduce Motion one change; fails on the cut), and the frame-by-frame before (main 4357fa0) / after recordings in `data/wid-picker-begin/`. The Windows picker still cuts and keeps its dialog; it follows in a later change.

## D-098: The Mac draws the same glyph weight as the web

- Date: 2026-11-08
- Decision: the Mac app turns CoreText font smoothing off for the whole process (`AppleFontSmoothing = 0` in
  its own preference domain, written in `main()` before any window draws). The web room already sets
  `-webkit-font-smoothing: antialiased`, so the Mac moves to the web, not the reverse. Light and dark both.
  Windows already draws plain grey antialiasing and is unchanged.
- Reason: the captain saw the same text visibly heavier on the Mac than on the web. Ink units are summed glyph
  coverage of the live line in logical px squared (paper grain is zero-mean and a text-free strip is the zero
  point). Measured on the same typed text, same size, same paper, real keystrokes in the Tart VM on macOS
  15.7.7 and 26.6.2 against Chrome 1x (Chrome 2x measures the same): Latin 28 pt light web 2184, Mac before
  2874 (+32%), after 2372 (+9%); dark web 2181, before 3314 (+52%), after 2402 (+10%); Latin 23 pt light web
  1454, before 1909 (+31%), after 1560 (+7%); Chinese 28 pt light web 1599, before 2254 (+41%), after 1791
  (+12%). The two macOS versions agree within 1%. Same font file, same size; the difference is CoreText stem
  thickening, which Chrome's `antialiased` switches off. What remains (+7% to +12%) is probably CoreText's own
  rasteriser and hinting. The web's lighter look is the approved one (D-069's reading contrast ladder was set
  against it). The VM display is 1x; no Retina capture exists.
- Supersedes: nothing recorded; `apps/windows/SYNC.md` row 18's remark that the Mac kept draft reads heavier
  than the grey-antialiased Windows one is now closed for the live and kept text alike.
- Evidence: `TypographyParityTests.glyphSmoothingIsOffLikeTheWeb`, and the same-text three-way captures
  (Chrome, Mac before = main build, Mac after = this build) on both macOS versions, with the ink-unit table, in
  `data/wid-ink-weight/before-after.pdf`.

## D-099: The unit is always `words`, in every language

- Date: 2026-11-08
- Decision: every count reads `word` or `words` on the Mac, Windows, the web room and the root landing
  trial: `0 words`, `1 word`, `2 words`, in the live corner, its accessibility label, the kept receipt
  (`1 minute. 3 words.`, `0:00 - 3 words kept.`) and the landing receipt. There is no switch to
  `characters` for a Chinese or Japanese draft. The number is unchanged from D-095: each Han, Hiragana or
  Katakana character (and the prolonged sound mark) is one word, each space-separated Latin, Hangul or other
  word is one, punctuation and emoji are zero. `usesCharacterCount` and its equivalents are deleted on all
  four surfaces. One fixture, `tests/fixtures/word-count.json`, holds the texts, their numbers and their
  labels; the web unit and Playwright tests, the Mac XCTest suite and the Windows Go tests all load it, so a
  surface that drifts fails its own suite. The count tooltip text is unchanged.
- Reason: the captain, 2026-11-08: a Chinese draft showed `1 character`, and
  asked why not `word`, which works for Chinese and English alike. A unit that changes with the language makes
  two writers read two different products, and the mostly-CJK threshold meant one quoted `你好` could flip a
  whole draft's label.
- Supersedes: D-095's label rule only (the `characters` unit and its half-of-the-letters threshold). D-095's
  sentence-case result screen, its Hangul note and its number rule stand.
- Evidence: `RoomTests.theCountMatchesTheSharedFixture`, `RoomTests.theUnitIsAlwaysWordsInEveryLanguage`,
  `apps/windows` `TestWordCountMatchesTheSharedFixture` and `TestCountLabelIsAlwaysWords`,
  `writeitdown/session.test.mjs`, `tests/cjk-count.spec.mjs`, `writeitdown/qa/phase4.spec.mjs`, and the
  Chinese before/after captures on macOS 15 and 26 and the web in `data/wid-word-count/`.

## D-100: The first refused delete's note sits centred under the line being written, not in the footer

- Date: 2026-11-08
- Decision: item 2 of D-077 moves; nothing else in it changes. The first refused delete of a session (Backspace
  or Delete, a word, line or paragraph delete, or the delete input types a touch keyboard sends) shows one
  sentence, `You can only add the next word.`, horizontally centred on the writing column and with its
  baseline 34 px (pt, DIP) under the live line's baseline, so it follows the caret line and stays fully visible,
  lifted only if the footer row would otherwise be touched. Quiet role (`--paper-quiet`, 7:1 on the sheet), the
  footer's 13 / 400 style, sentence case, no tracking (rule 27: no all caps). It appears on the refusal frame,
  holds two seconds, then fades out over 200 ms; under Reduce Motion it is an opacity step with no fade. It
  moves no text, never covers the live line, and is announced once (the visible note is hidden from assistive
  technology; the room's live region says the sentence instead of `Blocked. Forward only.`). The footer keeps
  `Esc to exit` and the count as they were, and its status slot is the exit confirmation's alone again.
  Later refusals in the same session show no text; the 200 ms shake and the 220 ms hairline stay on every
  refusal, the first included (D-022, D-046, unchanged). A session that ends (wipe, kept, a new start) earns
  its own note. Paste, cut, undo and caret moves only shake. The warning numeral and the stopped screen own the
  space under the line, so a note still showing steps aside and a delete refused there waits unspent. An armed
  exit confirmation no longer holds the note back, because the two no longer share a place.
- Reason: the captain saw the note at the bottom left, next to `Esc to exit`, far from where he was looking
  and where the rule was just broken. The writer's eyes are on the line; the note belongs one step under it.
  The sentence is the captain's pick (2026-11-08, from the help-copy options; the first draft read `Forward only.
  Deleting is blocked.`). It lives in one place per platform (`REFUSAL` in `writeitdown/room.js`, `refusalNoticeText` in `SessionViewController.swift`, generated
  into `tokens.StrRefusalNotice` on Windows), so changing it is a one-line edit.
- Why the footer was used (history): D-077 (c2b70e3, PR #81) put the note in the footer status slot, which is
  the exit confirmation's existing slot, so that nothing could move (D-077's own reason). No earlier
  decision said "below the text" for this note. The nearest is D-017, which puts the warning numeral and the
  wipe receipt under the writing line (ink top 44 pt under the baseline), and that is the numeral's space, which
  is why the note steps aside for the warning rather than sharing it. Windows took the footer slot over in
  b6ec572 (PR #85) from the Mac.
- Supersedes: D-077 item 2 on the place, the casing and the fade (D-077's footer slot, `FORWARD ONLY. DELETING
  IS BLOCKED.` in capitals, and "an armed exit confirmation keeps the slot and the notice waits"). D-088's
  remark that D-077's second item stands is read with this entry.
- Evidence: `writeitdown/qa/history-fade.spec.mjs` (placement against the line and the footer, centring within
  1 px, frames before/during/after, 2 s once, 200 ms fade and the Reduce Motion step, 1440 and 390),
  `RoomTests` (the same on the Mac), `room/behaviour_test.go` (pixel-measured on Windows), and the frame strips in the PR.

## D-101: The `?` sheet is three short lines at one level

- Date: 2026-11-08
- Decision: the Mac `?` popover and the Windows rules sheet drop the eyebrow `How it works`, the big title
  `Forward only. Nothing kept.` and the bold-title-plus-grey-text groups. They show three lines at one level, in
  ink, in the existing 15 pt body face: line 1 `Forward only, no deleting.`; line 2 `N seconds of silence
  deletes the draft.`, where N is the silence limit in use (the user's 5, 8 or 12 on the Mac and Windows, default
  8, never a literal; the web's fixed 8 is not shown on a `?` sheet because the web has none); line 3 `Write to 0:00 and the text is yours.` (the captain picked it from
  `(1) Write to 0:00 and the text is yours.`, `(2) Reach 0:00 to keep your text.` and `(3) Make it to 0:00 and keep
  what you wrote.`). The three lines are
  held in one string (`RulesViewController.lines(silenceSeconds:)`; Windows is generated from it), so a copy change
  is a one-line change plus a token regeneration. The popover now hugs its longest line (never past the
  60-character measure) instead of always being the measure wide. The picker's `?` keeps its accessible name
  `How it works`; its accessibility help sentence, which repeated the old three claims, is removed. The font
  and size stay (15 pt system body); the 21 pt serif alternative is an open captain call.
- Reason: the captain read the three options in `data/wid-help-copy-options/` and chose option B for lines 1
  and 2 ("At 0:00, copy your text" was rejected, then "B+A" was preferred), then picked option (1) for line 3. Rulebook
  rule 13 (delete filler): the eyebrow repeated the `?` button's name, the title summed up the three lines and
  contradicted `Reach zero, keep it`, and each bold title said what its grey text said.
- Supersedes: D-086's three titled rules on the `?` sheet (`No way back` / `You can only add the next word.`,
  `Silence deletes it` / `Stop for N seconds and the draft is deleted.`, `Reach zero, keep it` / `The text is
  yours to copy.`); D-076's rule-title weight step on that sheet (there are no titles); D-097's sheet content (the
  anchored popover itself stands). Not changed: the landing page's `#how` section and its h2 (the web has no
  `?` sheet), the first-delete hint (`wid-first-delete-hint`), every other string. The landing `#how` cards still
  carry the old titles and bodies.
- Evidence: `BrandTests.rulesViewReusesTheLandingExplanationAndDismisses`,
  `BrandTests.rulesSecondLineFollowsTheSilenceSetting` (5, 8 and 12),
  `DesignReviewFixesTests.rulesSheetUsesTheScaleForLeadingAndOneLevel`, `LongStringTests.rulesRowsGrowWithTheirText`;
  Windows `TestRulesSheetFollowsTheTypeScale` (N = 5, 8, 12); captures in `data/wid-help-copy-build/`.

## D-102: The Mac window has no ground of its own; the writer's wallpaper shows around the paper

- Date: 2026-11-07
- Decision: the Mac window is clear. Its background, the page colour behind the paper and the white strip of the
  title bar are gone, so the writer's own desktop shows around the paper (and around the picker, settings and
  activation cards). The paper keeps today's size and place (32 pt gutter, 16 pt radius, the sheet shadow) and
  the window's own shadow is off so the paper's is the only one. The title bar is clear: the traffic lights float
  over the wallpaper, there is no rule under them (and the system's lit 1 px top edge, its title bar decoration
  view, is kept hidden through resizes and focus changes), and the title is hidden (it stays the window name for Mission Control
  and the Window menu). Once the first character lands the traffic lights step out (alpha 0, no animation) so
  nothing but the paper is on screen while writing; they come back when the pointer reaches the title strip and
  whenever the room is not live (empty, stopped, kept, picker, settings).
  The minimum content size grows by the title bar's height so the paper's minimum stays 980 x 680. Dragging the
  clear margin moves the window. Full screen has no wallpaper behind it, so the page colour is the ground there.
  The window ground is one alpha step above 0 so a click in the margin stays on the window instead of falling
  through to the app behind. Nav, clock and footer already sit on the paper, not on the old page, so no text
  moves onto the wallpaper.
- Parity exception (intentional): this is Mac only. A web page cannot see the visitor's desktop, so the web
  landing and trial keep the page colour behind the paper (D-069, D-056 unchanged); the nearest web equivalent
  would be an invented backdrop, which this record does not add. The Windows app is not part of this decision.
- Reason: the captain, 2026-11-07, after the paper-vs-page options round (PR 125, options A, B and C): "on the
  desktop just remove the background and show the user's own background; the paper keeps its size; but do not
  use that white background". The white page and the wheat paper fought; removing the page leaves one surface.
- Supersedes: the page-colour ground behind the paper on the Mac in D-069's room description and the 32 pt gutter
  being drawn on `pageNSColor`. Paper colour, size, shadow and the writing contract stand.
- Evidence: `WallpaperWindowTests` (clear, non-opaque, shadow off, clear title bar, paper 32 pt from the edges,
  clear grounds on every surface, page colour in full screen) and Tart macOS 15.7.7 and 26.6.2 before/after
  captures on a light, a dark and a busy wallpaper in the PR.


## D-103: Red as words is brighter in dark mode; red fills do not move

- Date: 2026-11-08
- Decision: dark-mode red TEXT gets its own tokens so it clears contrast; the fill red, the hue (H about 32), the
  typeface and every light-mode value stay as they are. Web (`writeitdown/tokens.css`): `--red-text` (light
  `#b02a1e`, dark `#f6715a`) for the hand-lettered words (`.home .hand`, `.h1 .hand`) and the warning numeral
  (`.mo .n`), and `--red-text-small` (light `#b02a1e`, dark `#ff9b88`) for the 12 px `5 s · warning` label
  (`.line8 .lab b`). Mac (`Colors.swift`): `redTextNSColor` (light `0xB02A1E`, dark `0xFF9B88`) for the five small
  red text sites (the home status line, the two activation messages, the two Settings messages). `--red` and
  `redNSColor` stay for fills and borders only (`.hairline`, `.tag b`, `.key.no::after`, `.line8 .track i`, the
  Mac session border); `paperDangerNSColor` is untouched.
- Bar (APCA Lc and WCAG 2 on the real backgrounds): big text Lc 45, small text Lc 60. Dark before to after: the
  hand and numeral on the page `#15140f` Lc 39.6 to 47.5 (WCAG 5.33 to 6.52), the numeral on the red card
  `#3a1c15` Lc 37.4 to 45.3 (4.47 to 5.47), the small label and the Mac messages on the card `#26231c` Lc 37.7 to
  60.3 (4.53 to 7.69). Light is unchanged (`#b02a1e`, 6.13:1 on the page).
- Two dark text values on purpose: the one value that clears Lc 60 (`#ff9b88`) turns the big hand-lettered red
  pink, so big text takes the smallest lift that clears Lc 45 and small text takes the Lc 60 value.
- Parity: the web and the Mac use the same two dark values. The Mac has only small red text, so it uses the small
  value. The Windows token table (`apps/windows/tokens`, generated) is not part of this decision.
- Reason: the captain, 2026-11-08, picked option 3 of the accent-text options (dark red text brighter, fills
  and light unchanged). The audit found the hand-lettered words and the red small labels below the bar in dark.
- Supersedes: the use of the fill red as the text colour in dark in D-057's pen accent and in the pen-red
  roles of the Mac error messages. Fill values, hue and typeface stand.
- Evidence: `DesignTokenTests.redTextIsBrighterInDarkOnly`; `qa/mac.spec.mjs` (computed colours in dark and light, the
  track fill still `#e4604a`); the contrast table and the before/after captures in the PR.

## D-104: The web door is instant on a 2x screen - the room's sheet is textured before the click

- Date: 2026-11-08
- Decision: the room's sheet (the `.room-paper` canvas) is painted before `Give it 60 seconds` is clicked, not in the click's own task. While the visitor reads the landing, `room.js` measures the hidden room (shown and hidden again inside one task, so no frame sees it; focus and scroll are put back) and `paper.js` hands that size, the pixel ratio and the theme to a worker that runs the unchanged texture code (`paper-render.js`, split out of `paper.js`) on an `OffscreenCanvas`; the page only copies the finished bitmap. A resize or a theme change on the landing warms the room again. A click that lands while the worker is still painting waits for it and never paints the same sheet a second time; a browser without `OffscreenCanvas` paints on the page as before. The landing's own demo sheet still paints on the page at load, so the landing never shows it plain. The texture, tone, grain and every locked value are unchanged (D-069, D-073, D-093).
- Reason: the captain, 2026-11-08: clicking `Give it 60 seconds` takes about a second to enter the trial. Measured on the live site in Chrome at 1440x900 and 2x pixel ratio, the room was on screen on the next frame but the main thread was then held 1170 ms by the room's first texture (a 2752 x 1600 px canvas of per-pixel noise, fibres, flecks and a full-canvas mean scan), so the grow stalled and a first key waited behind it; at 1x the same work is about 140 ms, which is why the 1x baseline (1.33 s from page load, `data/wid-core-tasks-baseline/`) never showed it. Mac Begin already builds the room's sheet off the main thread while the writer chooses (case 79); this brings the web to the same rule.
- Supersedes: nothing recorded. D-097's door (the grow, 240 ms, Reduce Motion one change) stands unchanged; D-056/D-069's "painted once per size" stands, now ahead of the click.
- Evidence: `writeitdown/qa/door-instant.spec.mjs` (2x screen: longest main-thread task after the click under 150 ms, editor focused within 250 ms, the canvas is exactly the warmed one and the click does not repaint it, the landing's scroll, focus and visibility are untouched by the warm, and a resize re-warms; fails on the previous build), `door-grow.spec.mjs` unchanged, and the frame-by-frame before/after recordings and traces in `data/wid-web-trial-instant/`.

## D-105: The site sells only the Mac app until a Windows listing is live

- Date: 2026-11-09
- Decision: while no Microsoft Store listing is live, `mac.html` carries no Windows sale, price,
  activation or download claim. The licence reads `one license covers 2 computers` and `One license
  works on two computers`, with no `Mac or Windows` clause; the price row reads `2 computers. No
  subscription.`; the meta description drops the `Mac or Windows` clause and reads `... for two
  computers. Free updates and a 14-day refund.`; and the Requirements and Activate sections lose their
  Windows clauses. `privacy.html` loses its `#windows` section whole (memory-only draft, the 3-session
  trial terms and the $4.99 price, Credential Manager entries and their removal, Stripe checkout, no
  update check of its own), and its outside-request list names `the Mac app` instead of `the Mac and
  Windows apps`. `llms.txt` describes the privacy page as what the browser and the Mac app keep and
  send. Nothing replaces them: no Windows download, no Store link, no placeholder and no coming-soon
  line. D-083 stands unchanged: the kept screen's `Mac app` link becomes `Mac and Windows app` when the
  listing is live, and nothing else on that row changes.
- Reason: the captain, 2026-11-09, on C3 of the web design audit: the site must say only what actually
  ships today. The Windows app cannot be downloaded and no Store listing exists, so those sentences
  sold a product with no purchase path on any page. This retires the Windows copy PR #100 shipped on an
  earlier approval that assumed a live listing.
- Supersedes: the Windows strings approved in PR #100 (the `mac.html` requirement sentence,
  `privacy.html#windows`, the `Mac or Windows` licence clauses, the `llms.txt` privacy summary). It
  supersedes no recorded decision; D-083 is not superseded.
- Evidence: `writeitdown/qa/mac.spec.mjs` (no Windows text on `mac.html` and no Store or Windows href
  anywhere in it, its meta description included; `privacy.html` carries no Windows block and its
  outside-request sentence names the Mac app), `writeitdown/qa/seo.spec.mjs` (`llms.txt` names no
  Windows app); each new assertion fails on a page with the claim put back. Before/after captures of
  `mac.html` and `privacy.html` at 1440 and 390 in `data/wid-design-c3-windows/`.
