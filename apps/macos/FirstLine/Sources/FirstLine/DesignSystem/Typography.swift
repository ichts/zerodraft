/**
 * [INPUT]: BundledFonts (Newsreader human serif, IBM Plex Mono machine mono)
 * [OUTPUT]: FirstLineTypography font tokens for the Flood design system
 * [POS]: FirstLine typography layer; titles/body in Newsreader, chrome in IBM Plex Mono
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * Flood layers: Newsreader is the human layer (titles, body, tagline); IBM Plex Mono is the
 * machine layer (sidebar labels, microcopy/rules, clock/status, buttons). If a family is not
 * registered yet, each token falls back to the matching system design (serif / monospaced).
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

    private static func humanSerif(size: CGFloat) -> Font {
        if newsreaderAvailable {
            return Font.custom(BundledFonts.newsreaderUprightPostScript, size: size)
        }
        return .system(size: size, design: .serif)
    }

    private static func machineMono(size: CGFloat) -> Font {
        if plexMonoAvailable {
            return Font.custom(BundledFonts.plexMonoRegularPostScript, size: size)
        }
        return .system(size: size, design: .monospaced)
    }

    private static let newsreaderAvailable: Bool = {
        BundledFonts.ensureRegistered()
        return NSFont(name: BundledFonts.newsreaderUprightPostScript, size: 12) != nil
    }()

    private static let plexMonoAvailable: Bool = {
        BundledFonts.ensureRegistered()
        return NSFont(name: BundledFonts.plexMonoRegularPostScript, size: 12) != nil
    }()
}
