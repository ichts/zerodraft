# First Line Web / Native Alignment Notes

Date: 2026-06-14
Status: repair backlog

## Why this exists

The landing page and browser trial now sell the Mac app directly. The core promise is aligned enough, but the post-session surface is not. This note captures the differences that can affect user trust after download.

## What already matches

- Core mechanic: stop typing long enough and the draft is lost.
- Timing model: 5 seconds enters danger, 8 seconds clears/fails.
- Writing constraint: append-only; no delete, paste, or undo.
- Focus model: current thought stays readable, older thoughts fade or disappear.
- Failure model: lossful by design; no recovery flow.

## Trust-impact gaps

### 1. Web trial offers `Save .md`; native app does not

Impact: high.

The web trial result screen offers `Save .md`. The native success screen only offers `Copy full text` and `Discard and start next`. A user who tries the browser version first may expect the downloaded app to include at least the same manual export action.

Preferred repair:

- Add manual `Save .md` to native success.
- Do not auto-save every success.
- Use a normal macOS save/export panel or equivalent user-chosen destination.
- Keep the file as readable Markdown with minimal metadata.

Alternative repair:

- Remove `Save .md` from the web trial until native has parity.

Decision leaning: add native manual export.

### 2. Native success CTA says `Discard and start next`

Impact: high.

This is conceptually correct but emotionally harsh. Right after a successful session, the word `Discard` makes the product feel unsafe. The web trial says `Start next`, which feels calmer.

Preferred repair:

- Rename visible button to `Start next draft`.
- If the text has not been copied/exported, use a confirmation that says the text will be lost unless copied/exported.
- Keep destructive clarity in the confirmation, not in the primary visual label.

### 3. Web result nudges AI cleanup; native result does not

Impact: medium.

The web trial says: copy this into your AI editor and ask it to organize the mess. Native success only shows text and buttons. This changes the user's understanding of what to do next.

Preferred repair:

- Either add the same quiet post-session hint to native success, or remove it from web.
- If kept, phrase it as workflow guidance, not a product feature.

Decision leaning: keep one quiet, consistent hint on both surfaces.

### 4. Landing/trial polish is higher than first native transition

Impact: medium.

The web has a strong paper-to-fullscreen morph. Native Home to Session is a normal native switch. This is acceptable as landing-page theater, but it raises the emotional bar for first launch.

Preferred repair:

- Do not chase the exact web morph in Swift.
- Make native start feel intentional: strong focus handoff, no visual jump, timer/progress visible immediately, editor focused immediately.
- If adding motion, keep it short and native: subtle paper fade/scale, not web-style spectacle.

### 5. Public docs still contain stale persistence language

Impact: medium if published, low if internal only.

Examples found:

- `apps/macos/FirstLine/README.md` says progress is saved automatically.
- `apps/macos/FirstLine/docs/MANUAL_QA.md` still asks to confirm markdown files appear in Library.
- `PersistenceService.saveSuccessfulSession` exists, but current smoke tests assert success does not auto-save.

Preferred repair:

- Update user-facing README before release.
- Keep internal PRD as the source of truth: clipboard-first, manual export later, no internal document-manager posture.

## Recommended fix order

1. Add native manual `Save .md` or remove web `Save .md`.
2. Rename `Discard and start next` to `Start next draft` with a loss confirmation when needed.
3. Align the post-success AI/workflow hint across web and native.
4. Clean README/manual QA release-facing contradictions.
5. Only then consider native transition polish.

## Non-problems

- Web trial is fixed at 1 minute while native defaults to longer sprint presets. Trial is a sampler.
- Web autoplay demo loops and recovers from danger. Users will read this as explanation, not app behavior.
- Web has a morph transition and native does not. Acceptable unless native first-run feels broken or abrupt.
