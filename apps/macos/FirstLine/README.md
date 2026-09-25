# Write It Down for macOS

A native AppKit writing room. Choose 1, 5, 10, 20, or 30 minutes to start; the last choice is remembered, and the first-run default is one minute. Choose a 5-second (Strict), 8-second (Standard), or 12-second (Relaxed) silence limit before writing. Standard is the default. The warning begins three seconds before the selected limit; at the limit, the draft is deleted. Write forward: deletion, paste, cut, undo, and selection replacement are blocked. The clock starts on the first input. Reach the deadline first to keep and copy your text. Writing is not saved to disk or uploaded.

Settings offers focus mode, alignment, font size, and appearance; duration and silence choices stay on the start screen. Settings returns to the screen you left; the session and silence deadlines keep running, so a deadline can still complete or wipe the draft. Focus mode fills the screen during writing and hides the clock and word count until pointer hover; leaving fullscreen with the native window control turns focus mode off. The SwiftPM executable is not a distributable app. The Dodo license client is wired into the native app; checkout and paid activation require owner-supplied configuration before release. Signing and DMG packaging remain later work in `docs/WRITEITDOWN_PLAN.md`. See `docs/LICENSE_PAYMENT_SPEC.md` for the current entitlement and configuration rules.

## Build and test

Requires macOS 14 or later and a Swift toolchain.

```bash
cd apps/macos/FirstLine
swift build
swift test
```

The executable product is `WriteItDown`. The source directory retains its historical path. The Mac trial and licensing cache remain in place; see `docs/LICENSE_PAYMENT_SPEC.md` and the batch plan.

## License

Source is MIT licensed; see `LICENSE`. Distribution licensing for the app is described separately in `docs/WRITEITDOWN_PLAN.md`.
