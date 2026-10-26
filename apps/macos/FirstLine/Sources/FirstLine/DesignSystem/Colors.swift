/**
 * [INPUT]: writeitdown/tokens.css v2 (background A light palette + dark palette, same role names)
 * [OUTPUT]: Dynamic AppKit color roles for page, sheet, ink, mute, chrome, hairlines, sheet ring, red pen, wash, on-ink.
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
    /// Plain surfaces: cards, fields, buttons, controls.
    static var sheetNSColor: NSColor { adaptive(light: 0xFFFFFF, dark: 0x26231C) }
    /* The writing sheet is the Note paper (D-056). Its roles are measured against the paper's own
       tone, not against white: every word on it clears 7:1, so the quiet chrome is its own role
       and the pen red is deep enough to read on the paper and on its warn wash. */
    static var paperNSColor: NSColor { adaptive(light: 0xDBE6EC, dark: 0x21272A) }
    static var paperQuietNSColor: NSColor { adaptive(light: 0x464746, dark: 0xB8B5AC) }
    static var paperDangerNSColor: NSColor { adaptive(light: 0x63140B, dark: 0xFFB4A2) }
    /// The sheet's warn wash: `color-mix(in oklab, paper 88%, #C8392F)` and its deeper 76% step of the
    /// eighth second, the exact recipe the web paints (`--wash-paper`, `--wash-paper-deep`). The values
    /// are the browser compositor's own output, so both surfaces warm through the same ramp and land on
    /// the same colour instead of the Mac tinting a blue-grey sheet with a pale pink meant for white.
    static var paperWashNSColor: NSColor { adaptive(light: 0xDDD3D5, dark: 0x352C2C) }
    static var paperWashDeepNSColor: NSColor { adaptive(light: 0xDDC0BE, dark: 0x49302E) }
    /// Per-line history alphas: the ink composited at these stops keeps 9:1 and 7:1 on the paper,
    /// solved from the ink and the sheet tone by `PaperContrastTests`.
    static func paperHistoryAlphas(for appearance: NSAppearance) -> [CGFloat] {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? [0.846, 0.727] : [0.847, 0.769]
    }
    static var inkNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0xECE7D9) }
    static var muteNSColor: NSColor { adaptive(light: 0x6B655C, dark: 0xA39D8E) }
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
