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
