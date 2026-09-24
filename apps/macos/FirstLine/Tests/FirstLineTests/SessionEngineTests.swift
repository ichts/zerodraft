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
    func uncommittedCompositionWarnsAndWipesOnSilence() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })
        engine.start(duration: 60)
        engine.registerMarkedTextActivity()
        #expect(engine.text.isEmpty)
        uptime = 5
        engine.tick()
        #expect(engine.phase == .danger)
        #expect(engine.secondsUntilDeletion == 3)
        uptime = 8
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.unusedSeconds == 52)
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

        engine.start(duration: 60)
        engine.registerCommittedText("hello")
        for second in stride(from: 6.0, through: 54.0, by: 6.0) {
            uptime = second
            engine.registerMarkedTextActivity()
        }
        uptime = 60.0
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

        engine.start(duration: 60)
        engine.registerCommittedText("draft")
        // Both deadlines have passed; wipe (8) was first.
        uptime = 100.0
        engine.tick()

        #expect(engine.phase == .failure)
        #expect(engine.wipedText == "draft")
    }

    @Test
    func bothDeadlinesPassedWithCompletionEarlierResolvesToSuccess() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("draft")
        for second in stride(from: 6.0, through: 54.0, by: 6.0) {
            uptime = second
            engine.registerMarkedTextActivity()
        }
        uptime = 56
        engine.registerCommittedText(" more")
        // Completion at 60 precedes wipe at 64, even though tick arrives late.
        uptime = 100.0
        engine.tick()

        #expect(engine.phase == .success)
        #expect(engine.wipedText.isEmpty)
    }

    @Test
    func exactDeadlineTieResolvesToFailure() {
        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })

        engine.start(duration: 60)
        engine.registerCommittedText("draft")
        for second in stride(from: 6.0, through: 48.0, by: 6.0) {
            uptime = second
            engine.registerMarkedTextActivity()
        }
        uptime = 52
        engine.registerMarkedTextActivity()
        // Completion and wipe both land at 60.
        uptime = 60.0
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

        engine.start(duration: 60)
        // No text is ever typed, so there is no deadline.
        uptime = 65.0
        engine.tick()

        #expect(engine.phase == .writing)
        #expect(engine.text.isEmpty)
        #expect(engine.wipedText.isEmpty)
    }

    @Test func clockStartsOnFirstInputNotOnStart() {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 60)
        time = 30
        engine.tick()
        #expect(engine.remaining == 60)
        engine.registerCommittedText("go")
        time = 31
        engine.tick()
        #expect(engine.remaining == 59)
    }

    @Test func markedTextStartsTheClock() {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 60)
        time = 20
        engine.registerMarkedTextActivity()
        time = 21
        engine.registerCommittedText("你")
        #expect(engine.remaining == 59)
    }

    @Test func whitespaceOnlyDraftAtDeadlineWipes() {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 60)
        engine.registerCommittedText(" \n ")
        time = 54
        engine.registerMarkedTextActivity()
        time = 60
        engine.tick()
        #expect(engine.phase == .failure)
    }

    @Test func wipeReportsUnusedSeconds() {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 60)
        engine.registerCommittedText("draft")
        time = 100
        engine.tick()
        #expect(engine.unusedSeconds == 52)
        engine.start(duration: 60)
        engine.registerCommittedText("new")
        #expect(engine.unusedSeconds == nil)
        #expect(engine.remaining == 60)
        engine.start(duration: 60)
        engine.registerCommittedText("tie")
        for second in stride(from: 106.0, through: 148.0, by: 6.0) {
            time = second
            engine.registerMarkedTextActivity()
        }
        time = 152
        engine.registerMarkedTextActivity()
        time = 160
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.unusedSeconds == 0)
        engine.start(duration: 180)
        engine.registerCommittedText("long")
        time = 168
        engine.tick()
        #expect(engine.unusedSeconds == 172)
    }

    @Test func keystrokeAfterWipeStartsFreshSessionWithSameDuration() {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 180)
        engine.registerCommittedText("lost")
        let oldID = engine.sessionID
        time = 8
        engine.tick()
        engine.start(duration: 180)
        engine.registerCommittedText("again")
        #expect(engine.phase == .writing)
        #expect(engine.text == "again")
        #expect(engine.duration == 180)
        #expect(engine.sessionID != oldID)
        #expect(engine.unusedSeconds == nil)
    }

    @Test func wordCountMatchesWebCases() {
        let cases: [(String, Int)] = [
            ("  two\nwords ", 2), ("", 0), (" \n\t", 0), ("中文测试", 4),
            ("hello world 中文测试", 6), ("你好，world！", 3),
            ("café cafe\u{0301}", 2), ("مرحبا بالعالم", 2),
            ("こんにちは世界", 3), ("これはテストです。明日も書きます。", 10),
            ("👨‍👩‍👧‍👦 👍🏽 🇨🇳", 0),
            ("...，！？", 0), ("𠀀中文", 3), ("你好👩🏽‍💻world", 3)
        ]
        let engine = SessionEngine()
        for (text, count) in cases {
            engine.start(duration: 60)
            engine.registerCommittedText(text)
            #expect(engine.wordCount == count, "\(text)")
        }
    }

    @Test func wordCountTracksDraftAcrossActivityAndResets() {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 60)
        #expect(engine.wordCount == 0)
        engine.registerCommittedText("hello")
        #expect(engine.wordCount == 1)
        time = 4
        engine.registerMarkedTextActivity()
        engine.tick()
        #expect(engine.wordCount == 1)
        engine.registerCommittedText(" 中文")
        #expect(engine.wordCount == 3)
        time = 12
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.wordCount == 0)
        engine.start(duration: 60)
        #expect(engine.wordCount == 0)
        engine.registerCommittedText("new draft")
        #expect(engine.wordCount == 2)
        engine.abandon()
        #expect(engine.wordCount == 0)
    }

    @Test func fiveAndEightSecondRulesHoldForSixtyMinuteSession() {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 3600)
        engine.registerCommittedText("go")
        time = 5
        engine.tick()
        #expect(engine.phase == .danger)
        time = 8
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.unusedSeconds == 3592)
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
