/**
 * [INPUT]: Flood design-system color values (DESIGN.md)
 * [OUTPUT]: FirstLineColors tokens; canvas/paper/ink/dim/faint/danger, with ui/uiLight aliases
 * [POS]: FirstLine design-token layer; red is danger-only, green does not exist in this product
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * Flood values: canvas #f1f0eb, paper #ffffff, ink #17150f, dim #6b665b, faint #b3ada0,
 * danger #c8392f. Dark-mode values are adaptive approximations of the light Flood palette.
 */

import AppKit
import SwiftUI

enum FirstLineColors {
    // Canvas: neutral bone background. Never parchment.
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 21 / 255, green: 20 / 255, blue: 15 / 255, alpha: 1)
            : NSColor(srgbRed: 241 / 255, green: 240 / 255, blue: 235 / 255, alpha: 1)
    })

    // Paper: the only clean white writing surface.
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 28 / 255, green: 26 / 255, blue: 21 / 255, alpha: 1)
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    })

    // Ink: primary text color, warm near-black.
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 236 / 255, green: 233 / 255, blue: 226 / 255, alpha: 1)
            : NSColor(srgbRed: 23 / 255, green: 21 / 255, blue: 15 / 255, alpha: 1)
    })

    // Dim: secondary text.
    static let dim = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 138 / 255, green: 132 / 255, blue: 122 / 255, alpha: 1)
            : NSColor(srgbRed: 107 / 255, green: 102 / 255, blue: 91 / 255, alpha: 1)
    })

    // Faint: low-contrast borders and marks.
    static let faint = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 70 / 255, green: 66 / 255, blue: 59 / 255, alpha: 1)
            : NSColor(srgbRed: 179 / 255, green: 173 / 255, blue: 160 / 255, alpha: 1)
    })

    // Danger: reserved for danger and deletion-adjacent marks only. Exactly #c8392f.
    static let danger = Color(nsColor: NSColor(name: nil) { _ in
        NSColor(srgbRed: 200 / 255, green: 57 / 255, blue: 47 / 255, alpha: 1)
    })

    // Backward-compatible aliases mapping older token names onto the Flood vocabulary.
    static let ui = dim
    static let uiLight = faint

    // Deprecated alias: kept until UpgradeView/SessionView references migrate; never green.
    static let success = ink
}
