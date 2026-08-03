/**
 * [INPUT]: 依赖 AppState、DesignSystem、各 surface 视图
 * [OUTPUT]: 提供 RootView 主导航容器，包含 upgrade surface 路由
 * [POS]: FirstLine 原生壳子的主界面，驱动 session phase 与 trial gate 到主 surface 的跳转；壳子背景为 bone canvas（paper 仅限写作列）
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

struct RootView: View {
    @Bindable var appState: AppState

    var body: some View {
        surfaceView(for: appState.selectedSurface)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FirstLineColors.canvas)
            .onChange(of: appState.sessionEngine.phase) { _, phase in
            switch phase {
            case .failure:
                appState.selectedSurface = .failure
            case .success:
                appState.selectedSurface = .success
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func surfaceView(for surface: Surface) -> some View {
        switch surface {
        case .home:
            HomeView(appState: appState)
        case .session:
            SessionView(appState: appState)
        case .failure:
            FailureView(appState: appState)
        case .success:
            SuccessView(appState: appState)
        case .library:
            LibraryView(appState: appState)
        case .settings:
            SettingsView(appState: appState)
        case .upgrade:
            UpgradeView(appState: appState)
        }
    }
}
