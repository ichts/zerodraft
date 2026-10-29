/**
 * [INPUT]: The draft text (UTF-16 offsets, the editor's own coordinates)
 * [OUTPUT]: HistoryLines.lines(in:) - the draft cut into logical lines, each with its range and its ladder rung
 * [POS]: Pure rule for the history fade (D-077): the ladder's unit is the logical line, a sentence or the text up to a hard
 *        line break, never the visual row, so every row of one sentence shares one opacity. The web room cuts the same lines
 *        with Intl.Segmenter (`historyLines` in writeitdown/session.mjs); the two surfaces must not drift.
 * [PROTOCOL]: Keep the rule identical to session.mjs; update this header, then check AGENTS.md
 */

import Foundation

enum HistoryLines {
    /// Rung 0 is the live line, 1 and 2 are the ladder's two readable steps, `gone` is everything older.
    static let gone = 3

    struct Line: Equatable {
        let range: NSRange
        let rung: Int
    }

    /// The text cut into logical lines. A trailing hard break means the writer is already on a fresh, empty line,
    /// so every written line sits one rung further back.
    static func lines(in text: String) -> [Line] {
        let source = text as NSString
        var ranges: [NSRange] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length),
                                   options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        let live = ranges.count - 1 + (text.hasSuffix("\n") ? 1 : 0)
        return ranges.enumerated().map { Line(range: $1, rung: min(live - $0, gone)) }
    }
}
