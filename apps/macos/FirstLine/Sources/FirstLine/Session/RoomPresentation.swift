/*
 * [INPUT]: Deadline and idle values from SessionEngine, plus the obstacle to the next session (none, trial spent, or a license needed).
 * [OUTPUT]: The paper's one anchor fraction, room clock, the stopped screen's spoken sentence and pill help (restart or activation), word count, kept receipt, chosen-limit wash strength, copy, exit-confirmation timing, and deny state.
 * [POS]: Stateless presentation rules shared by the AppKit room and its tests; the live room sentences match writeitdown/room.js, the trial-end announcement is the Mac's own (the web trial has no license gate), and the kept receipt is the Mac's own quiet counterpart (D-030).
 * [PROTOCOL]: Keep the live strings and wash timing aligned with writeitdown/room.js and the consistency table; check nearest AGENTS.md.
 */
import AppKit

enum RoomPresentation {
    /// The paper's one anchor, as a fraction of the paper height: the active writing line sits on it,
    /// and the stopped group's midpoint sits on it, so the group replaces the line the writer was on
    /// and the two placements cannot disagree (D-070 supersedes D-025's 35%).
    static let paperAnchorFraction: CGFloat = 0.33

    /// Why the next session cannot start, in the terms the stopped screen may state. One boolean
    /// cannot tell an exhausted trial from licence residue, a trial-access error or a cleanup
    /// failure, so the copy takes the reason instead (D-070).
    enum RestartObstacle {
        case none
        case trialSpent
        case licenseNeeded
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// `You stopped. Draft deleted. 0:52 unused.` The stopped screen prints only its one line and
    /// keeps the clock off the sheet, so the deletion and the unused seconds are announced once,
    /// like the live trial (D-070). A blocked restart names only the reason that is actually true:
    /// the trial budget is spent, or a license is needed for some other reason.
    static func failureAnnouncement(unused: Int, obstacle: RestartObstacle) -> String {
        let deleted = "You stopped. Draft deleted. \(clock(unused)) unused."
        switch obstacle {
        case .none: return deleted
        case .trialSpent:
            return "\(deleted) Three free sessions used. A license is needed to keep writing."
        case .licenseNeeded:
            return "\(deleted) A license is needed to keep writing."
        }
    }

    /// The pill's visible label stays `Begin again`; its help names what Return will actually do.
    static func failurePillHelp(obstacle: RestartObstacle) -> String {
        switch obstacle {
        case .none: return "Return starts a new session."
        case .trialSpent: return "Three free sessions used. Return opens activation to keep writing."
        case .licenseNeeded: return "Return opens activation to keep writing."
        }
    }

    static func wordLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }

    /// Count rule shared by the room count and the kept acknowledgement.
    static let countRule = "Counts words. Each Chinese character counts as one. Punctuation and emoji do not count."

    /// `5 MINUTES. 63 WORDS.` The quiet small-caps counterpart of the counted word labels:
    /// the real session duration, then the count.
    static func keptReceipt(wordCount: Int, duration: TimeInterval) -> String {
        let minutes = max(Int((duration / 60).rounded()), 1)
        let minuteUnit = minutes == 1 ? "MINUTE" : "MINUTES"
        let wordUnit = wordCount == 1 ? "WORD" : "WORDS"
        return "\(minutes) \(minuteUnit). \(wordCount) \(wordUnit)."
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

    var isArmed: Bool { armedAt != nil }
}

struct DenyFeedbackState {
    private(set) var outlineVisible = false

    /// Every blocked key restarts the short feedback, so the animation is
    /// interruptible instead of dropping repeats while the previous one runs.
    mutating func begin() {
        outlineVisible = true
    }

    mutating func end() {
        outlineVisible = false
    }
}
