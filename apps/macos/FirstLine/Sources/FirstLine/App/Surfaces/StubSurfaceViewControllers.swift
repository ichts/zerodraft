/**
 * [INPUT]: 依赖 AppKit、App/AppState、DesignSystem/Colors
 * [OUTPUT]: Settings/Upgrade/Library 三个 surface 的占位 NSViewController
 * [POS]: FirstLine 重写过渡期占位界面；Home/Session/Failure/Success 已由真实 AppKit controller 替换。
 *        每个剩余 stub 持有 appState、画 bone canvas 背景并居中显示 surface 名，便于确认路由通。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 重写决策：Phase 1 用共享 StubSurfaceViewController 承载全部 surface 的占位实现；真实 controller
 * 落地时逐个移除对应具名 stub，SurfaceFactory 的类型契约保持不变。
 */

import AppKit

@MainActor
class StubSurfaceViewController: NSViewController {
    let appState: AppState
    let surfaceLabel: String

    init(surface: Surface, appState: AppState) {
        self.appState = appState
        self.surfaceLabel = "\(surface.rawValue) (stub)"
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = StubSurfaceView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = FirstLineColors.canvasNSColor.cgColor
        self.view = container

        let label = NSTextField(labelWithString: surfaceLabel)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .medium)
        label.textColor = FirstLineColors.inkNSColor
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }
}

/// 普通 NSView 子类，仅作为 bone canvas 背景容器。
final class StubSurfaceView: NSView {
    override var isFlipped: Bool { false }
}

// MARK: - Concrete surface stub types (Phase 3 replaces these)

// HomeViewController, SessionViewController, FailureViewController and SuccessViewController
// are real AppKit implementations. They are NOT stubs.

@MainActor
final class SettingsViewController: StubSurfaceViewController {
    init(appState: AppState) { super.init(surface: .settings, appState: appState) }
}
@MainActor
final class UpgradeViewController: StubSurfaceViewController {
    init(appState: AppState) { super.init(surface: .upgrade, appState: appState) }
}
@MainActor
final class LibraryViewController: StubSurfaceViewController {
    init(appState: AppState) { super.init(surface: .library, appState: appState) }
}
