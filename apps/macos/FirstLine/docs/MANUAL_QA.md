# First Line MVP — Manual QA Checklist

Use this checklist before direct distribution.

## First launch
- Delete `~/Library/Application Support/First Line/Config/settings.json`.
- Launch the app.
- Confirm Home appears directly, with no Intro or warm-up screen.
- Confirm Home says `The first draft only moves forward.`
- Confirm Home says `Stop for 8 seconds and the page clears.`
- Confirm the primary action says `Start writing`.
- Confirm the microcopy says `No delete. No paste. No undo.`

## Returning launch
- Relaunch the app.
- Confirm the app opens on the same Home screen.
- Confirm Home shows duration selection, the core 8-second rule, and `Start writing`.

## Keyboard navigation
- Press `⌘1` and confirm the app returns to Writing mode.
- Press `⌘0` and confirm Home opens.
- Press `⌘,` and confirm Settings opens only when no writing session is active.

## English keyboard
- Start session from Home.
- Type plain English text.
- Confirm input stays in the editor.
- Confirm Backspace / Delete / Paste / Undo do not rewrite prior text.

## Session feel
- Confirm there is no obvious bordered editor box in the middle of the session.
- Confirm the writing area reads like open paper rather than a contained panel.
- Confirm top chrome uses a subtle progress line plus small timer text.
- Confirm multiline text still weakens older lines.

## Chinese IME
- Switch to Chinese IME.
- Compose pinyin, open candidate list, confirm a candidate.
- Confirm composition does not prematurely trigger failure.
- Confirm committed Chinese text remains in the editor.

## Failure path
- Start a session.
- Stop typing for 8 seconds.
- Confirm Failure screen appears.
- Confirm no new markdown file appears in Library.

## Success path
- Complete a session countdown.
- Confirm Success screen appears.
- Confirm markdown file exists in `~/Library/Application Support/First Line/Library/`.

## Settings
- Change theme.
- Change default duration.
- Toggle immersive session mode.
- Change reduced motion override.
- Use Reveal Library Folder.

## Library
- Open Library.
- Confirm reverse chronological order.
- Open detail view.
- Verify Copy Text / Open in Default Editor / Reveal in Finder / Delete.
- Delete one item and verify file removal from disk.
