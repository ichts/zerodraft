import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct RoundThreeTests {
    // MARK: - Card alignment

    @Test func licensedCardCentresStartWritingAndPreLicenceGroup() throws {
        let licensed = UpgradeViewController(appState: licensedTestState())
        let window = makeWindow(licensed)
        let card = try #require(descendants(of: licensed.view, of: FirstLineCardView.self).first)
        let content = card.contentView
        let start = try #require(descendants(of: content, of: NSButton.self).first { $0.title == "Start writing" })
        assertCentred(start, in: content, "licensed Start writing")

        let inactive = UpgradeViewController(appState: try trialState(used: 3))
        let inactiveWindow = makeWindow(inactive)
        let inactiveCard = try #require(descendants(of: inactive.view, of: FirstLineCardView.self).first)
        let inactiveContent = inactiveCard.contentView
        let activate = try #require(descendants(of: inactiveContent, of: NSButton.self).first { $0.title == "Activate" })
        let buy = try #require(descendants(of: inactiveContent, of: NSButton.self).first { $0.title.hasPrefix("Buy a license") })
        let activateRect = inactiveContent.convert(activate.bounds, from: activate)
        let buyRect = inactiveContent.convert(buy.bounds, from: buy)
        let groupCentre = (min(activateRect.minX, buyRect.minX) + max(activateRect.maxX, buyRect.maxX)) / 2
        #expect(abs(groupCentre - inactiveContent.bounds.midX) <= 1,
                "pre-licence action group must stay centred as a unit")
        window.orderOut(nil)
        inactiveWindow.orderOut(nil)
    }

    // MARK: - Picker access line

    @Test func licensedPickerHidesAccessLineAndTrialPickerKeepsIt() throws {
        let licensed = HomeViewController(appState: licensedTestState())
        _ = makeWindow(licensed)
        let licensedTexts = descendants(of: licensed.view, of: NSTextField.self).map(\.stringValue)
        #expect(licensedTexts.contains("License active.") == false ||
                descendants(of: licensed.view, of: NSTextField.self)
                    .filter { $0.stringValue == "License active." }
                    .allSatisfy(\.isHiddenOrHasHiddenAncestor))

        let trial = HomeViewController(appState: try trialState(used: 2))
        _ = makeWindow(trial)
        let trialLine = try #require(descendants(of: trial.view, of: NSTextField.self)
            .first { $0.stringValue == "Free trial: 1 of 3 sessions left." })
        #expect(!trialLine.isHiddenOrHasHiddenAncestor)
    }

    // MARK: - Ink focus on every control

    @Test func everyCardControlUsesTheInkFocusRingInLightAndDark() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let roomState = licensedTestState(sessionEngine: engine,
                                          settingsStore: SettingsStore(configDirectory: tempRoot()),
                                          installIDStore: InstallIDStore(configDirectory: tempRoot()))
        roomState.startSession(duration: 60)
        let room = SessionViewController(appState: roomState)
        _ = room.view
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        editor.insertText("one line of draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            now.now = second
            engine.registerMarkedTextActivity()
        }
        now.now = 60
        room.tick()

        let cards: [(String, NSViewController)] = [
            ("picker", HomeViewController(appState: try trialState(used: 2))),
            ("activation", UpgradeViewController(appState: try trialState(used: 3))),
            ("licensed", UpgradeViewController(appState: licensedTestState())),
            ("settings", SettingsViewController(appState: licensedTestState())),
            ("room", SessionViewController(appState: licensedTestState())),
            ("kept", room),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, controller) in cards {
                let window = makeWindow(controller, appearance: appearance)
                let controls = descendants(of: controller.view, of: NSButton.self)
                #expect(!controls.isEmpty, "\(name) has no buttons")
                for control in controls {
                    #expect(control.focusRingType == .none, "\(name) control \(control.title) falls back to the system ring")
                    let ringing = try #require(control as? FirstLineInkFocusRinging,
                                               "\(name) control \(control.title) has no ink ring")
                    window.makeFirstResponder(control)
                    control.needsDisplay = true
                    control.displayIfNeeded()
                    #expect(ringing.showsInkFocusRing, "\(name) control \(control.title) did not show the ink ring")
                    let ringColor = resolved(ringing.inkFocusRingColor, appearance)
                    let ink = resolved(FirstLineColors.inkNSColor, appearance)
                    #expect(ringColor == ink, "\(name) control \(control.title) ring is not the ink token")
                }
                window.orderOut(nil)
            }
        }
    }

    // MARK: - Empty caret and placeholder

    @Test func emptyCaretSitsOnThePlaceholderFirstGlyphAndMarkedTextHidesIt() throws {
        let state = licensedTestState()
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let placeholder = try #require(descendants(of: room.view, of: NSTextField.self)
            .first { $0.stringValue == "Start typing." })
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let font = try #require(placeholder.font)
        let text = placeholder.stringValue as NSString
        let width = text.size(withAttributes: [.font: font]).width
        let x = placeholder.bounds.minX + max((placeholder.bounds.width - width) / 2, 0)
        let baseline = placeholder.bounds.maxY - placeholder.firstBaselineOffsetFromTop
        let expected = editor.convert(NSPoint(x: x, y: baseline), from: placeholder)
        let origin = try #require(editor.emptyCaretOrigin)
        #expect(abs(origin.x - expected.x) <= 1)
        #expect(abs(origin.y - expected.y) <= 1)
        let caret = editor.caretRectForCurrentInsertionPoint()
        #expect(abs(caret.minX - origin.x) <= 1)
        #expect(abs((caret.minY + (editor.font?.ascender ?? 0)) - origin.y) <= 1)
        #expect(!placeholder.isHidden)

        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        room.refreshRoom()
        #expect(editor.hasMarkedText())
        #expect(placeholder.isHidden)
        window.orderOut(nil)
    }

    // MARK: - Full sheet and room bars

    @Test func sheetFillsTheWindowAndKeepsTheReadableColumn() throws {
        for size in [NSSize(width: 1040, height: 720), NSSize(width: 1600, height: 1000)] {
            let state = licensedTestState()
            state.startSession()
            let room = SessionViewController(appState: state)
            let window = makeWindow(room, size: size)
            let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
            let scroll = try #require(editor.enclosingScrollView)
            let paper = try #require(scroll.superview)
            let insets = room.view.safeAreaInsets
            let bounds = room.view.bounds
            #expect(abs(paper.frame.minX - (insets.left + 32)) <= 1, "sheet leading margin at \(size)")
            #expect(abs(paper.frame.maxX - (bounds.maxX - insets.right - 32)) <= 1, "sheet trailing margin at \(size)")
            #expect(abs(paper.frame.minY - (insets.bottom + 32)) <= 1, "sheet bottom margin at \(size)")
            #expect(abs(paper.frame.maxY - (bounds.maxY - insets.top - 32)) <= 1, "sheet top margin at \(size)")
            let font = FirstLineTypography.writingNSFont(size: state.settings.writingFontSize.points)
            let character = ("0" as NSString).size(withAttributes: [.font: font]).width
            let expected = min(CGFloat(state.settings.writingAlignment.measureCharacters) * character,
                               scroll.bounds.width - 16)
            let measured = try #require(editor.textContainer).containerSize.width
            #expect(abs(measured - expected) <= 6, "writing column is \(measured), expected \(expected)")
            #expect(measured / character >= 55 && measured / character <= 70,
                    "column must stay a readable 60-70 characters (the 62ch cap fits the sheet)")
            let placeholder = try #require(descendants(of: room.view, of: NSTextField.self)
                .first { $0.stringValue == "Start typing." })
            #expect(abs(placeholder.frame.width - measured) <= 6)
            window.orderOut(nil)
        }
    }

    @Test func roomBarsFollowLiveTrialSemantics() throws {
        let now = MutableRoundClock(0)
        let engine = SessionEngine(now: { now.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: tempRoot()),
                                      installIDStore: InstallIDStore(configDirectory: tempRoot()))
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        let window = makeWindow(room)
        let editor = try #require(descendants(of: room.view, of: AppendOnlyTextView.self).first)
        let scroll = try #require(editor.enclosingScrollView)
        let paper = try #require(scroll.superview)
        let bars = descendants(of: room.view, of: FirstLineFillBar.self)
        #expect(bars.count == 2)
        let top = try #require(bars.first { abs($0.frame.height - 2) <= 0.5 })
        let bottom = try #require(bars.first { abs($0.frame.height - 3) <= 0.5 })
        #expect(abs(top.frame.maxY - paper.bounds.maxY) <= 1, "top bar pinned to the paper top")
        #expect(abs(bottom.frame.minY) <= 1, "bottom bar pinned to the paper bottom")
        #expect(abs(top.fraction - 1) <= 0.01, "top bar starts full")
        #expect(abs(bottom.fraction - 1) <= 0.01, "bottom bar starts full while typing")
        #expect(resolved(top.fillColor, .aqua) == resolved(FirstLineColors.inkNSColor, .aqua))

        for second in stride(from: 4.0, through: 28.0, by: 4.0) {
            now.now = second
            engine.registerCommittedText("a")
        }
        now.now = 30
        engine.registerCommittedText("a")
        room.tick()
        #expect(abs(top.fraction - engine.remaining / engine.duration) <= 0.02,
                "top bar tracks the remaining session time")
        #expect(top.fraction < 1)
        #expect(abs(bottom.fraction - 1) <= 0.02)

        now.now = 32
        room.tick()
        #expect(abs(bottom.fraction - 0.75) <= 0.02)
        #expect(resolved(bottom.fillColor, .aqua) == resolved(FirstLineColors.inkNSColor, .aqua))

        now.now = 35
        room.tick()
        #expect(abs(bottom.fraction - 0.375) <= 0.02)
        #expect(resolved(bottom.fillColor, .aqua) == resolved(FirstLineColors.redNSColor, .aqua))

        now.now = 38
        room.tick()
        #expect(top.fraction == 0)
        #expect(bottom.fraction == 0)
        window.orderOut(nil)
    }

    @Test func writingAlignmentNamesTheColumnMeasure() {
        #expect(WritingAlignment.centered.label == "Narrow column")
        #expect(WritingAlignment.left.label == "Wide column")
        #expect(WritingAlignment.centered.measureCharacters == 62)
        #expect(WritingAlignment.left.measureCharacters == 70)
    }

    // MARK: - IME composition paths

    @Test func markedBackspaceAndCandidateKeysPassThroughWithoutDeny() throws {
        let (editor, deny) = makeEditor()
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        editor.deleteBackward(nil)
        #expect(deny.count == 0)

        for candidateKey in ["1", "2", " ", "\n"] {
            editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            let marked = editor.markedRange()
            editor.insertText(candidateKey, replacementRange: marked)
            #expect(deny.count == 0, "candidate key \(candidateKey.debugDescription) denied")
        }
        #expect(deny.count == 0)
    }

    @Test func commitReplacingMarkedRangeAfterUnmarkDoesNotDeny() throws {
        let (editor, deny) = makeEditor()
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.markedRange()
        editor.insertText("你好", replacementRange: marked)
        #expect(deny.count == 0)
        #expect(editor.string == "你好")
        #expect(!editor.hasMarkedText())

        editor.setMarkedText("shijie", selectedRange: NSRange(location: 6, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let secondMarked = editor.markedRange()
        editor.unmarkText()
        editor.insertText("世界", replacementRange: secondMarked)
        #expect(deny.count == 0)
        #expect(editor.string == "你好世界")
    }

    @Test func markedReplacementAndDeleteCommandDoNotDeny() throws {
        let (editor, deny) = makeEditor()
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.replaceCharacters(in: editor.markedRange(), with: "zhongguo")
        #expect(deny.count == 0)
        #expect(!AppendOnlyInputPolicy.shouldDenyCommand(#selector(NSResponder.deleteBackward(_:)), hasMarkedText: true))
        #expect(!AppendOnlyInputPolicy.shouldDenyCommand(Selector(("moveLeft:")), hasMarkedText: true))
        #expect(AppendOnlyInputPolicy.shouldDenyCommand(#selector(NSResponder.deleteBackward(_:)), hasMarkedText: false))
    }

    @Test func japaneseKoreanAndShuangpinSequencesStayCompositionSafe() throws {
        for (name, marked, committed) in [
            ("japanese", "にほん", "日本"),
            ("korean", "한국", "한국"),
            ("shuangpin", "ni", "你"),
            ("pinyin", "nihao", "你好"),
        ] {
            let (editor, deny) = makeEditor()
            editor.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            let range = editor.markedRange()
            editor.deleteBackward(nil)
            #expect(deny.count == 0, "\(name) backspace denied")
            editor.insertText(committed, replacementRange: range)
            #expect(deny.count == 0, "\(name) commit denied")
            #expect(editor.string.contains(committed))
            editor.deleteBackward(nil)
            #expect(deny.count == 1, "\(name) committed deletion must deny")
        }
    }

    // MARK: - Helpers

    private func assertCentred(_ control: NSControl, in content: NSView, _ label: String) {
        let rect = content.convert(control.bounds, from: control)
        #expect(abs(rect.midX - content.bounds.midX) <= 1, "\(label) is not centred in the card content")
    }

    private func makeWindow(_ controller: NSViewController,
                            appearance: NSAppearance.Name = .aqua,
                            size: NSSize = NSSize(width: 1040, height: 720)) -> NSWindow {
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

    private func makeEditor() -> (AppendOnlyTextView, DenyCounter) {
        let editor = AppendOnlyTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        editor.configureSessionTypography()
        let counter = DenyCounter()
        editor.onDeny = { counter.count += 1 }
        return (editor, counter)
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

    private func resolved(_ color: NSColor, _ appearance: NSAppearance.Name) -> NSColor? {
        var result: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)
        }
        return result
    }

    private func descendants<T: NSView>(of view: NSView, of type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, of: type)
        }
    }
}

@MainActor
private enum WindowKeeper {
    static var windows: [NSWindow] = []
}

private final class MutableRoundClock {
    var now: TimeInterval
    init(_ now: TimeInterval) { self.now = now }
}

private final class DenyCounter {
    var count = 0
}
