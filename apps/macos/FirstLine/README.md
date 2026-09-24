# Zero Draft for macOS

> This app is being rebuilt as the writeitdown macOS app. The plan is `docs/WRITEITDOWN_PLAN.md`; until those batches land, the text below describes the current Zero Draft build.

Zero Draft is a forced-output writing tool. You write forward and cannot edit. Stay silent and the page deletes your draft.

This is the native macOS app, built with Swift and AppKit.

## Features

- Forward only. No delete, no paste, no undo. New text appends at the end.
- Five seconds of silence turns the page red and starts a countdown.
- Eight seconds of silence deletes the whole draft.
- The sixty-second clock starts on first input. Reach zero before the wipe and you keep the draft.
- On success, copy the full text or discard the draft.

It is not a distraction-free editor. It is a hired threat. This is the draft before the draft.

## Building from source

You need macOS 14 or later and the Swift toolchain.

```bash
git clone https://github.com/ichts/zerodraft.git
cd zerodraft/apps/macos/FirstLine
swift build
swift test
```

Or open `Package.swift` in Xcode and run the `FirstLine` target.

## Editor behavior

The editor is append-only. Deletion, paste, cut, undo, and selection replacement are blocked. IME composition still works: marked text from a Chinese, Japanese, or Korean input method starts the clock and counts as activity. If composition stops for five seconds, the warning appears; after eight seconds, the draft is wiped. The room stays open for the next input, subject to the three-session trial limit.

## License

Zero Draft is released under the MIT License. See `LICENSE` for details.
