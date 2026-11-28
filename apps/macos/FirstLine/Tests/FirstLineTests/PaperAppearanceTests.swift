import AppKit
import Testing
@testable import WriteItDown

/// The room follows the system appearance (D-124): aqua shows the white paper, darkAqua the black one. A change of
/// appearance is not input, so the draft, the phase and the silence clock carry on, and only colour changes.
@MainActor
struct PaperAppearanceTests {
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

    private func room(paper: TestPaper = .white) throws -> Room {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = Clock()
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state, confirmationNow: { clock.now })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: paper.appearance)
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

    /// An appearance change is not input (room.js): the draft, the phase, the session and its silence clock carry
    /// on, and the keyboard stays on the writing line.
    @Test func anAppearanceChangeIsNotInput() throws {
        let fixture = try room(paper: .white)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 3
        fixture.room.tick()
        let session = fixture.engine.sessionID
        let idle = fixture.engine.idleSeconds
        fixture.window.appearance = NSAppearance(named: TestPaper.black.appearance)
        fixture.room.view.layoutSubtreeIfNeeded()

        #expect(fixture.window.firstResponder === fixture.editor, "the keyboard left the writing")
        #expect(fixture.engine.text == "draft")
        #expect(fixture.engine.sessionID == session)
        #expect(fixture.engine.phase == .writing)
        #expect(fixture.engine.idleSeconds == idle, "an appearance change counted as input")

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

    /// White to black repaints the whole room through AppKit's own appearance change: the sheet, the words and the
    /// history are the black paper's, and the draft is untouched.
    @Test func whiteToBlackRepaintsTheWholeRoom() throws {
        let fixture = try room(paper: .white)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
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
                    let c = try #require(renderedPixel(rep, x: cx + dx, y: cy + dy))
                    sums[0] += c.redComponent; sums[1] += c.greenComponent; sums[2] += c.blueComponent
                }
            }
            return sums.map { Int(($0 / 1600 * 255).rounded()) }
        }
        let white = try sheetColour()
        let builds = paper.paints
        fixture.window.appearance = NSAppearance(named: TestPaper.black.appearance)
        let black = try sheetColour()

        #expect(paper.paints > builds, "the sheet was not repainted")
        #expect(white == [0xFF, 0xFF, 0xFF], "the white sheet is \(white)")
        #expect(black == [0x11, 0x11, 0x11], "the sheet stayed \(black)")
        let ink = try #require(fixture.editor.textStorage?.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor)
        #expect(srgb(ink, in: fixture.editor) == [0xED, 0xED, 0xED], "the live line kept the white paper's ink")
        #expect(abs(try historyAlpha(fixture.editor) - 0.17) < 0.001, "the history kept the white paper's step")
        #expect(fixture.engine.text == "one\ntwo")
        fixture.window.orderOut(nil)
    }

    /// Every word on the sheet takes a sheet role (ink, quiet, the numeral red, or the sheet's own tone inside an
    /// ink pill), on both papers and in every phase: a label left on a page or system colour would vanish on one of
    /// them (the kept heading did, D-120).
    @Test(arguments: TestPaper.allCases)
    func everyWordOnTheSheetTakesASheetRole(paper mode: TestPaper) throws {
        do {
            for phase in ["typing", "warning", "kept", "stopped"] {
                let fixture = try room(paper: mode)
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

    /// The app sets no appearance of its own: the system's choice is the only switch (D-124).
    @Test func theWindowFollowsTheSystemAppearance() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = licensedTestState(settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        let controller = RootWindowController(appState: state)
        #expect(controller.window?.appearance == nil)
        controller.window?.orderOut(nil)
    }

    private func historyAlpha(_ editor: AppendOnlyTextView) throws -> CGFloat {
        editor.settleHistoryDissolve()
        let color = try #require(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        return color.alphaComponent
    }
}
