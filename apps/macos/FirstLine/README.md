# Write It Down for macOS

A native AppKit writing room. Choose 1, 5, 10, 20, or 30 minutes to start; the last choice is remembered, and the first-run default is one minute. Choose a 5-second (Strict), 8-second (Standard), or 12-second (Relaxed) silence limit before writing. Standard is the default. The warning begins three seconds before the selected limit; at the limit, the draft is deleted. Write forward: deletion, paste, cut, undo, and selection replacement are blocked. The clock starts on the first input. Reach the deadline first to keep and copy your text. Writing is not saved to disk or uploaded. The current line and empty prompt sit above center; earlier lines move upward as you write.

Settings offers focus mode, narrow/wide paper, font size, and appearance; duration and silence choices stay on the start screen. Settings returns to the screen you left; the session and silence deadlines keep running, so a deadline can still complete or wipe the draft. Focus mode fills the screen during writing and hides the clock and word count until pointer hover; leaving fullscreen with the native window control turns focus mode off. The SwiftPM executable is not a distributable app. Mac offers three free writing sessions, then costs USD $4.99 once for two Macs with a 14-day refund. The first nonempty input spends a session; after three sessions, activate with an order number or activation code. The full browser trial is at https://writeitdown.app/. The app uses a Waffo-backed license service and a signed token bound to this installation. Public checkout remains closed until a genuine Waffo test order, callback, real app activation, and refund rejection pass. See `docs/RELEASE_CHECKLIST.md` for DMG packaging and `docs/LICENSE_PAYMENT_SPEC.md` for entitlement and configuration rules.

## Build and test

Requires macOS 14 or later and a Swift toolchain.

```bash
cd apps/macos/FirstLine
swift build
swift test
```

The executable product is `WriteItDown`. The source directory retains its historical path. License data is cached, but old trial and unlock markers cannot grant access; see `docs/LICENSE_PAYMENT_SPEC.md`.

## License

Source is MIT licensed; see `LICENSE`. Distribution licensing for the app is described separately in `docs/WRITEITDOWN_PLAN.md`.
