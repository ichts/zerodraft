# Feature flow

Status: the captain's standing rule, adopted 2026-10-25 (定). Every new captain-tier feature follows
these eight steps, from the first sentence to the retro. This file is process only:
`design/DESIGN.md` owns the visual tokens, `docs/wid-decisions.md` owns product decisions,
`docs/ui-quality.md` owns the quality bar a change is measured against, and `docs/missed-cases.md`
carries the misses every later sweep has to read.

## Why the flow looks like this

The captain is good at recognising and judging, and does not want to recall every case in advance. An
agent left alone invents a feature nobody asked for. So the agent generates, exhausts and writes, the
prototypes show the thing, and the captain only picks, rejects and marks.

A full pass costs the captain roughly 45 to 75 minutes of attention, not counting waits.

## Tiers, so the steps are not guesswork

The tier is decided by the change, not by who is in a hurry.

- Captain-tier: anything a person can see, touch or pay for that does not exist yet. A new
  interaction, state, route, modal or stored field; anything about pricing, licensing or updates;
  anything irreversible. If its rejection bar cannot be written in one sentence, it is captain-tier.
  It takes all eight steps.
- Tiny change: copy, one label, one value, one token, one spacing fix, one link. It skips steps 1 to 5
  as the fast path: make the change from current main, run the touched tests, capture the affected
  state, open the PR directly and record the deviation reason. Do not queue it behind a large lane
  that edits the same file, and do not let it grow.
- A bug fix, or a change inside one existing area, also skips steps 1 to 5. It owes the reproduction
  first - the problem is reproduced end to end before any patch - and it still owes the captures in
  step 8.
- When the tier is unclear, take captain-tier. A few extra questions cost minutes; a feature the
  captain never approved costs the product.

## The eight steps

The count is the captain's: the entry capture is step 1, and the two-minute retro closes step 8.

### 1. The idea and its rejection bar

Captain: says the idea however it comes out, a voice note or half a sentence.

Agent: restates it in three lines - who uses it, at what moment, and what they get - and asks one
question only: "What would make you reject this?" The answer is the rejection bar, and it goes onto
the feature card word for word.

Artifact: a short idea note carrying the three lines and the rejection bar.

### 2. Direction check against the vision

Agent: reads `VISION.md`, names any conflict with it out loud, and states a recommendation in one
line.

Captain: answers do, do not, or park. One minute, and it is the last cheap moment to stop the work.

Artifact: the one-line verdict.

### 3. Clickable prototypes

Agent: builds two or three genuinely different directions, not three variations of one layout. On the
web they sit on a throwaway route switched by `?v=a|b|c`; a logic-heavy feature also gets a
single-file state-machine demo. The Mac gets the same treatment on a disposable screen.

Captain: clicks, types, swipes, picks one, and says where the feel is wrong. Taste has the floor here;
that is the point of building before specifying.

Artifact: the prototypes plus the pick, which the card records with its route or build flag.

### 4. Grilling

Agent: asks only the decisions the prototype exposed. At most five questions per round, every
question carrying a recommended answer and worded so that "yes" accepts it. Facts the agent can look
up itself are looked up, not asked. At most three rounds, then the round ends whatever is still open,
and open items become assumptions on the card.

Captain: answers yes, picks A or B, or says "I don't know". "I don't know" is an answer.

Artifact: the decision list, one line per decision.

### 5. Edge-case sweep

Agent: runs an exhaustiveness pass on a GPT-family model. When the GPT quota is out, Gemini or
DeepSeek takes it. The pass is not a brainstorm: it walks the Hendrickson test heuristics - data-type
attacks, numbers, boundaries, CRUD, count, interruption, ordering - then a pre-mortem that assumes the
feature shipped and failed, split into Tigers (real threats), Paper Tigers (looks scary, not worried)
and Elephants (the worry nobody says out loud). It reads `docs/missed-cases.md` first, so the previous
misses are cases here.

A second pass on Fable or Opus cuts the list to at most ten cases and gives each one a default
handling. Cases that were cut stay in the same artifact under a folded heading with the reason they
were cut; nothing is deleted, because a cut case is raw material for the next sweep and for the retro.

Captain: marks each of the ten want, later, or ignore. That is the whole job on this step.

Artifact: the marked case list, top ten and the folded remainder.

### 6. The feature card

Agent: fills `docs/feature-card-template.md` from steps 1 to 5. One page. Anything the captain did not
confirm goes under "Still assumptions" rather than being written as if it were decided.

Captain: reads one page and corrects what is wrong. The captain does not fill the card.

Artifact: the card.

### 7. Implementation

Agent: a fresh session, reading the card and `AGENTS.md` and nothing else from the earlier
conversation. Thin slices, each one runnable. A decision the card did not contain is written into the
card's implementation notes instead of being made silently, so the next reader can see what was
invented.

Artifact: the code and the implementation notes.

### 8. Captures, the feel check, and the two-minute retro

Agent: captures every affected state at real size and records one pass or fail line per rule in
`docs/ui-quality.md`, each pointing at its measurement or capture. A different model family then
reviews those captures; the builder never grades its own evidence.

Captain: ten minutes on the real surface, checking how it feels rather than only whether it works.
Basic polish is not escalated to the captain; it is fixed without asking.

Then one question closes the feature: "What did this round miss?" Each miss is appended to
`docs/missed-cases.md`, newest first, with the date and the feature. Every later sweep reads that
list, so the same miss is not made twice.

Artifact: the capture set, the review, and the log entry.

## What the captain never does here

- Fill the card, mark the case list on the agent's behalf, or review the code.
- Sit through the exhaustiveness pass. It is a long list on purpose, and it is the agent's work.
- Approve a feature that never got a rejection bar.

## What the agent never does here

- Invent a fourth prototype direction after the captain picked one.
- Skip the folded cut list, or drop a case without a written reason.
- Ship without a card, or widen the scope beyond the card and call it a detail.
- Ask more than five questions in a round, or ask a question it could answer by reading the code.
