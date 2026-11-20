/**
 * [INPUT]: BundledFonts (Allo, with Resource Han Rounded as the writing face's Chinese cascade).
 * [OUTPUT]: FirstLineTypography tokens: Allo for every Latin role at the web's weights (writing 410, numeral 360,
 *           display 540, UI 400/500/600, the clock tabular 600); TextSmoothing, the process-wide switch that draws
 *           the web's glyph weight (D-098).
 * [POS]: Native typography layer; matches writeitdown/tokens.css (`--face`, `--face-ui`, `--w-*`, `--t-*`).
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 *
 * One face, as on the web (D-119, D-120): written text, the warning numeral, headings, buttons, labels and the
 * clock are all Allo; only the weight and size say which role a run plays. The system font is the fallback only
 * if the bundled file cannot be registered. Accessors are computed because NSFont is not Sendable and fonts are
 * cached.
 */

import AppKit

/// The web room sets `-webkit-font-smoothing: antialiased`, which draws plain grey-scale glyphs. CoreText on the
/// Mac thickens every stem unless the process turns smoothing off, so the same writing line (Newsreader when measured) carried 31% to 52%
/// more ink on the Mac (measured, D-098). `AppleFontSmoothing = 0` in the app's own preference domain is the
/// long-standing user default for it (Apple does not document it as API, so the ink-unit table in D-098 is the
/// proof, not the key); it must be written before the first window draws text.
enum TextSmoothing {
    static let key = "AppleFontSmoothing"

    static func matchWeb(_ defaults: UserDefaults = .standard) {
        defaults.set(0, forKey: key)
    }
}

enum FirstLineTypography {
    typealias Weight = BundledFonts.Weight

    /// Allo at a role's size and weight; the system font of the nearest weight only if the bundle is broken.
    static func allo(size: CGFloat, weight: CGFloat, tabular: Bool = false) -> NSFont {
        if let font = BundledFonts.allo(size: size, weight: weight, tabular: tabular) { return font }
        let system: NSFont.Weight = weight >= 590 ? .semibold : weight >= 490 ? .medium : .regular
        return tabular ? .monospacedDigitSystemFont(ofSize: size, weight: system) : .systemFont(ofSize: size, weight: system)
    }

    static func displayNSFont(size: CGFloat = 34) -> NSFont {
        allo(size: size, weight: Weight.display)
    }
    static func subtitleNSFont(size: CGFloat = 15) -> NSFont {
        allo(size: size, weight: Weight.regular)
    }

    /// The writing face (Allo 410 with the Chinese cascade once Chinese has asked for it).
    static func writingNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.writing(size: size)
    }

    /// The warning numeral: Allo 360, upright, tabular, so 3, 2 and 1 hold one width (`--w-numeral`).
    static func numeralNSFont(size: CGFloat) -> NSFont {
        allo(size: size, weight: Weight.numeral, tabular: true)
    }

    /// The result headings (`You wrote it down.`, `You stopped.`): Allo 540 (`--w-display`).
    static func writingMediumNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.allo(size: size, weight: Weight.display)
    }

    /// Machine-voice label text with the live trial's tracking (0.02-0.04 em).
    static func trackedText(_ text: String, font: NSFont, color: NSColor, kernEm: CGFloat,
                            lineHeightMultiple: CGFloat = 1.6,
                            fixedLineHeight: Bool = false) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        if fixedLineHeight {
            // Multi-line writing surfaces must use one pitch for every script; a
            // fallback font must not inflate its own lines.
            let lineHeight = font.pointSize * lineHeightMultiple
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.lineHeightMultiple = 1
        } else {
            paragraph.lineHeightMultiple = lineHeightMultiple
        }
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: font.pointSize * kernEm,
            .paragraphStyle: paragraph,
        ])
    }

    // The tool layer: the same face at the web's `--t-ui` 15 and `--t-small` 13.
    static var uiNSFont: NSFont { allo(size: 15, weight: Weight.regular) }
    static var uiSemiboldNSFont: NSFont { allo(size: 15, weight: Weight.semibold) }
    static var smallNSFont: NSFont { allo(size: 13, weight: Weight.regular) }
    static var smallSemiboldNSFont: NSFont { allo(size: 13, weight: Weight.semibold) }
    /// The live trial's machine voice weight for captions, reports and quiet links.
    static var smallMediumNSFont: NSFont { allo(size: 13, weight: Weight.medium) }
    static var fieldNSFont: NSFont { allo(size: 17, weight: Weight.regular) }
    /// The room clock: `600 15px/1`, tabular, so 1:00 and 0:59 hold one width.
    static var clockNSFont: NSFont { allo(size: 15, weight: Weight.semibold, tabular: true) }
}
