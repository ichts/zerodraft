import AppKit
import Testing
@testable import WriteItDown

/// The room's paper switch (D-120): the web room header's `.modes` group on the Mac sheet. Choosing a paper is not
/// input, so the draft, the phase and the silence clock carry on, and only colour changes.
@MainActor
struct PaperModeTests {
    private final class Clock {
        var now: TimeInterval = 0
    }

    private struct Room {
        let room: SessionViewController
        let state: AppState
        let engine: SessionEngine
        let editor: AppendOnlyTextView
        let clock: Clock
        let root: URL
        let window: NSWindow
    }

    private func room(mode: PaperMode = .lamp) throws -> Room {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = Clock()
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.updatePaperMode(mode)
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state, confirmationNow: { clock.now })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: PaperModeRepaint.appearanceName(for: mode))
        window.contentViewController = room
        window.setContentSize(NSSize(width: 1040, height: 720))
        room.view.layoutSubtreeIfNeeded()
        let editor = try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
        window.makeFirstResponder(editor)
        return Room(room: room, state: state, engine: engine, editor: editor, clock: clock, root: root, window: window)
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        view.subviews.flatMap { ((($0 as? T).map { [$0] }) ?? []) + descendants($0, of: type) }
    }

    private func srgb(_ color: NSColor, in view: NSView) -> [Int] {
        var parts: [Int] = []
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            parts = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        return parts
    }

    /// `.modes`: three labels in one group named Paper, each at least 44 x 44, 2 pt apart, 400 13 pt; the chosen
    /// paper in ink with a 1 pt underline 5 pt under the baseline, the others quiet and plain.
    @Test(arguments: PaperMode.allCases)
    func theSwitchIsTheWebsRadioGroup(mode: PaperMode) throws {
        try withPaperMode(mode) { _ in
            let fixture = try room(mode: mode)
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let modes = try #require(fixture.room.modeSwitch)
            #expect(modes.accessibilityRole() == .radioGroup)
            #expect(modes.accessibilityLabel() == "Paper")
            #expect(modes.options.map(\.title) == ["Lamp", "Paper", "Slate"])
            for (option, next) in zip(modes.options, modes.options.dropFirst()) {
                #expect(abs(next.frame.minX - option.frame.maxX - 2) < 0.01, "the labels are not 2 pt apart")
            }
            for option in modes.options {
                #expect(option.accessibilityRole() == .radioButton)
                #expect(option.frame.width >= 44 && option.frame.height >= 44, "\(option.title) is under 44 x 44")
                #expect(option.font == FirstLineTypography.smallNSFont)
                let chosen = option.choice == mode
                #expect(option.accessibilityValue() as? Bool == chosen)
                #expect((option.underlineRect != nil) == chosen, "\(option.title) underline")
                let role = chosen ? FirstLineColors.paperInkNSColor : FirstLineColors.paperQuietNSColor
                #expect(srgb(option.labelColor, in: option) == srgb(role, in: option), "\(option.title) colour")
                if let line = option.underlineRect {
                    #expect(line.height == 1)
                    // 5 pt under the baseline, on whole points so the 1 pt line stays crisp.
                    let gap = option.isFlipped ? line.minY - option.labelBaseline : option.labelBaseline - line.maxY
                    #expect(abs(gap - 5) <= 0.5, "the underline is \(gap) pt under the baseline")
                }
            }
            // The underline is drawn, not only placed: the row 5 pt under the chosen word's baseline is ink, and the
            // same row under the other words is the sheet (Lamp's quiet and ink are a hair apart, so without the
            // line the choice does not show).
            fixture.room.view.displayIfNeeded()
            let rep = try #require(modes.bitmapImageRepForCachingDisplay(in: modes.bounds))
            modes.cacheDisplay(in: modes.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / modes.bounds.width
            let ink = srgb(FirstLineColors.paperInkNSColor, in: modes)
            for option in modes.options {
                let line = try #require(option.underlineRect ?? modes.options.first(where: { $0.choice == mode })?
                    .underlineRect.map { NSRect(x: $0.minX, y: $0.minY, width: $0.width, height: 1) })
                let frame = modes.convert(line, from: option)
                let column = Int((frame.midX) * scale)
                // Bitmap rows run from the top.
                let row = Int(((modes.isFlipped ? frame.midY : modes.bounds.height - frame.midY)) * scale)
                // The switch has no fill of its own: off the line its pixels are clear.
                let pixel = try #require(rep.colorAt(x: column, y: row)?.usingColorSpace(.sRGB))
                let drawn = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent].map { Int(($0 * 255).rounded()) }
                if option.choice == mode {
                    let distance = zip(drawn, ink).map { abs($0 - $1) }.max() ?? 255
                    // `colorAt` reads the bytes as calibrated RGB, which lifts dark tones about a dozen levels.
                    #expect(pixel.alphaComponent > 0.9 && distance <= 16,
                            "\(mode): the chosen underline is not drawn (\(drawn) alpha \(pixel.alphaComponent) vs ink \(ink))")
                } else {
                    #expect(pixel.alphaComponent < 0.1, "\(mode): \(option.title) is underlined too")
                }
            }
            // On the sheet, across the clock row, its first label's text on the room's inset.
            let paper = try #require(descendants(fixture.room.view, of: PaperSheetView.self).first)
            let frame = paper.convert(modes.bounds, from: modes)
            #expect(abs(frame.minX + PaperModeSwitch.padding - 22) < 0.5, "the first word is not on the room inset")
            fixture.window.orderOut(nil)
        }
    }

    /// Choosing a paper is not input (room.js): the draft, the phase, the session and its silence clock carry on,
    /// the choice is stored, and the keyboard is back on the writing line.
    @Test func choosingAPaperIsNotInput() throws {
        let fixture = try room(mode: .lamp)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 3
        fixture.room.tick()
        let session = fixture.engine.sessionID
        let idle = fixture.engine.idleSeconds
        let slate = try #require(fixture.room.modeSwitch.options.first { $0.choice == .slate })
        fixture.window.makeFirstResponder(slate)
        slate.performClick(nil)

        #expect(fixture.state.settings.paperMode == .slate)
        #expect(try SettingsStore(configDirectory: fixture.root).load().paperMode == .slate, "the choice is not stored")
        #expect(fixture.room.modeSwitch.mode == .slate)
        #expect(fixture.window.firstResponder === fixture.editor, "the keyboard did not go back to the writing")
        #expect(fixture.engine.text == "draft")
        #expect(fixture.engine.sessionID == session)
        #expect(fixture.engine.phase == .writing)
        #expect(fixture.engine.idleSeconds == idle, "a paper switch counted as input")

        // The same 5 s of silence starts the warning and 8 s deletes, whatever the paper.
        fixture.clock.now = 4.9
        fixture.room.tick()
        #expect(fixture.engine.phase == .writing)
        fixture.clock.now = 5.1
        fixture.room.tick()
        #expect(fixture.engine.phase == .danger)
        fixture.clock.now = 8.1
        fixture.room.tick()
        #expect(fixture.engine.phase == .failure)
        fixture.window.orderOut(nil)
    }

    /// With Full Keyboard Access the arrows move the choice, wrapping, as a native radio group does.
    @Test func arrowKeysStepThroughThePapersAndWrap() throws {
        let fixture = try room(mode: .lamp)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let modes = try #require(fixture.room.modeSwitch)
        func press(_ key: NSEvent.SpecialKey, on option: PaperModeOption) {
            let character = String(Character(UnicodeScalar(key.rawValue)!))
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                         timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil,
                                         characters: character, charactersIgnoringModifiers: character,
                                         isARepeat: false, keyCode: 0)!
            option.keyDown(with: event)
        }
        press(.leftArrow, on: modes.options[0])
        #expect(fixture.state.settings.paperMode == .slate, "left from Lamp wraps to Slate")
        press(.rightArrow, on: modes.options[2])
        #expect(fixture.state.settings.paperMode == .lamp, "right from Slate wraps to Lamp")
        press(.downArrow, on: modes.options[0])
        #expect(fixture.state.settings.paperMode == .paper)
        fixture.window.orderOut(nil)
    }

    /// The switch is chrome: Focus Mode hides it with the clock and the count, and the pointer brings it back.
    @Test func focusModeHidesTheSwitchWithTheChrome() throws {
        let fixture = try room(mode: .lamp)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.state.updateFocusMode(true)
        fixture.room.viewDidAppear()
        #expect(fixture.room.modeSwitch.alphaValue == 0)
        fixture.state.updateFocusMode(false)
        fixture.room.viewDidAppear()
        #expect(fixture.room.modeSwitch.alphaValue == 1)
        fixture.window.orderOut(nil)
    }

    /// Lamp and Slate share the dark appearance, so AppKit never announces a switch between them: the repaint does.
    /// After it, the sheet, the words and the wash are the new mode's, and the draft is untouched.
    @Test func lampToSlateRepaintsTheWholeRoom() throws {
        let fixture = try room(mode: .lamp)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let previous = FirstLineColors.paperMode
        defer { PaperModeRepaint.apply(previous, to: fixture.window) }
        PaperModeRepaint.apply(.lamp, to: fixture.window)
        fixture.editor.insertText("one\ntwo", replacementRange: NSRange(location: NSNotFound, length: 0))
        let paper = try #require(descendants(fixture.room.view, of: PaperSheetView.self).first)
        func sheetColour() throws -> [Int] {
            fixture.room.view.layoutSubtreeIfNeeded()
            fixture.room.view.displayIfNeeded()
            let rep = try #require(paper.bitmapImageRepForCachingDisplay(in: paper.bounds))
            paper.cacheDisplay(in: paper.bounds, to: rep)
            var sums = [0.0, 0.0, 0.0]
            let (cx, cy) = (rep.pixelsWide / 2, rep.pixelsHigh * 3 / 4)
            for dx in -20..<20 {
                for dy in -20..<20 {
                    let c = try #require(rep.colorAt(x: cx + dx, y: cy + dy)?.usingColorSpace(.sRGB))
                    sums[0] += c.redComponent; sums[1] += c.greenComponent; sums[2] += c.blueComponent
                }
            }
            return sums.map { Int(($0 / 1600 * 255).rounded()) }
        }
        let lamp = try sheetColour()
        let builds = paper.paints
        PaperModeRepaint.apply(.slate, to: fixture.window)
        let slate = try sheetColour()

        #expect(paper.paints > builds, "the sheet was not repainted")
        #expect(lamp[0] > 150 && slate[0] < 90, "the sheet stayed \(slate), Lamp was \(lamp)")
        let ink = try #require(fixture.editor.textStorage?.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        #expect(srgb(ink, in: fixture.editor) == [0xF7, 0xEE, 0xDB], "the live line kept Lamp's ink")
        #expect(abs(try historyAlpha(fixture.editor) - 0.16) < 0.001, "the history kept Lamp's step")
        #expect(fixture.engine.text == "one\ntwo")
        #expect(fixture.window.appearance?.name == .darkAqua)
        fixture.window.orderOut(nil)
    }

    /// Every word on the sheet takes a sheet role (ink, quiet, danger, or the sheet's own tone inside an ink pill),
    /// in every paper and every phase: a label left on a page or system colour reads cream on Lamp's cream sheet
    /// (the kept heading did, D-120).
    @Test(arguments: PaperMode.allCases)
    func everyWordOnTheSheetTakesASheetRole(mode: PaperMode) throws {
        try withPaperMode(mode) { _ in
            for phase in ["typing", "warning", "kept", "stopped"] {
                let fixture = try room(mode: mode)
                defer { try? FileManager.default.removeItem(at: fixture.root) }
                fixture.editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
                switch phase {
                case "warning": fixture.clock.now = 5.6
                case "stopped": fixture.clock.now = 8.1
                case "kept":
                    for second in stride(from: 4.0, to: 60.0, by: 4.0) {
                        fixture.clock.now = second
                        fixture.engine.registerMarkedTextActivity()
                    }
                    fixture.clock.now = 60
                default: fixture.clock.now = 1
                }
                fixture.room.tick()
                fixture.room.view.layoutSubtreeIfNeeded()
                let paper = try #require(descendants(fixture.room.view, of: PaperSheetView.self).first)
                let roles = [FirstLineColors.paperInkNSColor, FirstLineColors.paperQuietNSColor,
                             FirstLineColors.paperDangerNSColor, FirstLineColors.paperNSColor].map { srgb($0, in: paper) }
                for field in descendants(paper, of: NSTextField.self) where !field.isHiddenOrHasHiddenAncestor
                    && !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    let attributed = field.attributedStringValue.length > 0
                        ? field.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                        : nil
                    let color = try #require(attributed ?? field.textColor)
                    // A pill's title is a clear placeholder under its drawn label; only drawn words count.
                    if color.alphaComponent == 0 { continue }
                    #expect(roles.contains(srgb(color, in: field)),
                            "\(mode) \(phase): '\(field.stringValue)' is \(srgb(color, in: field)), not a sheet role")
                }
                fixture.window.orderOut(nil)
            }
        }
    }

    private func historyAlpha(_ editor: AppendOnlyTextView) throws -> CGFloat {
        editor.settleHistoryDissolve()
        let color = try #require(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        return color.alphaComponent
    }
}
