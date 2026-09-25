/**
 * [INPUT]: 依赖 AppKit、App/AppState、App/RootWindowController、App/MainMenuBuilder
 * [OUTPUT]: 纯 AppKit 入口、AppDelegate 菜单动作与验证
 * [POS]: 建立 NSApplication、菜单与主窗口；生产应用注入 Dodo client；新篇命令同步清理房间、路由复制与设置
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 重写决策：删去 SwiftUI `@main struct FirstLineApp: App`。纯 AppKit 启动由
 * `@main enum FirstLineMain` 提供：main() 在主线程构造 NSApplication、AppDelegate 与
 * AppState，applicationDidFinishLaunching 里构建主菜单、显示主窗口并激活 app。
 * 完整 AppKit 应用由 RootWindowController 托管常驻 RootContainerViewController；Home、Writing、
 * Session 在单一房间承载 rest/typing/warn/wipe/kept；Settings 与 Upgrade 是容器内切换的原生 AppKit surface。
 */

import AppKit

@main
enum FirstLineMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = FirstLineAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class FirstLineAppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    private var rootWindowController: RootWindowController?

    init(appState: AppState = AppState(licenseClient: DodoLicenseClient()), windowController: RootWindowController? = nil) {
        self.appState = appState
        self.rootWindowController = windowController
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let menu = MainMenuBuilder.buildMenu(appState: appState, validationOwner: self)
        NSApp.mainMenu = menu

        let controller = RootWindowController(appState: appState)
        rootWindowController = controller
        controller.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu actions (target-action bridge to AppState)

    @objc func newPiece(_ sender: Any?) {
        appState.newPiece()
        rootWindowController?.refreshRoom()
    }
    @objc func copyKept(_ sender: Any?) { rootWindowController?.copyKeptText() }
    @objc func closeWindow(_ sender: Any?) { rootWindowController?.window?.performClose(sender) }
    @objc func openWriting(_ sender: Any?) { appState.openWritingMode() }
    @objc func goHome(_ sender: Any?) { appState.goHome() }
    @objc func openSettings(_ sender: Any?) { appState.openSettings() }
    @objc func terminateApp(_ sender: Any?) { NSApp.terminate(nil) }
    @objc func orderFrontStandardAboutPanel(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

// MARK: - Menu item validation

extension FirstLineAppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyKept):
            return appState.sessionEngine.phase == .success && appState.selectedSurface == .session
        case #selector(openSettings), #selector(newPiece), #selector(closeWindow):
            return true
        case #selector(openWriting), #selector(goHome):
            // success 阶段锁定导航（复刻原 SwiftUI .disabled 语义）。
            return appState.sessionEngine.phase != .success
        default:
            return true
        }
    }
}
