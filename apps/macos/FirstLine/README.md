# Write It Down for macOS

A native AppKit writing room. Choose 1, 5, 10, 20, or 30 minutes and a 5-, 8-, or 12-second silence limit, then click Begin. The last duration is remembered; the first-run defaults are one minute and eight seconds of silence. The warning begins three seconds before the selected limit; at the limit, the draft is deleted. Write forward: deletion, paste, cut, undo, and selection replacement are blocked. The clock starts on the first input. Reach the deadline first to keep and copy your text. Writing is not saved to disk or uploaded. The room follows the live writeitdown.app trial: the caret-only empty room and the current line are horizontally centred, with the line at 35% of the sheet's height, the bottom-right count slot reads `Type to start` until the first keystroke, earlier lines step through 100/22/7 opacity and shift one pitch as they move upward, and the clock, word count, warning and deletion sentence use the live strings; the kept sheet returns `You wrote it down.` with a quiet receipt naming the real duration and word count. The footer control reads `ESC - EXIT`; the first Escape or click shows `Press Esc again to leave and delete the draft.`, a second one within two seconds leaves, and typing dismisses the hint.

Settings offers focus mode, a narrow or wide writing column, font size, appearance, and, in a shipped app, `Check for updates automatically` (off by default); duration and silence choices stay on the start screen. Settings returns to the screen you left; the session and silence deadlines keep running, so a deadline can still complete or wipe the draft. Focus mode fills the screen during writing and hides the clock and word count until pointer hover; leaving fullscreen with the native window control turns focus mode off. The SwiftPM executable is not a distributable app. Mac offers three free writing sessions, then costs USD $4.99 once for two Macs with a 14-day refund. The first nonempty input spends a session; after three sessions, activate with an order number or activation code. The full browser trial is at https://writeitdown.app/. The app uses a signed license token bound to this installation. Buy opens hosted checkout in your browser, or the Mac purchase page if checkout cannot be opened. After payment, paste the returned license key into the app. The exact credential-padding rules are in [`docs/LICENSE_PAYMENT_SPEC.md`](docs/LICENSE_PAYMENT_SPEC.md#acceptance). Purchase delivery and the maintainer's pending installed-DMG TEST acceptance are documented in [`writeitdown/README.md`](../../../writeitdown/README.md#mac-page-release-order). See `docs/RELEASE_CHECKLIST.md` for DMG packaging and `docs/LICENSE_PAYMENT_SPEC.md` for entitlement and configuration rules.

## Updates

From 1.1 the app can check for updates. Nothing checks unless you turn on `Check for updates automatically` in Settings or choose `Check for Updates…` from the app menu, and no update window ever opens while the Session room is shown: a check or update found before the room opens is deferred and returned after you leave it. The feed is `https://writeitdown.app/download/appcast.xml` and every payload is an EdDSA-signed ZIP under `https://writeitdown.app/download/updates/`; the DMG stays the installer. The update signing key belongs to the captain and is never in this repository - see [`docs/RELEASE_KEY.md`](docs/RELEASE_KEY.md). `scripts/release-dmg.sh` builds the DMG and the update ZIP (refusing a placeholder key or a build number that is not greater than the last release), and `scripts/publish-appcast.sh` writes and verifies the feed.

## Build and test

Requires macOS 14 or later and a Swift toolchain. The first build fetches Sparkle 2.10.0 through SwiftPM (`Package.resolved` pins it).

```bash
cd apps/macos/FirstLine
swift build
swift test
```

The executable product is `WriteItDown`. The source directory retains its historical path. Trial-counter and signed-license rules are in `docs/LICENSE_PAYMENT_SPEC.md`.

## License

Source is MIT licensed; see `LICENSE`. Distribution licensing for the app is described separately in `docs/WRITEITDOWN_PLAN.md`.
