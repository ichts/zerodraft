import Foundation
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

    // MARK: - 空草稿 finish 永不 success（R4-M1）

    @Test
    func finishOnEmptyDraftGoesIdleNotSuccess() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        // 用户从未输入任何文字，直接 Cmd+Enter 完成。
        engine.finish()

        #expect(engine.phase == .idle)
        #expect(engine.text.isEmpty)
        #expect(engine.wipedText.isEmpty)
        // 剩余时间重置为完整时长，未产生 success。
        #expect(engine.remaining == engine.duration)
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

    // MARK: - Central deadline adjudication (Fix 1)

    @Test
    func lateActivityAfterWipeDeadlineIsRejectedAndPhaseIsFailure() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("the draft")
        // No tick has fired yet, but the 8s wipe deadline already passed.
        uptime = 9.0
        engine.registerCommittedText(" late keystroke")

        #expect(engine.phase == .failure)
        #expect(engine.wipedText == "the draft")
        #expect(engine.text.isEmpty)
    }

    @Test
    func bothDeadlinesPassedWithSilenceEarlierResolvesToFailure() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 10)
        engine.registerCommittedText("draft")
        // wipeDeadline = 8, completionDeadline = 10. At 12 both passed; wipe (8) is first.
        uptime = 12.0
        engine.tick()

        #expect(engine.phase == .failure)
        #expect(engine.wipedText == "draft")
    }

    @Test
    func bothDeadlinesPassedWithCompletionEarlierResolvesToSuccess() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 10)
        engine.registerCommittedText("draft")
        uptime = 6.0
        // Keep the draft alive: lastActivityAt moves to 6, wipeDeadline becomes 14.
        engine.registerCommittedText(" more")
        // completionDeadline = 10, wipeDeadline = 14. At 15 both passed; completion (10) is first.
        uptime = 15.0
        engine.tick()

        #expect(engine.phase == .success)
        #expect(engine.wipedText.isEmpty)
    }

    @Test
    func finishCalledAfterWipeDeadlineResolvesToFailure() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("draft")
        // wipeDeadline (8) passed; Cmd+Enter must not rescue the draft into success.
        uptime = 9.0
        engine.finish()

        #expect(engine.phase == .failure)
        #expect(engine.wipedText == "draft")
    }

    @Test
    func exactDeadlineTieResolvesToFailure() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        // completionDeadline = 0 + 8 = 8, wipeDeadline = 0 + 8 = 8: exact tie.
        engine.start(duration: 8)
        engine.registerCommittedText("draft")
        uptime = 8.0
        engine.tick()

        #expect(engine.phase == .failure)
        #expect(engine.wipedText == "draft")
    }

    @Test
    func markedTextActivityAfterWipeDeadlineIsRejected() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("draft")
        // A late IME event whose wipe deadline already passed must not reset the timer.
        uptime = 9.0
        engine.registerMarkedTextActivity()

        #expect(engine.phase == .failure)
        #expect(engine.wipedText == "draft")
    }

    // MARK: - Empty session never succeeds (Fix 4)

    @Test
    func emptyDraftAtCompletionDoesNotSucceed() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 5)
        // No text is ever typed.
        uptime = 5.0
        engine.tick()

        #expect(engine.phase == .idle)
        #expect(engine.text.isEmpty)
        #expect(engine.wipedText.isEmpty)
    }

    // MARK: - Suspend-inclusive default clock (Fix M-B1)

    @Test
    func continuousClockSecondsIsMonotonic() {
        // 默认时钟源是 ContinuousClock（Darwin 上由 mach_continuous_time 支持），
        // 是 suspend-inclusive 的：系统睡眠期间照常前进（与 ProcessInfo.systemUptime /
        // mach_absolute_time 不同）。此处验证单调性；真睡眠行为需真机 QA。
        let a = SessionEngine.continuousNowSeconds()
        Thread.sleep(forTimeInterval: 0.002)
        let b = SessionEngine.continuousNowSeconds()
        #expect(b > a)
        #expect(a >= 0)
        // 不是墙钟纪元（Unix 时间戳约 17 亿）；从进程本地参照开始。
        #expect(a < 1_000_000)
    }

}
