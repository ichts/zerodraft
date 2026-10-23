import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct RoomTests {
    @Test func clockFormatsAsMinutesAndSeconds() {
        #expect(RoomPresentation.clock(60) == "1:00")
        #expect(RoomPresentation.clock(3600) == "60:00")
        #expect(RoomPresentation.clock(0) == "0:00")
    }

    @Test func wipeReportStatesDeletionAndRestart() {
        #expect(RoomPresentation.wipeReport(elapsed: 8, canRestart: true) == "Draft deleted at 0:08. Type to start again.")
        #expect(RoomPresentation.wipeReport(elapsed: 8, canRestart: false) == "Draft deleted at 0:08. Activate to keep writing.")
    }

    @Test func wipeRearmsClockAndHidesInputHint() throws {
        var now = 0.0
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = SessionEngine(now: { now })
        let state = licensedTestState(sessionEngine: engine, settingsStore: SettingsStore(configDirectory: root))
        state.startSession()
        let room = SessionViewController(appState: state)
        _ = room.view
        engine.registerCommittedText("one sentence")
        now = 7
        room.tick()
        now = 8.1
        room.tick()
        #expect(engine.phase == .failure)
        #expect(engine.deletionElapsedSeconds == 8)

        func fields(_ view: NSView) -> [NSTextField] {
            view.subviews.flatMap { child in
                ((child as? NSTextField).map { [$0] } ?? []) + fields(child)
            }
        }
        let clock = try #require(fields(room.view).first(where: { $0.accessibilityLabel()?.hasPrefix("Time remaining") == true }))
        let hint = try #require(fields(room.view).first(where: { $0.stringValue == "Start typing." }))
        #expect(clock.stringValue == "1:00")
        #expect(fields(room.view).contains { $0.stringValue == "Draft deleted at 0:08. Type to start again." && !$0.isHidden })
        #expect(hint.isHidden)
    }

    @Test func wipeReportUsesExactDeadlineDespiteFractionalStart() {
        var now = 0.7
        let engine = SessionEngine(now: { now })
        engine.start(duration: 60)
        engine.registerCommittedText("a")
        now = 8.7
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.deletionElapsedSeconds == 8)
        #expect(RoomPresentation.wipeReport(elapsed: engine.deletionElapsedSeconds ?? -1, canRestart: false) ==
            "Draft deleted at 0:08. Activate to keep writing.")
    }

    @Test func sessionTagMatchesChosenLengthAndPhase() {
        #expect(RoomPresentation.sessionTag(duration: 60, phase: .writing) == "1 minute, forward only")
        #expect(RoomPresentation.sessionTag(duration: 300, phase: .danger) == "5 minutes, forward only")
        #expect(RoomPresentation.sessionTag(duration: 60, phase: .success) == "1 minute, done")
        #expect(RoomPresentation.wordLabel(1) == "1 word")
        #expect(RoomPresentation.wordLabel(0) == "0 words")
    }

    @Test func copyTextPutsExactDraftOnPasteboard() {
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { board.releaseGlobally() }
        #expect(RoomPresentation.copy("First line\n第二行", to: board))
        #expect(board.string(forType: .string) == "First line\n第二行")
    }

    @Test func denyFeedbackDoesNotRestartWhileRunning() {
        var feedback = DenyFeedbackState()
        let first = feedback.begin(reducesMotion: false)
        #expect(first)
        #expect(feedback.shakeOffset == -2)
        let repeated = feedback.begin(reducesMotion: false)
        #expect(!repeated)
        feedback.end()
        let next = feedback.begin(reducesMotion: false)
        #expect(next)
    }

    @Test func reducedMotionDenyHasNoShake() {
        var feedback = DenyFeedbackState()
        let began = feedback.begin(reducesMotion: true)
        #expect(began)
        #expect(feedback.shakeOffset == 0)
        #expect(feedback.outlineVisible)
    }

    @Test func escapeDuringCompositionDoesNotExit() {
        #expect(!RoomPresentation.shouldExitOnEscape(isComposing: true))
    }

    @Test func escapeReturnsToStartAndDropsDraft() {
        var now = 0.0
        let engine = SessionEngine(now: { now })
        let state = licensedTestState(sessionEngine: engine, settingsStore: SettingsStore(configDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        state.startSession()
        engine.registerCommittedText("private draft")
        #expect(RoomPresentation.shouldExitOnEscape(isComposing: false))
        state.abandonSession()
        #expect(state.selectedSurface == .home)
        #expect(engine.text.isEmpty)
        now += 1
    }

    @Test(arguments: [SessionPhase.writing, .danger, .failure, .success], [WritingAlignment.centered, .left])
    func mouseExitRemainsAvailableInEveryRoomPhase(phase: SessionPhase, alignment: WritingAlignment) throws {
        var now = 0.0
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = SessionEngine(now: { now })
        let state = licensedTestState(sessionEngine: engine, settingsStore: SettingsStore(configDirectory: root))
        state.settings.writingAlignment = alignment
        state.startSession()
        let room = SessionViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = room
        engine.registerCommittedText("private draft")
        switch phase {
        case .danger: now = 5.1
        case .failure: now = 8.1
        case .success:
            for second in 1...59 {
                now = Double(second)
                engine.registerCommittedText("private draft continues")
            }
            now = 60
        default: break
        }
        room.tick()
        room.view.layoutSubtreeIfNeeded()
        #expect(engine.phase == phase)
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let views = descendants(room.view)
        let exit = try #require(views.compactMap { $0 as? NSButton }.first { $0.title == "Esc to leave" })
        #expect(!exit.isHiddenOrHasHiddenAncestor)
        #expect(exit.isEnabled)
        let exitRect = exit.convert(exit.bounds, to: room.view)
        for other in views where !other.isHiddenOrHasHiddenAncestor {
            if let button = other as? NSButton, button !== exit {
                #expect(!exitRect.intersects(button.convert(button.bounds, to: room.view)))
            }
            if let hint = other as? NSTextField, hint.stringValue == "Keep typing" {
                #expect(!exitRect.intersects(hint.convert(hint.bounds, to: room.view)))
            }
        }
        exit.performClick(nil)
        #expect(state.selectedSurface == .home)
        #expect(engine.text.isEmpty)
        #expect(engine.phase == .idle)
    }

    @Test func homeRestoresStartButtonFocusWithoutStartingSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = licensedTestState(settingsStore: SettingsStore(configDirectory: root))
        state.startSession()
        state.abandonSession()
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = home
        home.viewDidAppear()
        let button = try #require(window.firstResponder as? NSButton)
        #expect(button.title == "Begin")
        #expect(button.accessibilityLabel() == "Begin writing")
        #expect(state.selectedSurface == .home)
        #expect(state.sessionEngine.phase == .idle)
    }

    @Test func keptViewHasReceiptAndActionsWithoutPromotionalHeading() {
        let state = licensedTestState()
        state.startSession()
        let room = SessionViewController(appState: state)
        func labels(_ view: NSView) -> [String] {
            let current = (view as? NSButton).map { [$0.title] } ?? (view as? NSTextField).map { [$0.stringValue] } ?? []
            return current + view.subviews.flatMap(labels)
        }
        #expect(!labels(room.view).contains("You wrote it down."))
        #expect(labels(room.view).contains("Copy text"))
        #expect(labels(room.view).contains("Run it again"))
    }

    @Test func warnWashTracksSelectedSilenceLimit() {
        for limit in SilenceLimit.allCases {
            let warnAt = Double(limit.rawValue - 3)
            #expect(RoomPresentation.washOpacity(idle: warnAt - 0.1, reducesMotion: false, limit: limit) == 0)
            #expect(RoomPresentation.washOpacity(idle: warnAt, reducesMotion: false, limit: limit) == 0)
            #expect(RoomPresentation.washOpacity(idle: warnAt + 1.5, reducesMotion: false, limit: limit) == 0.5)
            #expect(RoomPresentation.washOpacity(idle: Double(limit.rawValue), reducesMotion: false, limit: limit) == 1)
            #expect(RoomPresentation.washOpacity(idle: warnAt, reducesMotion: true, limit: limit) == 1)
        }
    }
}
