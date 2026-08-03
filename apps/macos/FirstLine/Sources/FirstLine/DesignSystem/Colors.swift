/**
 * [INPUT]: Flood design-system color values (DESIGN.md)
 * [OUTPUT]: FirstLineColors tokens; canvas/paper/ink/dim/faint/danger, with ui/uiLight aliases.
 *           Each token exposes both a SwiftUI Color and the underlying NSColor for AppKit consumption.
 * [POS]: FirstLine design-token layer; red is danger-only, green does not exist in this product
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * Flood values: canvas #f1f0eb, paper #ffffff, ink #17150f, dim #6b665b, faint #b3ada0,
 * danger #c8392f. Dark-mode values are adaptive approximations of the light Flood palette.
 *
 * Phase 0 decoupling: each token builds its NSColor through a shared provider so the SwiftUI
 * Color wrapper and the AppKit NSColor accessor resolve to the identical adaptive color. The
 * NSColor accessors are computed because NSColor is not Sendable; NSColor dynamic providers
 * are cheap and cached internally by AppKit.
 */

import AppKit
import SwiftUI

enum FirstLineColors {
    // Canvas: neutral bone background. Never parchment.
    static var canvasNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 21 / 255, green: 20 / 255, blue: 15 / 255, alpha: 1)
                : NSColor(srgbRed: 241 / 255, green: 240 / 255, blue: 235 / 255, alpha: 1)
        }
    }
    static let canvas = Color(nsColor: canvasNSColor)

    // Paper: the only clean white writing surface.
    static var paperNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 28 / 255, green: 26 / 255, blue: 21 / 255, alpha: 1)
                : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }
    static let paper = Color(nsColor: paperNSColor)

    // Ink: primary text color, warm near-black.
    static var inkNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 236 / 255, green: 233 / 255, blue: 226 / 255, alpha: 1)
                : NSColor(srgbRed: 23 / 255, green: 21 / 255, blue: 15 / 255, alpha: 1)
        }
    }
    static let ink = Color(nsColor: inkNSColor)

    // Dim: secondary text.
    static var dimNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 138 / 255, green: 132 / 255, blue: 122 / 255, alpha: 1)
                : NSColor(srgbRed: 107 / 255, green: 102 / 255, blue: 91 / 255, alpha: 1)
        }
    }
    static let dim = Color(nsColor: dimNSColor)

    // Faint: low-contrast borders and marks.
    static var faintNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 70 / 255, green: 66 / 255, blue: 59 / 255, alpha: 1)
                : NSColor(srgbRed: 179 / 255, green: 173 / 255, blue: 160 / 255, alpha: 1)
        }
    }
    static let faint = Color(nsColor: faintNSColor)

    // Danger: reserved for danger and deletion-adjacent marks only. Exactly #c8392f.
    static var dangerNSColor: NSColor {
        NSColor(name: nil) { _ in
            NSColor(srgbRed: 200 / 255, green: 57 / 255, blue: 47 / 255, alpha: 1)
        }
    }
    static let danger = Color(nsColor: dangerNSColor)

    // Backward-compatible aliases mapping older token names onto the Flood vocabulary.
    static let ui = dim
    static let uiLight = faint
    static var uiNSColor: NSColor { dimNSColor }
    static var uiLightNSColor: NSColor { faintNSColor }

    // Deprecated alias: kept until UpgradeView/SessionView references migrate; never green.
    static let success = ink
    static var successNSColor: NSColor { inkNSColor }
}
