---
name: verify-writing-deadlines
description: Check the real browser writing code when changing deadline adjudication, the first-input clock, silence deletion, late input, or the unused-time receipt in index.html or writeitdown/session.mjs. Explore a finite set of reachable prefixes and event orders and report failures without masking them.
---

# Verify writing deadlines

A late key must not rescue an expired draft or change the draft after its completion deadline, and the wipe receipt must describe the deadline that fired. A wrong decision either destroys earned writing or keeps writing that the product promised to delete.

## Run

From the repository root:

```sh
node .pi/skills/verify-writing-deadlines/verify.mjs
```

Node v26.12.1 was used for the recorded run. No npm dependencies are needed. The default checks both browser implementations and exits nonzero on ANY failed rule. `--surface root` and `--surface web` select one implementation. `--repo /absolute/scratch/path` checks a scratch source copy. `--rule root.tick.earliestDeadline` selects ONE rule for the mutation demonstration only; a pass there is not a full pass.

The checker executes the actual inline bridge, the editor input listener and the actual `data-on:fl*` expressions through Node VM. It only instruments the returned bridge object to expose `bindSessionEditor`. The sibling check imports the actual `advance` and `append` functions. No second implementation of the system under test is used. `decision` in the verifier is the independent requirement oracle: both deadlines are absolute, the earlier one wins, a tie goes to the wipe, and unused time is measured at the wipe deadline rather than at callback delivery.

## The rules it asserts

Every rule below is a permanent assertion. A failure is a real product bug, not a checker bug.

| Rule | What must hold | Failure this rule caught |
|---|---|---|
| `root.tick.earliestDeadline` | the tick applies the earlier absolute deadline | mutation proof below |
| `root.receipt.deadlineNotCallback` | the receipt reports `0:00` minus the wipe deadline, on the tick path and on the fresh-draft path | at `fa63af1` a 9 s catch-up tick printed `Draft wiped - 0:51 unused.` instead of `0:52` |
| `root.input.noLateRescue` | a key or composition commit after the wipe line starts a fresh draft holding exactly the text that event inserted | at `fa63af1` a key at 8.1 s left the editor holding `oldn` |
| `root.input.receiptDeadline` | a fresh draft announces the receipt for the deadline that fired, and the wipe report stays off the live room | a scratch break that measured the receipt at the key's instant announced `0:40` for a deadline that left `0:44` (last key at 0:08, key at 0:20) |
| `root.input.deadlineBeforeAppend` | a key after 0:00 is dropped and the draft is kept with the text it had | at `fa63af1` the session stayed live and grew to `old… new` |
| `root.input.liveAppend` | a live key appends exactly once | guard |
| `web.tick.earliestDeadline`, `web.tick.clearsDraft`, `web.receipt.deadlineNotCallback`, `web.input.noLateRescue`, `web.input.deadlineBeforeAppend`, `web.input.liveAppend` | the same rules on the shipped `writeitdown/session.mjs` | guard; these never failed |

At `fa63af1` (before the input path adjudicated its own keys and before the receipt used the triggering deadline) the unfiltered run reported exactly the three root-page failures above. At the current tree it reports `22976` checks with no failure; the three cases are kept as assertions so the regression cannot come back.

## How it runs the real code

- `index.html`: `commitInput`, `bindSessionEditor`'s input listener, `adjudicate`, `tickDispatch`, `sessionWipe`, `wipeReport`, `beginFreshDraft`, `sessionComplete`, and the body's `flinput`/`flfresh`/`flfail`/`flcomplete`/`fldanger` event expressions.
- `writeitdown/session.mjs`: `fresh`, `advance`, `append`.
- `root-adapter.mjs`: execution adapter only. An expression is compiled as a function body, the way Datastar compiles it, so `const`/`let` inside an expression are legal here exactly as in the browser. The fake document satisfies only the DOM calls the transition paths make (`querySelector('.trial-editor')`, `createRange`, `getSelection`, `focus`); it does not render and does not run `data-effect` DOM changes. It throws with an explicit message when the source shape it depends on moves, so review any adapter change against the real page.
- When a covered function or binding changes, compare the source with the adapter and oracle, rerun the unfiltered command, replay every counterexample, and repeat the mutation check. Advance the sync commit below only after confirming that the verifier still describes the new code. Use `/maintain-formal-verification-skill` for changes that skipped this check.

Last checked against the fix commit recorded in `git log -1 --format=%H -- .pi/skills/verify-writing-deadlines`.

## Scope and bounds

The finite input universe is 60 reachable committed-text prefixes, with latest input at each integral second 0 through 59. Prefixes keep typing at most four seconds apart. For each prefix, explore all integral callback/input times from that latest input through second 68, plus one millisecond before, exactly at, and one millisecond after warning, wipe and finish boundaries. Check tick alone and input delivered before the pending tick. The first input uses a positive epoch. Duration is 60 seconds, silence 8 seconds, warning 5 seconds. Text is nonempty ASCII, and every post-wipe case is fed twice: an append, and a composition commit whose text replaces the marked text the model already holds, so the committed DOM text is not an append of the model.

This is exhaustive over that finite universe, not a mathematical proof over arbitrary JS values or a symbolic proof of JavaScript. It does not cover actual Datastar scheduling, DOM effects, browser rendering, a real IME candidate window, wall-clock jumps, the Mac runtime, licence cryptography, or storage. The TLA+ model in `model/` is a separate design-level exploration, not a generated proof of source equivalence.

## Prove it can fail

```sh
node .pi/skills/verify-writing-deadlines/prove-break.mjs /tmp/verify-mutation
```

This copies `index.html` under the chosen evidence directory, changes the real tie comparison from `<=` to `<` in that copy, runs the real verifier, restores the copy in `finally`, then reruns. Expected sequence: before exit 0, broken exit 1, restored exit 0 for `root.tick.earliestDeadline`. The broken run must say the tie kept the draft rather than wiping it. The tracked product file is never edited. Use a directory outside the repository, or the default under the system temp directory.

## Read failures

Each failed rule prints the first concrete last-input time, callback/input time, expected outcome and actual outcome, plus the number of failing cases in the stated universe. One cause can fail many cases. If a counterexample cannot happen in the source, fix the adapter or model and document why. If it can happen, keep the finding. Never weaken a property to obtain a pass.

The Playwright suite asserts the same behaviour through the real browser and a controlled clock: `tests/trial-deadlines.spec.mjs` (`npm test`) covers the fresh draft after the wipe line and the receipt it announces, the dropped key after 0:00, the deadline-based receipt, the delayed keep, the tie, and a composition committed after the wipe line (a committed candidate that replaces the marked text, and one that equals it).

## Model

`model/WritingFlow.tla` and its configs are the design-level model of the room and the Mac admission boundary: 18 named invariants, one per rule a writer relies on. The model encodes the shipped rule on every surface: an input consults its own deadline (`InputAt` reads `Decision(t)`), so a post-wipe key replaces the draft instead of appending to it. The fresh draft's clock is faithful too: `FreshClockStartsAtKey` requires the restarted room's `started` and `last` to equal the key's instant, the same values `data-on:flfresh` writes. `DeadlineReceipt` checks the receipt on the tick path, where the ended session's numbers are still in the state; the key path's announced receipt is asserted by `root.input.receiptDeadline` and the browser spec, because the same step also resets the clock to the new session. `BeginAgain` is the kept room's way forward: `已保留` opens an armed empty room again, the next first key charges a Mac trial session as any first key does, and a spent trial goes to the activation screen instead. `WritingFlow-{5,8,12}.cfg` check all 18 plus deadlock and pass.

`WritingFlow-historical-fa63af1.cfg` is history, not a claim about today. Its `RootRule = "prefix"` restores the Root surface as it behaved at `fa63af1` - every input appended whatever the decision said, and the receipt was measured at the callback - so the pre-fix violations stay reproducible: `NoLateRescue`, `DeadlineBeforeInput`, `DeadlineReceipt`, and `FreshClockStartsAtKey`, because that key never reset the clock either. `WritingFlow-chart.cfg` is the chart-size config: the writer's room alone with the instants its story turns on, all 18 rules kept, 479 states. Run the model with `/statechart` and read the result with that skill's report, not as a proof of the source.

## Chart

`chart.mmd` is the Mermaid source the chart config produces, and `chart.png` is its render: 8 states, 17 arrows, Chinese labels, the whole room from `入口` to `已保留` / `已删除` / `已离开`. It shows the two ways forward out of a dead end - `已保留` goes back to `空房间` with `再次开写`, and the wiped room stays armed for the next key - and it keeps the warned draft that reaches 1:00: `静默警告` goes to `已保留` as well. Regenerate them from `WritingFlow-chart.cfg` whenever the model changes; a chart above 500 states is drawn only as bug paths, which this model no longer has.
