/**
 * [INPUT]: 依赖 AppKit、App/MainMenuBuilder、App/FirstLineMain、App/RootWindowController、Settings/SettingsViewController、Editor/AppendOnlyTextView
 * [OUTPUT]: 主菜单必须携带标准 Edit 菜单（六个 nil target 条目）；编辑命令只由真正接受它的文本视图点亮；成稿房间的前台响应者不是文本视图，因此产品自有的 Cmd+C 仍然拿到那一次按键并复制整篇
 * [POS]: 1.1.1 修复的回归断言：没有 Edit 菜单时 Cmd+V 在许可输入框里无处可去（AppKit 只经菜单项的快捷键派发 paste:/copy:/selectAll:/undo:）
 * [PROTOCOL]: 变更菜单形状或房间键盘契约时同步更新此头部与 docs/wid-decisions.md（D-082）
 *
 * 为什么这里不按快捷键驱动整条派发：AppKit 的菜单快捷键派发从 key window 的 responder chain 取
 * target，而 headless 的测试进程永远拿不到 key window（NSApp.keyWindow 为 nil），nil target 的条目
 * 会保持启用、按键返回 true 却什么也不发生。真实按键因此由 VM rig 记录，单元测试锁住它依赖的两件
 * 事：菜单形状，以及每个 surface 对编辑命令的接受/拒绝。
 */

import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct EditingCommandTests {
    // MARK: - Fixtures

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func fields(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields(in:))
    }

    private func editors(in view: NSView) -> [AppendOnlyTextView] {
        ((view as? AppendOnlyTextView).map { [$0] } ?? []) + view.subviews.flatMap(editors(in:))
    }

    private func submenu(_ title: String, in menu: NSMenu) -> NSMenu? {
        menu.items.compactMap(\.submenu).first { $0.title == title }
    }

    private func editItem(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        submenu("Edit", in: menu)?.items.first { $0.title == title }
    }

    private func room(in controller: RootWindowController) throws -> SessionViewController {
        let container = try #require(controller.window?.contentViewController as? RootContainerViewController)
        return try #require(container.children.first as? SessionViewController)
    }

    // MARK: - Menu shape

    @Test func mainMenuCarriesTheStandardEditingCommands() throws {
        let state = licensedTestState()
        // NSMenuItem.target is weak: the app holds its delegate, this test must too.
        let delegate = FirstLineAppDelegate(appState: state)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate)

        #expect(menu.items.compactMap { $0.submenu?.title } == ["", "Edit", "Navigate"],
                "the Edit menu sits between the app menu and Navigate")

        // D-085: one verb for beginning a session, so Cmd+N reads Begin, never New Piece.
        let navigate = try #require(submenu("Navigate", in: menu))
        #expect(navigate.items.first?.title == "Begin" && navigate.items.first?.keyEquivalent == "n")

        let edit = try #require(submenu("Edit", in: menu))
        #expect(edit.autoenablesItems,
                "nil-target items need AppKit's responder-chain validation, which disables them when nothing handles the action")
        #expect(!menu.autoenablesItems, "the app's own commands stay on explicit validateMenuItem")

        let expected: [(String, Selector, String)] = [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, action, key) in expected {
            let item = try #require(editItem(title, in: menu), "Edit menu item \(title) is missing")
            #expect(item.action == action)
            #expect(item.target == nil, "\(title) must route through the responder chain, not a fixed target")
            #expect(item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask.contains(.command))
        }

        // The product's own command keeps its key and its explicit target: it is what commits
        // ⌘C in the kept room, where no text view sits in the responder chain.
        let kept = try #require(submenu("Navigate", in: menu)?.items.first { $0.keyEquivalent == "c" })
        #expect(kept.action == #selector(FirstLineAppDelegate.copyKept(_:)))
        #expect(kept.target === delegate)
    }

    // MARK: - Which surface accepts which editing command

    @Test func aTextFieldAcceptsTheEditingCommandsTheEditMenuOffers() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root),
                             licenseClient: MockLicenseClient(),
                             installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        let settings = SettingsViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = settings
        defer { window.orderOut(nil) }
        let field = try #require(fields(in: settings.view)
            .first { $0.placeholderString == "License key" })

        // The licence field's editor is what answers the Edit menu while a buyer types a key.
        window.makeFirstResponder(field)
        let editor = try #require(window.fieldEditor(false, for: field) as? NSTextView,
                                  "focusing the licence field opens its field editor")
        func accepts(_ action: Selector) -> Bool {
            editor.validateUserInterfaceItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
        }
        // Paste is the buyer's path: available as soon as the field is focused and the
        // pasteboard carries text (validation reads the live pasteboard, exactly as the
        // Edit menu does when it decides whether the item is lit).
        let board = NSPasteboard.general
        let saved = board.string(forType: .string)
        defer {
            board.clearContents()
            if let saved { board.setString(saved, forType: .string) }
        }
        board.clearContents()
        board.setString("WID-PRIMARY-KEY-4242-7777", forType: .string)
        #expect(accepts(#selector(NSText.paste(_:))))
        // Cut/Copy follow the selection the way every macOS text field does, and Select All
        // needs something to select; the menu validates each item the same way.
        #expect(!accepts(#selector(NSText.copy(_:))))
        editor.string = "WID-PRIMARY-KEY-4242-7777"
        #expect(accepts(#selector(NSText.selectAll(_:))))
        editor.selectAll(nil)
        #expect(accepts(#selector(NSText.copy(_:))))
        #expect(accepts(#selector(NSText.cut(_:))))
    }

    @Test func typingInTheLicenceFieldUndoesFromTheEditMenu() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root),
                             licenseClient: MockLicenseClient(),
                             installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        // The buyer types a key in Settings, between the app menu and Navigate, inside the controller's window.
        state.selectedSurface = .settings
        let controller = RootWindowController(appState: state)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        let view = try #require(window.contentViewController?.view)
        let field = try #require(fields(in: view).first { $0.placeholderString == "License key" },
                                 "an unlicensed Mac offers the licence field in Settings")
        window.makeFirstResponder(field)
        let editor = try #require(window.fieldEditor(false, for: field) as? NSTextView)
        editor.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))

        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate(appState: state))
        let undo = try #require(editItem("Undo", in: menu))
        let redo = try #require(editItem("Redo", in: menu))
        // The nil-target Undo item resolves to the window controller, which forwards to the field's own manager.
        #expect(controller.validateMenuItem(undo))
        #expect(editor.tryToPerform(#selector(RootWindowController.undo(_:)), with: nil))
        #expect(editor.string.isEmpty)
        #expect(controller.validateMenuItem(redo))
        #expect(editor.tryToPerform(#selector(RootWindowController.redo(_:)), with: nil))
        #expect(editor.string == "abc")
    }

    @Test func theWritingRoomLeavesUndoDisabled() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = licensedTestState(settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 300)
        let controller = RootWindowController(appState: state)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        let room = try room(in: controller)
        let editor = try #require(editors(in: room.view).first)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        editor.insertText("forward", replacementRange: NSRange(location: NSNotFound, length: 0))

        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate(appState: state))
        let undo = try #require(editItem("Undo", in: menu))
        #expect(editor.allowsUndo == false)
        #expect(controller.validateMenuItem(undo) == false, "the append-only room never offers Undo")
        #expect(editor.tryToPerform(#selector(RootWindowController.undo(_:)), with: nil))
        #expect(editor.string == "forward", "⌘Z changes nothing in the room")
    }

    @Test func theWritingRoomRefusesEveryEditingCommand() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = licensedTestState(settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 300)
        let controller = RootWindowController(appState: state)
        let room = try room(in: controller)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }
        let editor = try #require(editors(in: room.view).first)
        editor.insertText("forward only ", replacementRange: NSRange(location: NSNotFound, length: 0))
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)

        // Append-only: the menu items for these commands stay disabled in the room.
        let blocked = [#selector(NSText.paste(_:)), #selector(NSText.cut(_:)),
                       Selector(("undo:")), Selector(("redo:")),
                       #selector(NSResponder.deleteBackward(_:)), #selector(NSText.selectAll(_:)),
                       #selector(NSText.copy(_:))]
        for action in blocked {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            #expect(!editor.validateUserInterfaceItem(item),
                    "the room must refuse \(NSStringFromSelector(action))")
        }

        // Typing still appends through the same editor.
        editor.insertText("next", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "forward only next")
        #expect(state.sessionEngine.text == "forward only next")
    }

    @Test func theKeptRoomCopiesItsWholeDraft() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var time = 0.0
        let engine = SessionEngine(now: { time })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        state.startSession(duration: 60)
        let controller = RootWindowController(appState: state)
        let room = try room(in: controller)
        let window = try #require(controller.window)
        defer { window.orderOut(nil) }

        engine.registerCommittedText("the whole draft")
        for second in stride(from: 4.0, to: 60, by: 4.0) {
            time = second
            engine.registerMarkedTextActivity()
        }
        time = 60
        window.makeKeyAndOrderFront(nil)
        room.tick()
        #expect(engine.phase == .success)
        room.refreshRoom()
        // The room moves focus onto COPY TEXT on the next main-queue turn.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let delegate = FirstLineAppDelegate(appState: state, windowController: controller)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate)
        let keptItem = try #require(submenu("Navigate", in: menu)?.items.first { $0.keyEquivalent == "c" })
        #expect(delegate.validateMenuItem(keptItem), "Copy Kept Text stays available in the kept room")

        let board = NSPasteboard.general
        let saved = board.string(forType: .string)
        defer {
            board.clearContents()
            if let saved { board.setString(saved, forType: .string) }
        }
        board.clearContents()
        board.setString("BEFORE-CMD-C", forType: .string)

        // The room's editor is the first responder in the kept phase, so the Edit menu's copy:
        // arrives there and must hand the draft to the room rather than copy an empty selection.
        let editor = try #require(editors(in: room.view).first)
        #expect(!editor.isEditable)
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        #expect(editor.validateUserInterfaceItem(copyItem),
                "the kept room lights up the Edit menu's Copy")
        editor.copy(nil)
        #expect(board.string(forType: .string) == "the whole draft")
        #expect(engine.copiedKeptText)

        // The product's own item carries the same action for the menu bar.
        board.clearContents()
        board.setString("BEFORE-CMD-C", forType: .string)
        #expect(NSApplication.shared.sendAction(keptItem.action!, to: keptItem.target, from: keptItem))
        #expect(board.string(forType: .string) == "the whole draft")
    }
}
