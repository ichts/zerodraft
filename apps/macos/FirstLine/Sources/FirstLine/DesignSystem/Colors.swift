/**
 * [INPUT]: writeitdown/site.css light and dark palette
 * [OUTPUT]: Dynamic AppKit colors for wall, paper, ink, chrome, alarm, wash and cut.
 * [POS]: Shared native color tokens; room choreography consumes wash/cut in batch 4.
 * [PROTOCOL]: Keep token values aligned with site.css and check FirstLine/AGENTS.md.
 */

import AppKit

enum FirstLineColors {
    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }

    static var canvasNSColor: NSColor { adaptive(light: 0xd8d2c3, dark: 0x15140f) }
    static var paperNSColor: NSColor { adaptive(light: 0xf7f4ea, dark: 0x211f18) }
    static var inkNSColor: NSColor { adaptive(light: 0x1a1813, dark: 0xece7d9) }
    static var dimNSColor: NSColor { adaptive(light: 0x6f6a5d, dark: 0x8f897a) }
    static var faintNSColor: NSColor { adaptive(light: 0xb3ada0, dark: 0x5c574c) }
    static var dangerNSColor: NSColor { adaptive(light: 0x8f4405, dark: 0xf2a93b) }
    static var washWallNSColor: NSColor { adaptive(light: 0xd1c1ac, dark: 0x2e1712) }
    static var washPaperNSColor: NSColor { adaptive(light: 0xebdfce, dark: 0x3a1c15) }
    static var deepWallNSColor: NSColor { adaptive(light: 0xc6b095, dark: 0x3d1d15) }
    static var deepPaperNSColor: NSColor { adaptive(light: 0xdecab3, dark: 0x4a2318) }

    static var uiNSColor: NSColor { dimNSColor }
    static var uiLightNSColor: NSColor { faintNSColor }
    static var successNSColor: NSColor { inkNSColor }
}
