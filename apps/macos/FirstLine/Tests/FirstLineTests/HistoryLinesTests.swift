import Foundation
import Testing
@testable import WriteItDown

/// The logical-line rule of D-077, with the same cases as `writeitdown/session.test.mjs` so the two surfaces cannot drift.
struct HistoryLinesTests {
    private func rungs(_ text: String) -> [Int] { HistoryLines.lines(in: text).map(\.rung) }

    @Test func everySentenceIsOneLineWithItsRungCountedFromTheEnd() {
        let text = "First is long. Second is long. Third is long. Fourth is long."
        let lines = HistoryLines.lines(in: text)
        let source = text as NSString
        #expect(lines.map { source.substring(with: $0.range).trimmingCharacters(in: .whitespaces) }
                == ["First is long.", "Second is long.", "Third is long.", "Fourth is long."])
        #expect(lines.map(\.rung) == [HistoryLines.gone, 2, 1, 0])
        #expect(rungs("only one") == [0])
        #expect(rungs("").isEmpty)
    }

    @Test func aHardBreakPutsTheWriterOnAFreshLiveLine() {
        #expect(rungs("one\ntwo\n") == [2, 1])
        #expect(rungs("one\ntwo") == [1, 0])
    }

    @Test func cjkStopsSplitSentencesAndTheRangesCoverTheText() {
        #expect(rungs("今天下雨。我在写字。") == [1, 0])
        let lines = HistoryLines.lines(in: "a. b. c")
        #expect(lines.first?.range.location == 0)
        #expect(lines.last.map { NSMaxRange($0.range) } == 7)
    }
}
