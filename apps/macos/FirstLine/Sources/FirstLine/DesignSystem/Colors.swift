/**
 * [INPUT]: writeitdown/tokens.css v3 (the three paper modes Lamp, Paper and Slate, same role names, D-119) and the
 *          process-wide PaperMode the app applies.
 * [OUTPUT]: FirstLineColors - dynamic AppKit roles for the page (page, sheet, ink, mute, chrome, hairlines, sheet ring,
 *           red, on-ink) and for the writing sheet (paper tone, paper ink, quiet, danger, wash, deep wash, paper hairs,
 *           history steps), plus FirstLineColors.Palette, the one table every role reads.
 * [POS]: Shared native colour tokens for every surface and the room; no parallel palette.
 * [PROTOCOL]: Keep values aligned with writeitdown/tokens.css and check FirstLine/AGENTS.md.
 *
 * How a role finds its mode: the app gives the window the aqua appearance in Paper and darkAqua in Lamp and Slate
 * (D-120), so a role reads Paper on aqua and, on darkAqua, Lamp or Slate from the stored mode. Lamp and Slate share
 * an appearance, so a switch between them is announced by `PaperModeRepaint` instead of by AppKit.
 * The page roles are the page's (`:root`), the paper roles the sheet's (`[data-paper]`): the room draws its words in
 * the paper roles, exactly as the web rebinds `--ink` to `--paper-ink` inside the sheet.
 */

import AppKit
import os

enum FirstLineColors {
    /// One mode's values, `tokens.css` verbatim. Alphas are the token's own; colours are sRGB hex.
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

        static let lamp = Palette(
            page: 0x120D0A, sheet: 0x1E1813, tagBackground: 0x1E1813,
            ink: 0xEFE6D1, mute: 0xB3A690, onInk: 0x1D1712,
            hairBase: 0xE9E2CE, hair: 0.12, hairStrong: 0.24,
            red: 0xE4604A, redText: 0xFF9B88,
            paper: 0xE9E2CE, paperInk: 0x1F1812, paperQuiet: 0x221A14, paperDanger: 0x380904,
            paperWash: 0xE8CFBB, paperWashDeep: 0xE6BCA7,
            paperHairBase: 0x241C16, paperHair: 0.16, paperHairStrong: 0.30,
            history: [1, 0.22, 0.07], shadow: 0x000000)

        static let paper = Palette(
            page: 0xF4F3EF, sheet: 0xFDFDFB, tagBackground: 0xECEBE6,
            ink: 0x1C1917, mute: 0x55514A, onInk: 0xFDFDFB,
            hairBase: 0x1C1917, hair: 0.10, hairStrong: 0.16,
            red: 0xB02A1E, redText: 0xB02A1E,
            paper: 0xFDFDFB, paperInk: 0x1C1917, paperQuiet: 0x3F3B36, paperDanger: 0x63140B,
            paperWash: 0xFAE7E2, paperWashDeep: 0xF6D0C9,
            paperHairBase: 0x1C1917, paperHair: 0.12, paperHairStrong: 0.22,
            history: [1, 0.22, 0.07], shadow: 0x1C1917)

        /// Slate keeps Lamp's reds and sheet shadow (`tokens.css` leaves them inherited).
        static let slate = Palette(
            page: 0x0B0C0D, sheet: 0x17191A, tagBackground: 0x17191A,
            ink: 0xE8E3D7, mute: 0xA29D92, onInk: 0x111315,
            hairBase: 0xC8C4BA, hair: 0.12, hairStrong: 0.24,
            red: 0xE4604A, redText: 0xFF9B88,
            paper: 0x363B3D, paperInk: 0xF7EEDB, paperQuiet: 0xF4EFE6, paperDanger: 0xFFE8DE,
            paperWash: 0x493E3D, paperWashDeep: 0x5A403D,
            paperHairBase: 0xECE6DA, paperHair: 0.16, paperHairStrong: 0.30,
            history: [1, 0.16, 0.05], shadow: 0x000000)

        static func of(_ mode: PaperMode) -> Palette {
            switch mode {
            case .lamp: .lamp
            case .paper: .paper
            case .slate: .slate
            }
        }
    }

    private static let storedMode = OSAllocatedUnfairLock(initialState: PaperMode.lamp)

    /// The mode the app last applied. Only `PaperModeRepaint.apply` writes it.
    static var paperMode: PaperMode {
        get { storedMode.withLock { $0 } }
        set { storedMode.withLock { $0 = newValue } }
    }

    /// The mode an appearance shows: Paper on aqua, the stored dark mode (Lamp or Slate) on darkAqua.
    static func mode(for appearance: NSAppearance) -> PaperMode {
        guard appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua else { return .paper }
        return paperMode == .slate ? .slate : .lamp
    }

    static func palette(for appearance: NSAppearance) -> Palette {
        .of(mode(for: appearance))
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
    static var segmentTrackNSColor: NSColor { role { ($0.ink, $0.page == Palette.paper.page ? 0.06 : 0.10) } }
    static var redNSColor: NSColor { role { $0.red } }
    /// Red as words (D-103): `--red-text-small`, bright enough in the dark modes for small text on the card.
    static var redTextNSColor: NSColor { role { $0.redText } }
    static var onInkNSColor: NSColor { role { $0.onInk } }
    static var shadowNSColor: NSColor { role { $0.shadow } }
    static var separatorNSColor: NSColor { hairNSColor }

    // MARK: Paper roles (`[data-paper]`)
    /* The writing sheet. Every word on it is measured against the sheet's own tone and clears 7:1 at the deepest
       warning in every mode, the dimmed history lines excepted (tokens.css v3). */
    static var paperNSColor: NSColor { role { $0.paper } }
    static var paperInkNSColor: NSColor { role { $0.paperInk } }
    static var paperQuietNSColor: NSColor { role { $0.paperQuiet } }
    static var paperDangerNSColor: NSColor { role { $0.paperDanger } }
    /// The warn wash and the deeper step of the eighth second (`--paper-wash`, `--paper-wash-deep`).
    static var paperWashNSColor: NSColor { role { $0.paperWash } }
    static var paperWashDeepNSColor: NSColor { role { $0.paperWashDeep } }
    static var paperHairNSColor: NSColor { role { ($0.paperHairBase, $0.paperHair) } }
    static var paperHairStrongNSColor: NSColor { role { ($0.paperHairBase, $0.paperHairStrong) } }

    /// History opacity per line ended by Return, live line first, older lines gone (D-092): the mode's own steps.
    /// These dimmed lines are exempt from the 7:1 rule (`--paper-history-1/2`).
    static func paperHistoryOpacities(for appearance: NSAppearance) -> [CGFloat] {
        palette(for: appearance).history
    }
}
