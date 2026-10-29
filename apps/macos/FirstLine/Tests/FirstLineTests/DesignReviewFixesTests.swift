import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// Regression tests for the Mac defects the full design review filed (problems 4, 5, 9, 10, 21, 24 and
/// the D-030 note, D-076); the review's wiped-room caret item is superseded by D-070 and keeps only a
/// restart-position guard. Every case measures the real AppKit surfaces; the geometry is the contract and a
/// capture only records it.
@MainActor
struct DesignReviewFixesTests {
    private static let windowSizes = [NSSize(width: 1040, height: 720), NSSize(width: 1600, height: 1000)]

    // MARK: - Problem 4: the kept block sits on the sheet's axis

    @Test func keptBlockSitsOnTheSheetAxis() throws {
        for size in Self.windowSizes {
            let fixture = try keptRoom(size: size)
            let paper = fixture.paper
            let paperCentre = fixture.room.view.convert(paper.bounds, from: paper).midX
            let fields = descendants(of: fixture.room.view, as: NSTextField.self)
            let heading = try #require(fields.first { $0.stringValue == "You wrote it down." })
            let receipt = try #require(fields.first { $0.stringValue.contains("WORDS.") })
            let copy = try #require(descendants(of: fixture.room.view, as: NSButton.self)
                .first { $0.title == "COPY TEXT" })
            let restart = try #require(descendants(of: fixture.room.view, as: NSButton.self)
                .first { $0.title == "RUN IT AGAIN" })
            for (name, view) in [("heading", heading as NSView), ("receipt", receipt)] {
                let centre = fixture.room.view.convert(view.bounds, from: view).midX
                #expect(abs(centre - paperCentre) <= 1,
                        "\(name) centres \(centre), the sheet centres \(paperCentre), at \(size)")
            }
            // The two actions are one row: the row centres on the axis, and no action
            // may push the pair off it.
            let actionSpan = fixture.room.view.convert(copy.bounds, from: copy).union(
                fixture.room.view.convert(restart.bounds, from: restart))
            #expect(abs(actionSpan.midX - paperCentre) <= 1,
                    "the action pair centres \(actionSpan.midX), the sheet \(paperCentre), at \(size)")
            fixture.window.orderOut(nil)
        }
    }

    @Test func keptBlockStaysOnTheAxisWhenTheDraftWraps() throws {
        // The block used to size itself from its widest child, so a wrapping heading moved it.
        for size in Self.windowSizes {
            let fixture = try keptRoom(size: size, text: String(repeating: "wrap ", count: 12))
            let paper = fixture.paper
            let paperCentre = fixture.room.view.convert(paper.bounds, from: paper).midX
            let heading = try #require(descendants(of: fixture.room.view, as: NSTextField.self)
                .first { $0.stringValue == "You wrote it down." })
            let centre = fixture.room.view.convert(heading.bounds, from: heading).midX
            #expect(abs(centre - paperCentre) <= 1, "kept heading \(centre) vs sheet \(paperCentre) at \(size)")
            fixture.window.orderOut(nil)
        }
    }

    // MARK: - Problem 5: the writing line holds the paper anchor for every draft length

    @Test(arguments: [WritingAlignment.centered, .left])
    func activeLineHoldsTheAnchorForShortAndLongDrafts(alignment: WritingAlignment) throws {
        for size in Self.windowSizes {
            let fixture = try room(size: size)
            fixture.state.settings.writingAlignment = alignment
            let paper = fixture.paper
            func expectAnchor(_ label: String) throws {
                fixture.room.viewDidLayout()
                fixture.room.refreshRoom()
                fixture.room.view.layoutSubtreeIfNeeded()
                let line = try currentLineCentre(in: fixture.editor, paper: paper)
                let anchor = paper.bounds.height * RoomPresentation.paperAnchorFraction
                #expect(abs(line - anchor) <= 1,
                        "\(label) at \(size): the writing line sits \(line) pt down a \(paper.bounds.height) pt sheet, expected the \(anchor) pt anchor")
            }
            try expectAnchor("empty")
            fixture.editor.insertText("One", replacementRange: NSRange(location: NSNotFound, length: 0))
            try expectAnchor("one line")
            fixture.editor.insertText("\ntwo\nthree", replacementRange: NSRange(location: NSNotFound, length: 0))
            try expectAnchor("three lines")
            fixture.editor.insertText("\n4\n5\n6\n7\n8\n9\n10", replacementRange: NSRange(location: NSNotFound, length: 0))
            try expectAnchor("ten lines")
            fixture.window.orderOut(nil)
        }
    }

    @Test func snapshotOrderKeepsTheAnchor() throws {
        // A kept/wiped surface is captured before its window exists, so the first layout pass
        // has to establish the anchor; that pass used to leave the active line at 51%.
        for size in Self.windowSizes {
            let fixture = try roomWithoutWindow(size: size)
            let editor = try #require(descendants(of: fixture.room.view, as: AppendOnlyTextView.self).first)
            editor.insertText("cant say this out loud but\ni dont want the promotion\npromotion. i want time",
                              replacementRange: NSRange(location: NSNotFound, length: 0))
            fixture.clock.now = 0.4
            fixture.engine.registerMarkedTextActivity()
            fixture.room.tick()
            let window = host(fixture.room, size: size)
            let paper = try #require(editor.enclosingScrollView?.superview)
            let line = try currentLineCentre(in: editor, paper: paper)
            let anchor = paper.bounds.height * RoomPresentation.paperAnchorFraction
            #expect(abs(line - anchor) <= 1,
                    "at \(size) the first layout pass leaves the writing line at \(line) of \(paper.bounds.height), expected \(anchor)")
            window.orderOut(nil)
        }
    }

    // MARK: - Problem 9: the licence card's free route and its paid action

    @Test func licenceCardShowsTheFreeRouteAsAControl() throws {
        for checkoutConfigured in [true, false] {
            let controller = UpgradeViewController(appState: try exhaustedState(checkoutConfigured: checkoutConfigured))
            let window = host(controller, size: NSSize(width: 1040, height: 720))
            let free = try #require(descendants(of: controller.view, as: NSButton.self)
                .first { $0.title == "Try the free web room" },
                "the free route is missing when checkout is \(checkoutConfigured ? "available" : "unavailable")")
            #expect(!free.isHiddenOrHasHiddenAncestor)
            #expect(free.isEnabled)
            #expect(abs(free.frame.height - 48) <= 0.5, "the free route is \(free.frame.height) pt tall, not a control")
            if let rep = free.bitmapImageRepForCachingDisplay(in: free.bounds) {
                free.cacheDisplay(in: free.bounds, to: rep)
            }
            #expect(free.layer?.borderWidth == 1, "the free route is not the outline secondary")
            // A real hit area: the control itself answers the pointer in its own middle.
            window.contentView?.displayIfNeeded()
            free.displayIfNeeded()
            let middle = try #require(free.superview).convert(NSPoint(x: free.bounds.midX, y: free.bounds.midY),
                                                              from: free)
            #expect(free.hitTest(middle) === free, "the free route has no hit area")
            let ringing = try #require(free as? FirstLineInkFocusRinging)
            var ringColour: NSColor?
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                ringColour = ringing.inkFocusRingColor.usingColorSpace(.sRGB)
            }
            var inkColour: NSColor?
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                inkColour = FirstLineColors.inkNSColor.usingColorSpace(.sRGB)
            }
            #expect(ringColour == inkColour, "the free route does not use the ink focus ring")
            window.orderOut(nil)
        }
    }

    @Test func licenceCardNeverOffersAPaidActionItCannotComplete() async throws {
        // Checkout unconfigured: no Buy at all, and the card says why.
        let unavailable = UpgradeViewController(appState: try exhaustedState(checkoutConfigured: false))
        let unavailableWindow = host(unavailable, size: NSSize(width: 1040, height: 720))
        #expect(!descendants(of: unavailable.view, as: NSButton.self)
            .contains { $0.title.hasPrefix("Buy a license") && !$0.isHiddenOrHasHiddenAncestor },
            "the card still offers Buy while checkout is unavailable")
        #expect(visibleStrings(in: unavailable.view).contains { $0.contains("Checkout is not available") })
        unavailableWindow.orderOut(nil)

        // Checkout configured: Buy is available, until a licence check is running.
        let state = try exhaustedState(checkoutConfigured: true)
        let available = UpgradeViewController(appState: state)
        let availableWindow = host(available, size: NSSize(width: 1040, height: 720))
        let buy = try #require(descendants(of: available.view, as: NSButton.self)
            .first { $0.title.hasPrefix("Buy a license") })
        #expect(!buy.isHiddenOrHasHiddenAncestor)
        #expect(buy.isEnabled, "Buy is disabled while checkout is available and idle")
        state.licenseActivationInFlight = true
        // The card re-reads the observable state on the next main-actor turn.
        try await Task.sleep(for: .milliseconds(200))
        available.view.layoutSubtreeIfNeeded()
        #expect(!buy.isEnabled, "Buy is still offered while a key is being checked")
        #expect(visibleStrings(in: available.view).contains("Checking your key..."))
        let free = try #require(descendants(of: available.view, as: NSButton.self)
            .first { $0.title == "Try the free web room" })
        #expect(free.isEnabled && !free.isHiddenOrHasHiddenAncestor,
                "the free route went away while the key was being checked")
        availableWindow.orderOut(nil)
    }

    // MARK: - Problem 10: one Settings grid, one name per control

    @Test func settingsPutsEveryRowOnOneGrid() throws {
        let settings = SettingsViewController(appState: licensedTestState(), updateSettings: StubUpdateSettings())
        let window = host(settings, size: NSSize(width: 1040, height: 720))
        let trailing: [(String, NSView)] = descendants(of: settings.view, as: NSPopUpButton.self)
            .map { ($0.titleOfSelectedItem ?? "popup", $0 as NSView) }
            + descendants(of: settings.view, as: NSSwitch.self)
            .map { ($0.accessibilityLabel() ?? "switch", $0 as NSView) }
        #expect(trailing.count >= 5, "expected the appearance rows and both boolean rows")
        let edges = trailing.map { ($0.0, settings.view.convert($0.1.bounds, from: $0.1).maxX) }
        for (name, edge) in edges {
            #expect(abs(edge - edges[0].1) <= 1,
                    "\(name) ends at \(edge), \(edges[0].0) ends at \(edges[0].1): one right edge only")
        }
        let rowLabels = ["Theme", "Reduced Motion", "Focus Mode", "Alignment", "Font Size",
                         "Check for updates automatically"]
        var leadingEdges: [CGFloat] = []
        for name in rowLabels {
            let field = try #require(descendants(of: settings.view, as: NSTextField.self)
                .first { $0.stringValue == name }, "the \(name) row lost its label")
            let frame = settings.view.convert(field.bounds, from: field)
            leadingEdges.append(frame.minX)
            #expect(abs(frame.maxX - edges[0].1) >= 40, "the \(name) row's control is not trailing")
        }
        for edge in leadingEdges {
            #expect(abs(edge - leadingEdges[0]) <= 1,
                    "row labels start at \(leadingEdges), not on one column")
        }
        // The About row's detail is text, not a control: it may sit 2 pt inside the edge.
        let version = try #require(descendants(of: settings.view, as: NSTextField.self)
            .first { $0.stringValue.hasPrefix("Version ") })
        #expect(abs(settings.view.convert(version.bounds, from: version).maxX - edges[0].1) <= 2)
        window.orderOut(nil)
    }

    @Test func settingsNamesEachControlOnce() throws {
        let settings = SettingsViewController(appState: licensedTestState(), updateSettings: StubUpdateSettings())
        let window = host(settings, size: NSSize(width: 1040, height: 720))
        let strings = visibleStrings(in: settings.view)
        #expect(strings.filter { $0 == "Focus Mode" }.count == 1, "the Focus Mode row is named twice: \(strings)")
        #expect(!strings.contains("Fullscreen focus"), "the same control still carries a second label")
        #expect(strings.filter { $0 == "Check for updates automatically" }.count == 1,
                "the updates row is named twice: \(strings)")
        for toggle in descendants(of: settings.view, as: NSSwitch.self) {
            let name = toggle.accessibilityLabel() ?? ""
            #expect(!name.isEmpty, "a switch has no accessible name at all")
            #expect(strings.filter { $0 == name }.count == 1,
                    "the switch repeats its row's label as a second visible name: \(strings)")
        }
        window.orderOut(nil)
    }

    // MARK: - Problem 21: the rules sheet follows the type scale

    @Test func rulesSheetUsesTheScaleForLeadingAndSubheads() throws {
        let rules = RulesViewController()
        let window = host(rules, size: NSSize(width: RulesViewController.cardWidth + 40, height: 760))
        let bodySize = RulesViewController.bodyFont.pointSize
        let expectedLeading = bodySize * RulesViewController.bodyLeading
        let bodies = ["Open it, start typing", "Deleting, pasting", "Stop typing for eight seconds", "Make it to the end"]
        var bodyLabels: [NSTextField] = []
        for prefix in bodies {
            let field = try #require(descendants(of: rules.view, as: NSTextField.self)
                .first { $0.stringValue.hasPrefix(prefix) }, "missing the body run beginning \(prefix)")
            bodyLabels.append(field)
            let paragraph = try #require(field.attributedStringValue.attribute(
                .paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(field.font?.pointSize == bodySize, "\(prefix) is \(field.font?.pointSize ?? 0) pt, not the body role")
            #expect(abs(paragraph.maximumLineHeight - expectedLeading) <= 0.01,
                    "\(prefix) leads at \(paragraph.maximumLineHeight), the scale says \(expectedLeading)")
            #expect(abs(paragraph.minimumLineHeight - expectedLeading) <= 0.01)
            #expect(paragraph.lineBreakMode == .byWordWrapping)
        }
        // Rendered pitch: a two-line body run is exactly two line boxes tall.
        let twoLine = try #require(bodyLabels.first {
            $0.stringValue.hasPrefix("Stop typing for eight seconds")
        })
        let lines = max(1, Int((twoLine.frame.height / expectedLeading).rounded()))
        #expect(lines >= 2, "the longest rule body did not wrap, so the pitch cannot be read")
        #expect(abs(twoLine.frame.height - CGFloat(lines) * expectedLeading) <= 1,
                "a \(lines)-line body is \(twoLine.frame.height) pt tall, expected \(CGFloat(lines) * expectedLeading)")

        // Subheads are one step up in weight at the body size, never smaller than their text.
        for title in ["No way back", "Eight seconds of silence", "Reach zero, keep it"] {
            let field = try #require(descendants(of: rules.view, as: NSTextField.self)
                .first { $0.stringValue == title })
            let size = try #require(field.font?.pointSize)
            #expect(size >= bodySize, "the \(title) subhead is \(size) pt above \(bodySize) pt body text")
            #expect(field.font?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                    "the \(title) subhead carries no weight step")
        }

        // The measure is 60 characters of the body face.
        let character = ("0" as NSString).size(withAttributes: [.font: RulesViewController.bodyFont]).width
        let measure = try #require(bodyLabels.first).preferredMaxLayoutWidth
        #expect(abs(measure - 60 * character) <= 1,
                "the body measure is \(measure) pt, not 60 characters (\(60 * character) pt)")
        window.orderOut(nil)
    }

    // MARK: - Problem 24: the picker line and the activation copy state the behaviour

    @Test func pickerTrialLineStatesHowASessionIsCounted() throws {
        let state = try exhaustedState(checkoutConfigured: true, used: 1)
        let picker = HomeViewController(appState: state)
        let window = host(picker, size: NSSize(width: 1040, height: 720))
        let line = try #require(visibleStrings(in: picker.view).first { $0.hasPrefix("Free trial:") },
                                "the picker lost its trial line")
        #expect(line == "Free trial: 2 of 3 sessions left, counted at the first character.",
                "the trial line does not match the counter: \(line)")
        let field = try #require(descendants(of: picker.view, as: NSTextField.self)
            .first { $0.stringValue == line })
        #expect(field.frame.height <= 20, "the trial line wrapped to \(field.frame.height) pt")
        window.orderOut(nil)
    }

    @Test func activationCopyStatesWhatTheAppDoes() throws {
        for used in [3, 4] {
            let controller = UpgradeViewController(appState: try exhaustedState(checkoutConfigured: true, used: used))
            let window = host(controller, size: NSSize(width: 1040, height: 720))
            let strings = visibleStrings(in: controller.view)
            #expect(strings.contains("A license is required to keep writing on this Mac."),
                    "the activation card still claims a cause the state may not have: \(strings)")
            #expect(!strings.contains("After 3 free sessions, a license is required to keep writing."))
            #expect(strings.contains("Try the free web room"),
                    "the free route is not named for the free web room: \(strings)")
            #expect(!strings.contains { $0.contains("full web app") },
                    "the card still calls the free web room the full web app")
            window.orderOut(nil)
        }
    }

    // MARK: - D-030: COPIED keeps the copy control's width

    @Test func copiedKeepsTheCopyWidthSoTheRowDoesNotShift() throws {
        let fixture = try keptRoom(size: NSSize(width: 1040, height: 720))
        let copy = try #require(descendants(of: fixture.room.view, as: NSButton.self)
            .first { $0.title == "COPY TEXT" })
        let restart = try #require(descendants(of: fixture.room.view, as: NSButton.self)
            .first { $0.title == "RUN IT AGAIN" })
        fixture.room.view.layoutSubtreeIfNeeded()
        let restingWidth = copy.frame.width
        let restingRestart = fixture.room.view.convert(restart.bounds, from: restart)
        let restingRow = fixture.room.view.convert(copy.superview?.bounds ?? .zero,
                                                   from: copy.superview ?? copy)
        fixture.room.copyKeptText()
        fixture.room.view.layoutSubtreeIfNeeded()
        #expect(copy.title == "COPIED")
        #expect(abs(copy.frame.width - restingWidth) <= 0.5,
                "COPIED is \(copy.frame.width) pt wide against COPY TEXT's \(restingWidth) pt")
        let copiedRestart = fixture.room.view.convert(restart.bounds, from: restart)
        #expect(abs(copiedRestart.minX - restingRestart.minX) <= 0.5,
                "RUN IT AGAIN moved \(copiedRestart.minX - restingRestart.minX) pt under the pointer")
        let copiedRow = fixture.room.view.convert(copy.superview?.bounds ?? .zero, from: copy.superview ?? copy)
        #expect(abs(copiedRow.midX - restingRow.midX) <= 0.5)
        fixture.window.orderOut(nil)
    }

    // MARK: - The wiped room restarts where a first entry starts
    //
    // Item 8 of the review asked for a visible caret on the wiped room. D-070 supersedes that (the stopped
    // group sits where the line was, so the writing layer is transparent and no caret is drawn inside it),
    // and RoundThreeTests asserts the invisible layer. What stays testable is that the insertion point a
    // restart types at is exactly the first-entry one, never left where the long draft scrolled to.

    @Test func wipedRoomRestartsOnTheFirstEntryInsertionPoint() throws {
        for size in Self.windowSizes {
            let fresh = try room(size: size)
            fresh.room.viewDidLayout()
            fresh.window.makeKeyAndOrderFront(nil)
            fresh.room.viewDidAppear()
            fresh.room.view.layoutSubtreeIfNeeded()
            let freshCaret = caretInPaper(fresh.editor, paper: fresh.paper)

            let wiped = try room(size: size)
            wiped.window.makeKeyAndOrderFront(nil)
            wiped.room.viewDidAppear()
            let long = (1...12).map { "line \($0) of a draft long enough to scroll" }.joined(separator: "\n")
            wiped.editor.insertText(long, replacementRange: NSRange(location: NSNotFound, length: 0))
            wiped.clock.now = 1
            wiped.engine.registerMarkedTextActivity()
            wiped.room.tick()
            wiped.clock.now = 20
            wiped.room.tick()
            wiped.room.endCutAnimation()
            wiped.room.viewDidLayout()
            wiped.room.view.layoutSubtreeIfNeeded()

            #expect(wiped.engine.phase == .failure)
            #expect(wiped.editor.string.isEmpty)
            #expect(wiped.editor.isEditable)
            #expect(wiped.window.firstResponder === wiped.editor, "the wiped room lost the editor focus")
            let scroll = try #require(wiped.editor.enclosingScrollView)
            let caret = caretInPaper(wiped.editor, paper: wiped.paper)
            #expect(caret.height > 0, "the wiped insertion point has no height")
            #expect(abs(caret.minX - freshCaret.minX) <= 1,
                    "at \(size) the wiped caret is \(caret.minX), a fresh entry puts it at \(freshCaret.minX)")
            #expect(abs(caret.midY - freshCaret.midY) <= 1,
                    "at \(size) the wiped caret is \(caret.midY) pt down, first entry puts it at \(freshCaret.midY)")
            let visible = scroll.contentView.documentVisibleRect
            let inClip = scroll.contentView.convert(wiped.editor.caretRectForCurrentInsertionPoint(),
                                                    from: wiped.editor)
            #expect(visible.contains(NSPoint(x: inClip.midX, y: inClip.midY)),
                    "the wiped caret at \(inClip) is outside the visible writing area \(visible)")
            fresh.window.orderOut(nil)
            wiped.window.orderOut(nil)
        }
    }

    // MARK: - Fixtures

    private final class Clock {
        var now: TimeInterval = 0
    }

    private struct RoomFixture {
        let room: SessionViewController
        let window: NSWindow
        let editor: AppendOnlyTextView
        let paper: NSView
        let engine: SessionEngine
        let state: AppState
        let clock: Clock
    }

    private struct KeptFixture {
        let room: SessionViewController
        let window: NSWindow
        let paper: NSView
    }

    private func room(size: NSSize) throws -> RoomFixture {
        let fixture = try roomWithoutWindow(size: size)
        fixture.window.contentViewController = fixture.room
        fixture.window.setContentSize(size)
        fixture.room.view.layoutSubtreeIfNeeded()
        fixture.room.viewDidLayout()
        fixture.room.view.layoutSubtreeIfNeeded()
        return fixture
    }

    private func roomWithoutWindow(size: NSSize) throws -> RoomFixture {
        let root = temporaryRoot()
        let clock = Clock()
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state, pasteboard: NSPasteboard(name: .init(UUID().uuidString)))
        _ = room.view
        let editor = try #require(descendants(of: room.view, as: AppendOnlyTextView.self).first)
        let paper = try #require(editor.enclosingScrollView?.superview)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        RoomWindowKeeper.windows.append(window)
        return RoomFixture(room: room, window: window, editor: editor, paper: paper,
                           engine: engine, state: state, clock: clock)
    }

    private func keptRoom(size: NSSize, text: String = "cant say this out loud but\ni dont want the promotion\npromotion. i want time") throws -> KeptFixture {
        let fixture = try roomWithoutWindow(size: size)
        fixture.editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            fixture.clock.now = second
            fixture.engine.registerMarkedTextActivity()
        }
        fixture.clock.now = 60
        fixture.engine.tick()
        fixture.room.tick()
        fixture.window.contentViewController = fixture.room
        fixture.window.setContentSize(size)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        fixture.room.view.layoutSubtreeIfNeeded()
        fixture.room.viewDidLayout()
        fixture.room.view.layoutSubtreeIfNeeded()
        #expect(fixture.engine.phase == .success)
        return KeptFixture(room: fixture.room, window: fixture.window, paper: fixture.paper)
    }

    private func exhaustedState(checkoutConfigured: Bool, used: Int = 3) throws -> AppState {
        let root = temporaryRoot()
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = used
        let store = SettingsStore(configDirectory: root)
        try store.save(settings)
        let checkout: CheckoutClient = checkoutConfigured
            ? MockCheckoutClient()
            : HostedCheckoutClient(baseURL: nil)
        return AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                        checkoutClient: checkout, installIDStore: InstallIDStore(configDirectory: root),
                        productID: "prod_mock")
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        RoomWindowKeeper.roots.append(root)
        return root
    }

    private func host(_ controller: NSViewController, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentViewController = controller
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        controller.view.layoutSubtreeIfNeeded()
        RoomWindowKeeper.windows.append(window)
        return window
    }

    // MARK: - Geometry helpers

    private func currentLineCentre(in editor: AppendOnlyTextView, paper: NSView) throws -> CGFloat {
        let layout = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        layout.ensureLayout(for: container)
        let length = (editor.string as NSString).length
        let rect: NSRect
        if editor.string.isEmpty || editor.string.hasSuffix("\n") {
            rect = layout.extraLineFragmentRect
        } else {
            let glyph = layout.glyphIndexForCharacter(at: max(length - 1, 0))
            rect = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        let y = editor.textContainerOrigin.y + rect.midY
        return paper.bounds.height - paper.convert(NSPoint(x: 0, y: y), from: editor).y
    }

    private func caretInPaper(_ editor: AppendOnlyTextView, paper: NSView) -> NSRect {
        let caret = editor.caretRectForCurrentInsertionPoint()
        let origin = paper.convert(NSPoint(x: caret.minX, y: caret.maxY), from: editor)
        return NSRect(x: origin.x, y: paper.bounds.height - origin.y,
                      width: caret.width, height: caret.height)
    }

    private func descendants<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, as: type)
        }
    }

    private func visibleStrings(in view: NSView) -> [String] {
        ((view as? NSTextField).flatMap { $0.isHiddenOrHasHiddenAncestor ? nil : [$0.stringValue] } ?? [])
            + ((view as? NSButton).flatMap { $0.isHiddenOrHasHiddenAncestor || $0.title.isEmpty ? nil : [$0.title] } ?? [])
            + view.subviews.flatMap(visibleStrings)
    }
}

@MainActor
private enum RoomWindowKeeper {
    static var windows: [NSWindow] = []
    static var roots: [URL] = []
}
