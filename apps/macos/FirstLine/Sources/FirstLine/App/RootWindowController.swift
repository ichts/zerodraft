/**
 * [INPUT]: 依赖 AppKit、Observation、App/AppState、AppKit surfaces、DesignSystem/Colors
 * [OUTPUT]: 主窗口（无自身底色：透明窗口、透明标题栏（无分隔线、隐藏系统顶边高光）、桌面壁纸透出，D-102）、surface 路由、theme/focus 响应、成稿复制与新篇同步刷新菜单桥接，以及 Edit 菜单 Undo/Redo 到文本框 undo manager 的转发
 * [POS]: writeitdown AppKit 窗口壳与路由真相源；退役 SwiftUI RootView，把 AppState.selectedSurface
 *        经常驻 RootContainerViewController 映射到各 surface 子 VC，并应用 theme 与最小尺寸契约。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 路由：本控制器观察 selectedSurface 和 theme：
 *   1) selectedSurface -> 换常驻容器内的子控制器；
 *   2) theme -> 更新窗口外观；focusMode -> 全屏切换；
 * Observation 的 withObservationTracking 只触发一次回调，因此在回调里重新 arm 观察实现持续跟踪。
 */

import AppKit
import Observation

@MainActor
final class RootWindowController: NSWindowController {
    let appState: AppState
    let container: RootContainerViewController
    var programmaticFullScreenExitPending = false
    func copyKeptText() { container.copyKeptText() }
    func refreshRoom() { container.refreshRoom() }

    init(appState: AppState, updateSettings: (any UpdateSettings)? = nil) {
        self.appState = appState
        self.container = RootContainerViewController(appState: appState, updateSettings: updateSettings)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Write It Down"
        window.acceptsMouseMovedEvents = true
        Self.letWallpaperShow(window)

        super.init(window: window)
        NotificationCenter.default.addObserver(self, selector: #selector(didExitFullScreen(_:)),
                                               name: NSWindow.didExitFullScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterFullScreen(_:)),
                                               name: NSWindow.willEnterFullScreenNotification, object: window)
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowChromeChanged(_:)), name: name, object: window)
        }
        // 常驻容器是窗口的 contentViewController（只设一次、只 size 一次）；各 surface 作为它的子 VC
        // 原地切换。之前每次换 contentViewController 会让 AppKit 按 success/failure 的 0-fitting-size
        // 根视图把窗口缩成 0x0（显示旧 session 残留快照），而在回调里 setFrame 补救又触发递归 layout
        // 死循环卡死机器。这里把窗口尺寸与 surface 彻底解耦：窗口在此 size 一次，show() 只换子视图。
        window.contentViewController = container
        Self.hideTitlebarDecoration(window)
        window.setFrame(NSRect(x: 0, y: 0, width: 1040, height: 720), display: false)
        window.center()
        applyTheme()
        container.show(appState.selectedSurface)
        armSurfaceObservation()
        armThemeObservation()
        armFocusObservation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// D-102: the window has no ground of its own. The paper (or card) keeps its size and place with its one
    /// soft shadow, and the writer's own desktop shows around it. The title bar is clear and its title hidden
    /// (the traffic lights float over the wallpaper; the title stays for Mission Control and the Window
    /// menu). The window's own shadow is off so the paper's is the only one. A window pixel at alpha 0
    /// would let clicks fall through to the app behind, so the clear ground is one alpha step above 0 and
    /// the margin still drags the window. Full screen has no wallpaper: `setFullScreenGround` paints the
    /// page colour there.
    static func letWallpaperShow(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = NSColor(white: 0, alpha: 1.0 / 255.0)
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        // contentMinSize counts the clear title bar now; add it back so the paper's minimum stays 980 x 680.
        let titleBar = max(0, window.frame.height - window.contentLayoutRect.height)
        window.contentMinSize = NSSize(width: 980, height: 680 + titleBar)
        hideTitlebarDecoration(window)
    }

    /// The system lights a 1 px edge along the top of a titled window through its title bar decoration view. Over
    /// a clear ground that edge floats above the paper as a stray hairline (seen in the macOS 15 and 26
    /// captures). The view is found by name and kept hidden, so an OS that drops it makes this a no-op.
    static func hideTitlebarDecoration(_ window: NSWindow) {
        func walk(_ view: NSView) {
            for child in view.subviews {
                if String(describing: type(of: child)).contains("TitlebarDecoration") {
                    if !child.isHidden { child.isHidden = true }
                } else {
                    walk(child)
                }
            }
        }
        if let frame = window.contentView?.superview { walk(frame) }
    }

    @objc private func windowChromeChanged(_ notification: Notification) {
        if let window { Self.hideTitlebarDecoration(window) }
    }

    @objc private func willEnterFullScreen(_ notification: Notification) { container.setFullScreenGround(true) }

    /// Edit 菜单的 Undo/Redo 是 nil-target 条目：AppKit 需要一个实现 undo:/redo: 的响应者，否则条目永远
    /// 灰着、⌘Z 在许可输入框里什么都不做。文本框的字段编辑器把自己的编辑记在自己的 undo manager 上，
    /// 这里只把命令转给它；房间不参与（append-only 关掉了 undo，canUndo 为假，条目保持灰着）（D-082）。
    @objc func undo(_ sender: Any?) { firstResponderUndoManager?.undo() }
    @objc func redo(_ sender: Any?) { firstResponderUndoManager?.redo() }

    private var firstResponderUndoManager: UndoManager? {
        guard let editor = window?.firstResponder as? NSTextView, editor.allowsUndo else { return nil }
        return editor.undoManager
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        applyFocusMode()
    }

    // MARK: - Routing

    private func swapToSurface(_ surface: Surface) {
        // 只在常驻容器内切换子 VC；不碰窗口尺寸、不换 contentViewController，故无 resize / 0x0 / 递归 layout。
        container.show(surface)
        applyFocusMode()
    }

    private func armSurfaceObservation() {
        withObservationTracking { [weak self] in
            _ = self?.appState.selectedSurface
        } onChange: { [weak self] in
            // Observation 回调可能在任意线程触发；路由切换必须回到主线程。
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.swapToSurface(self.appState.selectedSurface)
                self.armSurfaceObservation()
            }
        }
    }

    private func armThemeObservation() {
        withObservationTracking { [weak self] in
            _ = self?.appState.settings.theme
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyTheme()
                self.armThemeObservation()
            }
        }
    }

    private func armFocusObservation() {
        withObservationTracking { [weak self] in
            _ = self?.appState.settings.focusMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyFocusMode()
                self.armFocusObservation()
            }
        }
    }

    private func applyFocusMode() {
        guard let window else { return }
        let shouldFillScreen = appState.settings.focusMode && appState.selectedSurface == .session
        guard window.styleMask.contains(.fullScreen) != shouldFillScreen else { return }
        if !shouldFillScreen { programmaticFullScreenExitPending = true }
        window.toggleFullScreen(nil)
    }

    @objc private func didExitFullScreen(_ notification: Notification) {
        if let window { Self.hideTitlebarDecoration(window) }
        container.setFullScreenGround(false)
        if programmaticFullScreenExitPending {
            programmaticFullScreenExitPending = false
            if appState.selectedSurface == .session && appState.settings.focusMode { applyFocusMode() }
            return
        }
        guard appState.selectedSurface == .session, appState.settings.focusMode else { return }
        appState.updateFocusMode(false)
    }

    private func applyTheme() {
        switch appState.settings.theme {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// surface -> NSViewController 工厂。Phase 1 全部返回占位 VC；Phase 2+ 逐个分支替换为真实实现。
enum SurfaceFactory {
    @MainActor
    static func makeViewController(surface: Surface, appState: AppState,
                                   updateSettings: (any UpdateSettings)? = nil) -> NSViewController {
        switch surface {
        case .home:     return HomeViewController(appState: appState)
        case .session:  return SessionViewController(appState: appState)
        case .settings: return SettingsViewController(appState: appState, updateSettings: updateSettings)
        case .upgrade:  return UpgradeViewController(appState: appState)
        }
    }
}

// Edit 菜单的 Undo/Redo 由本控制器实现，可用性跟随当前第一响应者的 undo manager。
extension RootWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return firstResponderUndoManager?.canUndo ?? false
        case #selector(redo(_:)): return firstResponderUndoManager?.canRedo ?? false
        default: return true
        }
    }
}
