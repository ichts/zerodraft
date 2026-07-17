/**
 * [INPUT]: 依赖 FirstLineColors 和 SwiftUI ButtonStyle
 * [OUTPUT]: 提供 FirstLine 主按钮与次按钮样式，对齐 Landing 的 control radius
 * [POS]: FirstLine 原生壳子的按钮层级 token
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

struct FirstLinePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FirstLineTypography.buttonLabel)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .foregroundStyle(FirstLineColors.paper)
            .background(FirstLineColors.ink.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FirstLineSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FirstLineTypography.buttonLabel)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .foregroundStyle(FirstLineColors.ink)
            .background(configuration.isPressed ? FirstLineColors.uiLight.opacity(0.5) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FirstLineColors.uiLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
