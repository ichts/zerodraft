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

    @Test func wipeReportTextMatchesWeb() {
        #expect(RoomPresentation.wipeReport(unused: 45) == "DRAFT WIPED - 0:45 UNUSED. TYPE TO RESTART.")
    }

    @Test func keptReceiptTextMatchesWeb() {
        #expect(RoomPresentation.keptReceipt(words: 12) == "0:00 - 12 WORDS KEPT.")
        #expect(RoomPresentation.keptReceipt(words: 1) == "0:00 - 1 WORD KEPT.")
        #expect(RoomPresentation.wordLabel(1) == "1 WORD")
        #expect(RoomPresentation.wordLabel(0) == "0 WORDS")
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
        let state = AppState(sessionEngine: engine, settingsStore: SettingsStore(configDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        state.startSession()
        engine.registerCommittedText("private draft")
        #expect(RoomPresentation.shouldExitOnEscape(isComposing: false))
        state.abandonSession()
        #expect(state.selectedSurface == .home)
        #expect(engine.text.isEmpty)
        now += 1
    }

    @Test func homeRestoresStartButtonFocusWithoutStartingSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root))
        state.startSession()
        state.abandonSession()
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = home
        home.viewDidAppear()
        let button = try #require(window.firstResponder as? NSButton)
        #expect(button.title == "1")
        #expect(button.accessibilityLabel() == "Start 1 minute session")
        #expect(state.selectedSurface == .home)
        #expect(state.sessionEngine.phase == .idle)
    }

    @Test func keptViewHasReceiptAndActionsWithoutPromotionalHeading() {
        let state = AppState()
        state.startSession()
        let room = SessionViewController(appState: state)
        func labels(_ view: NSView) -> [String] {
            let current = (view as? NSButton).map { [$0.title] } ?? (view as? NSTextField).map { [$0.stringValue] } ?? []
            return current + view.subviews.flatMap(labels)
        }
        #expect(!labels(room.view).contains("You wrote it down."))
        #expect(labels(room.view).contains("COPY TEXT"))
        #expect(labels(room.view).contains("RUN IT AGAIN"))
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
