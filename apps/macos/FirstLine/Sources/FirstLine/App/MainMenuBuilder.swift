/**
 * [INPUT]: 依赖 AppKit、App/AppState
 * [OUTPUT]: AppKit 菜单，包含标准 Edit 菜单（Undo/Redo/Cut/Copy/Paste/Select All，nil target 走 responder chain）、Cmd+N 新篇、Cmd+C 成稿复制、Cmd+W 关窗、Cmd+, Settings 与 Check for Updates…。
 * [POS]: 菜单 target-action 桥接 AppDelegate，动态命令由 validateMenuItem 验证；标准编辑命令不带 target，由 AppKit 按 first responder 校验后交给正在编辑的文本框。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit

enum MainMenuBuilder {
    @MainActor
    static func buildMenu(appState: AppState, validationOwner: NSMenuItemValidation & AnyObject,
                          showsUpdateCheck: Bool = false) -> NSMenu {
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

        // Check for Updates… sits where macOS users look for it: under About. It is the only
        // visible affordance for the update feature; automatic checks stay off until the writer
        // turns them on in Settings.
        if showsUpdateCheck {
            let updateItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(FirstLineAppDelegate.checkForUpdates(_:)),
                keyEquivalent: ""
            )
            updateItem.target = validationOwner
            appMenu.addItem(updateItem)
        }

        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(FirstLineAppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = validationOwner
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(FirstLineAppDelegate.closeWindow(_:)), keyEquivalent: "w")
        closeItem.target = validationOwner
        appMenu.addItem(closeItem)

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

        // Edit 菜单：AppKit 只在菜单项的快捷键里派发标准编辑命令（paste:、copy:、selectAll:、
        // undo:、cut:），条目保持 nil target，命令由 responder chain 交给第一响应者，因此许可
        // 输入框（字段编辑器）和任何文本框都能用 ⌘V/⌘A/⌘C/⌘X/⌘Z。这些条目必须保留自动启用：
        // 主菜单关掉了 autoenablesItems，只有子菜单的自动校验才会让“没有响应者能处理”的条目禁用。
        // ⌘C 与 Navigate 的 Copy Kept Text 同键，按阶段各有唯一结果：写作中房间的编辑器禁用 copy:，
        // ⌘C 什么也不做；成稿后同一个编辑器把 copy: 沿 responder chain 转给房间，复制整篇草稿，而
        // Navigate 的产品条目仍是同一动作的菜单入口（D-082）。
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.autoenablesItems = true
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Navigate 菜单。
        let navigateMenuItem = NSMenuItem()
        mainMenu.addItem(navigateMenuItem)
        let navigateMenu = NSMenu(title: "Navigate")
        navigateMenuItem.submenu = navigateMenu

        let newItem = NSMenuItem(title: "Begin", action: #selector(FirstLineAppDelegate.newPiece(_:)), keyEquivalent: "n")
        newItem.target = validationOwner
        navigateMenu.addItem(newItem)
        let copyItem = NSMenuItem(title: "Copy Kept Text", action: #selector(FirstLineAppDelegate.copyKept(_:)), keyEquivalent: "c")
        copyItem.target = validationOwner
        navigateMenu.addItem(copyItem)
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
