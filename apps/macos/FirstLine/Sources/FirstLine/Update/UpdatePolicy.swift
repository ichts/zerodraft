/**
 * [INPUT]: 无外部依赖（纯 Swift，不含 Sparkle 类型）
 * [OUTPUT]: UpdatePolicy（更新界面何时可以出现的规则）与 UpdateDeferralPolicy（被推迟的定时更新记录）
 * [POS]: 更新界面的时机真相源：写作会话运行中绝不展示更新窗口，定时检查到的更新先记录再在会话结束后请回一次
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 为什么房间内不放更新窗口：写入房间靠静默计时判死，任何抢走键盘焦点的窗口都会让计时继续跑而用户
 * 打不了字，代价是整篇草稿。因此更新界面只在没有会话运行时出现，定时检查到的更新被推迟到会话结束。
 */

enum UpdatePolicy {
    /// 标准 Sparkle 窗口只有在写作会话不运行时才能出现。
    nonisolated static func mayPresentUpdateUI(sessionIsRunning: Bool) -> Bool {
        !sessionIsRunning
    }

    /// 「Check for Updates…」菜单项：只在确实装有更新器、且没有会话运行时可用。
    /// 试用耗尽也照样可用，更新不是付费功能。
    nonisolated static func mayRunUserInitiatedCheck(hasUpdater: Bool, sessionIsRunning: Bool) -> Bool {
        hasUpdater && mayPresentUpdateUI(sessionIsRunning: sessionIsRunning)
    }
}

/// Sparkle 把定时检查到的更新交给 delegate 之后，delegate 必须记住"欠用户一次展示"并在安全时机请回。
/// 更新本身由 Sparkle 持有，这里只需要一个待办标记。
struct UpdateDeferralPolicy: Equatable {
    private(set) var hasDeferredUpdate = false

    mutating func deferUpdate() {
        hasDeferredUpdate = true
    }

    /// 至多请回一次：条件不满足时保留待办，满足时消费它并返回 true。
    /// `canCheckForUpdates` 对应 `SPUUpdater.canCheckForUpdates`，避免在 Sparkle 正忙时调用检查。
    mutating func takePresentationRequest(sessionIsRunning: Bool, canCheckForUpdates: Bool) -> Bool {
        guard hasDeferredUpdate, UpdatePolicy.mayPresentUpdateUI(sessionIsRunning: sessionIsRunning),
              canCheckForUpdates else { return false }
        hasDeferredUpdate = false
        return true
    }

    mutating func clear() {
        hasDeferredUpdate = false
    }
}
