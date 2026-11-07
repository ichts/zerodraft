/**
 * [INPUT]: The draft text (UTF-16 offsets, the editor's own coordinates)
 * [OUTPUT]: HistoryLines.lines(in:) - the draft cut into logical lines, each with its range and its ladder rung
 * [POS]: Pure rule for the history fade (D-088, superseding D-077's sentence unit): the ladder's unit is the line the writer
 *        ended with Return, the text up to a hard break, never a sentence and never the visual row, so every row of one
 *        wrapped line shares one opacity. The web room (`historyLines` in writeitdown/session.mjs) and the Windows room
 *        (`session/lines.go`) cut the same lines; the three surfaces must not drift.
 * [PROTOCOL]: Keep the rule identical to session.mjs and lines.go; update this header, then check AGENTS.md
 */

import Foundation

enum HistoryLines {
    /// Rung 0 is the live line, 1 and 2 are the ladder's two readable steps, `gone` is everything older.
    static let gone = 3

    struct Line: Equatable {
        let range: NSRange
        let rung: Int
    }

    /// The text cut into lines. A hard break is LF, CRLF or a lone CR and belongs to the line it ends. A trailing LF
    /// means the writer is already on a fresh, empty line, so every written line sits one rung further back.
    static func lines(in text: String) -> [Line] {
        let source = text as NSString
        var ranges: [NSRange] = []
        var start = 0
        var index = 0
        while index < source.length {
            let unit = source.character(at: index)
            let isCR = unit == 0x0D
            let crlf = isCR && index + 1 < source.length && source.character(at: index + 1) == 0x0A
            index += 1
            guard unit == 0x0A || (isCR && !crlf) else { continue }
            ranges.append(NSRange(location: start, length: index - start))
            start = index
        }
        if start < source.length { ranges.append(NSRange(location: start, length: source.length - start)) }
        let live = ranges.count - 1 + (text.hasSuffix("\n") ? 1 : 0)
        return ranges.enumerated().map { Line(range: $1, rung: min(live - $0, gone)) }
    }
}
