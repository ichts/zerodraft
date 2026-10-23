# Write It Down for macOS

A native AppKit writing room. Choose 1, 5, 10, 20, or 30 minutes and a 5-, 8-, or 12-second silence limit, then click Begin. The last duration is remembered; the first-run defaults are one minute and eight seconds of silence. The warning begins three seconds before the selected limit; at the limit, the draft is deleted. Write forward: deletion, paste, cut, undo, and selection replacement are blocked. The clock starts on the first input. Reach the deadline first to keep and copy your text. Writing is not saved to disk or uploaded. The room follows the live writeitdown.app trial: the current line and empty prompt are centred at 39% of the sheet, earlier lines fade as they move upward, and the clock, word count, warning, deletion sentence and kept sheet use the live strings. The footer control reads `ESC - EXIT`; the first Escape or click shows `Press Esc again to leave. The draft is deleted.`, a second one within two seconds leaves, and typing dismisses the hint.

Settings offers focus mode, narrow/wide paper, font size, and appearance; duration and silence choices stay on the start screen. Settings returns to the screen you left; the session and silence deadlines keep running, so a deadline can still complete or wipe the draft. Focus mode fills the screen during writing and hides the clock and word count until pointer hover; leaving fullscreen with the native window control turns focus mode off. The SwiftPM executable is not a distributable app. Mac offers three free writing sessions, then costs USD $4.99 once for two Macs with a 14-day refund. The first nonempty input spends a session; after three sessions, activate with an order number or activation code. The full browser trial is at https://writeitdown.app/. The app uses a signed license token bound to this installation. Buy opens hosted checkout in your browser, or the Mac purchase page if checkout cannot be opened. After payment, paste the returned license key into the app; surrounding whitespace is removed automatically. Purchase delivery and the maintainer's pending installed-DMG TEST acceptance are documented in [`writeitdown/README.md`](../../../writeitdown/README.md#mac-page-release-order). See `docs/RELEASE_CHECKLIST.md` for DMG packaging and `docs/LICENSE_PAYMENT_SPEC.md` for entitlement and configuration rules.

## Build and test

Requires macOS 14 or later and a Swift toolchain.

```bash
cd apps/macos/FirstLine
swift build
swift test
```

The executable product is `WriteItDown`. The source directory retains its historical path. Trial-counter and signed-license rules are in `docs/LICENSE_PAYMENT_SPEC.md`.

## License

Source is MIT licensed; see `LICENSE`. Distribution licensing for the app is described separately in `docs/WRITEITDOWN_PLAN.md`.
