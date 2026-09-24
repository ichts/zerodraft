# Write It Down for macOS

A native AppKit writing room. Write forward: deletion, paste, cut, undo and selection replacement are blocked. The clock starts on the first input. After five seconds of silence a warning appears; after eight seconds your draft is deleted. Reach the deadline first to keep and copy your text. Writing is not saved to disk or uploaded.

The brand-and-token transition is batch 3 of `docs/WRITEITDOWN_PLAN.md`. The room visuals, duration picker, paid license integration and signed DMG are separate later batches; do not mistake the SwiftPM executable for a distributable app.

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
