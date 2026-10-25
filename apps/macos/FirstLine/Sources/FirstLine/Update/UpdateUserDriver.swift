/**
 * [INPUT]: 依赖 AppKit、Sparkle 的 SPUStandardUserDriver/SPUStandardUserDriverDelegate 与 SUAppcastItem、Update/UpdatePolicy
 * [OUTPUT]: UpdateUserDriver（定时更新的 gentle reminder 委托）与 RoomAwareStandardUserDriver（标准 Sparkle 界面的房间闸门）
 * [POS]: 更新界面与写作之间的唯一闸门：写作会话活跃时（房间任何阶段或房间之外仍在走的会话）拒绝或推迟任何更新窗口，窗口已经出现时通过 Sparkle 自己的取消/回复路径结束它
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * Sparkle 在主线程回调这些方法，但协议本身不是 @MainActor，因此以 nonisolated 实现并在内部
 * MainActor.assumeIsolated 里读写状态：状态归属仍然是主 actor，没有第二份并发真相。
 */

import AppKit
import Sparkle

@MainActor
final class UpdateUserDriver: NSObject, SPUStandardUserDriverDelegate {
    private let isWritingSessionActive: () -> Bool
    private var deferral = UpdateDeferralPolicy()

    /// 定时检查到的更新由本 delegate 负责展示；控制器在这里把已经建好的标准窗口请回前台。
    var onScheduledUpdateReady: (() -> Void)?

    init(isWritingSessionActive: @escaping () -> Bool) {
        self.isWritingSessionActive = isWritingSessionActive
        super.init()
    }

    func deferUpdate() {
        deferral.deferUpdate()
    }

    /// 离开房间或应用回到前台后，由 UpdateController 询问是否可以把推迟的更新请回一次。
    func takePresentationRequest(canCheckForUpdates: Bool) -> Bool {
        deferral.takePresentationRequest(isWritingSessionActive: isWritingSessionActive(), canCheckForUpdates: canCheckForUpdates)
    }

    // MARK: - SPUStandardUserDriverDelegate（Sparkle 在主线程调用）

    /// 只有声明支持 gentle reminder，Sparkle 才会把定时检查到的更新交给 delegate 决定是否展示。
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 定时更新一律由本 delegate 决定何时展示。让标准 driver 自己处理时，它会把窗口推迟到下一次
    /// applicationDidBecomeActive，那时房间可能已经重新出现。
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // 用户发起的检查由 RoomAwareStandardUserDriver 在展示时闸门。
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            if let onScheduledUpdateReady {
                onScheduledUpdateReady()
            } else {
                deferral.deferUpdate()
            }
        }
    }
}

/// 标准 Sparkle 界面的写作闸门。真正展示前检查写作会话是否活跃；会话活跃时终止已经展示的更新会话。
/// 终止走 Sparkle 自己的 reply / cancellation，始终让一个更新会话有明确结局，而不是把窗口丢在原地。
@MainActor
final class RoomAwareStandardUserDriver: SPUStandardUserDriver {
    private let isWritingSessionActive: () -> Bool
    private let onDeferred: () -> Void
    private var activeCloser: (() -> Void)?

    init(
        hostBundle: Bundle,
        delegate: SPUStandardUserDriverDelegate,
        isWritingSessionActive: @escaping () -> Bool,
        onDeferred: @escaping () -> Void
    ) {
        self.isWritingSessionActive = isWritingSessionActive
        self.onDeferred = onDeferred
        super.init(hostBundle: hostBundle, delegate: delegate)
    }

    /// 写作会话接管窗口时调用：结束当前更新界面，并把更新记成待办。
    func endPresentationForRoom() {
        guard let closer = activeCloser else { return }
        activeCloser = nil
        onDeferred()
        closer()
    }

    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        guard !isWritingSessionActive() else {
            onDeferred()
            cancellation()
            return
        }
        let tracked = trackCancellation(cancellation)
        activeCloser = { tracked() }
        super.showUserInitiatedUpdateCheck(cancellation: tracked)
    }

    override func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        guard !isWritingSessionActive() else {
            onDeferred()
            reply(.dismiss)
            return
        }
        let tracked = trackReply(reply)
        activeCloser = { tracked(.dismiss) }
        super.showUpdateFound(with: appcastItem, state: state, reply: tracked)
    }

    override func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        guard !isWritingSessionActive() else {
            acknowledgement()
            return
        }
        activeCloser = nil
        super.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    override func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        guard !isWritingSessionActive() else {
            acknowledgement()
            return
        }
        activeCloser = nil
        super.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    override func showDownloadInitiated(cancellation: @escaping () -> Void) {
        guard !isWritingSessionActive() else {
            onDeferred()
            cancellation()
            return
        }
        let tracked = trackCancellation(cancellation)
        activeCloser = { tracked() }
        super.showDownloadInitiated(cancellation: tracked)
    }

    override func showDownloadDidStartExtractingUpdate() {
        guard !isWritingSessionActive() else {
            onDeferred()
            dismissUpdateInstallation()
            return
        }
        // 下载已经结束，下载取消不再有效；提取期间房间出现时先关掉状态窗，安装询问会再次经过房间闸门。
        activeCloser = { [weak self] in self?.dismissUpdateInstallation() }
        super.showDownloadDidStartExtractingUpdate()
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !isWritingSessionActive() else {
            onDeferred()
            reply(.dismiss)
            return
        }
        let tracked = trackReply(reply)
        activeCloser = { tracked(.dismiss) }
        super.showReady(toInstallAndRelaunch: tracked)
    }

    override func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        activeCloser = nil
        super.showInstallingUpdate(withApplicationTerminated: applicationTerminated,
                                   retryTerminatingApplication: retryTerminatingApplication)
    }

    override func dismissUpdateInstallation() {
        activeCloser = nil
        super.dismissUpdateInstallation()
    }

    override func showUpdateInFocus() {
        guard !isWritingSessionActive() else { return }
        super.showUpdateInFocus()
    }

    private func trackCancellation(_ cancellation: @escaping () -> Void) -> () -> Void {
        var used = false
        return { [weak self] in
            guard !used else { return }
            used = true
            self?.activeCloser = nil
            cancellation()
        }
    }

    private func trackReply(
        _ reply: @escaping (SPUUserUpdateChoice) -> Void
    ) -> (SPUUserUpdateChoice) -> Void {
        var used = false
        return { [weak self] choice in
            guard !used else { return }
            used = true
            self?.activeCloser = nil
            reply(choice)
        }
    }
}
