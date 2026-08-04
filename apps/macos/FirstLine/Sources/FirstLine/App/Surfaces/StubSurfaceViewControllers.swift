/**
 * [INPUT]: 依赖 AppKit、App/AppState、DesignSystem/Colors
 * [OUTPUT]: 七个 surface 占位 NSViewController（Home/Session/Failure/Success/Settings/Upgrade/Library）
 * [POS]: FirstLine 重写 Phase 1 占位界面；下阶段（Phase 2+）逐个替换为真实 NSViewController。
 *        每个 VC 持有 appState、画 bone canvas 背景并居中显示 surface 名，便于视觉验收确认路由通。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 重写决策：Phase 1 用一个共享 StubSurfaceViewController 承载七个 surface 的占位实现，
 * 七个具名类型（HomeViewController 等）继承它以稳定 surface 工厂的类型契约；Phase 2+ 替换
 * 具名类型的实现时，SurfaceFactory 无需改动。
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

// MARK: - Concrete surface stub types (Phase 2+ replaces these)

@MainActor
final class HomeViewController: StubSurfaceViewController {
    init(appState: AppState) { super.init(surface: .home, appState: appState) }
}
// Note: SessionViewController (Phase 2a), FailureViewController and
// SuccessViewController (Phase 3) are real AppKit implementations in
// Session/*ViewController.swift. They are NOT stubs.

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
