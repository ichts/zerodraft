# First Line — Opening Flow Simplification Slice 1

**Status:** Ready for execution  
**Scope:** Slice 1 only  
**Source PRD:** `docs/prd/first-line-opening-flow-simplification.v0.md`  
**Target app:** `apps/macos/FirstLine/`  
**Created:** 2026-05-17

---

## Objective

Remove the separate first-run warm-up intro and make every launch open to one minimal Home gate.

The execution agent must make First Line feel like a focused drafting tool, not an onboarding flow.

---

## Non-goals

Do not implement any of these:

- No editor typography/caret/font changes.
- No danger timing changes.
- No SessionView redesign.
- No SuccessView redesign.
- No Markdown export.
- No Library/Settings redesign.
- No tutorial, tooltip, coach mark, quote, or welcome document.
- No changes outside `apps/macos/FirstLine/` except this PRD/slice if needed.

---

## Product Decision

Implement this exact opening model:

```text
Launch -> Home -> choose duration -> Start writing -> Session
```

There must be no intro path:

```text
Launch -> Intro -> 90-second warm-up
```

---

## Exact Home Copy

Use this exact copy:

```text
First Line
The first draft only moves forward.

Stop for 8 seconds and the page clears.

Choose a sprint
[3 min] [5 min] [10 min] [15 min] [25 min]

Start writing

No delete. No paste. No undo.
```

Do not use these rejected strings anywhere in Home/Intro:

- `Write the first draft. Do not look back.`
- `For 90 seconds, write without editing.`
- `Start 90-second warm-up`
- `After the warm-up, choose your own session length.`

---

## Files to Inspect

- `apps/macos/FirstLine/Sources/FirstLine/App/AppState.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/RootView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/HomeView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/IntroView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/Infrastructure/SettingsStore.swift`
- `apps/macos/FirstLine/Tests/FirstLineTests/SmokeFlowTests.swift`
- `apps/macos/FirstLine/Tests/FirstLineTests/SettingsStoreTests.swift`
- `apps/macos/FirstLine/docs/MANUAL_QA.md`
- `apps/macos/FirstLine/CLAUDE.md`

---

## Files Likely to Modify

- `apps/macos/FirstLine/Sources/FirstLine/App/AppState.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/RootView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/HomeView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/IntroView.swift` — preferred delete
- `apps/macos/FirstLine/Sources/FirstLine/Infrastructure/SettingsStore.swift`
- `apps/macos/FirstLine/Tests/FirstLineTests/SmokeFlowTests.swift`
- `apps/macos/FirstLine/Tests/FirstLineTests/SettingsStoreTests.swift`
- `apps/macos/FirstLine/docs/MANUAL_QA.md`
- `apps/macos/FirstLine/CLAUDE.md`

Optional only if touched:

- `apps/macos/FirstLine/Sources/FirstLine/Session/FailureView.swift`

---

## Exact Todo List

Keep one item in progress at a time.

1. Remove the intro route and onboarding state.
2. Update Home to the exact minimal launch gate copy.
3. Update tests/docs and run validation.

---

## Required Code Changes

### 1. `AppState.swift`

Remove:

- `Surface.intro`
- `isIntroductionTrialActive`
- `startIntroductionTrial()`
- `completeIntroductionIfNeeded()`
- `settings.hasCompletedIntroduction` checks inside `launchInitialSurface()`

Make launch behavior:

```swift
private func launchInitialSurface() {
    selectedSurface = .home
}
```

Keep:

- `selectedDuration`
- `startSession(duration:)`
- `openWritingMode()` behavior unless tests prove it must change
- Library/Settings methods unless compile cleanup requires changes

### 2. `RootView.swift`

Remove `.intro` case from routing.

### 3. `IntroView.swift`

Preferred: delete the file.

If deletion creates project-file friction, leaving the file unused is acceptable only as a temporary compile-safe fallback, but there must be no runtime route to it.

### 4. `SettingsStore.swift`

Remove `hasCompletedIntroduction` from `AppSettings`.

Do not add migration code unless tests prove decoding old settings fails.

### 5. `HomeView.swift`

Update to exact copy above.

Visible Home controls must be only:

- duration segmented picker
- `Start writing` button

Home must not show:

- intro/warm-up text
- quote
- font controls
- tutorial paragraphs
- Library/Settings buttons

### 6. Tests

Update tests; do not delete coverage to get green.

Required test intent:

- fresh `AppState` selects `.home`
- returning/settings-backed `AppState` selects `.home`
- settings round-trip no longer uses `hasCompletedIntroduction`
- existing session and editor tests still pass

---

## Acceptance Criteria

Slice 1 is done only when all are true:

- Fresh launch shows Home, not Intro.
- Returning launch shows Home.
- `Surface.intro` is gone.
- No runtime path calls `startIntroductionTrial()`.
- `AppSettings.hasCompletedIntroduction` is gone.
- Home uses exact copy from this slice.
- Home duration options remain exactly 3, 5, 10, 15, 25 minutes.
- `Start writing` starts a normal session using selected duration.
- Append-only behavior is unchanged.
- Chinese IME behavior is unchanged.
- Fixed fonts remain Pitch Light + Zhuque Fangsong.
- `swift build` passes.
- `swift test` passes.
- Manual `swift run` visually confirms Home is the opening surface.

---

## Validation Commands

Run from `apps/macos/FirstLine`:

```bash
swift build
swift test
swift run
```

Manual QA must include a clean config launch:

```bash
rm "$HOME/Library/Application Support/First Line/Config/settings.json"
swift run
```

If preserving the user's real settings during QA, back up and restore that file.

---

## Risks

- Current tests explicitly assert `.intro`; update them to assert `.home`, do not delete them.
- Removing `hasCompletedIntroduction` changes `AppSettings` initializer sites.
- `CLAUDE.md` must be updated if `IntroView.swift` is deleted.
- A stale settings file with `hasCompletedIntroduction` should not block launch.

---

## Stop Conditions

Stop and ask before continuing if:

- Removing `hasCompletedIntroduction` requires custom migration code.
- Removing `Surface.intro` cascades into a broad navigation redesign.
- Any editor, IME, caret, typography, or danger-timer behavior breaks.
- The implementation would require changing SuccessView, Library, export, or Settings beyond compile cleanup.

---

## Handoff

Use this exact execution brief:

```text
/start-work docs/prd/first-line-opening-flow-simplification.slice-1.md
```
