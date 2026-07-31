/**
 * [INPUT]: 依赖 AppState、SessionEngine 和 DesignSystem token
 * [OUTPUT]: 提供 FailureView 失败界面
 * [POS]: Session normal failure surface，不保存失败文本
 * [PROTOCOL]: 变更时更新此头部和 FirstLine/CLAUDE.md
 */

import SwiftUI

struct FailureView: View {
    @Bindable var appState: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(FirstLineColors.danger)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: FirstLineSpacing.sm) {
                    Spacer(minLength: FirstLineSpacing.lg)

                    Text("Draft deleted.")
                        .font(FirstLineTypography.title.weight(.medium))
                        .foregroundStyle(FirstLineColors.ink)

                    Text("You stopped for eight seconds. It joined the pile.")
                        .font(FirstLineTypography.body)
                        .foregroundStyle(FirstLineColors.ui)

                    HStack(spacing: FirstLineSpacing.md) {
                        Button("Try Again") {
                            appState.startSession()
                        }
                        .buttonStyle(FirstLinePrimaryButtonStyle())

                        Button("Back to Home") {
                            appState.goHome()
                        }
                        .buttonStyle(FirstLineSecondaryButtonStyle())
                    }
                    .padding(.top, FirstLineSpacing.xs)

                    Spacer()
                }
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // the joined fossil: first 64 chars of the wiped draft, dead at the margin
            if let fossil = joinedFossil {
                Text(fossil)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FirstLineColors.ink.opacity(0.14))
                    .rotationEffect(.degrees(3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 20)
                    .padding(.bottom, 64)
                    .allowsHitTesting(false)
            }
        }
    }

    private var joinedFossil: String? {
        let text = appState.sessionEngine.wipedText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        return String(text.prefix(64))
    }
}
