/**
 * [INPUT]: 依赖 AppKit、App/AppState、App/RootWindowController、App/MainMenuBuilder
 * [OUTPUT]: 提供 FirstLine 的纯 AppKit 入口（@main），替代原 SwiftUI WindowGroup 入口
 * [POS]: FirstLine 重写 Phase 1 应用骨架根入口；建立 NSApplication、主菜单、主窗口与路由，不再使用 SwiftUI 生命周期
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 重写决策：删去 SwiftUI `@main struct FirstLineApp: App`。纯 AppKit 启动由
 * `@main enum FirstLineMain` 提供：main() 在主线程构造 NSApplication、AppDelegate 与
 * AppState，applicationDidFinishLaunching 里构建主菜单、显示主窗口并激活 app。
 * 这是「全量 AppKit 重写」的 Phase 1：窗口与菜单路由通，真实界面仍是占位 VC（Phase 2+）。
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
    let appState = AppState()
    private var rootWindowController: RootWindowController?

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

    @objc func openWriting(_ sender: Any?) { appState.openWritingMode() }
    @objc func goHome(_ sender: Any?) { appState.goHome() }
    @objc func openLibrary(_ sender: Any?) { appState.openLibrary() }
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
        case #selector(openSettings), #selector(openLibrary):
            return appState.canNavigateToSupportSurface
        case #selector(openWriting), #selector(goHome):
            // success 阶段锁定导航（复刻原 SwiftUI .disabled 语义）。
            return appState.sessionEngine.phase != .success
        default:
            return true
        }
    }
}
