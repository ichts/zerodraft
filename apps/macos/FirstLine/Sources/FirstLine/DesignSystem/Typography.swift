/**
 * [INPUT]: 依赖 Landing 的 Charter serif 字体栈和 session 写作字体
 * [OUTPUT]: 提供 FirstLineTypography 字体 token，UI 层用 Charter 对齐 Landing
 * [POS]: FirstLine 原生壳子的排版层，统一 web/native 视觉语言
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

enum FirstLineTypography {
    // UI layer: Charter matches Landing's --font-body stack
    static let title = Font.custom("Charter", size: 32)
    static let tagline = Font.custom("Charter", size: 18)
    static let body = Font.custom("Charter", size: 18)
    static let sidebar = Font.system(size: 14, weight: .medium, design: .default)
    static let microcopy = Font.custom("Charter", size: 13)
    static let buttonLabel = Font.custom("Charter", size: 15)

    // Session chrome: stays neutral, writing editor applies Pitch Light separately
    static let sessionStatus = Font.system(size: 11, weight: .regular, design: .monospaced)
}
