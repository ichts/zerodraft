/**
 * [INPUT]: BundledFonts (Newsreader human serif, IBM Plex Mono machine mono)
 * [OUTPUT]: FirstLineTypography font tokens for the Flood design system.
 *           Each token exposes both a SwiftUI Font and the underlying NSFont for AppKit consumption.
 * [POS]: FirstLine typography layer; titles/body in Newsreader, chrome in IBM Plex Mono
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * Flood layers: Newsreader is the human layer (titles, body, tagline); IBM Plex Mono is the
 * machine layer (sidebar labels, microcopy/rules, clock/status, buttons). If a family is not
 * registered yet, each token falls back to the matching system design (serif / monospaced).
 *
 * Phase 0 decoupling: the NSFont builders are the source of truth; the SwiftUI Font tokens
 * reuse them so AppKit surfaces resolve the exact same family/size with the same fallback.
 */

import AppKit
import SwiftUI

enum FirstLineTypography {
    // Human layer: bundled Newsreader.
    static let title = humanSerif(size: 32)
    static let tagline = humanSerif(size: 18)
    static let body = humanSerif(size: 18)

    // Machine layer: bundled IBM Plex Mono.
    static let sidebar = machineMono(size: 14)
    static let microcopy = machineMono(size: 13)
    static let buttonLabel = machineMono(size: 15)
    static let sessionStatus = machineMono(size: 11)

    // AppKit accessors (same family/size/fallback as the SwiftUI Font tokens above).
    // Computed, because NSFont is not Sendable and the bundled font is cached by the font registry.
    static var titleNSFont: NSFont? { humanSerifNSFont(size: 32) }
    static var taglineNSFont: NSFont? { humanSerifNSFont(size: 18) }
    static var bodyNSFont: NSFont? { humanSerifNSFont(size: 18) }

    static var sidebarNSFont: NSFont? { machineMonoNSFont(size: 14) }
    static var microcopyNSFont: NSFont? { machineMonoNSFont(size: 13) }
    static var buttonLabelNSFont: NSFont? { machineMonoNSFont(size: 15) }
    static var sessionStatusNSFont: NSFont? { machineMonoNSFont(size: 11) }

    private static func humanSerif(size: CGFloat) -> Font {
        if let nsFont = humanSerifNSFont(size: size) {
            return Font(nsFont)
        }
        return .system(size: size, design: .serif)
    }

    private static func machineMono(size: CGFloat) -> Font {
        if let nsFont = machineMonoNSFont(size: size) {
            return Font(nsFont)
        }
        return .system(size: size, design: .monospaced)
    }

    private static func humanSerifNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.registeredFont(postScriptName: BundledFonts.newsreaderUprightPostScript, size: size)
    }

    private static func machineMonoNSFont(size: CGFloat) -> NSFont? {
        BundledFonts.registeredFont(postScriptName: BundledFonts.plexMonoRegularPostScript, size: size)
    }
}
