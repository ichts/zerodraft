# First Line — Opening Flow Simplification Frozen PRD

**Status:** Frozen for Slice 1 implementation  
**Scope:** Slice 1 only unless user explicitly approves more  
**Source PRD:** `docs/prd/first-line-opening-flow-simplification.v0.md`  
**Execution slice:** `docs/prd/first-line-opening-flow-simplification.slice-1.md`  
**Sisyphus plan:** `.sisyphus/plans/first-line-opening-flow-simplification-slice-1.md`  
**Date:** 2026-05-17

---

## Frozen Decision

Implement one minimal launch gate:

```text
Launch -> Home -> choose duration -> Start writing -> Session
```

Remove the separate intro/warm-up path:

```text
Launch -> Intro -> 90-second warm-up
```

This is based on the writing-app reference pattern:

- iA Writer: no popups, no onboarding ceremony, immediate writing.
- Flowstate / Write or Die: one minimal gate with the destructive rule, then canvas.
- Ulysses / Bear welcome-document patterns are rejected because First Line is not a document manager.

---

## Exact Home Copy

Use exactly:

```text
First Line
The first draft only moves forward.

Stop for 8 seconds and the page clears.

Choose a sprint
[3 min] [5 min] [10 min] [15 min] [25 min]

Start writing

No delete. No paste. No undo.
```

---

## Blockers

None.

---

## Non-goals

- No editor typography/caret/font changes.
- No danger timing changes.
- No SessionView redesign.
- No SuccessView redesign.
- No Markdown export.
- No Library/Settings redesign.
- No tutorial, tooltip, coach mark, quote, or welcome document.

---

## Handoff

Start implementation from:

```text
/start-work docs/prd/first-line-opening-flow-simplification.slice-1.md
```
