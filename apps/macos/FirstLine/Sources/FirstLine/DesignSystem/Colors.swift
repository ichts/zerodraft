/**
 * [INPUT]: 依赖现有 zerodraft 设计系统的颜色值
 * [OUTPUT]: 提供 FirstLineColors 颜色 token
 * [POS]: FirstLine 原生壳子的设计 token 层
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI
import AppKit

enum FirstLineColors {
    // Kami-inspired: #f5f4ed parchment (was #FAFAF8)
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 
            NSColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1) : 
            NSColor(red: 245 / 255, green: 244 / 255, blue: 237 / 255, alpha: 1)
    })
    
    // Kami-inspired: #141413 warm olive-black (was #1A1A1A)
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 
            NSColor(red: 235 / 255, green: 235 / 255, blue: 235 / 255, alpha: 1) : 
            NSColor(red: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)
    })
    
    static let danger = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 
            NSColor(red: 235 / 255, green: 87 / 255, blue: 87 / 255, alpha: 1) : 
            NSColor(red: 193 / 255, green: 64 / 255, blue: 61 / 255, alpha: 1)
    })
    
    static let success = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 
            NSColor(red: 87 / 255, green: 166 / 255, blue: 90 / 255, alpha: 1) : 
            NSColor(red: 46 / 255, green: 89 / 255, blue: 48 / 255, alpha: 1)
    })
    
    static let ui = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 
            NSColor(red: 110 / 255, green: 110 / 255, blue: 110 / 255, alpha: 1) : 
            NSColor(red: 139 / 255, green: 139 / 255, blue: 139 / 255, alpha: 1)
    })
    
    static let uiLight = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 
            NSColor(red: 60 / 255, green: 60 / 255, blue: 60 / 255, alpha: 1) : 
            NSColor(red: 212 / 255, green: 212 / 255, blue: 212 / 255, alpha: 1)
    })
}
