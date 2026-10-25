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

### Color - six colors + one alarm

| Token | Value | Use |
|---|---|---|
| `--bone` | `#f1f0eb` | The wall. Environment, everywhere. |
| `--paper` | `#ffffff` | The one object. Nothing else in the product is white. |
| `--ink` | `#17150f` | Words, primary chrome, the door. |
| `--dim` | `#6b665b` | Secondary chrome, reports, receipts. |
| `--faint` | `#b3ada0` | Receded chrome while typing. The quietest legal text. |
| `--line` | `#dedcd5` | Hairlines only. 1px, never thicker. |
| `--danger` | `#c8392f` | The warn numeral and the wipe cut. Nothing else. |

Red is a budget: it means "you are losing the draft". The logotype underscore is ink. No red on links, borders, emphasis, or decoration. No blue. Selection is an ink tint (`rgba(23,21,15,.18)`).

The wash exists only during warn, seconds 5-8:

| Token | Value | Use |
|---|---|---|
| `--wash-wall` | `color-mix(in oklab, bone 88%, danger)` | The landing wall during warn. |
| `--wash-paper` | `color-mix(in oklab, paper 88%, danger)` | The paper (and the trial room) during warn. |
| `--wash-wall-deep` / `--wash-paper-deep` | color-mix at 76% | The eighth second goes one step deeper: at 8.0s the wash deepens to double the danger share for the wipe-cut beat, then exits. |
| `--wash-*-1` / `--wash-*-2` | color-mix at 96% / 92% | Reduced-motion wash steps (see §6). |

### Type - two faces

Newsreader is the human. IBM Plex Mono is the machine. The machine never speaks serif; the human never speaks mono.

| Style | Spec | Use |
|---|---|---|
| display | Newsreader 500 · clamp(44px, 6vw, 72px)/1.04 · -.015em | Landing headline only |
| deck | Newsreader italic 400 · 24/1.45 · `--dim` | "It's not supposed to be good yet." |
| script | Newsreader 400 · 21/1.6 · measure <=62ch · never justified | The user's words. Typos survive. |
| numeral | Plex Mono 600 · min(40vh, 360px) · tabular · `--danger` | Exists only while paused >=5s. The loudest object we own. |
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

The wall is gone; the paper is the room (the room is paper white). Objects: paper · clock. Chrome lives in the corners: rules TL · timer TR · exit BL · words BR. Idle chrome is full ink; while keys arrive it recedes to faint (the timer runs at dim). Nothing reacts to a keystroke - no sparks, no shake, no sound. The reward for writing is silence.

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
| TYPING - keys arriving | unchanged; the room never reacts to a keystroke | recedes to faint; timer runs at dim | the user's serif - the only mess allowed | identical |
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
The primary web header is the landing, the room, `/download/`, and `mac.html`; those surfaces use the lockup, and
the social card uses the same lockup. The legal, support, and answer pages keep the mono `WRITE_IT_DOWN` logotype
and adopt the favicon. The native Mac app's in-app start screen uses the lockup; the app icon and volume icon carry
the mark.

### 11.1 The mark and the wordmark

The mark is the split W: Newsreader's W with a vertical notch through its middle peak. The wordmark is
`Write It Down` in Newsreader 500, with the same split W. The web header sets the mark as its own object beside
the wordmark (11.6); the Mac start screen and the social card keep the wordmark lockup, whose W already carries
the notch.

- Site header and footer: `writeitdown/logo/write-it-down-lockup.svg` - the app-icon chip, a gap, and the
  wordmark, at 21 px type on desktop, 19 px below 820 px, and 16 px at 380 px and below. The site draws it as one
  CSS mask over `currentColor`, so one vector serves the light and dark themes and the brand follows the site's
  ink token. Minimum lockup width: 16 px type, the narrow-phone step; the 16 px favicon is the smallest use of
  the mark.
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
  used in the light appearance. The header chip (11.6) is not a plate colour at all: its plate is the ink token
  and its W is a hole, so it is ink on the light page and bone on the dark page.
- The mark itself is flat: no gradient, outline, shadow, bevel, or second colour. The app icon's plate gets the
  system shadow; the volume icon may carry the Finder/disk shadow as a packaging surface.

### 11.3 Sizes and clear space

- App icon: 1024 master, with optical 16 and 32 drawings, all on the bone plate with the ink W. The
  `AppIcon.appiconset` uses the opticals for the 16/16@2x and 32/32@2x entries and the master for 128 and above.
  The plate is the 824/1024 macOS squircle on a 1024 canvas. The 16 and 32 app icons keep the optical drawing, not
  a downscaled master.
- Favicon: `favicon.svg` and `apple-touch-icon.png` use the master split W; `favicon-16.png` and `favicon-32.png`
  use the same optical split drawings as the small app icons on the bone plate. `favicon-dark.svg` and the dark
  16/32 PNG are the `prefers-color-scheme: dark` links; `apple-touch-icon.png` is 180 on the bone plate. The
  favicon is the full-bleed square, not the app icon's transparent-margin squircle.
- Site header: 21 px desktop, 19 px at 820 px and below, 16 px at 380 px and below; the chip is 1.5 cap heights
  (1.046 em: 22 px at 21 px type, 19.9 px at 19 px, 16.7 px at 16 px), the gap to the wordmark is 0.34 em, and
  the lockup box is 7.467 x 1.046 em. The lockup's clear space is at least a quarter of the cap height on all
  sides (about 5 px at 21 px). The header link may extend its hit area without enlarging the lockup.
- Site header, mobile: the lockup takes 141.9 px of the 19 px row, so the mobile header keeps 12 px between the
  brand and the page action and 6 px inside the action group; that is what puts the theme button back on the
  page's right gutter at 390 px.
- Site header, narrow phones: at 380 px and below the lockup is 16 px type (119.5 px of row), which is what keeps
  the widest header - `/download/`, with the brand, `Try it in your browser` and the theme button - off the right
  edge: 10 px of gutter at 360 px, 17.6 at 375 px, 20 at 390 px. One rule for every page that uses `.brand`, so
  `/download/` does not diverge from the landing and `mac.html`.
- Volume icon: `packaging/VolumeIcon.icns`, all Finder sizes from 16 to 1024.
- The source set is `writeitdown/logo/`, `writeitdown/favicon*`, `writeitdown/apple-touch-icon.png`, and
  `writeitdown/og.png` for the site; the app icon set, `packaging/VolumeIcon.icns`, and
  `Sources/FirstLine/Resources/write-it-down-lockup.svg` for the Mac. The legal, support, and answer pages use the
  mono `WRITE_IT_DOWN` logotype; the Mac start screen uses the bundled lockup. The app icon `.icns` is the light
  plate; there is no dark app-icon alternate in the app icon set.

### 11.4 Do not

- Put red, the old red underscore, or the old `WID` sheet in the mark.
- Give the header chip a second colour. It is one ink-only mask: the plate is `currentColor` and the W is a hole,
  so the tile is ink on the light page and bone on the dark page without a light/dark pair of files.
- Separate the chip from the wordmark inside one SVG (no line, no rule, no caption) or set the chip alone above,
  below, or after the wordmark.
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
- Site header: `qa/mac.spec.mjs` "the header lockup shows the A mark chip beside the wordmark" reads the shipped
  mask at the rendered header size and requires the plate to cover the top of the chip, the W to be knocked out
  of it, the split to survive at 2x, and the wordmark to follow it; it fails on a wordmark-only lockup.
  "the header keeps its right gutter and a legible chip at 360 px" repeats it at 360 px and requires no
  horizontal overflow, at least 6 px of right gutter, one lockup step across landing, `/download/` and `mac.html`,
  and a chip of at least 16 px with the split still reading. 21 px desktop, 19 px below 820 px, 16 px below
  380 px, light and dark, with no clipping and no shift in the nav.

### 11.6 The web header chip

The header and footer lockup opens with the mark as a chip: the app icon's squircle plate at 1.5 cap heights, the
split W knocked out of it, the wordmark 0.34 em to its right on the same baseline. At 21 px the notch inside the
wordmark is invisible, so a wordmark-only lockup reads as plain words and the product has no logo in the corner;
the chip makes the mark an object while staying one colour and one file.

- The chip is the app icon's drawing: the 824/1024 macOS squircle plate around the master split W, at the app
  icon's 620/824 W share, with the plate optically centred on the wordmark's cap band.
- The chip is the small-size variant of the mark: its notch is 180 word-units (11% of the W) instead of the
  master's 90, the same optical widening the 16/32 favicons use, so the split still reads at 22 px.
- Because the W is a hole, the tile takes the page colour where the light falls through it: dark tile with a light
  W on the light page, bone tile with a dark W on the dark page. That is the app icon's two appearances without a
  second palette, a second file, or a theme switch in CSS.
- Do not carry the chip to the Mac start screen or the social card; both keep the wordmark lockup.
- On narrow phones the lockup steps to 16 px type (DESIGN 11.3) instead of letting the header push the theme
  button past the page gutter; the chip's widened notch is what keeps the split readable at 16.7 px.
- Mac: the split-W lockup on the start screen in light and dark; the app icon at 16/32 (optical), 128 (Dock), and
  1024; the volume icon at 128 and 1024. Static asset inspection, the deterministic view test and the light/dark
  start-screen captures are recorded in `apps/macos/FirstLine/docs/MANUAL_QA.md`; Dock and Finder captures on light
  and dark remain separate independent acceptance.
- `grep` for the old `WID` icon, the red underscore, and the `.brand i` caret returns nothing in the shipped
  surfaces. The logo files contain no `<text>` and no red token.
