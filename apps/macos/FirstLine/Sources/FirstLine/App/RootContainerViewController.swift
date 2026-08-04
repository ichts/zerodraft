/**
 * [INPUT]: 依赖 AppKit、App/AppState、App/RootWindowController 的 SurfaceFactory、DesignSystem/Colors
 * [OUTPUT]: RootContainerViewController - 常驻窗口内容控制器，用子 VC 承载各 surface 并原地切换
 * [POS]: FirstLine AppKit 壳的 surface 宿主；窗口只设一次尺寸，切 surface 只换子视图，避免每次
 *        换 contentViewController 触发的窗口 resize / 0x0 fitting-size / 递归 layout
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
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
    private var current: NSViewController?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let canvas = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        canvas.autoresizingMask = [.width, .height]
        self.view = canvas
    }

    /// 切到某个 surface：先挂入新子 VC 的视图（填满容器、随之 autoresize），再摘除旧子 VC。
    /// 只操作子视图，不碰窗口尺寸、不 setFrame 窗口，因此无 resize 抖动、无递归 layout。
    func show(_ surface: Surface) {
        let incoming = SurfaceFactory.makeViewController(surface: surface, appState: appState)
        addChild(incoming)
        let incomingView = incoming.view
        incomingView.translatesAutoresizingMaskIntoConstraints = true
        incomingView.frame = view.bounds
        incomingView.autoresizingMask = [.width, .height]
        view.addSubview(incomingView)

        if let outgoing = current {
            outgoing.view.removeFromSuperview()
            outgoing.removeFromParent()
        }
        current = incoming
    }
}
