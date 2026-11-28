/**
 * [INPUT]: writeitdown/tokens.css (D-124: the white and the black paper, one red per mode; values D-130, red D-131) and the window's effective
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
            page: 0xF3F2EF, sheet: 0xFCFCFA, tagBackground: 0xEDEDEA,
            ink: 0x45433D, mute: 0x6E6D68, onInk: 0xFCFCFA,
            hairBase: 0x45433D, hair: 0.12, hairStrong: 0.20,
            red: 0x9A3326, redText: 0x9A3326,
            paper: 0xFCFCFA, paperInk: 0x45433D, paperQuiet: 0x4B4943, paperDanger: 0x9A3326,
            paperWash: 0xF4F3F0, paperWashDeep: 0xEAE9E5,
            paperHairBase: 0x45433D, paperHair: 0.14, paperHairStrong: 0.24,
            history: [1, 0.26, 0.084], shadow: 0x45433D)

        static let black = Palette(
            page: 0x141413, sheet: 0x1C1C1A, tagBackground: 0x232321,
            ink: 0xDCDAD3, mute: 0xA3A29B, onInk: 0x1C1C1A,
            hairBase: 0xDCDAD3, hair: 0.10, hairStrong: 0.18,
            red: 0xEC8878, redText: 0xEC8878,
            paper: 0x1C1C1A, paperInk: 0xDCDAD3, paperQuiet: 0xBDBBB3, paperDanger: 0xEC8878,
            paperWash: 0x232321, paperWashDeep: 0x2A2A27,
            paperHairBase: 0xDCDAD3, paperHair: 0.16, paperHairStrong: 0.30,
            history: [1, 0.172, 0.061], shadow: 0x000000)
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
