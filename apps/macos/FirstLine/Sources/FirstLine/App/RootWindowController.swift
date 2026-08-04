/**
 * [INPUT]: 依赖 AppKit、Observation、App/AppState、App/Surfaces 下的占位 VC、DesignSystem/Colors
 * [OUTPUT]: RootWindowController - 主窗口 + surface 路由（selectedSurface -> contentViewController）
 * [POS]: FirstLine 重写 Phase 1 窗口壳与路由真相源；退役 SwiftUI RootView，把 AppState.selectedSurface
 *        映射到占位 NSViewController，并应用 theme 与最小尺寸契约。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 路由：本控制器观察两个信号：
 *   1) selectedSurface -> 换 contentViewController；
 *   2) sessionEngine.phase -> 当变为 .failure/.success 时把它写回 selectedSurface，接管退役
 *      SwiftUI RootView.onChange(of: phase) 的确切职责（AppState.handleEngineStateChange
 *      只做持久化(success)/aftermath(failure)/idle->Home，不设 failure/success 的 surface）。
 * Observation 的 withObservationTracking 只触发一次回调，因此在回调里重新 arm 观察实现持续跟踪。
 */

import AppKit
import Observation

@MainActor
final class RootWindowController: NSWindowController {
    let appState: AppState

    init(appState: AppState) {
        self.appState = appState

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "First Line"
        window.contentMinSize = NSSize(width: 980, height: 680)
        window.center()

        super.init(window: window)
        applyTheme()
        swapToSurface(appState.selectedSurface)
        armSurfaceObservation()
        armPhaseObservation()
        armThemeObservation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Routing

    private func swapToSurface(_ surface: Surface) {
        // Phase 1 占位 VC 每次新建；Phase 2 起按 surface 复用（尤其 session 的生命周期）。
        let vc = SurfaceFactory.makeViewController(surface: surface, appState: appState)
        guard let window else { return }
        // Preserve the outer window frame across controller assignment. AppKit otherwise sizes
        // a zero-intrinsic success/failure root down to 0x0 before Auto Layout gets its first pass.
        let preservedFrame = window.frame
        let root = vc.view
        root.frame = window.contentView?.bounds
            ?? NSRect(origin: .zero, size: window.contentLayoutRect.size)
        root.translatesAutoresizingMaskIntoConstraints = true
        root.autoresizingMask = [.width, .height]
        window.contentViewController = vc
        window.setFrame(preservedFrame, display: true)
        root.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
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

    // engine.phase -> selectedSurface：接管退役 RootView.onChange(of: phase) 的 failure/success 路由。
    // 只在 phase 真正变为 .failure/.success 时写一次；set 相同值不触发循环（surface 等值时不写）。
    private func armPhaseObservation() {
        withObservationTracking { [weak self] in
            _ = self?.appState.sessionEngine.phase
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.appState.sessionEngine.phase {
                case .failure:
                    if self.appState.selectedSurface != .failure {
                        self.appState.selectedSurface = .failure
                    }
                case .success:
                    if self.appState.selectedSurface != .success {
                        self.appState.selectedSurface = .success
                    }
                default:
                    break
                }
                self.armPhaseObservation()
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
    static func makeViewController(surface: Surface, appState: AppState) -> NSViewController {
        switch surface {
        case .home:     return HomeViewController(appState: appState)
        case .session:  return SessionViewController(appState: appState)
        case .failure:  return FailureViewController(appState: appState)
        case .success:  return SuccessViewController(appState: appState)
        case .library:  return LibraryViewController(appState: appState)
        case .settings: return SettingsViewController(appState: appState)
        case .upgrade:  return UpgradeViewController(appState: appState)
        }
    }
}
