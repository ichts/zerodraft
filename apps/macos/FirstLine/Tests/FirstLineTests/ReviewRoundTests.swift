import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// Fix round for the blind visual review (F-02, F-05..F-12, F-15).
@MainActor
struct ReviewRoundTests {
    private final class Clock {
        var now: TimeInterval = 0
    }

    // MARK: - F-02: a wiped draft keeps a focused, visible caret

    @Test func wipedStateKeepsTheEditorFocusedForTheNextDraft() throws {
        let now = Clock()
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        editor.insertText("hello there", replacementRange: NSRange(location: NSNotFound, length: 0))
        now.now = 9
        room.tick()
        room.endCutAnimation()
        room.view.layoutSubtreeIfNeeded()

        #expect(engine.phase == .failure)
        #expect(window.firstResponder === editor, "the deleted state lost the editor focus")
        #expect(editor.isEditable)
        #expect(!descendants(of: room.view, of: NSTextField.self)
            .contains { $0.stringValue == "Start typing." })
        let container = try #require(editor.textContainer)
        let caret = editor.caretRectForCurrentInsertionPoint()
        let insertionX = editor.textContainerOrigin.x + container.containerSize.width / 2
        #expect(abs(caret.midX - insertionX) <= 1, "the wiped caret is not on the centred insertion point")
        #expect(caret.height > 0)
        window.orderOut(nil)
    }

    // MARK: - F-06 / F-07: the kept actions share one baseline; copy width is fixed

    @Test func keptActionsShareOneOpticalCentreAndThePillFitsItsLabel() throws {
        let fixture = keptRoom()
        let copy = try #require(descendants(of: fixture.room.view, of: NSButton.self)
            .first { $0.title == "COPY TEXT" })
        let restart = try #require(descendants(of: fixture.room.view, of: NSButton.self)
            .first { $0.title == "RUN IT AGAIN" })
        fixture.room.view.layoutSubtreeIfNeeded()
        fixture.room.view.displayIfNeeded()

        let rep = try #require(fixture.room.view.bitmapImageRepForCachingDisplay(in: fixture.room.view.bounds))
        fixture.room.view.cacheDisplay(in: fixture.room.view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / fixture.room.view.bounds.width
        let copyFrame = fixture.room.view.convert(copy.bounds, from: copy)
        let restartFrame = fixture.room.view.convert(restart.bounds, from: restart)
        // The copy title is white on the ink pill; the restart title is dark on paper.
        let copyInk = try inkRow(in: rep, frame: copyFrame.insetBy(dx: 12, dy: 6), scale: scale) { colour in
            let luma = 0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent
            return luma > 0.85
        }
        let restartInk = try inkRow(in: rep, frame: restartFrame.insetBy(dx: 12, dy: 6), scale: scale) { colour in
            let luma = 0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent
            return luma < 0.5
        }
        let copyInkCentre = (CGFloat(copyInk.lowerBound) + CGFloat(copyInk.upperBound)) / 2
        let restartInkCentre = (CGFloat(restartInk.lowerBound) + CGFloat(restartInk.upperBound)) / 2
        let centreDelta = abs(copyInkCentre - restartInkCentre) / scale
        #expect(centreDelta <= 1, "COPY TEXT and RUN IT AGAIN ink centres are \(centreDelta) pt apart")
        #expect(abs(copy.frame.height - 48) <= 0.5)
        #expect(abs(restart.frame.height - 48) <= 0.5, "RUN IT AGAIN is not the primary height")
        #expect(restart.layer?.borderWidth == 1, "RUN IT AGAIN is not a quiet outlined control")
        // The pill label must be optically centred: the ink gaps above and below
        // are equal within 1 pt (the fourth hands-on report: it sat low).
        let height = CGFloat(rep.pixelsHigh) / scale
        let pillTopRow = (height - copyFrame.maxY) * scale
        let pillBottomRow = (height - copyFrame.minY) * scale
        let topGap = (CGFloat(copyInk.lowerBound) - pillTopRow) / scale
        let bottomGap = (pillBottomRow - CGFloat(copyInk.upperBound)) / scale
        #expect(abs(topGap - bottomGap) <= 1,
                "COPY TEXT ink sits \(topGap) pt from the top and \(bottomGap) pt from the bottom")

        let copyLabel = try #require(descendants(of: copy, of: NSTextField.self)
            .first { $0.stringValue == "COPY TEXT" })
        let padding = copy.frame.width - copyLabel.intrinsicContentSize.width
        #expect(padding >= 40 && padding <= 56,
                "the copy pill carries \(padding) pt around its label")
        let originalWidth = copy.frame.width
        fixture.room.copyKeptText()
        fixture.room.view.layoutSubtreeIfNeeded()
        #expect(copy.title == "COPIED")
        #expect(copy.frame.width < originalWidth, "the COPIED pill kept the widest label width")
        let actions = try #require(copy.superview)
        let rowCentre = fixture.room.view.convert(actions.bounds, from: actions).midX
        #expect(abs(rowCentre - fixture.room.view.bounds.midX) <= 1,
                "the action row is not centred after the pill shrank")
        fixture.window.orderOut(nil)
    }

    @Test func keptRestartEntersTheWritingRoomWithoutATick() throws {
        let fixture = keptRoom()
        let restart = try #require(descendants(of: fixture.room.view, of: NSButton.self)
            .first { $0.title == "RUN IT AGAIN" })
        let editor = try #require(descendants(of: fixture.room.view, of: AppendOnlyTextView.self).first)
        let scroll = try #require(editor.enclosingScrollView)
        #expect(fixture.engine.phase == .success)
        #expect(scroll.isHidden)

        restart.performClick(nil)

        #expect(fixture.engine.phase == .writing)
        #expect(!scroll.isHidden)
        #expect(editor.isEditable)
        #expect(fixture.window.firstResponder === editor)
        editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.engine.text == "x")
        fixture.window.orderOut(nil)
    }

    @Test func keptDraftRecentersAfterEveryWindowResize() throws {
        let fixture = keptRoom(text: "第一行\n这是一段较长的草稿，用来检查窗口尺寸变化后的居中。\nshort latin line")
        let body = try #require(descendants(of: fixture.room.view, of: NSTextField.self)
            .first { $0.stringValue.hasPrefix("第一行") })
        for size in [NSSize(width: 1728, height: 1117), NSSize(width: 900, height: 700),
                     NSSize(width: 1728, height: 1117)] {
            fixture.window.setContentSize(size)
            fixture.window.contentView?.layoutSubtreeIfNeeded()
            fixture.room.view.layoutSubtreeIfNeeded()
            let centre = fixture.room.view.convert(body.bounds, from: body).midX
            let expected = fixture.room.view.bounds.midX
            #expect(abs(centre - expected) <= 1,
                    "kept draft centre \(centre) at \(size), expected \(expected)")
        }
        fixture.window.orderOut(nil)
    }

    // MARK: - F-08 / F-09: one aligned license block with real controls

    @Test func settingsLicenseBlockIsOneAlignedBlockWithRealControls() throws {
        let settings = SettingsViewController(appState: try trialState(used: 3))
        let window = makeWindow(settings)
        settings.view.layoutSubtreeIfNeeded()
        settings.view.displayIfNeeded()
        let labels = visibleLabels(in: settings.view)
        let status = try #require(labels.first { $0.stringValue == "Activate this Mac to start writing." })
        let explanation = try #require(labels.first { $0.stringValue.hasPrefix("Enter your order number") })
        let field = try #require(descendants(of: settings.view, of: NSTextField.self)
            .first { $0.placeholderString == "Order number or activation code" })
        let activate = try #require(descendants(of: settings.view, of: NSButton.self).first { $0.title == "Activate" })
        let buy = try #require(descendants(of: settings.view, of: NSButton.self)
            .first { $0.title.hasPrefix("Buy a license") })
        let done = try #require(descendants(of: settings.view, of: NSButton.self).first { $0.title == "Done" })
        let theme = try #require(descendants(of: settings.view, of: NSPopUpButton.self).first)

        let statusFrame = settings.view.convert(status.bounds, from: status)
        let explanationFrame = settings.view.convert(explanation.bounds, from: explanation)
        #expect(abs(statusFrame.minX - explanationFrame.minX) <= 1, "license text is not left-aligned")
        #expect(!field.isHidden)

        let activateFrame = settings.view.convert(activate.bounds, from: activate)
        let buyFrame = settings.view.convert(buy.bounds, from: buy)
        #expect(abs(activateFrame.height - 48) <= 0.5)
        #expect(abs(buyFrame.height - 48) <= 0.5, "Buy is not on the Activate height")
        #expect(abs(activateFrame.midY - buyFrame.midY) <= 1, "Activate and Buy are not one row")
        #expect(buy.isEnabled)
        buy.displayIfNeeded()
        #expect((buy.layer?.borderWidth ?? 0) == 1, "Buy has no outline-control affordance")

        let card = try #require(descendants(of: settings.view, of: FirstLineCardView.self).first)
        let contentRight = settings.view.convert(NSPoint(x: card.contentView.bounds.maxX, y: 0),
                                                 from: card.contentView).x
        let doneRight = settings.view.convert(done.bounds, from: done).maxX
        // Auto Layout aligns a popup's alignment rect; its bezel frame overhangs by
        // its cell inset (4 pt), which is normal macOS chrome, not a column drift.
        let themeRight = settings.view.convert(theme.alignmentRect(forFrame: theme.frame),
                                               from: theme.superview).maxX
        #expect(abs(doneRight - contentRight) <= 1)
        #expect(abs(themeRight - contentRight) <= 1, "appearance controls do not reach the card content edge")
        #expect(abs(buyFrame.maxX - contentRight) <= 1, "the license controls do not align with Done")

        #expect(!labels.contains { $0.stringValue.contains("Instance:") }, "the instance id is still shown")
        #expect(descendants(of: settings.view, of: FirstLineStatusView.self).isEmpty,
                "the license status still carries a status dot")
        expectNoDividerTouchesText(in: settings.view)
        window.orderOut(nil)
    }

    @Test func licensedSettingsShowDatesWithoutImplementationDetails() throws {
        let settings = SettingsViewController(appState: licensedTestState())
        let window = makeWindow(settings)
        settings.view.layoutSubtreeIfNeeded()
        settings.view.displayIfNeeded()
        let labels = visibleLabels(in: settings.view)
        #expect(labels.contains { $0.stringValue.hasPrefix("Activated ") })
        #expect(labels.contains { $0.stringValue.hasPrefix("Last validated ") })
        #expect(!labels.contains { $0.stringValue.contains("Instance:") })
        #expect(!labels.contains { $0.stringValue.hasPrefix("Enter your order number") })
        #expect(descendants(of: settings.view, of: NSButton.self)
            .filter { !$0.isHiddenOrHasHiddenAncestor }
            .contains { $0.title == "Activate" } == false,
                "the activation entry is still visible for a licensed Mac")
        expectNoDividerTouchesText(in: settings.view)
        window.orderOut(nil)
    }

    // MARK: - F-10: the activation pair shares one height on one row

    @Test func activationActionsShareOneHeightOnOneRow() throws {
        let upgrade = UpgradeViewController(appState: try trialState(used: 3))
        let window = makeWindow(upgrade)
        upgrade.view.layoutSubtreeIfNeeded()
        let activate = try #require(descendants(of: upgrade.view, of: NSButton.self).first { $0.title == "Activate" })
        let buy = try #require(descendants(of: upgrade.view, of: NSButton.self)
            .first { $0.title.hasPrefix("Buy a license") })
        let activateFrame = upgrade.view.convert(activate.bounds, from: activate)
        let buyFrame = upgrade.view.convert(buy.bounds, from: buy)
        #expect(abs(activateFrame.height - buyFrame.height) <= 0.5,
                "Activate \(activateFrame.height) and Buy \(buyFrame.height) are different heights")
        #expect(abs(activateFrame.height - 48) <= 0.5)
        #expect(abs(activateFrame.midY - buyFrame.midY) <= 1)
        window.orderOut(nil)
    }

    // MARK: - F-11: picker control labels share one style and placement

    @Test func pickerControlLabelsShareOneStyleAndPlacement() throws {
        let home = HomeViewController(appState: try trialState(used: 2))
        let window = makeWindow(home)
        home.view.layoutSubtreeIfNeeded()
        let labels = visibleLabels(in: home.view)
        let minutes = try #require(labels.first { $0.stringValue == "Minutes" })
        let silence = try #require(labels.first { $0.stringValue == "Delete after silence" })
        #expect(minutes.font?.fontName == silence.font?.fontName)
        #expect(minutes.font?.pointSize == silence.font?.pointSize)
        #expect(minutes.font?.fontDescriptor.symbolicTraits == silence.font?.fontDescriptor.symbolicTraits)
        #expect(minutes.alignment == silence.alignment)
        let duration = try #require(descendants(of: home.view, of: FirstLineSegmentedControl.self)
            .first { $0.accessibilityLabel() == "Session length" })
        let silenceControl = try #require(descendants(of: home.view, of: FirstLineSegmentedControl.self)
            .first { $0.accessibilityLabel() == "Delete after silence" })
        let minutesFrame = home.view.convert(minutes.bounds, from: minutes)
        let silenceFrame = home.view.convert(silence.bounds, from: silence)
        let durationFrame = home.view.convert(duration.bounds, from: duration)
        let silenceControlFrame = home.view.convert(silenceControl.bounds, from: silenceControl)
        #expect(minutesFrame.minY > durationFrame.maxY, "the minutes label is not above its control")
        #expect(silenceFrame.minY > silenceControlFrame.maxY, "the silence label is not above its control")
        let minutesGap = minutesFrame.minY - durationFrame.maxY
        let silenceGap = silenceFrame.minY - silenceControlFrame.maxY
        #expect(abs(minutesGap - silenceGap) <= 1, "the two labels use different label-to-control gaps")
        window.orderOut(nil)
    }

    @Test func pickerRadiosExposeTheirFullNameAndSelectedValue() throws {
        let home = HomeViewController(appState: try trialState(used: 2))
        let window = makeWindow(home)
        let duration = try #require(descendants(of: home.view, of: FirstLineSegmentedControl.self)
            .first { $0.accessibilityLabel() == "Session length" })
        let silence = try #require(descendants(of: home.view, of: FirstLineSegmentedControl.self)
            .first { $0.accessibilityLabel() == "Delete after silence" })

        let oneMinute = try #require(duration.button(forTag: 60))
        let fiveMinutes = try #require(duration.button(forTag: 300))
        #expect(oneMinute.accessibilityRole() == .radioButton)
        #expect(oneMinute.accessibilityTitle() == "1 minute")
        #expect(oneMinute.accessibilityLabel() == "1 minute")
        #expect((oneMinute.accessibilityValue() as? NSNumber)?.intValue == 1)
        #expect((fiveMinutes.accessibilityValue() as? NSNumber)?.intValue == 0)

        fiveMinutes.performClick(nil)
        #expect(duration.selectedTag == 300)
        #expect((oneMinute.accessibilityValue() as? NSNumber)?.intValue == 0)
        #expect((fiveMinutes.accessibilityValue() as? NSNumber)?.intValue == 1)

        let standard = try #require(silence.button(forTag: SilenceLimit.standard.rawValue))
        let strict = try #require(silence.button(forTag: SilenceLimit.strict.rawValue))
        #expect(standard.accessibilityTitle() == "Standard 8 s")
        #expect((standard.accessibilityValue() as? NSNumber)?.intValue == 1)
        #expect((strict.accessibilityValue() as? NSNumber)?.intValue == 0)

        strict.performClick(nil)
        #expect(silence.selectedTag == SilenceLimit.strict.rawValue)
        #expect((standard.accessibilityValue() as? NSNumber)?.intValue == 0)
        #expect((strict.accessibilityValue() as? NSNumber)?.intValue == 1)
        window.orderOut(nil)
    }

    // MARK: - F-15: the warning wash is in the rendered frame
    @Test func warningWashTintsTheRenderedPaper() throws {
        let now = Clock()
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let paper = try #require(editor.enclosingScrollView?.superview)
        editor.insertText("hello there", replacementRange: NSRange(location: NSNotFound, length: 0))
        now.now = 6.5
        room.tick()
        room.view.layoutSubtreeIfNeeded()
        room.view.displayIfNeeded()
        #expect(engine.phase == .danger)

        let rep = try #require(room.view.bitmapImageRepForCachingDisplay(in: room.view.bounds))
        room.view.cacheDisplay(in: room.view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / room.view.bounds.width
        // Sample the empty upper middle of the paper, away from the clock and the text.
        let x = Int(paper.frame.midX * scale)
        let y = Int((room.view.bounds.height - (paper.frame.maxY - 80)) * scale)
        let colour = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        #expect(colour.redComponent - colour.greenComponent > 0.02,
                "the warning paper is not tinted: \(colour)")
        #expect(colour.greenComponent < 0.98)
        window.orderOut(nil)
    }

    // MARK: - Second hands-on round: empty state, kept layout, count

    @Test func emptyCaretAndCountPromptMatchAfterAWipe() throws {
        func measure(wiped: Bool) -> (caret: NSRect, count: String, receipt: NSRect?) {
            let now = Clock()
            let engine = SessionEngine(now: { now.now })
            let state = licensedTestState(sessionEngine: engine,
                                          settingsStore: SettingsStore(configDirectory: tempRoot()),
                                          installIDStore: InstallIDStore(configDirectory: tempRoot()))
            state.startSession(duration: 60)
            let room = SessionViewController(appState: state)
            let window = makeWindow(room)
            let editor = descendants(of: room.view, of: AppendOnlyTextView.self).first!
            let paper = editor.enclosingScrollView!.superview!
            if wiped {
                editor.insertText(Array(repeating: "a long line of draft text\n", count: 12).joined(),
                                  replacementRange: NSRange(location: NSNotFound, length: 0))
                room.view.layoutSubtreeIfNeeded()
                now.now = 9
                room.tick()
                room.endCutAnimation()
                room.view.layoutSubtreeIfNeeded(); room.viewDidLayout(); room.view.layoutSubtreeIfNeeded()
            }
            let caret = paper.convert(editor.caretRectForCurrentInsertionPoint(), from: editor)
            let count = descendants(of: room.view, of: NSTextField.self)
                .first { $0.stringValue == "Type to start" || $0.stringValue == "0 words" }!
            let receipt = descendants(of: room.view, of: NSTextField.self)
                .first { $0.stringValue.hasPrefix("DRAFT DELETED AT") && !$0.isHiddenOrHasHiddenAncestor }
                .map { paper.convert($0.bounds, from: $0) }
            #expect(!descendants(of: room.view, of: NSTextField.self)
                .contains { $0.stringValue == "Start typing." })
            window.orderOut(nil)
            return (caret, count.stringValue, receipt)
        }
        let fresh = measure(wiped: false)
        let afterWipe = measure(wiped: true)
        #expect(abs(afterWipe.caret.minY - fresh.caret.minY) <= 1, "the caret moved after a wipe")
        #expect(abs(afterWipe.caret.midX - fresh.caret.midX) <= 1)
        #expect(fresh.count == "Type to start")
        #expect(afterWipe.count == "0 words")
        #expect(fresh.receipt == nil)
        #expect(afterWipe.receipt != nil)
    }

    @Test func keptActionsStayAboveALongDraftWithTheDefaultAcknowledgement() throws {
        let longDraft = (1...120).map { "line \($0) of the kept draft" }.joined(separator: "\n")
        let fixture = keptRoom(text: longDraft)
        let kept = try #require(descendants(of: fixture.room.view, of: SessionKeptView.self).first)
        let copy = kept.copyButton
        let restart = kept.restartButton
        let search = try #require(descendants(of: fixture.room.view, of: NSScrollView.self)
            .first { $0 === kept.scrollView })
        let copyFrame = fixture.room.view.convert(copy.bounds, from: copy)
        let restartFrame = fixture.room.view.convert(restart.bounds, from: restart)
        let scrollFrame = fixture.room.view.convert(search.bounds, from: search)
        #expect(copyFrame.minY > scrollFrame.maxY, "COPY TEXT is not above the draft area")
        #expect(restartFrame.minY > scrollFrame.maxY, "RUN IT AGAIN is not above the draft area")
        #expect(!copy.isHiddenOrHasHiddenAncestor)
        #expect(search.documentView!.frame.height > search.contentSize.height,
                "the long draft does not scroll under the fixed actions")

        let heading = try #require(descendants(of: fixture.room.view, of: NSTextField.self)
            .first { $0.stringValue == "You wrote it down." })
        #expect(!heading.isHiddenOrHasHiddenAncestor)
        let receipt = try #require(descendants(of: fixture.room.view, of: NSTextField.self)
            .first { $0.stringValue == RoomPresentation.keptReceipt(
                wordCount: fixture.engine.wordCount, duration: fixture.engine.duration) })
        #expect(!receipt.isHiddenOrHasHiddenAncestor)
        #expect(receipt.toolTip == RoomPresentation.countRule)
        let count = try #require(descendants(of: fixture.room.view, of: NSTextField.self)
            .first { $0.stringValue.hasSuffix("words") })
        #expect(count.toolTip == RoomPresentation.countRule)
        fixture.window.orderOut(nil)
    }

    // MARK: - Helpers

    private struct KeptFixture {
        let room: SessionViewController
        let window: NSWindow
        let state: AppState
        let engine: SessionEngine
        let now: Clock
    }

    private func keptRoom(text: String = "hello there. this draft is kept.") -> KeptFixture {
        let root = tempRoot()
        let now = Clock()
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = descendants(of: room.view, of: AppendOnlyTextView.self).first!
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            now.now = second
            engine.registerMarkedTextActivity()
        }
        now.now = 60
        room.tick()
        room.view.layoutSubtreeIfNeeded()
        room.viewDidLayout()
        room.view.layoutSubtreeIfNeeded()
        return KeptFixture(room: room, window: window, state: state, engine: engine, now: now)
    }

    /// Rows containing the requested ink in one view's rendered frame, in bitmap pixels.
    private func inkRow(in rep: NSBitmapImageRep, frame: NSRect, scale: CGFloat,
                        isInk: (NSColor) -> Bool) throws -> ClosedRange<Int> {
        let x0 = max(Int(frame.minX * scale), 0)
        let x1 = min(Int(frame.maxX * scale), rep.pixelsWide - 1)
        let height = CGFloat(rep.pixelsHigh) / scale
        let y0 = max(Int((height - frame.maxY) * scale), 0)
        let y1 = min(Int((height - frame.minY) * scale), rep.pixelsHigh - 1)
        guard x0 < x1, y0 < y1 else { throw NoInk() }
        var rows: [Int] = []
        for row in y0...y1 {
            for column in x0...x1 {
                guard let colour = rep.colorAt(x: column, y: row)?.usingColorSpace(.sRGB),
                      colour.alphaComponent > 0.4 else { continue }
                if isInk(colour) { rows.append(row); break }
            }
        }
        guard let first = rows.first, let last = rows.last else { throw NoInk() }
        return first...last
    }

    private func visibleLabels(in view: NSView) -> [NSTextField] {
        descendants(of: view, of: NSTextField.self).filter { !$0.isHiddenOrHasHiddenAncestor }
    }

    private func expectNoDividerTouchesText(in view: NSView) {
        let dividers = descendants(of: view, of: FloodCanvasView.self)
            .filter { abs($0.bounds.height - 1) <= 0.5 && !$0.isHiddenOrHasHiddenAncestor }
            .map { view.convert($0.bounds, from: $0) }
        let labels = visibleLabels(in: view).map { view.convert($0.bounds, from: $0) }
        for divider in dividers {
            for label in labels {
                #expect(!divider.insetBy(dx: 0, dy: -2).intersects(label),
                        "a hairline touches text at \(label)")
            }
        }
    }

    private func trialState(used: Int) throws -> AppState {
        let root = tempRoot()
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = used
        let store = SettingsStore(configDirectory: root)
        try store.save(settings)
        return AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                        checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                        productID: "prod_mock")
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeWindow(_ controller: NSViewController,
                            size: NSSize = NSSize(width: 1040, height: 720),
                            appearance: NSAppearance.Name = .aqua) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentViewController = controller
        window.setContentSize(size)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidAppear()
        controller.view.layoutSubtreeIfNeeded()
        WindowKeeper.windows.append(window)
        return window
    }

    private func descendants<T: NSView>(of view: NSView, of type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, of: type)
        }
    }
}

private struct NoInk: Error {}

@MainActor
private enum WindowKeeper {
    static var windows: [NSWindow] = []
}
