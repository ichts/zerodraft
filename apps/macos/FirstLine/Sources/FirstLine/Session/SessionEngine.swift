/**
 * [INPUT]: 依赖单调时间源和编辑器活动事件
 * [OUTPUT]: 提供 SessionEngine 与 SessionPhase 状态机，暴露 idleSeconds / secondsUntilDeletion / wipedText / lastDenyAt
 * [POS]: FirstLine 核心会话循环，负责 danger / failure / success；集中式截止时间裁决在 tick / registerCommittedText / registerMarkedTextActivity / finish 入口先于活动应用
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

enum SessionPhase: Equatable {
    case idle
    case writing
    case danger
    case failure
    case success
}

@Observable
@MainActor
final class SessionEngine {
    nonisolated static let dangerAfterSeconds: TimeInterval = 5
    nonisolated static let wipeAfterSeconds: TimeInterval = 8
    nonisolated static let defaultDurationSeconds: TimeInterval = 60

    private let now: () -> TimeInterval

    /// Suspend-inclusive monotonic reference. On Darwin, ContinuousClock is
    /// backed by mach_continuous_time and advances during system sleep (unlike
    /// ProcessInfo.systemUptime / mach_absolute_time), so a draft left through
    /// a Mac sleep is adjudicated against the real silence deadline.
    nonisolated private static let clockReference: ContinuousClock.Instant = ContinuousClock().now

    /// Suspend-inclusive monotonic seconds since clockReference. Exposed for
    /// tests that verify monotonicity without real system sleep.
    nonisolated static func continuousNowSeconds() -> TimeInterval {
        let elapsed = clockReference.duration(to: ContinuousClock().now)
        let c = elapsed.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1_000_000_000_000_000_000
    }

    var phase: SessionPhase = .idle
    var text = ""
    var duration: TimeInterval = SessionEngine.defaultDurationSeconds
    var elapsed: TimeInterval = 0
    var remaining: TimeInterval = SessionEngine.defaultDurationSeconds
    /// Silence so far, computed in tick from lastActivityAt.
    private(set) var idleSeconds: TimeInterval = 0
    /// Text captured immediately before a failure wiped it; empty otherwise.
    private(set) var wipedText = ""
    /// Last time a blocked edit (delete/paste/undo/selection replace) was denied.
    private(set) var lastDenyAt: TimeInterval?
    private(set) var sessionID = UUID()
    var onStateChange: ((SessionPhase) -> Void)?

    /// Countdown of seconds left before the draft is deleted (3-2-1 in danger).
    var secondsUntilDeletion: Int {
        max(0, Int(ceil(SessionEngine.wipeAfterSeconds - idleSeconds)))
    }

    private var startedAt: TimeInterval?
    private var lastActivityAt: TimeInterval?

    init(now: @escaping () -> TimeInterval = { SessionEngine.continuousNowSeconds() }) {
        self.now = now
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var hasMultipleLines: Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).count > 1
    }

    func start(duration: TimeInterval) {
        let current = now()
        self.duration = duration
        sessionID = UUID()
        elapsed = 0
        remaining = duration
        idleSeconds = 0
        wipedText = ""
        lastDenyAt = nil
        phase = .writing
        text = ""
        startedAt = current
        lastActivityAt = current
        emitStateChange()
    }

    func tick() {
        // Central adjudication runs first: a deadline that already passed (during a
        // main-thread stall, sleep/wake, or a delayed tick) wins over the progress update.
        if adjudicateDeadlines() { return }
        guard let startedAt, let lastActivityAt else { return }
        guard phase == .writing || phase == .danger else { return }

        let current = now()
        elapsed = min(max(current - startedAt, 0), duration)
        remaining = max(duration - elapsed, 0)
        idleSeconds = max(current - lastActivityAt, 0)
        // An empty draft has nothing to lose: silence danger and deletion only
        // arm once there is text, so an untouched session never dies (or burns a trial).
        guard text.isEmpty == false else { return }

        phase = idleSeconds >= SessionEngine.dangerAfterSeconds ? .danger : .writing
        emitStateChange()
    }

    func registerCommittedText(_ inserted: String) {
        guard phase == .writing || phase == .danger else { return }
        // Adjudicate against now BEFORE applying the new activity: a late keystroke
        // whose 8s wipe deadline already passed must not resurrect the draft.
        if adjudicateDeadlines() { return }
        guard inserted.isEmpty == false else { return }
        text += inserted
        lastActivityAt = now()
        idleSeconds = 0
        phase = .writing
        tick()
    }

    func registerMarkedTextActivity() {
        guard phase == .writing || phase == .danger else { return }
        if adjudicateDeadlines() { return }
        lastActivityAt = now()
        idleSeconds = 0
        phase = .writing
        tick()
    }

    /// Central deadline adjudication. Called at the start of every entry point,
    /// BEFORE the new activity is applied. Computes absolute deadlines from the
    /// monotonic clock: wipeDeadline = lastActivityAt + 8s, completionDeadline =
    /// startedAt + duration. If a deadline has already passed, the engine
    /// transitions to the phase whose deadline occurred first; an exact tie goes
    /// to failure. The empty-text exemption holds: the wipe never fires while the
    /// draft is empty. Returns true when a terminal transition occurred.
    @discardableResult
    private func adjudicateDeadlines() -> Bool {
        guard let startedAt, let lastActivityAt else { return false }
        guard phase == .writing || phase == .danger else { return false }

        let current = now()
        let completionDeadline = startedAt + duration
        let wipeDeadline = lastActivityAt + SessionEngine.wipeAfterSeconds
        let textIsEmpty = text.isEmpty

        let completionPassed = current >= completionDeadline
        let wipePassed = textIsEmpty == false && current >= wipeDeadline

        if completionPassed && wipePassed {
            // The deadline that occurred first wins; a tie goes to failure (the gun is faster).
            if wipeDeadline <= completionDeadline {
                wipeOut()
            } else {
                completeSuccessfully()
            }
            return true
        } else if wipePassed {
            wipeOut()
            return true
        } else if completionPassed {
            // An empty draft reaches its deadline having produced nothing: it does
            // not "succeed" and saves nothing. End the session as abandoned (idle).
            if textIsEmpty {
                reset(clearText: true)
            } else {
                completeSuccessfully()
            }
            return true
        }
        return false
    }

    private func wipeOut() {
        wipedText = text
        phase = .failure
        text = ""
        emitStateChange()
    }

    private func completeSuccessfully() {
        elapsed = duration
        remaining = 0
        phase = .success
        emitStateChange()
    }

    /// Called by the editor bridge when a blocked edit (delete, paste, cut, undo,
    /// selection replacement) is denied. Only records the timestamp.
    func registerDeny() {
        lastDenyAt = now()
    }

    /// Ends the session into success with the current text, same as natural completion.
    /// Adjudicates first: if the 8s wipe deadline already passed, finish cannot
    /// rescue the draft into success. An empty draft never succeeds: finish routes
    /// it to idle (consistent with the completion-deadline empty-text exemption).
    func finish() {
        guard phase == .writing || phase == .danger else { return }
        guard startedAt != nil else { return }
        if adjudicateDeadlines() { return }
        // 空草稿永不 success：与 completion-deadline 空文本豁免一致，走 idle。
        if text.isEmpty {
            reset(clearText: true)
            return
        }
        completeSuccessfully()
    }

    func abandon() {
        reset(clearText: true)
    }

    private func emitStateChange() {
        onStateChange?(phase)
    }

    private func reset(clearText: Bool) {
        phase = .idle
        elapsed = 0
        remaining = duration
        idleSeconds = 0
        wipedText = ""
        lastDenyAt = nil
        if clearText {
            text = ""
        }
        startedAt = nil
        lastActivityAt = nil
        emitStateChange()
    }
}
