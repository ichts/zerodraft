# Siege motion model (landing, desktop)

This file is the SOLE authority for the siege's math. Every constant and formula
below is contract; `design/DESIGN.md` section 7 describes the motion in prose and
points here, and the implementation lives in the `Siege motion` block of
`index.html` (functions `siegeCapture`, `siegeAssignDeadline`, `siegeSynthesize`,
`siegeBuildReinfPool`, `siegeStart`/`siegeBeginPress`, `siegeFrame`,
`siegeAdvanceReinfs`, `siegeKill`, `siegeRecover`, `siegeReset`). If a number here
and a number in the code disagree, the change is not finished.

Provenance: the model was originally derived in a GPT-5.6 Sol advisory that lived
in an unversioned private directory and is lost. This document was reconstructed
from the shipped implementation and verified against it in a real browser
(recorded state samples and a full demo cycle). The parameter values are
therefore authoritative, but the original derivation rationale (why these gamma
ranges, why these compression coefficients) is unrecoverable and is deliberately
not reconstructed here.

## Scope and gating

The siege runs only in the landing demo preview's scripted silence windows, on
desktop, with motion allowed:

- context: demo only - never the fullscreen trial, never an inline live session
  (`siegeContextOk`); active only while the demo pause machinery is in its
  `pause` phase (`siegePauseActive`)
- viewport: desktop only - at or above the flood band-mode breakpoint
  (`design/DESIGN.md` section 11 owns that constant), evaluated at capture/resize
  and cached so the rAF loop never reads layout
- `prefers-reduced-motion: reduce`: engine off at every entry point (press, kill,
  recovery); danger colors still change; wipe and fossil render statically
- offscreen (`IntersectionObserver`) or `document.hidden`: the press is
  cancelled with the demo pause clock; geometry freezes and re-arms on resume

## Clocks and ownership

- The silence clock is the only time source: `t = (demoPauseElapsed + (now -
  demoPauseStartedAt)) / 1000`, clamped to [0, 8] - the same origin the demo's
  danger countdown and 8s wipe read. All geometry is a pure function of `t`;
  nothing integrates per frame, so dropped frames can never drift the wall or
  burst spawns.
- Discrete state (danger on/off, countdown seconds, the wipe trigger) is owned by
  the demo pause machinery's 100ms timeout chain (`updateDemoPause`). The
  Datastar `data-on-interval` ticker owns live sessions, which have no siege.
- Continuous geometry is owned by one rAF loop that writes only `transform`
  (translate3d + rotate) and the two flank opacities. No layout reads inside the
  loop; `will-change` is applied only while the pile moves and removed at
  identity.

## Capture (seeding)

Runs at the end of every `layoutFlood` (load, `document.fonts.ready`, debounced
resize). Deterministic per layout: all randomness comes from `mulberry32(909090)`
(fragment parameters) and `mulberry32(909090 + 7)` (spawn schedule).

- Eligible fragments: the left/right gutter fossils of `#floodBase`, reparented
  to a shared coordinate space. Axis-band and top-band fragments stay put and
  only redden.
- Rank width caps (fossils clip mid-word at the clean column): front 320px,
  mid 280px, back 240px.
- Ranks per side, by capped edge distance to the paper (nearest first): the
  nearest 25% are front, the next 35% mid, the rest back.
- Leads: per side, the front fragment and the mid fragment vertically closest to
  the current line (the paper's rest anchor, `design/DESIGN.md` section 6) are
  leads. Per side, the farthest
  back fragment is the straggler.
- A side with fewer than 3 eligible fragments gets seeded synthetic fossils so
  both flanks always field a wall.
- Travel budgets (inward-only motion by construction): front 130-220px,
  mid 180-320px, back 240-460px, seeded within the range and clamped to the
  available gutter. A rest position shorter than the seeded floor is moved
  outward to the floor; longer than the ceiling, inward to the ceiling.
- Total cap across seeds + reinforcements: 48 fragments.

## Press (the advance)

Per fragment: start `s`, deadline `a`, exponent `gamma`, contact window `rho`,
pressure weight `w`, with `h` a fresh seeded uniform [0,1) per parameter:

| rank  | s              | a (lead / straggler)        | a (others)        | gamma            | rho  | w    |
|-------|----------------|------------------------------|-------------------|------------------|------|------|
| front | 1.00 + 0.18 h  | lead: exactly 5.000          | 5.040 + 0.180 h   | 2.30 + 0.30 h    | 0.85 | 1.00 |
| mid   | 1.06 + 0.24 h  | lead: exactly 6.000          | 6.040 + 0.200 h   | 2.10 + 0.30 h    | 0.65 | 0.65 |
| back  | 1.12 + 0.32 h  | straggler: exactly 7.000     | 6.680 + 0.320 h   | 1.90 + 0.30 h    | 0.45 | 0.40 |

- Arm threshold: below `t = 1.0s` of silence nothing runs, not even the rAF - a
  single timeout is scheduled to the threshold. The pile is pixel-still for the
  first second of every pause.
- Deadline progress: `q = clamp01((t - s) / (a - s))`, position `p = q^gamma` -
  pure ease-in with momentum, no deceleration, no spring. The front lead contacts
  exactly on the 5s danger beat; every seeded fragment holds contact by 7.000s -
  the wall itself is a second countdown.
- Contact load: `z = clamp01((t - a) / rho)`, `c = 1 - (1 - z)^2`.
- Underlap (post-contact push into the paper edge, seeded): front `2 + 8 h`px,
  mid `5 h`px, back `3 h`px.
- Fragment position each frame: `dx = (liveEdge - x0) * p + sideSign * underlap * c`,
  where `liveEdge` is recomputed from the shell's current scale/translate so the
  wall stays glued to the compressing paper.

## Pressure and the shell

- Per-side aggregate: `qL`, `qR` = weighted mean of contact loads `c` by weight
  `w`. Overall pressure `P = (qL + qR) / 2` (0 before first contact, so the shell
  never compresses early).
- Shell compression (`.siege-shell` is the one transform owner wrapping paper +
  result/failure + footer): `sx = 1 - 0.16 * P^1.10`, `sy = 1 - 0.035 * P^1.30` -
  a squeeze, never a zoom-out.
- Asymmetric drift: a seeded strong side biases the sides by +/-5%
  (`qLb = (1 +/- 0.05) qL`, mirrored for `qRb`); `dQ = qLb - qRb`; below the
  0.015 deadband `tx = 0`, otherwise `tx = clamp(40 * dQ, -6, +6)`px.
- Flank shadows (28px red gradients pinned to the paper's vertical edges) carry
  contact pressure only: opacity `0.04 * q` per side, plus `0.14 * q` while
  `body.danger` is set. The rAF drives only their opacity.

## Reinforcement supply

DOM is pre-created at capture (never inserted inside the rAF); widths are
measured in the next frame's read phase.

- Schedule: first slot at `t = 1.35s`, cadence `0.540 + 0.240 h` s (540-780ms),
  last slot before `t = 7.75s`. The birth clock is the scheduled slot, not the
  rAF frame's `t`, so a delayed frame can neither burst spawns nor reclassify a
  seed. One spawn per frame; a slot that fails lane placement is skipped and the
  pool element retries at the next slot.
- Side choice: seeded, balanced within 2 spawns of the other side, never 3
  consecutive on the same side. Counters commit only on a successful birth.
- Lanes: center must be >= 38px from every same-side fragment/reinforcement
  center, within a 440px band centered on the current line; 6 placement retries.
- Birth position: 24-120px beyond the viewport edge.
- Late reserves: a spawn after `t = 6.45s` stops 12px outside the viewport and
  waits for the kill pounce. Earlier spawns stage 36-110px behind the current
  outermost same-side fragment (falling back to the paper edge if that side has
  no wall yet).
- Reinforcement deadline: `a = min(7.000, max(birth + 0.550, 6.700 + 0.300 h))`,
  exponent `gamma = 1.90 + 0.30 h`, same `p = q^gamma` progress from the birth
  slot.
- A reinforcement that reaches its staging face holds there across pauses (the
  silence clock resets each pause; a stale birth clock must never snap a staged
  fragment back to its spawn point).

## Collective kill (the wipe)

Timeline from the wipe moment, total 500ms (inside section 8's wipe budget):

1. 0-120ms pounce: `K(u) = u^2.60`; every fragment (reserves included) snaps
   toward the 0.78-scaled paper edge (+ its underlap) while the shell slams to
   `scale(0.78, 0.78)` and `body.siege-kill` forces all fragments red with no
   transition.
2. At k = 120ms (impact): the lost draft's fossil takes off through the siege
   lines (the existing flight + flash + settle). An interrupted kill that never
   reached impact joins the fossil directly - a wipe always leaves exactly one.
3. 120-180ms: hold.
4. 180-500ms settle: `R(u) = 1 - (1 - u)^3` back to rest/staging/identity;
   `siege-kill` clears at the start of the settle; flank shadows fade across the
   whole kill.

## Recovery and reset

- Scripted teaching recovery (the demo's own resume at the brink): colors and
  flank shadows clear in the first frame; geometry lerps snapshot -> rest over
  180ms with the same `R(u) = 1 - (1 - u)^3`, same curve for all ranks.
- A real keystroke never plays that retreat: real input resets the siege to
  identity instantly (`siegeReset`) because the trial morph takes over the
  screen in the same beat. The 180ms retreat is exclusively the demo's acted
  beat.
- Hard stops (real input, entering the trial, a reduced-motion flip): cancel
  everything, instant identity.

## Performance constraints (contract, not implementation detail)

These are what keep the siege from ever becoming a layout feedback loop:

- no layout reads inside the rAF loop (all rects and the desktop check cached at
  capture); the only per-frame DOM read is a classList check
- transform and opacity writes only; fragment reparenting and pool creation
  happen at capture, never mid-loop
- geometry is a pure function of the silence clock - no per-frame accumulation
- at rest (before arm, after recovery, after the kill, in the dead state) no rAF
  runs and no `will-change` promotion remains

## Verification record

Verified against the shipped implementation in headless Chrome (2026-08-25,
1440x1000 and 390x844): front-lead contact on the 5s danger beat; teaching-pause
maximum squeeze measured `sx = 0.8400`, `sy = 0.9650`, `tx = 4.0` at `P = 0.9999`;
kill observed `scale(0.78, 0.78)` at impact with `siege-kill` held into the
settle; renderer CPU 0.7-3.5% of one core during the press and ~0% at rest; under
`--force-prefers-reduced-motion` no movement in 12s of polling; at 390px the
engine never arms.
