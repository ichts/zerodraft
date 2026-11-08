/**
 * [INPUT]: 依赖 AppKit、App/AppState、App/RootWindowController 的 SurfaceFactory、Update/UpdateController、DesignSystem/Colors
 * [OUTPUT]: 常驻窗口内容容器（透明底，全屏时才铺 page 色，D-102），原地切换 surface 子 VC 并转发当前房间菜单动作与新篇同步刷新
 * [POS]: FirstLine AppKit 壳的 surface 宿主；Begin（Home -> Session）时把选择器卡片矩形交给房间的 growPaper（D-097）；窗口只设一次尺寸，切 surface 只换子视图，同一 surface
 *        重复 show 不重建（保留房间的瞬态状态如 COPIED），避免每次换 contentViewController 触发的
 *        窗口 resize / 0x0 fitting-size / 递归 layout
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 为什么不每次换 window.contentViewController：那会让 AppKit 按新 VC 的 fitting size 调整窗口，
 * 而 success/failure 的约束根视图 fitting size 会塌成 0x0（窗口显示旧 session 残留快照），任何
 * 在回调里 setFrame 的补救又会引发 re-entrant layout 死循环把机器卡死。这里用子 VC 容器：window
 * 的 contentViewController 是本控制器（只设一次、只 size 一次），show() 只做子 VC 的 add/remove +
 * 视图 autoresize 填充，彻底把窗口尺寸与 surface 解耦。子 VC containment 正确驱动
 * viewDidAppear/viewWillDisappear（session 的焦点获取与 tick Timer 生命周期依赖它）。
 */

import AppKit

@MainActor
final class RootContainerViewController: NSViewController {
    private let appState: AppState
    private let updateSettings: (any UpdateSettings)?
    private var current: NSViewController?
    private var currentSurface: Surface?

    func copyKeptText() { (current as? SessionViewController)?.copyKeptText() }
    func refreshRoom() { (current as? SessionViewController)?.refreshRoom() }

    init(appState: AppState, updateSettings: (any UpdateSettings)? = nil) {
        self.appState = appState
        self.updateSettings = updateSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let canvas = FloodCanvasView(fillColor: .clear)
        canvas.autoresizingMask = [.width, .height]
        self.view = canvas
    }

    /// Full screen has no wallpaper behind the window, so the page colour is the ground there; in a window
    /// the ground is clear and the writer's desktop shows (D-102).
    func setFullScreenGround(_ on: Bool) {
        (view as? FloodCanvasView)?.fillColor = on ? FirstLineColors.pageNSColor : .clear
    }

    /// 切到某个 surface：先挂入新子 VC 的视图（填满容器、随之 autoresize），再摘除旧子 VC。
    /// 只操作子视图，不碰窗口尺寸、不 setFrame 窗口，因此无 resize 抖动、无递归 layout。
    func show(_ surface: Surface) {
        guard surface != currentSurface else { return }
        currentSurface = surface
        let incoming = SurfaceFactory.makeViewController(surface: surface, appState: appState,
                                                        updateSettings: updateSettings)
        addChild(incoming)
        let incomingView = incoming.view
        incomingView.translatesAutoresizingMaskIntoConstraints = true
        incomingView.frame = view.bounds
        incomingView.autoresizingMask = [.width, .height]
        view.addSubview(incomingView)

        // Begin: the room's paper grows out of the picker's card rather than cutting in (D-096).
        if let home = current as? HomeViewController, let room = incoming as? SessionViewController {
            room.growPaper(from: home.cardFrame)
        }

        if let outgoing = current {
            outgoing.view.removeFromSuperview()
            outgoing.removeFromParent()
        }
        current = incoming
    }
}
