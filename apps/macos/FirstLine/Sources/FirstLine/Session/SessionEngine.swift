/*
 * [INPUT]: 单调时间源、NaturalLanguage 分词与编辑器提交、IME 活动
 * [OUTPUT]: SessionEngine / SessionPhase、词数、截止时间与失败时 unusedSeconds
 * [POS]: 首次输入启动时钟与绝对截止时间裁决；正文变化时更新词数，重启由 AppState 授权，草稿只在内存
 * [PROTOCOL]: 变更时检查最近 AGENTS.md
 */
import Foundation
import NaturalLanguage

enum SessionPhase: Equatable {
    case idle, writing, danger, failure, success
}

@Observable
@MainActor
final class SessionEngine {
    nonisolated static let dangerAfterSeconds: TimeInterval = 5
    nonisolated static let wipeAfterSeconds: TimeInterval = 8
    nonisolated static let defaultDurationSeconds: TimeInterval = 60

    nonisolated private static let clockReference = ContinuousClock().now
    nonisolated static func continuousNowSeconds() -> TimeInterval {
        let c = clockReference.duration(to: ContinuousClock().now).components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1_000_000_000_000_000_000
    }

    nonisolated static func validDuration(_ value: TimeInterval) -> TimeInterval {
        [60.0, 180, 300, 600, 900, 1200, 1800, 3600].contains(value) ? value : defaultDurationSeconds
    }

    private static let hanPattern = try! NSRegularExpression(pattern: "(\\p{Script=Han}\\p{Mark}*)")

    private let now: () -> TimeInterval
    var phase: SessionPhase = .idle
    private(set) var text = ""
    private(set) var wordCount = 0
    var duration: TimeInterval = defaultDurationSeconds
    var elapsed: TimeInterval = 0
    var remaining: TimeInterval = defaultDurationSeconds
    private(set) var idleSeconds: TimeInterval = 0
    private(set) var wipedText = ""
    private(set) var unusedSeconds: Int?
    private(set) var lastDenyAt: TimeInterval?
    private(set) var sessionID = UUID()
    var onStateChange: ((SessionPhase) -> Void)?
    private var startedAt: TimeInterval?
    private var lastActivityAt: TimeInterval?

    init(now: @escaping () -> TimeInterval = { SessionEngine.continuousNowSeconds() }) {
        self.now = now
    }

    var secondsUntilDeletion: Int { max(0, Int(ceil(Self.wipeAfterSeconds - idleSeconds))) }

    private static func countWords(in text: String) -> Int {
        let source = text as NSString
        let separated = Self.hanPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: source.length), withTemplate: " $1 ")
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = separated
        var count = 0
        tokenizer.enumerateTokens(in: separated.startIndex..<separated.endIndex) { range, _ in
            if separated[range].unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) {
                count += 1
            }
            return true
        }
        return count
    }

    var hasMultipleLines: Bool { text.contains("\n") }

    func start(duration: TimeInterval) {
        self.duration = Self.validDuration(duration)
        sessionID = UUID()
        elapsed = 0
        remaining = self.duration
        idleSeconds = 0
        wipedText = ""
        unusedSeconds = nil
        lastDenyAt = nil
        text = ""
        wordCount = 0
        startedAt = nil
        lastActivityAt = nil
        phase = .writing
        emitStateChange()
    }

    func tick() {
        if adjudicateDeadlines() { return }
        guard let startedAt, let lastActivityAt, phase == .writing || phase == .danger else { return }
        let current = now()
        elapsed = min(max(current - startedAt, 0), duration)
        remaining = max(duration - elapsed, 0)
        idleSeconds = max(current - lastActivityAt, 0)
        phase = idleSeconds >= Self.dangerAfterSeconds ? .danger : .writing
        emitStateChange()
    }

    func registerCommittedText(_ inserted: String) {
        guard !inserted.isEmpty else { return }
        guard phase == .writing || phase == .danger, !adjudicateDeadlines() else { return }
        let current = now()
        if startedAt == nil { startedAt = current }
        text += inserted
        wordCount = Self.countWords(in: text)
        lastActivityAt = current
        idleSeconds = 0
        phase = .writing
        tick()
    }

    func registerMarkedTextActivity() {
        guard phase == .writing || phase == .danger, !adjudicateDeadlines() else { return }
        let current = now()
        if startedAt == nil { startedAt = current }
        lastActivityAt = current
        idleSeconds = 0
        phase = .writing
        tick()
    }

    @discardableResult
    private func adjudicateDeadlines() -> Bool {
        guard let startedAt, let lastActivityAt, phase == .writing || phase == .danger else { return false }
        let current = now()
        let finish = startedAt + duration
        let wipe = lastActivityAt + Self.wipeAfterSeconds
        let wipePassed = current >= wipe
        let finishPassed = current >= finish
        guard wipePassed || finishPassed else { return false }
        if wipePassed && (!finishPassed || wipe <= finish) ||
            finishPassed && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unusedSeconds = max(0, Int(ceil(finish - wipe)))
            wipedText = text
            text = ""
            wordCount = 0
            phase = .failure
        } else {
            elapsed = duration
            remaining = 0
            phase = .success
        }
        emitStateChange()
        return true
    }

    func registerDeny() { lastDenyAt = now() }
    func abandon() {
        phase = .idle
        elapsed = 0
        remaining = duration
        idleSeconds = 0
        wipedText = ""
        unusedSeconds = nil
        lastDenyAt = nil
        text = ""
        wordCount = 0
        startedAt = nil
        lastActivityAt = nil
        emitStateChange()
    }

    private func emitStateChange() { onStateChange?(phase) }
}
