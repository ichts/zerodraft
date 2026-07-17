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
        VStack(spacing: FirstLineSpacing.md) {
            Text("The draft is gone.")
                .font(FirstLineTypography.title)
                .foregroundStyle(FirstLineColors.danger)

            Text("Eight seconds of silence. That is the rule.")
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
        }
        .padding(FirstLineSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
