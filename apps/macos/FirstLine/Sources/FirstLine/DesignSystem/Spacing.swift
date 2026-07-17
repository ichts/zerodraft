/**
 * [INPUT]: 依赖现有 zerodraft 垂直间距系统
 * [OUTPUT]: 提供 FirstLineSpacing 间距 token
 * [POS]: FirstLine 原生壳子的布局节奏层
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

enum FirstLineSpacing {
    static let xs: Double = 8
    static let sm: Double = 16
    static let md: Double = 32
    static let lg: Double = 64
    static let xl: Double = 96
}
