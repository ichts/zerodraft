/**
 * [INPUT]: 依赖 AppKit、Sparkle 的 SPUStandardUserDriverDelegate 与 SUAppcastItem、Update/UpdatePolicy
 * [OUTPUT]: UpdateUserDriver：标准 Sparkle 界面的 gentle reminder delegate，记录被推迟的定时更新并在安全时机请回
 * [POS]: 更新界面与写作房间之间的闸门；只在会话结束且 Sparkle 空闲时把推迟的更新交给标准界面
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * Sparkle 在主线程回调这些方法，但协议本身不是 @MainActor，因此以 nonisolated 实现并在内部
 * MainActor.assumeIsolated 里读写状态：状态归属仍然是主 actor，没有第二份并发真相。
 */

import Foundation
import Sparkle

@MainActor
final class UpdateUserDriver: NSObject, SPUStandardUserDriverDelegate {
    private let sessionIsRunning: () -> Bool
    private var deferral = UpdateDeferralPolicy()

    init(sessionIsRunning: @escaping () -> Bool) {
        self.sessionIsRunning = sessionIsRunning
        super.init()
    }

    /// 会话结束或应用回到前台后，由 UpdateController 询问是否可以把推迟的更新请回一次。
    func takePresentationRequest(canCheckForUpdates: Bool) -> Bool {
        deferral.takePresentationRequest(sessionIsRunning: sessionIsRunning(), canCheckForUpdates: canCheckForUpdates)
    }

    // MARK: - SPUStandardUserDriverDelegate（Sparkle 在主线程调用）

    /// 只有声明支持 gentle reminder，Sparkle 才会把定时检查到的更新交给 delegate 决定是否展示。
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // 该回调必须无副作用：返回 NO 表示 delegate 负责展示，记录发生在 willHandleShowingUpdate。
        MainActor.assumeIsolated {
            UpdatePolicy.mayPresentUpdateUI(sessionIsRunning: sessionIsRunning())
        }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                deferral.clear()
            } else {
                deferral.deferUpdate()
            }
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { deferral.clear() }
    }
}
