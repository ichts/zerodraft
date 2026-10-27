/**
 * [INPUT]: writeitdown/tokens.css v2 (background A light palette + dark palette, same role names)
 * [OUTPUT]: Dynamic AppKit color roles for page, sheet, ink, mute, paper quiet, chrome, hairlines, sheet ring, red pen, wash, on-ink.
 * [POS]: Shared native color tokens for every surface and the room wash; no parallel palette.
 * [PROTOCOL]: Keep values aligned with writeitdown/tokens.css and check FirstLine/AGENTS.md.
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

    private static func adaptive(light: UInt32, dark: UInt32, lightAlpha: CGFloat, darkAlpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = darkMode ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255,
                           alpha: darkMode ? darkAlpha : lightAlpha)
        }
    }

    // MARK: Roles (background A light, same names in dark)
    static var pageNSColor: NSColor { adaptive(light: 0xF7F7F5, dark: 0x15140F) }
    static var sheetNSColor: NSColor { adaptive(light: 0xFFFFFF, dark: 0x26231C) }
    static var inkNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0xECE7D9) }
    static var muteNSColor: NSColor { adaptive(light: 0x6B655C, dark: 0xA39D8E) }
    /// The sheet's quiet role (`--paper-quiet`): quiet words that sit on the writing sheet and must clear 7:1 on it.
    static var paperQuietNSColor: NSColor { adaptive(light: 0x464746, dark: 0xB8B5AC) }
    static var chromeNSColor: NSColor { adaptive(light: 0x5C564D, dark: 0xA39D8E) }
    static var hairNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0xECE7D9, lightAlpha: 0.10, darkAlpha: 0.10) }
    /// Sheet ring from the approved tokens.swift (ink 7% in light, hair 10% in dark).
    static var sheetRingNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0xECE7D9, lightAlpha: 0.07, darkAlpha: 0.10) }
    static var hairStrongNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0xECE7D9, lightAlpha: 0.16, darkAlpha: 0.18) }
    static var tagBackgroundNSColor: NSColor { adaptive(light: 0xF2F2F0, dark: 0x2E2A22) }
    static var segmentTrackNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0xECE7D9, lightAlpha: 0.06, darkAlpha: 0.10) }
    static var redNSColor: NSColor { adaptive(light: 0xB02A1E, dark: 0xE4604A) }
    static var redSoftNSColor: NSColor { adaptive(light: 0xF6E2DC, dark: 0x3A1C15) }
    static var redDeepNSColor: NSColor { adaptive(light: 0xEBC8BD, dark: 0x4A2318) }
    static var onInkNSColor: NSColor { adaptive(light: 0xFFFFFF, dark: 0x15140F) }
    static var shadowNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0x000000) }
    static var separatorNSColor: NSColor { hairNSColor }
}
