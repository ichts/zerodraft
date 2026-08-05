/**
 * [INPUT]: Flood design-system color values (DESIGN.md)
 * [OUTPUT]: FirstLineColors NSColor tokens; canvas/paper/ink/dim/faint/danger, with ui/uiLight aliases.
 * [POS]: FirstLine design-token layer (AppKit-native); red is danger-only, green does not exist in this product
 * [PROTOCOL]: 变更时更新此头部
 *
 * Flood values: canvas #f1f0eb, paper #ffffff, ink #17150f, dim #6b665b, faint #b3ada0,
 * danger #c8392f. Dark-mode values are adaptive approximations of the light Flood palette.
 *
 * SwiftUI Color wrappers were retired with the SwiftUI shell; all surfaces now consume the
 * NSColor accessors directly. The accessors are computed because NSColor is not Sendable;
 * NSColor dynamic providers are cheap and cached internally by AppKit.
 */

import AppKit

enum FirstLineColors {
    // Canvas: neutral bone background. Never parchment.
    static var canvasNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 21 / 255, green: 20 / 255, blue: 15 / 255, alpha: 1)
                : NSColor(srgbRed: 241 / 255, green: 240 / 255, blue: 235 / 255, alpha: 1)
        }
    }

    // Paper: the only clean white writing surface.
    static var paperNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 28 / 255, green: 26 / 255, blue: 21 / 255, alpha: 1)
                : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    // Ink: primary text color, warm near-black.
    static var inkNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 236 / 255, green: 233 / 255, blue: 226 / 255, alpha: 1)
                : NSColor(srgbRed: 23 / 255, green: 21 / 255, blue: 15 / 255, alpha: 1)
        }
    }

    // Dim: secondary text.
    static var dimNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 138 / 255, green: 132 / 255, blue: 122 / 255, alpha: 1)
                : NSColor(srgbRed: 107 / 255, green: 102 / 255, blue: 91 / 255, alpha: 1)
        }
    }

    // Faint: low-contrast borders and marks.
    static var faintNSColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 70 / 255, green: 66 / 255, blue: 59 / 255, alpha: 1)
                : NSColor(srgbRed: 179 / 255, green: 173 / 255, blue: 160 / 255, alpha: 1)
        }
    }

    // Danger: reserved for danger and deletion-adjacent marks only. Exactly #c8392f.
    static var dangerNSColor: NSColor {
        NSColor(name: nil) { _ in
            NSColor(srgbRed: 200 / 255, green: 57 / 255, blue: 47 / 255, alpha: 1)
        }
    }

    // Backward-compatible aliases mapping older token names onto the Flood vocabulary.
    static var uiNSColor: NSColor { dimNSColor }
    static var uiLightNSColor: NSColor { faintNSColor }

    // Deprecated alias: kept for the success timer color; never green.
    static var successNSColor: NSColor { inkNSColor }
}
