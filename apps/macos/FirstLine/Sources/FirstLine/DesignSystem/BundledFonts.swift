/**
 * [INPUT]: BundledResources bundle fonts (the web's own woff2 files, byte for byte) + OFL licences.
 * [OUTPUT]: BundledFonts - process registration of Allo (eager) and Resource Han Rounded (on the first Chinese
 *           character), Allo at any `wght` with optional tabular figures, and the writing face with its CJK cascade.
 * [POS]: The one font boundary of the app; FirstLineTypography and the editor resolve every face through it.
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * The faces are the ones writeitdown.app serves (D-119, D-120, SIL Open Font License, see Resources/OFL-*.txt):
 *   - Allo (allo-latin.woff2, Latin subset, ROND pinned at 30, opsz 9-32, wght 300-700): every Latin role.
 *   - Resource Han Rounded (resource-han-rounded-gb2312.woff2, GB2312 subset): Chinese, as the writing face's
 *     cascade. Nothing registers it before Chinese input appears, as on the web: a committed Chinese character or
 *     marked text that already shows one. Registering is local and synchronous (~60-80 ms once per launch), so
 *     the first Chinese character is already drawn in it and no drawn character ever changes face (D-109).
 * Weight is set through the `wght` axis only; the optical size follows the point size, as Chromium applies it.
 */

import AppKit
import CoreText
import Foundation
import os

enum BundledFonts {
    /// PostScript names (name table, nameID 6) of the registered default instances.
    static let alloPostScript = "AlloVariable-Regular"
    static let cjkPostScript = "Resource-Han-Rounded-CN-Normal"

    /// The files shipped under Resources/, the same bytes as writeitdown/fonts/.
    static let latinFile = "allo-latin.woff2"
    static let cjkFile = "resource-han-rounded-gb2312.woff2"

    /// The web's weights (writeitdown/tokens.css `--w-*` and the room's own rules).
    enum Weight {
        static let regular: CGFloat = 400
        static let medium: CGFloat = 500
        static let semibold: CGFloat = 600
        static let writing: CGFloat = 410
        static let numeral: CGFloat = 360
        static let display: CGFloat = 540
    }

    /// The characters that ask for the Chinese face, the web room's own test (`room.js` `CJK`).
    static func asksForCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }
    }

    private static let wghtAxis = 0x7767_6874
    private static let latinLock = OSAllocatedUnfairLock(initialState: false)
    private static let cjkLock = OSAllocatedUnfairLock(initialState: false)

    private static func register(_ file: String) {
        let parts = file.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let url = BundledResources.bundle.url(forResource: parts[0], withExtension: parts[1]) else { return }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    /// Registers Allo into the process exactly once. Idempotent and thread-safe.
    static func ensureRegistered() {
        latinLock.withLock { done in
            guard !done else { return }
            register(latinFile)
            done = true
        }
    }

    /// Registers Resource Han Rounded exactly once; a caller that arrives mid-registration waits for it.
    static func ensureCJKRegistered() {
        cjkLock.withLock { done in
            guard !done else { return }
            register(cjkFile)
            done = true
        }
    }

    /// True once the Chinese face is registered; never blocks on a registration in flight.
    static var isCJKRegistered: Bool {
        cjkLock.withLockIfAvailable { $0 } ?? false
    }

    /// Allo at `size` and `weight`, with tabular figures when the role's digits must not move. CoreText names the
    /// instance after its axes (`AlloVariable-Regular_opsz_wght...`), so the family is checked by prefix.
    static func allo(size: CGFloat, weight: CGFloat, tabular: Bool = false) -> NSFont? {
        ensureRegistered()
        var attributes: [NSFontDescriptor.AttributeName: Any] = [
            .name: alloPostScript,
            .variation: [wghtAxis: weight],
        ]
        if tabular {
            attributes[.featureSettings] = [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]]
        }
        guard let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: attributes), size: size),
              font.fontName.hasPrefix(alloPostScript) else { return nil }
        return font
    }

    /// Resource Han Rounded at `size`, registering it first.
    static func cjk(size: CGFloat) -> NSFont? {
        ensureCJKRegistered()
        return NSFont(name: cjkPostScript, size: size)
    }

    /// The writing face: Allo at `weight`, cascading to Resource Han Rounded once Chinese has asked for it. The room
    /// and the kept sheet both take this, so a Chinese glyph keeps one face and one pitch on both.
    static func writing(size: CGFloat, weight: CGFloat = Weight.writing) -> NSFont? {
        guard let base = allo(size: size, weight: weight) else { return nil }
        guard isCJKRegistered, let cjk = NSFont(name: cjkPostScript, size: size) else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [cjk.fontDescriptor]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
