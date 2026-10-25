/**
 * [INPUT]: 依赖 AppKit、Observation、Sparkle 的 SPUUpdater、App/AppState、Update/UpdateUserDriver、Update/UpdatePolicy
 * [OUTPUT]: UpdateController（Sparkle 标准更新器）与 UpdateSettings（Settings 面需要的唯一可写开关）
 * [POS]: 更新功能的入口：自动检查默认关闭，只有 Settings 开关或「Check for Updates…」菜单动作才会发起检查；写作会话活跃期间（房间任何阶段或房间之外仍在走的会话）不展示更新界面
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 「默认不检查」由 Info.plist 的 SUEnableAutomaticChecks=false 落地：Sparkle 因此既不询问也不排期；
 * 设置开关写 updater.automaticallyChecksForUpdates，持久化真相只属于 Sparkle 的 user defaults。
 */

import AppKit
import Foundation
import Observation
import Sparkle

/// Settings 面依赖的最小接口：一个开关。测试用替身实现它，不启动 Sparkle。
@MainActor
protocol UpdateSettings: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
}

@MainActor
final class UpdateController: UpdateSettings {
    private let appState: AppState
    private let userDriver: UpdateUserDriver
    private let presenter: RoomAwareStandardUserDriver
    private let updater: SPUUpdater

    /// 只在真实 .app 内启动更新器：裸可执行文件（swift run、单元测试）没有 Info.plist 的更新配置，
    /// 启动 Sparkle 只会触发一段配置错误提示。
    static func make(appState: AppState) -> UpdateController? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return nil }
        return UpdateController(appState: appState)
    }

    private init?(appState: AppState) {
        let isWritingSessionActive: () -> Bool = { [weak appState] in appState?.isWritingSessionActive ?? false }
        let delegate = UpdateUserDriver(isWritingSessionActive: isWritingSessionActive)
        let presenter = RoomAwareStandardUserDriver(
            hostBundle: .main,
            delegate: delegate,
            isWritingSessionActive: isWritingSessionActive,
            onDeferred: { [weak delegate] in delegate?.deferUpdate() }
        )
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: presenter,
            delegate: nil
        )
        self.appState = appState
        self.userDriver = delegate
        self.presenter = presenter
        self.updater = updater

        delegate.onScheduledUpdateReady = { [weak self] in self?.presentScheduledUpdate() }
        do {
            try updater.start()
        } catch {
            NSLog("Write It Down could not start the updater: %@", error.localizedDescription)
            return nil
        }
        armWritingSessionObservation()
        armActivationObservation()
    }

    /// 菜单动作与唯一的手动检查入口。写作会话活跃时即使被程序调用也不发起检查。
    func checkForUpdates() {
        guard UpdatePolicy.mayPresentUpdateUI(isWritingSessionActive: appState.isWritingSessionActive) else { return }
        updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// surface 与运行状态的变化都重新裁决：写作会话一活跃就结束已有的更新窗口，
    /// 会话结束（离开房间且不再运行）后把推迟的更新请回一次。
    private func armWritingSessionObservation() {
        withObservationTracking { [weak self] in
            _ = self?.appState.isWritingSessionActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appState.isWritingSessionActive {
                    self.presenter.endPresentationForRoom()
                } else {
                    self.refreshDeferredUpdate()
                }
                self.armWritingSessionObservation()
            }
        }
    }

    /// 定时更新在应用不在前台时先记住待办，回到前台再由 activation observer 请回，避免抢走别的 app 的焦点。
    private func armActivationObservation() {
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDeferredUpdate()
            }
        }
    }

    /// 定时检查已经把标准窗口建好但还没展示；这里是它唯一的展示时机。
    private func presentScheduledUpdate() {
        guard UpdatePolicy.mayPresentUpdateUI(isWritingSessionActive: appState.isWritingSessionActive),
              NSApp.isActive else {
            userDriver.deferUpdate()
            return
        }
        updater.checkForUpdates()
    }

    private func refreshDeferredUpdate() {
        guard userDriver.takePresentationRequest(canCheckForUpdates: updater.canCheckForUpdates) else { return }
        updater.checkForUpdates()
    }
}
