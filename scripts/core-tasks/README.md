# Core tasks: the three things a person must be able to do

One command answers "is the product cheaper to use than it was", for the three tasks the captain's design rulebook
names:

| | task | starts | ends |
|---|---|---|---|
| T1 | Begin to writing | navigation begins | the first character is painted |
| T2 | Finish to text | the first character is painted | the text is on the clipboard |
| T3 | Buy to checkout | the landing is loaded | the hand-off to Stripe Checkout |

For each: **steps** (the actions a person must take, typing reported separately) and **ms** (the sum of the product's
own latencies). Human think time is not included and nothing is estimated: a value that cannot be measured is `null`
and the line says `unmeasured`.

## Run it

```bash
npm run core-tasks                                   # 3 runs, both viewports, all three tasks (~25 min: T2 is a real 60 s write)
npm run core-tasks -- --tasks 1,3 --runs 1           # the fast shape while working on the door or the buy path
npm run core-tasks -- --compare docs/core-tasks-baseline.json
npm run core-tasks:test                              # the scorecard's wording and noise rule, no browser
```

Output goes to `scripts/core-tasks/out/<stamp>/`: `web.json` (raw runs), `metrics.json` (the same shape
`data/wid-core-tasks-baseline` reads, so `core-tasks.py compare` accepts it too) and `shots/` (the landing, the empty
room, the first character, the kept and copied screens, the purchase page).

It serves `writeitdown/` itself over loopback on a free port and drives the installed Chrome, from a fresh browser
context every run (empty cache, storage and cookies). Timestamps are taken in the page with
`performance.timeOrigin + performance.now()`, one wall clock across both documents.

## What it will never do

- **No money and no licence request.** T3 answers `POST /api/v1/checkout` locally and aborts the navigation to
  `checkout.stripe.com` before it leaves the browser, so no session is created and no card is touched. The licence
  service is never contacted, and no key is fetched: the return leg is not measured here.
- **No Mac.** The Mac half of the three tasks needs the VM rig; that harness stays in
  `data/wid-core-tasks-baseline/mac/` and is not replaced by this one.
- **No claim about a person.** It reads the page instantly; every number is the product's own latency floor.

## Reading a number

Two things make a raw millisecond mean less than it looks:

- **The host.** Every value carries whatever the machine took. The run prints the load average before and after; a
  run at load 70 and a run at load 5 are not comparable in absolute terms. `--compare` therefore calls a change
  smaller than 5% or 50 ms `within noise` and reports only steps as a hard number.
- **The deadline.** T2's 60 seconds is the product's rule, not a latency. The meaningful figures are
  `deadline_overrun_vs_60000` (first input event to the kept screen painted, so the milliseconds a writer waits past
  zero) and the copy click.

`docs/core-tasks-baseline.json` is the recorded baseline (main `89b4870`, 2026-11-10, three runs per viewport, load
average 4 to 8.) Re-record it only when the product's own rules change, and say which build it came from.
