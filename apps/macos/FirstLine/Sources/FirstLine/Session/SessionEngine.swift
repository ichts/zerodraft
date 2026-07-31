/**
 * [INPUT]: 依赖单调时间源和编辑器活动事件
 * [OUTPUT]: 提供 SessionEngine 与 SessionPhase 状态机，暴露 idleSeconds / secondsUntilDeletion / wipedText / lastDenyAt
 * [POS]: FirstLine 核心会话循环，负责 danger / failure / success
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

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
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
        guard let startedAt, let lastActivityAt else { return }
        guard phase == .writing || phase == .danger else { return }

        let current = now()
        elapsed = min(max(current - startedAt, 0), duration)
        remaining = max(duration - elapsed, 0)

        if elapsed >= duration {
            phase = .success
            emitStateChange()
            return
        }

        let idle = current - lastActivityAt
        idleSeconds = max(idle, 0)
        // An empty draft has nothing to lose: silence danger and deletion only
        // arm once there is text, so an untouched session never dies (or burns a trial).
        guard text.isEmpty == false else { return }

        if idle >= SessionEngine.wipeAfterSeconds {
            wipedText = text
            phase = .failure
            text = ""
            emitStateChange()
            return
        }

        phase = idle >= SessionEngine.dangerAfterSeconds ? .danger : .writing
        emitStateChange()
    }

    func registerCommittedText(_ inserted: String) {
        guard phase == .writing || phase == .danger else { return }
        guard inserted.isEmpty == false else { return }
        text += inserted
        lastActivityAt = now()
        idleSeconds = 0
        phase = .writing
        tick()
    }

    func registerMarkedTextActivity() {
        guard phase == .writing || phase == .danger else { return }
        lastActivityAt = now()
        idleSeconds = 0
        phase = .writing
        tick()
    }

    /// Called by the editor bridge when a blocked edit (delete, paste, cut, undo,
    /// selection replacement) is denied. Only records the timestamp.
    func registerDeny() {
        lastDenyAt = now()
    }

    /// Ends the session into success with the current text, same as natural completion.
    func finish() {
        guard phase == .writing || phase == .danger else { return }
        guard startedAt != nil else { return }
        elapsed = duration
        remaining = 0
        phase = .success
        emitStateChange()
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
