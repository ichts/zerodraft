/**
 * [INPUT]: 依赖单调时间源和编辑器活动事件
 * [OUTPUT]: 提供 SessionEngine 与 SessionPhase 状态机
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
    private let now: () -> TimeInterval

    var phase: SessionPhase = .idle
    var text = ""
    var duration: TimeInterval = 300
    var elapsed: TimeInterval = 0
    var remaining: TimeInterval = 300
    private(set) var sessionID = UUID()
    var onStateChange: ((SessionPhase) -> Void)?

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
        if idle >= 8 {
            phase = .failure
            text = ""
            emitStateChange()
            return
        }

        phase = idle >= 5 ? .danger : .writing
        emitStateChange()
    }

    func registerCommittedText(_ inserted: String) {
        guard phase == .writing || phase == .danger else { return }
        guard inserted.isEmpty == false else { return }
        text += inserted
        lastActivityAt = now()
        phase = .writing
        tick()
    }

    func registerMarkedTextActivity() {
        guard phase == .writing || phase == .danger else { return }
        lastActivityAt = now()
        phase = .writing
        tick()
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
        if clearText {
            text = ""
        }
        startedAt = nil
        lastActivityAt = nil
        emitStateChange()
    }
}
