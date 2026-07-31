import Testing
@testable import FirstLine

@MainActor
struct SessionEngineTests {
    @Test
    func dangerAndFailureTransitions() {
        var uptime = 100.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 30)
        engine.registerCommittedText("hello draft")
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
    func defaultDurationIsSixtySeconds() {
        let engine = SessionEngine()
        #expect(engine.duration == SessionEngine.defaultDurationSeconds)
        #expect(engine.duration == 60)
        #expect(engine.remaining == 60)
    }

    @Test
    func namedThresholdConstantsDrivePhaseMachine() {
        #expect(SessionEngine.dangerAfterSeconds == 5)
        #expect(SessionEngine.wipeAfterSeconds == 8)
        #expect(SessionEngine.defaultDurationSeconds == 60)
    }

    @Test
    func idleSecondsAndSecondsUntilDeletionTrackSilence() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("hello")
        #expect(engine.idleSeconds == 0)
        #expect(engine.secondsUntilDeletion == 8)

        uptime = 3.0
        engine.tick()
        #expect(engine.phase == .writing)
        #expect(engine.idleSeconds == 3)
        #expect(engine.secondsUntilDeletion == 5)

        uptime = 5.0
        engine.tick()
        #expect(engine.phase == .danger)
        #expect(engine.idleSeconds == 5)
        #expect(engine.secondsUntilDeletion == 3)

        uptime = 6.4
        engine.tick()
        #expect(engine.secondsUntilDeletion == 2)

        uptime = 7.2
        engine.tick()
        #expect(engine.secondsUntilDeletion == 1)
    }

    @Test
    func wipedTextCapturesDraftBeforeFailureClearsIt() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("the draft that hesitated")
        #expect(engine.wipedText.isEmpty)

        uptime = 8.0
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.text.isEmpty)
        #expect(engine.wipedText == "the draft that hesitated")

        engine.start(duration: 60)
        #expect(engine.wipedText.isEmpty)
    }

    @Test
    func registerDenyRecordsDenialTimestamp() {
        var uptime = 20.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        #expect(engine.lastDenyAt == nil)

        engine.registerDeny()
        #expect(engine.lastDenyAt == 20.0)

        uptime = 21.5
        engine.registerDeny()
        #expect(engine.lastDenyAt == 21.5)

        engine.start(duration: 60)
        #expect(engine.lastDenyAt == nil)
    }

    @Test
    func finishEndsLiveSessionIntoSuccess() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("kept moving")
        engine.finish()
        #expect(engine.phase == .success)
        #expect(engine.text == "kept moving")
        #expect(engine.remaining == 0)
    }

    @Test
    func committedTextResetsDanger() {
        var uptime = 50.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 30)
        engine.registerCommittedText("start")
        uptime = 55.0
        engine.tick()
        #expect(engine.phase == .danger)

        engine.registerCommittedText("你")
        #expect(engine.phase == .writing)
        #expect(engine.text == "start你")
    }

    @Test
    func markedTextActivityResetsDanger() {
        var uptime = 10.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 30)
        engine.registerCommittedText("start")
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
    @Test
    func emptyDraftNeverEntersDangerOrFailure() {
        var uptime = 100.0
        let engine = SessionEngine(now: { uptime })
        engine.start(duration: SessionEngine.defaultDurationSeconds)
        uptime = 109.0
        engine.tick()
        #expect(engine.phase == .writing)
        uptime = 114.0
        engine.tick()
        #expect(engine.phase == .writing)
        #expect(engine.wipedText.isEmpty)
    }

}
