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
    /* The writing sheet is the Wheat paper (the captain's 2026-10-27 Wheat decision, superseding D-056's
       Note tone). Its roles are measured against the paper's own tone, not against white: every reading
       role clears 7:1, and the completed lines keep D-027's deliberate fade below that floor (D-069), so
       the quiet chrome is its own role and the pen red is deep enough to read on the paper and its wash. */
    static var paperNSColor: NSColor { adaptive(light: 0xE9E2CE, dark: 0x342E24) }
    static var paperQuietNSColor: NSColor { adaptive(light: 0x464746, dark: 0xC1BEB5) }
    static var paperDangerNSColor: NSColor { adaptive(light: 0x63140B, dark: 0xFFC5B2) }
    /// The sheet's warn wash: `color-mix(in oklab, paper 88%, #C8392F)` and its deeper 76% step of the
    /// eighth second, the exact recipe the web paints (`--wash-paper`, `--wash-paper-deep`). The values
    /// are the browser compositor's own output, so both surfaces warm through the same ramp and land on
    /// the same colour instead of the Mac tinting the sheet with a pale pink meant for white.
    static var paperWashNSColor: NSColor { adaptive(light: 0xE8CFBB, dark: 0x453226) }
    static var paperWashDeepNSColor: NSColor { adaptive(light: 0xE6BCA7, dark: 0x573428) }
    /// Per-logical-line history opacity: the current line full, one line up 22 %, two lines up 7 %, older
    /// lines gone (D-027). One fixed ladder for both appearances: a theme switch can never leave a stale
    /// step baked into a completed line (D-069).
    static let paperHistoryOpacities: [CGFloat] = [1, 0.22, 0.07]
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
    static var onInkNSColor: NSColor { adaptive(light: 0xFFFFFF, dark: 0x15140F) }
    static var shadowNSColor: NSColor { adaptive(light: 0x1C1917, dark: 0x000000) }
    static var separatorNSColor: NSColor { hairNSColor }
}
