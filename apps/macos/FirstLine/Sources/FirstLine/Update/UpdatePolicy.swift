/**
 * [INPUT]: 无外部依赖（纯 Swift，不含 Sparkle 类型）
 * [OUTPUT]: UpdatePolicy（更新界面何时可以出现的规则）与 UpdateDeferralPolicy（被推迟的更新记录）
 * [POS]: 更新界面的时机真相源：写作会话活跃时（房间任何阶段，或离开房间后仍在走的会话）绝不出现更新窗口，定时检查到的更新先记录再在会话结束后请回一次
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 为什么写作时不放更新窗口：房间靠静默计时判死，任何抢走键盘焦点的窗口都会让计时继续跑而用户
 * 打不了字，代价是整篇草稿。从房间进 Settings 时会话仍在走，所以判据是会话是否活跃，而不是
 * 只看当前 surface；定时检查到的更新被推迟到会话结束之后。
 */

enum UpdatePolicy {
    /// 标准 Sparkle 窗口只有在写作会话不活跃时才能出现：房间任何阶段，或房间之外仍在走的会话都算活跃。
    nonisolated static func mayPresentUpdateUI(isWritingSessionActive: Bool) -> Bool {
        !isWritingSessionActive
    }

    /// 「Check for Updates…」菜单项：只在确实装有更新器、且写作会话不活跃时可用。
    /// 试用耗尽也照样可用，更新不是付费功能。
    nonisolated static func mayRunUserInitiatedCheck(hasUpdater: Bool, isWritingSessionActive: Bool) -> Bool {
        hasUpdater && mayPresentUpdateUI(isWritingSessionActive: isWritingSessionActive)
    }
}

/// Sparkle 在 delegate 决定不立即展示更新后，delegate 必须记住"欠用户一次展示"并在安全时机请回。
/// 更新本身由 Sparkle 持有，这里只需要一个待办标记。
struct UpdateDeferralPolicy: Equatable {
    private(set) var hasDeferredUpdate = false

    mutating func deferUpdate() {
        hasDeferredUpdate = true
    }

    /// 至多请回一次：写作会话仍活跃或 Sparkle 正忙时保留待办，条件满足时消费它并返回 true。
    mutating func takePresentationRequest(isWritingSessionActive: Bool, canCheckForUpdates: Bool) -> Bool {
        guard hasDeferredUpdate,
              UpdatePolicy.mayPresentUpdateUI(isWritingSessionActive: isWritingSessionActive),
              canCheckForUpdates else { return false }
        hasDeferredUpdate = false
        return true
    }
}
