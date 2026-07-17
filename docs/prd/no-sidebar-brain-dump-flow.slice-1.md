# First Line — No-Sidebar Brain Dump Flow Slice 1

**Status:** Ready for `/start-work`  
**Scope:** Slice 1 only  
**Source PRD:** `docs/prd/no-sidebar-brain-dump-flow.freeze.md`  
**Target app:** `apps/macos/FirstLine/`  
**Created:** 2026-04-25

---

## Objective

Make the first writing loop stop feeling like a document app.

Slice 1 must:

1. Remove the persistent sidebar and sidebar-based navigation.
2. Replace the hub-like home screen with a minimal start screen.
3. Stop automatically saving successful sessions to the internal library.
4. Replace the current success page with a simple writing-finished page: **Copy full text** or **Discard and start next**.

In plain language: after writing, First Line should say, “Here is what you wrote. Copy it, or throw it away and start again.”

---

## Non-goals

Do not implement these in Slice 1:

- No locked-prefix Continue flow.
- No Markdown export.
- No Obsidian or iCloud Drive export.
- No app-window close interception.
- No full settings redesign.
- No internal Library surface in the primary flow.
- No Open in Default Editor.
- No Reveal in Finder.
- No Go to Library.
- No changes to the separate Datastar web app.

---

## Relevant PRD

- Frozen PRD: `docs/prd/no-sidebar-brain-dump-flow.freeze.md`
- Slice source: section `15. Implementation Slices` → `Slice 1 — Remove sidebar and clean up the first writing loop`

Frozen scope reminder:

> Slice 1 only unless user explicitly approves more.

---

## Files to inspect

- `apps/macos/FirstLine/Sources/FirstLine/App/RootView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/AppState.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/HomeView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/FirstLineApp.swift`
- `apps/macos/FirstLine/Sources/FirstLine/Session/SuccessView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/Infrastructure/PersistenceService.swift`
- `apps/macos/FirstLine/Tests/FirstLineTests/SmokeFlowTests.swift`

---

## Files likely to modify

- `apps/macos/FirstLine/Sources/FirstLine/App/RootView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/AppState.swift`
- `apps/macos/FirstLine/Sources/FirstLine/App/HomeView.swift` or a new minimal start view file
- `apps/macos/FirstLine/Sources/FirstLine/Session/SuccessView.swift`
- `apps/macos/FirstLine/Sources/FirstLine/FirstLineApp.swift`
- `apps/macos/FirstLine/Tests/FirstLineTests/SmokeFlowTests.swift`
- `apps/macos/FirstLine/CLAUDE.md` if file responsibilities change

Do not modify files outside this slice unless a compile/test failure proves it is necessary.

---

## Exact todo list

Keep at most one item in progress at a time.

1. Replace sidebar navigation with single-surface routing.
2. Replace the home/success flow with minimal start and writing-finished actions.
3. Update tests/docs and run validation.

---

## Acceptance criteria

Slice 1 is done only when all are true:

- App launch/primary route renders no persistent sidebar.
- Primary flow exposes no Library, Settings, Open Folder, Open in Default Editor, Reveal in Finder, or Go to Library action.
- Start screen has only the minimal start experience: framing, preset duration, and start action.
- Starting a session still reaches the append-only writing surface.
- Existing danger behavior still works: idle enters danger, extended idle fails, duration completion succeeds.
- Successful session does **not** automatically save to the internal library.
- Writing-finished page shows only:
  - Copy full text
  - Discard and start next
- User cannot start the next session from the writing-finished page without copying or explicitly discarding.
- Writing-finished page does not show Export Markdown or Continue.
- Success/failure routing works without `NavigationSplitViewVisibility`.

---

## Validation commands

Run from `apps/macos/FirstLine`:

```bash
swift build
swift test
```

Both must exit successfully before the slice is considered complete.

---

## Risks

- Existing tests encode sidebar visibility and will need careful replacement, not deletion for convenience.
- Removing navigation shortcuts may leave dead menu commands.
- Current success flow assumes `lastSavedFileURL` and automatic persistence.
- Stopping auto-save may expose hidden coupling between `AppState`, `SessionEngine`, `SuccessView`, and `PersistenceService`.
- Copy-to-clipboard may need a test seam if direct pasteboard assertions are brittle.

---

## Stop conditions

Stop and reassess before continuing if any of these happen:

- Append-only typing breaks.
- Chinese/IME typing breaks.
- Danger timer or failure behavior breaks.
- App cannot route back from writing-finished/failure to start.
- Successful sessions are still automatically written to the internal library.
- Implementing Slice 1 requires adding Markdown export, Continue, or a new document-management surface.

---

## Handoff to `/start-work`

Use this slice as the implementation brief:

```text
/start-work docs/prd/no-sidebar-brain-dump-flow.slice-1.md
```

Implementation must stay inside Slice 1. Do not add Export Markdown, Continue, Obsidian/iCloud export, or window-close interception unless the user explicitly approves expanding scope.
