/**
 * [INPUT]: 依赖 AppState 和 DesignSystem token
 * [OUTPUT]: 提供 HomeView 极简启动页和 Mac trial 状态
 * [POS]: FirstLine 的 Home launch gate，负责说明规则、选择时长、展示 trial 状态并启动 session
 * [PROTOCOL]: 变更时更新此头部和 FirstLine/CLAUDE.md
 */

import SwiftUI

private struct DurationOption: Identifiable {
    let seconds: TimeInterval

    var id: TimeInterval { seconds }
    var label: String { "\(Int(seconds / 60)) min" }
}

struct HomeView: View {
    @Bindable var appState: AppState

    private let options = [180.0, 300.0, 600.0, 900.0, 1500.0].map(DurationOption.init)

    var body: some View {
        VStack(spacing: FirstLineSpacing.md) {
            VStack(spacing: FirstLineSpacing.sm) {
                Text("First Line")
                    .font(FirstLineTypography.title)
                    .foregroundStyle(FirstLineColors.ink)

                Text("The first draft only moves forward.")
                    .font(FirstLineTypography.tagline)
                    .foregroundStyle(FirstLineColors.ui)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: FirstLineSpacing.xs) {
                Text("Stop for 8 seconds and the page clears.")
                    .font(FirstLineTypography.body)
                    .foregroundStyle(FirstLineColors.ink)

                Text("No delete. No paste. No undo.")
                    .font(FirstLineTypography.microcopy)
                    .foregroundStyle(FirstLineColors.ui)
            }
            .multilineTextAlignment(.center)

            Text(appState.trialStatusText)
                .font(FirstLineTypography.microcopy)
                .foregroundStyle(appState.isTrialExhausted ? FirstLineColors.danger : FirstLineColors.ui)

            VStack(spacing: FirstLineSpacing.xs) {
                Text("Choose a sprint")
                    .font(FirstLineTypography.microcopy)
                    .foregroundStyle(FirstLineColors.ui)

                HStack(spacing: FirstLineSpacing.sm) {
                    ForEach(options) { option in
                        Button(action: { appState.selectedDuration = option.seconds }) {
                            Text(option.label)
                                .font(FirstLineTypography.microcopy)
                                .foregroundStyle(
                                    appState.selectedDuration == option.seconds
                                        ? FirstLineColors.ink
                                        : FirstLineColors.ui.opacity(0.6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(appState.isTrialExhausted ? "Unlock to keep writing" : "Start writing") {
                appState.startSession()
            }
            .buttonStyle(FirstLinePrimaryButtonStyle())
        }
        .padding(FirstLineSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
