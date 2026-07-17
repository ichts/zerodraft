/**
 * [INPUT]: 依赖 AppState、SessionEngine 和 DesignSystem token
 * [OUTPUT]: 提供 SuccessView 成功界面
 * [POS]: Session success surface，展示 session 结果并提供复制/丢弃操作
 * [PROTOCOL]: 变更时更新此头部和 FirstLine/CLAUDE.md
 */

import SwiftUI

struct SuccessView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: FirstLineSpacing.md) {
            Text("\(appState.sessionEngine.wordCount) words")
                .font(FirstLineTypography.title)
                .foregroundStyle(FirstLineColors.success)

            ScrollView {
                Text(appState.sessionEngine.text)
                    .font(FirstLineTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 320)
            .frame(maxWidth: 640)

            HStack(spacing: FirstLineSpacing.md) {
                Button("Copy full text") {
                    appState.copySuccessText()
                }
                .buttonStyle(FirstLinePrimaryButtonStyle())

                Button("Discard and start next") {
                    appState.abandonSession()
                }
                .buttonStyle(FirstLineSecondaryButtonStyle())
            }
        }
        .padding(FirstLineSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
