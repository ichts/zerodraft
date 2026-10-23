/**
 * [INPUT]: BundledFonts (Newsreader human serif) and the macOS system UI font.
 * [OUTPUT]: FirstLineTypography tokens: Newsreader for writing, kept heading and warning numerals, system sans for UI and display headings.
 * [POS]: Native typography layer; matches writeitdown/tokens.css (serif = what you write, sans = the tool).
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 *
 * The machine mono layer is retired from the app chrome. UI labels, buttons, clock, counts, tags and
 * field labels and display headings use the system font so controls stay native; written text and
 * warning numerals use the bundled Newsreader. Accessors are computed because NSFont is not Sendable and fonts are cached.
 */

import AppKit

enum FirstLineTypography {
    static func displayNSFont(size: CGFloat = 34) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }
    static func subtitleNSFont(size: CGFloat = 15) -> NSFont {
        .systemFont(ofSize: size)
    }

    static func writingNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.registeredFont(postScriptName: BundledFonts.newsreaderUprightPostScript, size: size)
    }

    static func writingItalicNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.registeredFont(postScriptName: BundledFonts.newsreaderItalicPostScript, size: size)
    }

    /// Newsreader 500, the live kept heading weight.
    static func writingMediumNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.registeredFont(postScriptName: BundledFonts.newsreaderMediumPostScript, size: size)
    }

    /// Machine-voice label text with the live trial's tracking (0.02-0.04 em).
    static func trackedText(_ text: String, font: NSFont, color: NSColor, kernEm: CGFloat,
                            lineHeightMultiple: CGFloat = 1.6) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = lineHeightMultiple
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: font.pointSize * kernEm,
            .paragraphStyle: paragraph,
        ])
    }

    // Tool layer: macOS system sans.
    static var uiNSFont: NSFont { .systemFont(ofSize: 15) }
    static var uiSemiboldNSFont: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
    static var smallNSFont: NSFont { .systemFont(ofSize: 13) }
    static var smallSemiboldNSFont: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
    /// The live trial's machine voice weight for captions, reports and quiet links.
    static var smallMediumNSFont: NSFont { .systemFont(ofSize: 13, weight: .medium) }
    static var fieldNSFont: NSFont { .systemFont(ofSize: 17) }
    static var clockNSFont: NSFont { .monospacedDigitSystemFont(ofSize: 15, weight: .semibold) }
}
