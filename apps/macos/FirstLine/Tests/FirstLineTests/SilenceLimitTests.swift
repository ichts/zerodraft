import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct SilenceLimitTests {
    @Test func offersExactlyThreeFixedChoicesWithStandardDefault() {
        #expect(SilenceLimit.allCases.map(\.rawValue) == [5, 8, 12])
        #expect(AppSettings.defaultValue.silenceLimit == .standard)
    }

    private func verify(_ limit: SilenceLimit) {
        var time = 0.0
        let engine = SessionEngine(now: { time })
        engine.start(duration: 60, silenceLimit: limit)
        engine.registerCommittedText("draft")
        time = Double(limit.rawValue - 3) - 0.01
        engine.tick()
        #expect(engine.phase == .writing)
        time = Double(limit.rawValue - 3)
        engine.tick()
        #expect(engine.phase == .danger)
        #expect(engine.secondsUntilDeletion == 3)
        time = Double(limit.rawValue)
        engine.tick()
        #expect(engine.phase == .failure)
    }

    @Test func strictWarnsAtTwoAndWipesAtFive() { verify(.strict) }
    @Test func standardWarnsAtFiveAndWipesAtEight() { verify(.standard) }
    @Test func relaxedWarnsAtNineAndWipesAtTwelve() { verify(.relaxed) }

    @Test func typingCancelsWarningForEveryLimit() {
        for limit in SilenceLimit.allCases {
            var time = 0.0
            let engine = SessionEngine(now: { time })
            engine.start(duration: 60, silenceLimit: limit)
            engine.registerCommittedText("first")
            time = Double(limit.rawValue - 3)
            engine.tick()
            #expect(engine.phase == .danger)
            engine.registerCommittedText(" second")
            #expect(engine.phase == .writing)
            #expect(engine.secondsUntilDeletion == limit.rawValue)
        }
    }

    @Test func deadlineTieStillWipesForEveryLimit() {
        for limit in SilenceLimit.allCases {
            var time = 0.0
            let engine = SessionEngine(now: { time })
            engine.start(duration: 60, silenceLimit: limit)
            time = 60 - Double(limit.rawValue)
            engine.registerCommittedText("draft")
            time = 60
            engine.tick()
            #expect(engine.phase == .failure)
        }
    }
}
