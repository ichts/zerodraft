# Zero Draft Web Design System (Constitution v2)

This is the visual constitution for all web-facing pages in this repo. It supersedes the Flood system (kept in git history only; `design-demos/flood-v2.html` is an archive, not a reference). The authority upstream of this file is the captain's accepted constitution document; this file is the in-repo map and must match the terrain (`index.html`). Every new page, component, section, or experiment must reference this document.

Interrogation-room minimal. One paper. One clock. One door. Danger enters the room only while you are stopped, and it always states what happens next.

The graveyard is closed: no fossil text, no eulogies, no always-on dread. Pressure is conditional, legible, and spent only on the clock.

## 1. Soul

Eight lines. Memorize.

1. The user hires a threat. Be one that keeps its word - exact numbers, every time. 5 means 5.
2. Danger is felt only during pause. Typing buys total silence; the room reacts to stopping, never to writing.
3. One paper. One clock. One door. Everything else is wall.
4. Every alarming pixel answers: what happens if I stay stopped? If it can't answer, it's scenery. Cut it.
5. Messy is the user's text. Urgent is the clock. Raw is the wipe. The three jobs never trade.
6. Rules print on the object they constrain: forward only / 5s warn / 8s wipe / 60s, on the paper's edge.
7. Deletion is a result, not a funeral. Report it in machine voice. Rearm.
8. The realer the session, the emptier the room. The landing holds four objects; the trial holds two.

Voice: short, plain sentences about mechanism and consequence. Machine captions state what happened or what happens next. Banned registers: therapeutic, ceremonial, self-help, eulogy ("gone", "it joined the pile", mourning the draft), and any copy that says deletion is okay. Deletion stays flat and unsentimental.

## 2. Tokens

Tokens ship as CSS custom properties in the `:root` block of `index.html`. Values are never copied inline; if a value is not a token, it does not exist.

### Color - the wall, the paper, ink, one alarm

| Token | Value | Use |
|---|---|---|
| `--bone` | `#f1f0eb` | The wall. Environment, everywhere. |
| `--paper` | `#dbe6ec` | The one object: the Note sheet (D-056). Nothing else is the paper. |
| `--ink` | `#1c1917` | Words, primary chrome, the door. 13.78:1 on the paper. |
| `--paper-quiet` | `#464746` | Every quiet role **on the paper**: clock, count, hint, receipt, exit link. 7.35:1, measured, never assumed. |
| `--paper-danger` | `#63140b` | The pen **on the paper**: the warn numeral and the wipe receipt. Clears 7:1 on the sheet and on the wash the numeral sits on. |
| `--dim` | `#6b665b` | Secondary chrome **on the wall**. |
| `--faint` | `#b3ada0` | Receded wall chrome, the quietest legal text on the wall. Never used on the paper. |
| `--line` | `#dedcd5` | Hairlines only. 1px, never thicker. |
| `--danger` | `#c8392f` | The wash mix and the deny hairline. |

Red is a budget: it means "you are losing the draft". The logotype underscore is ink. No red on links, borders, emphasis, or decoration. No blue. Selection is an ink tint (`rgba(28,25,23,.18)`).

The page around the paper keeps its white identity (D-056): the wall, the chrome and the header are never tinted with the paper, and a surface that sits on the wall (cards, buttons, fields) stays `#ffffff`.

The paper is textured, not flat (D-056): grain 70 of 100 at size 1.00, generated once per sheet size and theme - device-pixel tooth, a coarser pulp cloud upscaled with smoothing, short fibres and sparse pigment flecks - painted under the words and never regenerated while the writer types. Its tone stays in CSS so a wash can still tint it.

Every reading role on the paper is measured against the paper's own tone, not against white: ink 13.78:1, the quiet role 7.35:1, the pen red 10.1:1 - nothing that carries reading reads below 7:1. The completed lines above the writing line keep D-027's fade (100/22/7 of the ink): it is the zen step, not a reading role, and D-058 records the trade.

The wash exists only during warn, seconds 5-8:

| Token | Value | Use |
|---|---|---|
| `--wash-wall` | `color-mix(in oklab, bone 88%, danger)` | The landing wall during warn. |
| `--wash-paper` | `color-mix(in oklab, paper 88%, danger)` (`#ddd3d5` light / `#352c2c` dark) | The paper (and the trial room) during warn. The sheet's own mix, not a pale tint meant for white: on the Note paper a white-sheet tint lands on grey at mid-ramp (D-056). |
| `--wash-wall-deep` / `--wash-paper-deep` | color-mix at 76% | The eighth second goes one step deeper: at 8.0s the wash deepens to double the danger share for the wipe-cut beat, then exits. |
| `--wash-*-1` / `--wash-*-2` | color-mix at 96% / 92% | Reduced-motion wash steps (see §6). |

### Type - two faces

Newsreader is the human. IBM Plex Mono is the machine. The machine never speaks serif; the human never speaks mono.

| Style | Spec | Use |
|---|---|---|
| display | Newsreader 500 · clamp(44px, 6vw, 72px)/1.04 · -.015em | Landing headline only |
| deck | Newsreader italic 400 · 24/1.45 · `--dim` | "It's not supposed to be good yet." |
| script | Newsreader 400 · 21/1.6 · measure <=62ch · never justified | The user's words. Typos survive. |
| numeral | Plex Mono 600 · min(40vh, 360px) · tabular · `--paper-danger` | Exists only while paused >=5s. The loudest object we own. |
| timer | Plex Mono 500 · 16/1 · tabular | Always running during a session, never blinking |
| label | Plex Mono 500 · 11/1.5 · caps · .16em | Rules, counts, captions |
| system | Plex Mono 400 · 13/1.9 · caps · .08em | Reports and receipts |

All numerals are `font-variant-numeric: tabular-nums`. The receipt example is written one way everywhere: `0:00 - 148 WORDS KEPT.` (the old draft of this constitution wobbled between 48 and 148; the code shows the real count and the doc example is always 148).

### Space

Seven steps: `--s1: 4` `--s2: 8` `--s3: 12` `--s4: 20` `--s5: 32` `--s6: 56` `--s7: 96`. The wall may be most of the frame; emptiness is load-bearing.

### Radius and shadow

`--radius: 0`. Round nothing. If an element wants softening, delete it instead.

One shadow in the product, `--lift`: `0 1px 0 rgba(23,21,15,.04), 0 24px 48px -32px rgba(23,21,15,.3)` - the paper's lift off the wall. Warn changes the room, never the object: the lift is constant.

### Motion

Linear or step. Easing is persuasion, and we don't persuade.

| Token | Value | Use |
|---|---|---|
| `--snap` | 120ms linear | Chrome state switches. On, then off. Nothing glides. |
| `--wash-ramp` | 3000ms linear | The environment tint, second 5 to second 8. The only slow thing we own, because it is a fuse. |
| `--wipe-cut` | 200ms | A cut, not a dissolve. No letter-by-letter ceremony, no merciful fade. |
| numeral | step, never tweens | It does not arrive; it is suddenly there. 3, 2, 1 swap in a single frame. |
| focus | 1px ink, 3px offset | Square outline. No glow. |

The recovery snap: one keystroke during warn (say at 6.5s of silence) ends the warn. The wash and the numeral return on the 120ms snap: the numeral vanishes in one frame, the wash transitions back over 120ms linear. The snap is the only return idiom - wipe exit and adjudicated completion use it too. Implementation: entering warn applies `transition: background-color var(--wash-ramp) linear` from the `body.danger` selector; leaving it finds only the base 120ms snap, so the return is always 120ms regardless of how warn ended.

## 3. Surfaces

One world end to end; the session sheds objects as it gets real. Objects on stage: landing 4 → trial 2 → warn 3 → wipe 2 → kept 3.

### 3.1 Landing - four objects

Logotype · headline · door · demo paper. That's four. The `MAC RELEASE ->` link rides with the logotype as one nav unit; it is not a fifth object.

- Copy hierarchy is law: (1) `We force you to write something down. You leave with words.` (2) `It's not supposed to be good yet.` - load-bearing; it kills the inner editor. Do not cut. (3) the door: `Give it sixty seconds.`
- One door: the CTA. No second entrance, no whisper under the button. The demo paper is theater, not an entrance - pointer and keystrokes on the landing do nothing.
- The wall is blank. Permitted texture: none. Never sentences.
- The footer carries the one-line privacy promise and the support links. That is a legal/support need, not a fifth object on stage.

### 3.2 The demo paper - watch-only theater

A scripted loop at real speed; the demo never cheats its own numbers. Loop: types ~7s → stops → 5s of nothing → warn (wash + 3-2-1) → wipe at 8 → the machine report holds 2s → rearms at 1:00 and loops. Rules print on its edge; its timer runs and burns through the silence exactly like a live session, and the report states the real unused seconds. The loop pauses while offscreen or while the tab is hidden and resumes the same beat (its clocks are absolute: carry + origin, so timer drift cannot cheat the numbers). Under `prefers-reduced-motion` the theater is fully static: the sample fully typed, the clock parked at 1:00, no loop.

The demo's numeral scales to its paper (the theater is a scale model of the room); the min(40vh, 360px) numeral token owns the trial.

### 3.3 Trial, typing - two objects

The wall is gone; the paper is the room (the room is the Note paper, grain and all - D-056). Objects: paper · clock. Chrome lives in the corners: rules TL · timer TR · exit BL · words BR. Idle chrome is full ink; while keys arrive it recedes to the paper's quiet role (D-056). Nothing reacts to a keystroke - no sparks, no shake, no sound. The reward for writing is silence.

The empty room carries one hint in faint mono caps: `Type here. The law is live: 5s warn, 8s wipe, 60s to keep.`

### 3.4 Trial, warn (paused 5-8s) - three objects

The only time the environment moves. The wash ramps linearly, peaking at second 8. The numeral counts the grace: 3 → 2 → 1, full size, instantly, no entrance animation. The caption: KEEP TYPING OR THE DRAFT IS DELETED. Chrome snaps from faint to ink. The 60s clock keeps burning through the warn: pausing costs twice.

Warn does not move the object. The paper never translates, scales, shakes, or changes its lift during warn; only the room (the wash) and the chrome change. (The deny shake is a different beat - rule enforcement for a blocked action, over in 160ms - and is not warn.)

### 3.5 Wipe (8.0s lands) - two objects

A cut, not a ceremony: the text is gone in <=200ms, one pass. At the eighth second the wash steps one step deeper (`--wash-*-deep`) for the cut beat, then exits on the snap; bone returns. The machine report states the cost: `DRAFT WIPED - 0:37 UNUSED.` then rearms: `TYPE TO RESTART.` - and it is literal: the editor stays armed, and the next keystroke starts a fresh 60s session. The timer rearms to 1:00. No ash, no fade, no italic, no condolences.

### 3.6 Kept (0:00 reached) - three objects

The only quiet surface. The clock stops at 0:00; the paper returns to the wall (the room goes bone, the paper sits on it with the lift). Receipt, not praise: `0:00 - 148 WORDS KEPT.` No confetti, no "well done." One action: COPY TEXT (its completed state is COPIED - same door, feedback in ink). One mono link: RUN IT AGAIN (fresh 60s, same room). One caption: NOTHING HERE IS SAVED. The words are the biggest thing on the surface; they won, let them.

## 4. State matrix

| State | Environment (wall · paper) | Chrome (clock · rules · counts) | Voice | Reduced motion |
|---|---|---|---|---|
| IDLE - before the first key | bone wall, paper lifted, still | full ink; timer parked at 1:00 | label: rules on the paper's edge | identical |
| TYPING - keys arriving | unchanged; the room never reacts to a keystroke, and the paper's grain is never regenerated | recedes to faint; timer runs at dim | the user's serif - the only mess allowed | identical |
| PAUSE <5S - 0-5.0s still | nothing changes; restraint is deliberate | caret blinks; timer keeps running | - | identical |
| WARN 5-8S - second 5.0 lands | wash ramps linearly, peaking at 8s; the only environmental motion | snaps to ink; numeral 3→2→1 in danger, min(40vh,360px); caption KEEP TYPING OR THE DRAFT IS DELETED | machine caps; states the consequence | wash steps once per second (96%, 92%, 88% mixes); numeral identical; nothing withheld |
| WIPE @8S - second 8.0 lands | wash steps one step deeper for the <=200ms cut, then exits on the snap | text cut in one pass; timer rearms to 1:00 | DRAFT WIPED - 0:37 UNUSED. TYPE TO RESTART. | the cut is already a step |
| KEPT @0:00 - the clock reaches zero | bone; still; the room lets go | timer stops at 0:00, ink; receipt row + COPY TEXT | receipt: 0:00 - 148 WORDS KEPT. | identical |

Reduced motion removes ramps, never information. Warn still lands at 5.0s - red, huge, on time.

## 5. The clock and the silence (behavioral law)

The timing contract is 5s warn, 8s wipe, 60s session, 100ms tick. It does not bend.

Session end adjudication is explicit: the 60s deadline and the 8s wipe line race as absolute deadlines on the same tick, and whichever comes first wins. A pause at 0:54 warns at 0:59, but the wipe line (1:02) is never reached - the 1:00 deadline lands first and the draft is KEPT. A pause at 0:52 reaches the wipe line at exactly 1:00 - a tie, and the tie goes to the wipe: eight seconds of silence means eight seconds. A catch-up tick after background-tab throttling can land past both deadlines at once; the same comparison honors whichever occurred first.

Three things in plain words:

1. The first five seconds of silence are deliberate. Before 5.0s nothing changes - no tint, no numeral, no hint of the clock's opinion. The grace is the design, not a delay in the machinery.
2. Dark mode is forbidden. One bone room, one paper, one alarm. No dark variant, ever.
3. Repeated pauses never escalate the punishment. The tenth pause looks exactly like the first: same 5s grace, same wash, same 3-2-1. No ratchet, no stacking penalty, no memory of past pauses.

## 6. The door out (ESC / EXIT)

ESC and the EXIT corner are the same act with the same consequence: leave the room immediately and return to the landing, on the snap. No confirmation - the threat does not negotiate, and nothing is saved anywhere:

- An active or paused draft is discarded. No wipe cut, no receipt, no fossil. The clock stops and rearms to 1:00 for the next visit.
- A kept draft you did not copy is gone. The receipt says nothing here is saved; leaving is the proof.
- A wipe report simply closes.
- Focus returns to the door. ESC on the landing does nothing.

## 7. Captions

One consistent form: Plex Mono caps, label or system style, machine voice. Every caption carries its reading - it states what happened or what happens next. The full set:

- Hint (empty trial): TYPE HERE. THE LAW IS LIVE: 5S WARN, 8S WIPE, 60S TO KEEP.
- Warn: KEEP TYPING OR THE DRAFT IS DELETED
- Wipe: DRAFT WIPED - 0:37 UNUSED. / TYPE TO RESTART.
- Kept: 0:00 - 148 WORDS KEPT. / NOTHING HERE IS SAVED.
- Copy completed: COPIED.
- Deny (screen reader only): BLOCKED. FORWARD ONLY.

CTA capitalization is consistent within each voice: the door speaks human sentence case (`Give it sixty seconds.`); machine actions and links go caps (COPY TEXT, RUN IT AGAIN, ESC - EXIT, MAC APP ->). Labels do not take trailing periods; system sentences do.

## 8. Interaction contract

- Forward-only guards on `beforeinput`: block `delete*`, `historyUndo/Redo`, `insertFromPaste/Drop/Yank/ReplacementText/Transpose`; allow `insertText/Paragraph/LineBreak/CompositionText` only with a collapsed caret at the very end. `paste/cut/drop` prevented. Backward caret motion keys (ArrowLeft/Up, Home, PageUp) denied.
- Every blocked action has a body: the room shakes 2px for 160ms, a red hairline flashes on the paper's edge for 90ms, and the screen-reader line says BLOCKED. FORWARD ONLY. This is rule enforcement, not danger.
- IME composition works: `compositionstart/end` tracked, composition input types never intercepted, the model syncs on `compositionend`, and composition counts as activity - never a false deny, never a false silence.
- The demo paper is watch-only. The CTA is the only way in. The `#trial` route is preserved (direct links and Back work).
- No localStorage, no session history, no streaks. The visit remembers nothing.
- Signals are the only UI-state truth (`_session.*` on `<body>`); JavaScript is the stateless bridge that writes only through `fl*` custom events.

## 9. What not to become

- Kami/parchment: fiber textures, warm sepia, the paper mattering more than the clock.
- Medium: typography tuned for an audience. This draft has no audience yet.
- Notion: toolbars, blocks, a second object on the desk.
- Headspace: rounded corners, breathing animations, "you did great."
- Literary magazine: drop caps and pull quotes - the draft starts performing.
- TMDWA clone: all threat, no artifact - a timer in 8pt and nothing kept at the end.
- The graveyard (our own past): readable dead-draft fragments, fossil piles, eulogy copy. Closed.

The test: if a frame would hang comfortably in any of these rooms, keep deleting until it wouldn't.

## 10. Verification checklist (run for every change)

- Desktop 1440x900 and phone 390x844: landing at rest, demo typing/warn/wipe/report, trial at rest, typing, warn, recovery, wipe aftermath, kept, COPIED state, ESC and EXIT outcomes; `scrollWidth` equals viewport; no console errors.
- Forward-only: Backspace/Delete/Cmd+Z/X/A, paste, cut, drop, selection-replace all blocked with the deny body; IME composes and counts as activity.
- Demo: loop timing is exact (warn at 5.0s of silence, wipe at 8.0s, report 2s, rearm); pauses offscreen and when hidden; static under reduced motion.
- Timing: warn at 5.0s, wipe at 8.0s, kept at 60s; the 54s-pause adjudication keeps the draft; the tie goes to the wipe.
- Danger is felt in a full-page screenshot without reading any text.
- `grep` for U+2014 and U+2013 returns nothing.
- Focus ring (1px ink, 3px offset) on every interactive element; the numeral is announced via `aria-live`.
- Reduced motion: fully static ramps, stepped wash, warn on time, wipe instant.

## 11. Write It Down logo

This is the brand for writeitdown.app and the native Mac app. It is a sibling of the root Zero Draft landing: the
`ZERO_DRAFT` logotype in `index.html` is unchanged, and the Write It Down lockup is not placed on the root landing.
Every shipped writeitdown.app page - the landing, the room, `/download/`, `mac.html`, and the legal, support and
answer pages - uses the chip-and-wordmark lockup (11.6), so no page keeps a mono logotype (D-053). The social card
keeps the wordmark-only lockup. The native Mac app's in-app start screen uses the wordmark-only lockup; the app
icon and volume icon carry the mark.

### 11.1 The mark and the wordmark

The mark is the split W: Newsreader's W with a vertical notch through its middle peak. The wordmark is
`Write It Down` in Newsreader 500, with the same split W. The web header sets the mark as its own object beside
the wordmark (11.6); the Mac start screen and the social card keep the wordmark lockup, whose W already carries
the notch.

- Site header and footer: the chip-and-wordmark lockup uses the two aligned masks defined in 11.6, at the
  responsive sizes in 11.3.
- App icon and favicon: the mark alone on the bone plate with the ink W. The full-bleed favicon is the bone
  square with the ink W. The ink plate with the bone W is the dark-appearance variant for the favicon's
  `prefers-color-scheme: dark` links. A macOS `.icns` app icon has no appearance switch, so the shipped `.icns`
  is the light plate.
- Mac start screen: `Sources/FirstLine/Resources/write-it-down-lockup.svg` at 21 px type (128x16.25), tinted with
  the app ink token. The app icon and volume icon carry the mark.
- The volume icon: the bone sheet with the ink W on the dark disc, as the DMG volume composition.
- Social card: `writeitdown/og.png` at 1200x630 uses the wordmark lockup on the light page; it is the link preview
  for the landing and `/download/`.

### 11.2 Palette and type

- Ink `#17150f`, bone `#f1f0eb`, paper `#ffffff`. No red in the logo. Red stays the alarm for the pause and the
  wipe, and the site's red hand word is not a logo colour.
- The wordmark is Newsreader 500; the mark is the same W drawing. Do not re-typeset, track, stretch, or replace
  the W.
- The app icon plate is bone with the ink mark. The favicon is the bone square with the ink mark, with dark links
  pointing at the ink square with the bone mark. The volume icon is a bone sheet with the ink mark on a dark disc.
  The light app icon and favicon are self-contained; the dark favicon link is not the default, and it is never
  used in the light appearance. The header chip's theme roles are defined in 11.6.
- The mark itself is flat: no gradient, outline, shadow, bevel, or second colour. The app icon's plate gets the
  system shadow; the volume icon may carry the Finder/disk shadow as a packaging surface. The header chip's
  plate carries only its one 1 px `--hair-2` edge (11.6); the mark never does.

### 11.3 Sizes and clear space

- App icon: 1024 master, with optical 16 and 32 drawings, all on the bone plate with the ink W. The
  `AppIcon.appiconset` uses the opticals for the 16/16@2x and 32/32@2x entries and the master for 128 and above.
  The plate is the 824/1024 macOS squircle on a 1024 canvas. The 16 and 32 app icons keep the optical drawing, not
  a downscaled master.
- Favicon: `favicon.svg` and `apple-touch-icon.png` use the master split W; `favicon-16.png` and `favicon-32.png`
  use the same optical split drawings as the small app icons on the bone plate. `favicon-dark.svg` and the dark
  16/32 PNG are the `prefers-color-scheme: dark` links; `apple-touch-icon.png` is 180 on the bone plate. The
  favicon is the full-bleed square, not the app icon's transparent-margin squircle.
- Site header: 21 px above 820 px, 19 px from 391 to 820 px, 16 px at 390 px and below; the chip is 1.5 cap
  heights (1.046 em: 22 px at 21 px type, 19.9 px at 19 px, 16.7 px at 16 px), the clear space from the chip's
  edge to the wordmark's first stroke is 0.36 em, and the lockup box is 7.467 x 1.046 em. The lockup's clear
  space is at least a quarter of the cap height on all sides (about 5 px at 21 px). The header link may extend
  its hit area without enlarging the lockup.
- Site header invariant: at every width from 320 to 1440 px the header never scrolls sideways and the theme
  button keeps at least 6 px of right gutter, with the 36 px theme button unscaled and the page action present
  at 380 px and above and hidden below 380 px. The room drops it sooner on phones; see the mobile rule
  below. `writeitdown/qa/mac.spec.mjs` "the header holds its gutter at every width from 320 to 1440 px"
  sweeps the widest header (`/download/`) in 1 px steps from 320 to 420 and 8 px steps from 420 to 1440
  under the wider-font action model, so a breakpoint that leaves an uncovered band fails; keep the range
  sweep instead of sampled widths. The landing's header also keeps the page container's left edge and width:
  `writeitdown/qa/mac.spec.mjs` "the landing header spans the page container at every width" pins the nav's
  left edge and width to the page container at 320, 375, 390, 768, 1024 and 1440, because `.wrap`'s auto
  margins inside the first screen's flex column would otherwise shrink it to its content and centre it
  (D-055, D-068).
- Site header, mobile: from 391 to 820 px the 19 px lockup takes 141.9 px of the row, with 12 px between the
  brand and the page action and 6 px inside the action group; at 380-390 px the 16 px lockup takes 119.5 px,
  the brand-to-action gap is 8 px, and the action-group gap stays 6 px. Below 380 px the nav page action is
  hidden on every page, leaving the brand lockup and the 36 px theme button; each page keeps its call to action
  in the body, so the mark never shrinks below 16 px and the header stays one 56 px row. The action is dropped
  rather than stacked into a second header row, so the room's header height and its dynamic-viewport paper
  sizing stay unchanged. One rule for every page that uses `.brand` - these sizes and the single
  `--brand-plate` token in 11.6 - so `/download/` does not diverge from the landing, trial room and `mac.html`.
  The room drops the action sooner: from 767 px down its nav keeps only the lockup and the theme icon, and the
  Mac link moves into the exit row, so nothing in the header competes with the clock (D-053).
- Volume icon: `packaging/VolumeIcon.icns`, all Finder sizes from 16 to 1024.
- The source set is `writeitdown/logo/`, `writeitdown/favicon*`, `writeitdown/apple-touch-icon.png`, and
  `writeitdown/og.png` for the site; the app icon set, `packaging/VolumeIcon.icns`, and
  `Sources/FirstLine/Resources/write-it-down-lockup.svg` for the Mac. The Mac start screen uses the bundled
  lockup. The app icon `.icns` is the light plate; there is no dark app-icon alternate in the app icon set.

### 11.4 Do not

- Put red, the old red underscore, or the old `WID` sheet in the mark.
- Add a palette colour, a border beyond the single `--hair-2` plate edge in 11.6, a shadow, or a gradient to the
  header chip. Its two masks use only the `--brand-plate` and ink tokens. Do not put the dark plate in the light
  header or the light plate in the dark header.
- Insert a line, rule, or caption between the chip and wordmark, or set the chip alone above, below, or after
  the wordmark.
- Use the ink plate as the favicon default; it is the dark-appearance favicon alternate only. Do not put the light
  plate behind a dark-appearance link.
- Round the favicon square, add a border to the app icon plate, or add a caption or tagline to the lockup.
- Use the mark on a busy, photographic, or low-contrast surface, or below 16 px.
- Replace the root `ZERO_DRAFT` logotype with this lockup.

### 11.5 Verification

- Browser tab: the 16 px favicon is the split-W mark on a bone tile by default, and the bone split-W mark on an
  ink tile when the `prefers-color-scheme: dark` links are selected; the 32 px, SVG, and apple-touch versions carry
  the same mark.
- Plate decision: the light plate passes at 16 and 32 px. The static 16/32 inspection and the light/dark
  start-screen captures are recorded in `apps/macos/FirstLine/docs/MANUAL_QA.md`; real Dock and Finder captures
  remain pending. The dark plate remains the favicon alternate.
- Site header: `writeitdown/qa/mac.spec.mjs` "the header lockup shows the A mark chip beside the wordmark" reads the shipped
  masks at the rendered header size and requires the plate to cover the top of the chip, the W strokes to sit
  inside it with matching bounds, the split to survive at 2x, and the wordmark to follow it. Computed colours
  must give a lighter plate than W in light appearance and a darker plate than W in dark appearance.
  It fails on a wordmark-only lockup or inverted polarity.
  "the header chip paints one plate colour on every page" reads the rendered `::before` background on every
  shipped page and the room and requires one `--brand-plate` value per theme, so a page-local fallback cannot
  make the chip diverge again. The same test reads the plate's rendered border and requires the 1 px solid
  `--hair-2` edge to equal the theme button's boundary on every page, so a missing or per-page edge fails.
  "the header keeps its right gutter and a legible chip at 360 px" repeats the visual check at 360, 375 and
  390 px and requires no horizontal overflow, at least 6 px of right gutter and one lockup step across every
  shipped page and the room; at 360 px it also requires a chip of at least 16 px with the split still
  reading. "the header holds its gutter at every width from 320 to 1440 px" sweeps `/download/`
  in 1 px steps from 320 to 420 and 8 px steps from 420 to 1440 under the wider-font action model and requires
  no horizontal overflow, at least 6 px of right gutter, the page action at 380 px and above and absent below,
  and the 36 px theme button at every width, so a breakpoint that leaves a band uncovered fails. Verify the
  sizes in 11.3 in light and dark, with no clipping and no shift in the nav.

- Mac: the split-W lockup on the start screen in light and dark; the app icon at 16/32 (optical), 128 (Dock), and
  1024; the volume icon at 128 and 1024. Static asset inspection, the deterministic view test and the light/dark
  start-screen captures are recorded in `apps/macos/FirstLine/docs/MANUAL_QA.md`; Dock and Finder captures on light
  and dark remain separate independent acceptance.
- `grep` for the old `WID` icon, the red underscore, and the `.brand i` caret returns nothing in the shipped
  surfaces. The logo files contain no `<text>` and no red token.

### 11.6 The web header chip

The header and footer lockup opens with the mark as a chip: the app icon's squircle plate around the split W,
followed by the wordmark on the same baseline. Sizes and spacing are defined in 11.3. At 21 px the notch inside
the wordmark is invisible, so a wordmark-only lockup reads as plain words and the product has no logo in the corner.
The chip makes the mark an object using two aligned alpha-only mask files, not theme-specific assets.

- The chip is the app icon's drawing: the 824/1024 macOS squircle plate around the master split W, at a
  0.798 W width share (the app icon's 0.752 share widened by the chip notch below) and 0.526 of the plate
  height, with the plate optically centred on the wordmark's cap band.
- The chip is the small-size variant of the mark: its notch is 142 word-units wide (11% of the W) instead of
  the master's 90 (6.5%), the same optical widening the 16/32 favicons use, so the split still reads at 22 px.
- The aligned alpha-only masks are `writeitdown/logo/write-it-down-lockup-plate.svg` for the plate and
  `writeitdown/logo/write-it-down-lockup.svg` for the W and wordmark. The plate paints the `--brand-plate`
  token; the W and wordmark paint `currentColor` from `--ink`. `--brand-plate` has one value per theme and is
  owned with the other root colour roles in `writeitdown/tokens.css`, so `.brand` consumes it directly with no
  page-local fallback: light is the paper plate `#ffffff` with the ink W, dark is the ink plate `#26231c` with
  the bone W, on every shipped page and the room alike. Paper against the page wall is 1.07:1, so the plate
  carries one 1 px edge in `--hair-2` - the same boundary `.theme-btn` draws - on the chip square, with a
  corner radius that matches the squircle; that edge is what keeps the 21 px chip an
  object. No other border, shadow, or colour. Both layers share one viewBox and
  `shape-rendering="geometricPrecision"`, with no theme-specific CSS or new palette colour. The glyph layer
  retains the split strokes with `fill-rule="evenodd"`.
- Do not carry the chip to the Mac start screen or the social card; both keep the wordmark lockup.
- On narrow phones the lockup steps to 16 px type (DESIGN 11.3) instead of letting the header push the theme
  button past the page gutter; the chip's widened notch is what keeps the split readable at 16.7 px.

## 12. Faces on writeitdown.app and the Mac app (D-057)

Section 2 owns the root Zero Draft landing's type pairing. This section owns the faces of the product
surfaces - every shipped writeitdown.app page and the native Mac app - which share one set, with the Mac
as the reference. A web role that leaves this set, or a Mac role that drifts from the web's numbers, is a
defect, and `writeitdown/qa/typography.spec.mjs` and
`apps/macos/FirstLine/Tests/FirstLineTests/TypographyParityTests.swift` fail on it rather than a captain
noticing that the two do not look alike.

| Role | Face | Web spec | Mac spec |
| --- | --- | --- | --- |
| writing text, and every heading | Newsreader (bundled variable, `wght` 200-800, `opsz` 6-72) | `--serif`; 400 at `--t-write` 28/1.6; headings 500 | `Newsreader16pt-Regular`; `NewsreaderRoman-Medium` for the kept heading and failure headline |
| the same roles in Chinese | Zhuque Fangsong | `--cjk`, second in the writing stack, GB2312 slices in `fonts-cjk.css` | bundled cascade on the writing font |
| everything the tool says | the system sans | `--sans` at 13/15/17 px | `.systemFont` at 13/15/17 pt, `.semibold` where the pill needs it |
| the clock | the system sans with tabular digits | `600 15px/1`, `font-variant-numeric: tabular-nums` | `monospacedDigitSystemFont(15, .semibold)` |
| literal machine strings | the system monospace | `ui-monospace` on `code` only (a shell command, a SHA-256) | none: the app has no code surface |
| the hand accent (exception) | Reenie Beanie | the landing's `write it down` hero word and its two section headings, nowhere else | never |

Rules that follow from the table:

- **Tracking.** The kept heading and the failure headline are untracked on both surfaces. The machine
  voice's own tracking stays where the Mac has it: `.02em` on the receipts and the wipe report, `.04em` on
  the warning caption and the pill labels.
- **Every face is served by the site.** `writeitdown/fonts/` holds the woff2 files and their OFL texts,
  `writeitdown/fonts/build-fonts.py` builds them from the app's bundled faces, and `fonts.css` /
  `fonts-cjk.css` are generated from it. No page requests a font host: a third-party font that fails must
  not change what a page renders, and a page that sells privacy must not leak a visitor to a font provider.
- **The declared exception.** The hand accent is the one face outside the product's set. It is a
  marketing voice for the page that sells the product, chosen by the captain on 2026-10-25 (option B of
  the typography inventory). It lives on the landing only: never in the room, never in a copy or result
  state, never on the Mac, and not added to any new surface without a new dated decision. Reenie Beanie has
  one weight, no CJK, and a script face at 13 px would fight the native control look, so the app must not
  gain it.
- **The writing measure is fixed.** One pitch for every script (D-026); the CJK subset must never carry
  altered vertical metrics, because the room's line pitch is fixed in CSS and where a glyph sits inside it
  comes from those metrics.
