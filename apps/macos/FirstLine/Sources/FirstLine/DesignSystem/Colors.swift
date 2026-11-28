/**
 * [INPUT]: writeitdown/tokens.css (D-124: the white and the black paper, one red per mode) and the window's effective
 *          appearance, which follows the system.
 * [OUTPUT]: FirstLineColors - dynamic AppKit roles for the page (page, sheet, ink, mute, chrome, hairlines, sheet ring,
 *           red, on-ink) and for the writing sheet (paper tone, paper ink, quiet, the numeral red, wash, deep wash,
 *           paper hairs, history steps), plus FirstLineColors.Palette, the one table every role reads.
 * [POS]: Shared native colour tokens for every surface and the room; no parallel palette.
 * [PROTOCOL]: Keep values aligned with writeitdown/tokens.css (DesignTokenTests reads it) and check FirstLine/AGENTS.md.
 *
 * How a role finds its paper: aqua shows the white paper, darkAqua the black one (D-124). The app never sets an
 * appearance of its own, so the system's choice is the only switch and AppKit repaints on it.
 */

import AppKit

enum FirstLineColors {
    /// One paper's values, `tokens.css` verbatim. Alphas are the token's own; colours are sRGB hex.
    struct Palette: Sendable {
        let page: UInt32, sheet: UInt32, tagBackground: UInt32
        let ink: UInt32, mute: UInt32, onInk: UInt32
        /// `--hair` and `--hair-2`: the ink-side colour at its alpha.
        let hairBase: UInt32, hair: CGFloat, hairStrong: CGFloat
        let red: UInt32, redText: UInt32
        let paper: UInt32, paperInk: UInt32, paperQuiet: UInt32, paperDanger: UInt32
        let paperWash: UInt32, paperWashDeep: UInt32
        let paperHairBase: UInt32, paperHair: CGFloat, paperHairStrong: CGFloat
        /// `--paper-history-1/2`: the two steps of the lines above the live one (D-092).
        let history: [CGFloat]
        let shadow: UInt32

        static let white = Palette(
            page: 0xF7F7F5, sheet: 0xFFFFFF, tagBackground: 0xF2F2F0,
            ink: 0x1C1917, mute: 0x6B655C, onInk: 0xFFFFFF,
            hairBase: 0x1C1917, hair: 0.10, hairStrong: 0.16,
            red: 0xB00C15, redText: 0xB00C15,
            paper: 0xFFFFFF, paperInk: 0x1C1917, paperQuiet: 0x3F3B36, paperDanger: 0xB00C15,
            paperWash: 0xF2F2F2, paperWashDeep: 0xE6E6E6,
            paperHairBase: 0x1C1917, paperHair: 0.12, paperHairStrong: 0.22,
            history: [1, 0.22, 0.07], shadow: 0x1C1917)

        static let black = Palette(
            page: 0x000000, sheet: 0x111111, tagBackground: 0x1B1B1B,
            ink: 0xEDEDED, mute: 0xA3A3A3, onInk: 0x111111,
            hairBase: 0xEDEDED, hair: 0.10, hairStrong: 0.18,
            red: 0xFF453A, redText: 0xFF453A,
            paper: 0x111111, paperInk: 0xEDEDED, paperQuiet: 0xC2BFB7, paperDanger: 0xFF453A,
            paperWash: 0x1B1B1B, paperWashDeep: 0x262626,
            paperHairBase: 0xEDEDED, paperHair: 0.16, paperHairStrong: 0.30,
            history: [1, 0.17, 0.065], shadow: 0x000000)
    }

    /// Whether an appearance shows the black paper (darkAqua) rather than the white one (aqua).
    static func showsBlack(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func palette(for appearance: NSAppearance) -> Palette {
        showsBlack(appearance) ? .black : .white
    }

    private static func srgb(_ rgb: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }

    private static func role(_ value: @escaping @Sendable (Palette) -> UInt32) -> NSColor {
        NSColor(name: nil) { srgb(value(palette(for: $0))) }
    }

    private static func role(_ value: @escaping @Sendable (Palette) -> (UInt32, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let (rgb, alpha) = value(palette(for: appearance))
            return srgb(rgb, alpha: alpha)
        }
    }

    // MARK: Page roles (`:root`)
    static var pageNSColor: NSColor { role { $0.page } }
    /// Plain surfaces: cards, fields, buttons, controls.
    static var sheetNSColor: NSColor { role { $0.sheet } }
    static var inkNSColor: NSColor { role { $0.ink } }
    static var muteNSColor: NSColor { role { $0.mute } }
    static var chromeNSColor: NSColor { role { $0.mute } }
    static var hairNSColor: NSColor { role { ($0.hairBase, $0.hair) } }
    /// A card's ring: the page hairline, as the web's `--lift` draws it.
    static var sheetRingNSColor: NSColor { hairNSColor }
    static var hairStrongNSColor: NSColor { role { ($0.hairBase, $0.hairStrong) } }
    static var tagBackgroundNSColor: NSColor { role { $0.tagBackground } }
    static var segmentTrackNSColor: NSColor { role { ($0.ink, $0.page == Palette.white.page ? 0.06 : 0.10) } }
    static var redNSColor: NSColor { role { $0.red } }
    /// Red as words: the same one red per paper (D-124).
    static var redTextNSColor: NSColor { role { $0.redText } }
    static var onInkNSColor: NSColor { role { $0.onInk } }
    static var shadowNSColor: NSColor { role { $0.shadow } }
    static var separatorNSColor: NSColor { hairNSColor }

    // MARK: Paper roles (`[data-paper]`)
    /* The writing sheet. Every word on it clears 7:1 against the sheet at the deepest wash, except the dimmed history
       lines and the large warning numeral, which takes the one red at the large-text 3:1 floor (D-124). */
    static var paperNSColor: NSColor { role { $0.paper } }
    static var paperInkNSColor: NSColor { role { $0.paperInk } }
    static var paperQuietNSColor: NSColor { role { $0.paperQuiet } }
    /// The warning numeral's red (`--red`).
    static var paperDangerNSColor: NSColor { role { $0.paperDanger } }
    /// The warn wash and the deeper step of the eighth second (`--paper-wash`, `--paper-wash-deep`).
    static var paperWashNSColor: NSColor { role { $0.paperWash } }
    static var paperWashDeepNSColor: NSColor { role { $0.paperWashDeep } }
    static var paperHairNSColor: NSColor { role { ($0.paperHairBase, $0.paperHair) } }
    static var paperHairStrongNSColor: NSColor { role { ($0.paperHairBase, $0.paperHairStrong) } }

    /// History opacity per line ended by Return, live line first, older lines gone (D-092): the paper's own steps.
    /// These dimmed lines are exempt from the 7:1 rule (`--paper-history-1/2`).
    static func paperHistoryOpacities(for appearance: NSAppearance) -> [CGFloat] {
        palette(for: appearance).history
    }
}
