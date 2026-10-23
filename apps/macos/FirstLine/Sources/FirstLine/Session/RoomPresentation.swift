/*
 * [INPUT]: Deadline and idle values from SessionEngine, plus whether the next session may restart.
 * [OUTPUT]: Room clock, elapsed deletion report with restart/activation copy, receipt, chosen-limit wash strength, copy, and deny state.
 * [POS]: Stateless presentation rules shared by the AppKit room and its tests.
 * [PROTOCOL]: Keep wash timing aligned with writeitdown/room.js; native wipe and receipt copy live here and are not required to match the website.
 */
import AppKit

enum RoomPresentation {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func wipeReport(elapsed: Int, canRestart: Bool) -> String {
        "Draft deleted at \(clock(elapsed)). \(canRestart ? "Type to start again." : "Activate to keep writing.")"
    }

    static func wordLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }

    static func sessionTag(duration: TimeInterval, phase: SessionPhase) -> String {
        let minutes = max(1, Int(duration / 60))
        let length = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return phase == .success ? "\(length), done" : "\(length), forward only"
    }

    static func washOpacity(idle: TimeInterval, reducesMotion: Bool, limit: SilenceLimit) -> CGFloat {
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
