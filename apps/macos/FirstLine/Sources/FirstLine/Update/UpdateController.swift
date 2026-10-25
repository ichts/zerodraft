/**
 * [INPUT]: 依赖 AppKit、Observation、Sparkle 的 SPUStandardUpdaterController/SPUUpdater、App/AppState、Update/UpdateUserDriver、Update/UpdatePolicy
 * [OUTPUT]: UpdateController（Sparkle 标准更新器）与 UpdateSettings（Settings 面需要的唯一可写开关）
 * [POS]: 更新功能的入口：自动检查默认关闭，只有 Settings 开关或「Check for Updates…」菜单动作才会发起检查；会话运行中不展示更新界面
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 「默认不检查」由 Info.plist 的 SUEnableAutomaticChecks=false 落地：Sparkle 因此既不询问也不排期；
 * 设置开关写 updater.automaticallyChecksForUpdates，持久化真相只属于 Sparkle 的 user defaults。
 */

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
    private let updaterController: SPUStandardUpdaterController

    private var updater: SPUUpdater { updaterController.updater }

    /// 只在真实 .app 内启动更新器：裸可执行文件（swift run、单元测试）没有 Info.plist 的更新配置，
    /// 启动 Sparkle 只会触发一段配置错误提示。
    static func make(appState: AppState) -> UpdateController? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return nil }
        return UpdateController(appState: appState)
    }

    private init(appState: AppState) {
        let driver = UpdateUserDriver(sessionIsRunning: { [weak appState] in appState?.sessionIsRunning ?? false })
        self.appState = appState
        self.userDriver = driver
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: driver
        )
        armSessionObservation()
    }

    /// 菜单动作与唯一的手动检查入口。房间内即使被程序调用也不发起检查。
    func checkForUpdates() {
        guard UpdatePolicy.mayPresentUpdateUI(sessionIsRunning: appState.sessionIsRunning) else { return }
        updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// 会话从运行变为结束时，把被推迟的更新请回一次标准界面。
    private func armSessionObservation() {
        withObservationTracking { [weak self] in
            _ = self?.appState.sessionIsRunning
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshDeferredUpdate()
                self.armSessionObservation()
            }
        }
    }

    private func refreshDeferredUpdate() {
        guard userDriver.takePresentationRequest(canCheckForUpdates: updater.canCheckForUpdates) else { return }
        updater.checkForUpdates()
    }
}
