/*
 * [INPUT]: Deadline and idle values from SessionEngine, plus whether the next session may restart.
 * [OUTPUT]: Room clock, unused-time deletion sentence with restart/activation copy, word count, kept receipt, chosen-limit wash strength, copy, exit-confirmation timing, and deny state.
 * [POS]: Stateless presentation rules shared by the AppKit room and its tests; the visible sentences match writeitdown/room.js.
 * [PROTOCOL]: Keep the strings and wash timing aligned with writeitdown/room.js and the consistency table; check nearest AGENTS.md.
 */
import AppKit

enum RoomPresentation {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// `DRAFT DELETED AT 0:52. TYPE TO START AGAIN.` uses the session's unused seconds, like the web.
    static func wipeReport(unused: Int, canRestart: Bool) -> String {
        "DRAFT DELETED AT \(clock(unused)). \(canRestart ? "TYPE TO START AGAIN." : "ACTIVATE TO KEEP WRITING.")"
    }

    static func wordLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }

    static func wordCountLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "WORD" : "WORDS")"
    }

    /// `0:00 - N WORDS KEPT.` The wall-clock receipt on the kept sheet; the web hardcodes 0:00.
    static func keptReceipt(wordCount: Int) -> String {
        "0:00 - \(wordCountLabel(wordCount)) KEPT."
    }

    static func washOpacity(idle: TimeInterval, reducesMotion: Bool, limit: SilenceLimit) -> CGFloat {
        let warnAt = Double(limit.rawValue - 3)
        guard idle >= warnAt else { return 0 }
        if reducesMotion { return 1 }
        return CGFloat(min(max((idle - warnAt) / 3, 0), 1))
    }

    /// Escape is ignored while an IME composition owns the key.
    static func handlesEscape(isComposing: Bool) -> Bool { !isComposing }

    static func copy(_ text: String, to board: NSPasteboard) -> Bool {
        board.clearContents()
        return board.setString(text, forType: .string)
    }
}

/// Two-step, time-bounded room exit. The first request arms the inline confirmation;
/// a second request inside the window leaves. Typing dismisses the armed state.
struct ExitConfirmation: Equatable {
    static let defaultWindow: TimeInterval = 2

    let window: TimeInterval
    private(set) var armedAt: TimeInterval?

    init(window: TimeInterval = defaultWindow) {
        self.window = window
    }

    mutating func request(now: TimeInterval) -> Bool {
        if let armedAt, now - armedAt <= window {
            self.armedAt = nil
            return true
        }
        armedAt = now
        return false
    }

    mutating func dismiss() {
        armedAt = nil
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
