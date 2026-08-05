/**
 * [INPUT]: BundledFonts (Newsreader human serif, IBM Plex Mono machine mono)
 * [OUTPUT]: FirstLineTypography font tokens for the Flood design system (AppKit NSFont).
 * [POS]: FirstLine typography layer; titles/body in Newsreader, chrome in IBM Plex Mono
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * Flood layers: Newsreader is the human layer (titles, body, tagline); IBM Plex Mono is the
 * machine layer (sidebar labels, microcopy/rules, clock/status, buttons). If a family is not
 * registered yet, each token falls back to the matching system font (serif / monospaced).
 *
 * Accessors are computed, because NSFont is not Sendable and the bundled font is cached by the
 * font registry.
 */

import AppKit

enum FirstLineTypography {
    // Human layer: bundled Newsreader.
    static var titleNSFont: NSFont? { humanSerifNSFont(size: 32) }
    static var taglineNSFont: NSFont? { humanSerifNSFont(size: 18) }
    static var bodyNSFont: NSFont? { humanSerifNSFont(size: 18) }

    // Machine layer: bundled IBM Plex Mono.
    static var sidebarNSFont: NSFont? { machineMonoNSFont(size: 14) }
    static var microcopyNSFont: NSFont? { machineMonoNSFont(size: 13) }
    static var buttonLabelNSFont: NSFont? { machineMonoNSFont(size: 15) }
    static var sessionStatusNSFont: NSFont? { machineMonoNSFont(size: 11) }

    private static func humanSerifNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.registeredFont(postScriptName: BundledFonts.newsreaderUprightPostScript, size: size)
    }

    private static func machineMonoNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.registeredFont(postScriptName: BundledFonts.plexMonoRegularPostScript, size: size)
    }
}
