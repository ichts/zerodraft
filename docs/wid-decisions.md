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
