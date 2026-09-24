/**
 * [INPUT]: 依赖 AppKit、App/AppState
 * [OUTPUT]: MainMenuBuilder.buildMenu - 构建纯 AppKit 主菜单（App 菜单 + Navigate 菜单）
 * [POS]: writeitdown AppKit 菜单构造器；以 target-action 桥接 AppDelegate 上的 @objc 方法，
 *        validateMenuItem(_:) 负责启用/禁用（Settings 在会话中禁用，Writing/Home 在 success 禁用）。
 *        Cmd+, 打开站内 Settings surface。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit

enum MainMenuBuilder {
    @MainActor
    static func buildMenu(appState: AppState, validationOwner: NSMenuItemValidation & AnyObject) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.autoenablesItems = false

        // App 菜单（标题对 app 名；macOS 会把第一项的标题替换为 app 名）。
        let appMenuItem = NSMenuItem(title: "Write It Down", action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: "About Write It Down",
            action: #selector(FirstLineAppDelegate.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = validationOwner
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(FirstLineAppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = validationOwner
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "Hide Write It Down", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Write It Down",
            action: #selector(FirstLineAppDelegate.terminateApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = validationOwner
        appMenu.addItem(quitItem)

        // Navigate 菜单。
        let navigateMenuItem = NSMenuItem()
        mainMenu.addItem(navigateMenuItem)
        let navigateMenu = NSMenu(title: "Navigate")
        navigateMenuItem.submenu = navigateMenu

        let writingItem = NSMenuItem(
            title: "Writing",
            action: #selector(FirstLineAppDelegate.openWriting(_:)),
            keyEquivalent: "1"
        )
        writingItem.target = validationOwner
        navigateMenu.addItem(writingItem)

        let homeItem = NSMenuItem(
            title: "Home",
            action: #selector(FirstLineAppDelegate.goHome(_:)),
            keyEquivalent: "0"
        )
        homeItem.target = validationOwner
        navigateMenu.addItem(homeItem)

        _ = appState // 保留 appState 参数以显式声明构建期的依赖；validation 由 validateMenuItem 用 target 驱动。

        return mainMenu
    }
}
