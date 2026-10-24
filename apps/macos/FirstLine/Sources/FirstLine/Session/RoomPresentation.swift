/*
 * [INPUT]: Deadline and idle values from SessionEngine, plus whether the next session may restart.
 * [OUTPUT]: Room clock, unused-time deletion sentence with restart/activation copy, word count, kept receipt, chosen-limit wash strength, copy, exit-confirmation timing, and deny state.
 * [POS]: Stateless presentation rules shared by the AppKit room and its tests; the visible sentences match writeitdown/room.js.
 * [PROTOCOL]: Keep the strings and wash timing aligned with writeitdown/room.js and the consistency table; check nearest AGENTS.md.
 */
import AppKit

enum RoomPresentation {
    /// The active line's anchor from the paper top. The live web trial uses 39%;
    /// the Mac uses 35% so the active line sits a little higher, in the comfortable
    /// ergonomic gaze band (D-025).
    static let writingAnchorFraction: CGFloat = 0.35

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

    /// Count rule shared by the room count and the kept receipt.
    static let countRule = "Counts words. Each Chinese character counts as one. Punctuation and emoji do not count."

    /// `N WORDS WRITTEN DOWN IN M MINUTES.` The kept receipt names the real session
    /// duration instead of a meaningless 0:00.
    static func keptReceipt(wordCount: Int, duration: TimeInterval) -> String {
        let minutes = max(Int((duration / 60).rounded()), 1)
        let unit = minutes == 1 ? "MINUTE" : "MINUTES"
        return "\(wordCountLabel(wordCount)) WRITTEN DOWN IN \(minutes) \(unit)."
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

    /// Every blocked key restarts the short feedback, so the animation is
    /// interruptible instead of dropping repeats while the previous one runs.
    mutating func begin(reducesMotion: Bool) -> Bool {
        _ = reducesMotion
        outlineVisible = true
        return true
    }

    mutating func end() {
        outlineVisible = false
    }
}
