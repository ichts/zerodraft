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

    @Test func warnWashOpacityRampsFromFiveToEightSeconds() {
        #expect(RoomPresentation.washOpacity(idle: 4.9, reducesMotion: false) == 0)
        #expect(RoomPresentation.washOpacity(idle: 5, reducesMotion: false) == 0)
        #expect(RoomPresentation.washOpacity(idle: 6.5, reducesMotion: false) == 0.5)
        #expect(RoomPresentation.washOpacity(idle: 8, reducesMotion: false) == 1)
        #expect(RoomPresentation.washOpacity(idle: 5, reducesMotion: true) == 1)
    }
}
