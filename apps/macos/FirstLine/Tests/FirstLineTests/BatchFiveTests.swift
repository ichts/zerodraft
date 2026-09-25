import AppKit
import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct DurationPickerTests {
    private func buttons(_ view: NSView) -> [NSButton] {
        ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap(buttons)
    }

    @Test func offersExactlyFiveDirectStartLengths() {
        let home = HomeViewController(appState: AppState())
        #expect(buttons(home.view).filter { $0.tag >= 60 }.map(\.tag) == [60, 300, 600, 1200, 1800])
    }

    @Test func selectionStartsWritingWithFocusedEditor() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = home
        home.viewDidAppear()
        #expect((window.firstResponder as? NSButton)?.tag == 60)
        let five = buttons(home.view).first { $0.tag == 300 }!
        five.performClick(nil)
        #expect(state.selectedSurface == .session)
        #expect(state.sessionEngine.remaining == 300)
        let room = SessionViewController(appState: state)
        window.contentViewController = room
        room.viewDidAppear()
        #expect(window.firstResponder is AppendOnlyTextView)
        room.viewWillDisappear()
    }

    @Test func lastChoiceIsDefaultAcrossLaunches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        let state = AppState(settingsStore: store, installIDStore: InstallIDStore(configDirectory: root))
        state.updateDefaultDuration(1200)
        let next = AppState(settingsStore: store, installIDStore: InstallIDStore(configDirectory: root))
        #expect(next.selectedDuration == 1200)
        next.startSession()
        #expect(next.sessionEngine.duration == 1200)
    }

    @Test func invalidStoredDurationFallsBackToOneMinute() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        try store.save(.defaultValue)
        let file = root.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: file)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["defaultDuration"] = 180
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let state = AppState(settingsStore: store, installIDStore: InstallIDStore(configDirectory: root))
        #expect(state.selectedDuration == 60)
        #expect(SessionEngine.validDuration(180) == 60)
    }
}

@MainActor
struct SettingsTests {
    private func state() -> (AppState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(settingsStore: SettingsStore(configDirectory: root),
                             installIDStore: InstallIDStore(configDirectory: root))
        return (state, root)
    }

    @Test func durationAndSilenceLimitLockDuringWriting() {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession(duration: 60)
        state.sessionEngine.registerCommittedText("draft")
        state.updateDefaultDuration(300)
        state.updateSilenceLimit(.strict)
        #expect(state.selectedDuration == 60)
        #expect(state.sessionEngine.silenceLimit == .standard)
        #expect(state.settings.silenceLimit == .standard)
    }

    @Test func preWritingChoicesPersistWithoutDraftText() throws {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        state.updateDefaultDuration(600)
        state.updateSilenceLimit(.relaxed)
        state.startSession()
        state.sessionEngine.registerCommittedText("private unique draft")
        let data = try Data(contentsOf: root.appendingPathComponent("settings.json"))
        #expect(!String(decoding: data, as: UTF8.self).contains("private unique draft"))
        let next = try state.settingsStore.load()
        #expect(next.defaultDuration == 600)
        #expect(next.silenceLimit == .relaxed)
    }

    @Test func focusModeHidesChromeUntilHoverWithoutHidingAccessibility() throws {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        state.updateFocusMode(true)
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = room
        room.viewDidAppear()
        defer { room.viewWillDisappear() }
        func fields(_ view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields)
        }
        let clock = try #require(fields(room.view).first { $0.stringValue == "1:00" })
        let count = try #require(fields(room.view).first { $0.stringValue == "0 WORDS" })
        #expect(clock.alphaValue == 0 && count.alphaValue == 0)
        #expect(clock.accessibilityLabel() == "Time remaining 1:00")
        #expect(count.accessibilityLabel() == "0 WORDS written")
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(room.view.trackingAreas.contains { $0.options.contains([.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow]) })
        func move(to point: NSPoint) {
            let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                           clickCount: 0, pressure: 0)!
            room.mouseMoved(with: event)
        }
        move(to: clock.convert(NSPoint(x: clock.bounds.midX, y: clock.bounds.midY), to: nil))
        #expect(clock.alphaValue == 1 && count.alphaValue == 1)
        move(to: NSPoint(x: window.contentView!.bounds.midX, y: window.contentView!.bounds.midY))
        #expect(clock.alphaValue == 0 && count.alphaValue == 0)
        move(to: count.convert(NSPoint(x: count.bounds.midX, y: count.bounds.midY), to: nil))
        #expect(clock.alphaValue == 1 && count.alphaValue == 1)
        let exit = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 0, pressure: 0)!
        room.mouseExited(with: exit)
        #expect(clock.alphaValue == 0 && count.alphaValue == 0)

        state.updateFocusMode(false)
        room.tick()
        #expect(clock.alphaValue == 1 && count.alphaValue == 1)
        #expect(clock.accessibilityLabel() == "Time remaining 1:00")
    }

    @Test func roomTypographyUpdatesOnlyWhenPreferencesChange() throws {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = room
        room.viewDidAppear()
        defer { room.viewWillDisappear() }
        func textViews(_ view: NSView) -> [NSTextView] {
            ((view as? NSTextView).map { [$0] } ?? []) + view.subviews.flatMap(textViews)
        }
        let kept = try #require(textViews(room.view).first { !$0.isEditable })
        #expect(kept.font?.pointSize == WritingFontSize.medium.points)
        #expect(kept.alignment == .center)
        state.updateFontSize(.large)
        state.updateAlignment(.left)
        room.tick()
        #expect(kept.font?.pointSize == WritingFontSize.large.points)
        #expect(kept.alignment == .left)
        room.tick()
        #expect(kept.font?.pointSize == WritingFontSize.large.points)
        #expect(kept.alignment == .left)
    }

    @Test func alignmentAndFontSizeDefaultsAndChoices() {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(state.settings.writingAlignment == .centered)
        #expect(state.settings.writingFontSize == .medium)
        state.updateAlignment(.left)
        state.updateFontSize(.large)
        #expect(state.settings.writingAlignment == .left)
        #expect(state.settings.writingFontSize.points == 34)
        #expect(WritingFontSize.allCases == [.small, .medium, .large])
    }

    @Test func focusWindowDeliversMouseMovementAndHasNoPinnedCommand() {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = RootWindowController(appState: state)
        #expect(controller.window?.acceptsMouseMovedEvents == true)
        let delegate = FirstLineAppDelegate(appState: state)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate)
        #expect(menu.items.last?.submenu?.items.contains { $0.keyEquivalent == "i" } == false)
    }

    @Test func nativeFullScreenExitRestoresChromeWithoutDiscardingDraft() {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        state.sessionEngine.registerCommittedText("draft stays")
        state.updateFocusMode(true)
        let sessionID = state.sessionEngine.sessionID
        let controller = RootWindowController(appState: state)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: controller.window)
        #expect(!state.settings.focusMode)
        #expect(state.sessionEngine.text == "draft stays")
        #expect(state.sessionEngine.sessionID == sessionID)
        #expect(state.selectedSurface == .session)
    }

    @Test func leavingFullScreenForSettingsKeepsFocusPreference() {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        state.sessionEngine.registerCommittedText("draft stays")
        state.updateFocusMode(true)
        let controller = RootWindowController(appState: state)
        state.openSettings()
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: controller.window)
        #expect(state.settings.focusMode)
        state.closeSettings()
        #expect(state.selectedSurface == .session)
        #expect(state.sessionEngine.text == "draft stays")
    }

    @Test func appearanceDefaultsToSystem() {
        #expect(AppSettings.defaultValue.theme == .system)
        #expect(AppSettings.defaultValue.focusMode == false)
    }

    @Test func liveVisualSettingsPreserveDraftAndDeadline() {
        let (state, root) = state()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        state.sessionEngine.registerCommittedText("draft")
        let id = state.sessionEngine.sessionID
        state.updateAlignment(.left)
        state.updateFontSize(.small)
        state.updateTheme(.dark)
        state.updateFocusMode(true)
        #expect(state.sessionEngine.text == "draft")
        #expect(state.sessionEngine.sessionID == id)
    }
}

@MainActor
struct KeyboardFlowTests {
    @Test func homeMenuAbandonsActiveDraftBeforeShowingChoices() throws {
        for fromSettings in [false, true] {
            var now = 0.0
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let state = AppState(sessionEngine: SessionEngine(now: { now }),
                                 settingsStore: SettingsStore(configDirectory: root),
                                 installIDStore: InstallIDStore(configDirectory: root))
            let delegate = FirstLineAppDelegate(appState: state)
            let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate)
            let home = try #require(menu.items.last?.submenu?.items.first { $0.keyEquivalent == "0" })
            #expect(home.target === delegate)
            #expect(delegate.validateMenuItem(home))

            state.startSession()
            state.sessionEngine.registerCommittedText("private draft")
            if fromSettings {
                now = 5
                state.handleTick()
                #expect(state.sessionEngine.phase == .danger)
                state.openSettings()
                state.closeSettings()
                #expect(state.selectedSurface == .session)
                #expect(state.sessionEngine.text == "private draft")
                state.openSettings()
            }
            #expect(NSApplication.shared.sendAction(home.action!, to: home.target, from: home))
            #expect(state.selectedSurface == .home)
            #expect(state.sessionEngine.phase == .idle)
            #expect(state.sessionEngine.text.isEmpty)

            state.updateDefaultDuration(300)
            state.updateSilenceLimit(.strict)
            state.startSession()
            #expect(state.selectedSurface == .session)
            #expect(state.sessionEngine.duration == 300)
            #expect(state.sessionEngine.silenceLimit == .strict)
            #expect(state.settings.trialSessionsUsed == 2)

            state.newPiece()
            #expect(state.settings.trialSessionsUsed == 3)
            state.newPiece()
            #expect(state.selectedSurface == .upgrade)
            #expect(state.sessionEngine.phase == .idle)
        }
    }

    @Test func commandNStartsNewPieceThroughTrialGate() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        state.startSession()
        state.sessionEngine.registerCommittedText("lost")
        state.settings.trialSessionsUsed = AppState.trialSessionLimit
        state.newPiece()
        #expect(state.selectedSurface == .upgrade)
        #expect(state.sessionEngine.text.isEmpty)
    }

    @Test func commandCCopiesEntireKeptDraft() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var time = 0.0
        let engine = SessionEngine(now: { time })
        let state = AppState(sessionEngine: engine, settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        state.startSession()
        engine.registerCommittedText("the entire draft")
        for second in stride(from: 4.0, to: 60, by: 4.0) {
            time = second
            engine.registerMarkedTextActivity()
        }
        time = 60
        engine.tick()
        #expect(engine.phase == .success)
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { board.releaseGlobally() }
        let room = SessionViewController(appState: state, pasteboard: board)
        _ = room.view
        room.copyKeptText()
        #expect(board.string(forType: .string) == "the entire draft")
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate())
        let copy = menu.items.last?.submenu?.items.first { $0.keyEquivalent == "c" }
        #expect(copy?.action == #selector(FirstLineAppDelegate.copyKept(_:)))
    }

    @Test func largeDraftAppendsThroughGuardedInputPath() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 1800)
        let room = SessionViewController(appState: state)
        func editor(_ view: NSView) -> AppendOnlyTextView? {
            if let text = view as? AppendOnlyTextView { return text }
            return view.subviews.lazy.compactMap(editor).first
        }
        let input = editor(room.view)!
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<150 { input.insertText(String(repeating: "writing forward ", count: 7), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        let duration = CFAbsoluteTimeGetCurrent() - start
        #expect(input.string == state.sessionEngine.text)
        #expect(input.string.count > 15_000)
        #expect(duration < 10, "\(duration) seconds for 15,750-character draft")
    }

    @Test func commandWClosesWindow() {
        let state = AppState()
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate())
        let close = menu.items.first?.submenu?.items.first { $0.keyEquivalent == "w" }
        #expect(close?.action == #selector(FirstLineAppDelegate.closeWindow(_:)))
    }
}
