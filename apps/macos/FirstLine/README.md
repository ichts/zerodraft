# First Line for macOS

First Line is a forced-output writing tool. You write forward and cannot edit. Stay silent and the page deletes your draft.

This is the native macOS app, built with Swift and SwiftUI.

## Features

- Forward only. No delete, no paste, no undo. New text appends at the end.
- Five seconds of silence turns the page red and starts a countdown.
- Eight seconds of silence deletes the whole draft.
- A session lasts sixty seconds. Finish it and you keep the draft.
- Keep the draft three ways: copy full text, copy for AI, or download a Markdown file.

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

The editor is append-only. Deletion, paste, cut, undo, and selection replacement are blocked. IME composition still works: marked text from a Chinese, Japanese, or Korean input method is counted as activity, so an unfinished composition does not start the danger countdown until it is committed.

## License

First Line is released under the MIT License. See `LICENSE` for details.
