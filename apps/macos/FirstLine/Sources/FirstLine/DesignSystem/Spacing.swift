/**
 * [INPUT]: writeitdown/tokens.css 4-pt spacing and shape tokens.
 * [OUTPUT]: FirstLineSpacing s1-s8 and FirstLineRadius control/sheet/card/stage.
 * [POS]: Shared layout rhythm and corner radii for native surfaces.
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 */

import CoreGraphics

enum FirstLineSpacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64

    // Legacy aliases.
    static let xs = s2
    static let sm = s4
    static let md = s6
    static let lg = s8
    static let xl: CGFloat = 96
}

enum FirstLineRadius {
    static let control: CGFloat = 8
    static let sheet: CGFloat = 16
    static let card: CGFloat = 22
    static let stage: CGFloat = 28
}
