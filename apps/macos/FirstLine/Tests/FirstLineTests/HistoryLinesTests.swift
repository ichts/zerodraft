import Foundation
import Testing
@testable import WriteItDown

/// The line rule of D-088, with the same cases as `writeitdown/session.test.mjs` and `apps/windows/session/lines_test.go`
/// so the three surfaces cannot drift.
struct HistoryLinesTests {
    private func rungs(_ text: String) -> [Int] { HistoryLines.lines(in: text).map(\.rung) }

    @Test func theLadderCountsLinesEndedByReturnNeverSentences() {
        let text = "First is long. Second is long.\nThird is long. Fourth is long.\nLive. Still live"
        let lines = HistoryLines.lines(in: text)
        let source = text as NSString
        #expect(lines.map { source.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }
                == ["First is long. Second is long.", "Third is long. Fourth is long.", "Live. Still live"])
        #expect(lines.map(\.rung) == [2, 1, 0])
        #expect(rungs("One. Two. Three.") == [0], "a full stop never ends a line")
        #expect(rungs("only one") == [0])
        #expect(rungs("").isEmpty)
    }

    @Test func aHardBreakPutsTheWriterOnAFreshLiveLine() {
        #expect(rungs("one\ntwo\n") == [2, 1])
        #expect(rungs("one\ntwo") == [1, 0])
        #expect(rungs("a\n\nb") == [2, 1, 0], "a blank line is a line")
        #expect(rungs("a\r\nb\rc") == [2, 1, 0], "CRLF is one break")
    }

    @Test func cjkStopsDoNotSplitALineAndTheRangesCoverTheText() {
        #expect(rungs("今天下雨。我在写字。") == [0])
        #expect(rungs("今天下雨。\n我在写字。") == [1, 0])
        let lines = HistoryLines.lines(in: "a. b.\nc")
        #expect(lines.first?.range.location == 0)
        #expect(lines.last.map { NSMaxRange($0.range) } == 7)
    }
}
