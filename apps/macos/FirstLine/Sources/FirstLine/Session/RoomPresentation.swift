/*
 * [INPUT]: Site room copy and deadline/idle values from SessionEngine.
 * [OUTPUT]: Room clock, report, receipt, chosen-limit wash strength, copy, and deny state.
 * [POS]: Stateless presentation rules shared by the AppKit room and its tests.
 * [PROTOCOL]: Keep strings and wash timing aligned with writeitdown/room.js.
 */
import AppKit

enum RoomPresentation {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func wipeReport(unused: Int) -> String {
        "DRAFT WIPED - \(clock(unused)) UNUSED. TYPE TO RESTART."
    }

    static func wordLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "WORD" : "WORDS")"
    }

    static func keptReceipt(words: Int) -> String {
        "0:00 - \(wordLabel(words)) KEPT."
    }

    static func washOpacity(idle: TimeInterval, reducesMotion: Bool, limit: SilenceLimit = .standard) -> CGFloat {
        let warnAt = Double(limit.rawValue - 3)
        guard idle >= warnAt else { return 0 }
        if reducesMotion { return 1 }
        return CGFloat(min(max((idle - warnAt) / 3, 0), 1))
    }

    static func shouldExitOnEscape(isComposing: Bool) -> Bool { !isComposing }

    static func copy(_ text: String, to board: NSPasteboard) -> Bool {
        board.clearContents()
        return board.setString(text, forType: .string)
    }
}

struct DenyFeedbackState {
    private(set) var outlineVisible = false
    private(set) var shakeOffset: CGFloat = 0

    mutating func begin(reducesMotion: Bool) -> Bool {
        guard !outlineVisible else { return false }
        outlineVisible = true
        shakeOffset = reducesMotion ? 0 : -2
        return true
    }

    mutating func end() {
        outlineVisible = false
        shakeOffset = 0
    }
}
