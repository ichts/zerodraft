import Testing
@testable import FirstLine

@MainActor
struct SessionEngineTests {
    @Test
    func dangerAndFailureTransitions() {
        var uptime = 100.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 30)
        #expect(engine.phase == .writing)

        uptime = 104.9
        engine.tick()
        #expect(engine.phase == .writing)

        uptime = 105.0
        engine.tick()
        #expect(engine.phase == .danger)

        uptime = 108.0
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.text.isEmpty)
    }

    @Test
    func committedTextResetsDanger() {
        var uptime = 50.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 30)
        uptime = 55.0
        engine.tick()
        #expect(engine.phase == .danger)

        engine.registerCommittedText("你")
        #expect(engine.phase == .writing)
        #expect(engine.text == "你")
    }

    @Test
    func markedTextActivityResetsDanger() {
        var uptime = 10.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 30)
        uptime = 15.0
        engine.tick()
        #expect(engine.phase == .danger)

        uptime = 15.1
        engine.registerMarkedTextActivity()
        #expect(engine.phase == .writing)
    }

    @Test
    func sessionSucceedsWhenDurationCompletes() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 5)
        engine.registerCommittedText("hello")

        uptime = 5.0
        engine.tick()
        #expect(engine.phase == .success)
        #expect(engine.wordCount == 1)
    }

    @Test
    func sessionStartCreatesNewSessionIdentityAndClearsText() {
        let engine = SessionEngine()

        engine.start(duration: 30)
        let firstSessionID = engine.sessionID
        engine.registerCommittedText("old text")
        #expect(engine.text == "old text")

        engine.start(duration: 30)
        #expect(engine.sessionID != firstSessionID)
        #expect(engine.text.isEmpty)
    }
}
