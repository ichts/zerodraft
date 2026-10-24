/**
 * [INPUT]: BundledResources bundle fonts + OFL licenses
 * [OUTPUT]: BundledFonts registration + WritingFontCandidate / ChineseFontCandidate writing fonts
 * [POS]: FirstLine writing-font layer; fonts register from the bundle and resolve by PostScript name
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * Flood design-system fonts are bundled (SIL Open Font License, see Resources/OFL-*.txt):
 *   - Newsreader (variable upright + italic): human serif layer
 *   - IBM Plex Mono (Regular): machine mono layer
 *   - Zhuque Fangsong (Regular): CJK fangsong layer
 * The legacy `pitchLight` case name is kept source-compatible but now resolves to bundled
 * Newsreader (latin); `zhuqueFangsong` resolves to bundled Zhuque Fangsong (CJK).
 */

import AppKit
import CoreText
import Foundation
import os

/// Single source of truth for bundled-font registration and PostScript-name lookup.
/// Nonisolated and thread-safe so both the SwiftUI typography layer and the AppKit
/// editor can resolve fonts without depending on MainActor ordering.
enum BundledFonts {
    // PostScript names (name table, nameID 6) of the registered default instances.
    static let newsreaderUprightPostScript = "Newsreader16pt-Regular"
    static let newsreaderMediumPostScript = "NewsreaderRoman-Medium"
    static let newsreaderItalicPostScript = "Newsreader16pt-Italic"
    static let plexMonoRegularPostScript = "IBMPlexMono-Regular"
    static let zhuquePostScript = "ZhuqueFangsong-Regular"

    // Resource basenames (without extension) shipped under Resources/.
    private static let fontResources = [
        "Newsreader-Variable",
        "Newsreader-Italic-Variable",
        "IBMPlexMono-Regular",
        "ZhuqueFangsong-Regular",
    ]

    private static let registrationLock = OSAllocatedUnfairLock(initialState: false)

    /// Registers every bundled font into the process exactly once. Idempotent.
    static func ensureRegistered() {
        registrationLock.withLock { done in
            guard !done else { return }
            for resource in fontResources {
                guard let url = BundledResources.bundle.url(forResource: resource, withExtension: "ttf") else {
                    continue
                }
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            }
            done = true
        }
    }

    /// Resolves a registered font by PostScript name, registering first if needed.
    /// Returns nil only if the named instance is not present after registration.
    static func registeredFont(postScriptName: String, size: CGFloat) -> NSFont? {
        ensureRegistered()
        return NSFont(name: postScriptName, size: size)
    }
}

/// Latin writing font for the session editor.
/// `.pitchLight` is a deprecated label retained for source compatibility:
/// it previously resolved to an unbundled Klim Pitch Light test font and now
/// resolves to bundled Newsreader (Flood human layer).
enum WritingFontCandidate: String, CaseIterable, Identifiable, Hashable {
    case pitchLight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pitchLight:
            "Newsreader"
        }
    }

    @MainActor
    var isAvailable: Bool {
        return font(size: 12) != nil
    }

    @MainActor
    func font(size: CGFloat) -> NSFont? {
        return BundledFonts.registeredFont(postScriptName: BundledFonts.newsreaderUprightPostScript, size: size)
    }

    @MainActor
    func punctuationFont(size: CGFloat) -> NSFont? {
        font(size: size)
    }

    /// The writing face plus the bundled CJK cascade. The room and the kept sheet
    /// must use the same fallback, or Chinese glyphs change face and apparent
    /// leading between the two surfaces.
    @MainActor
    func fontWithCJKFallback(size: CGFloat) -> NSFont? {
        guard let base = font(size: size) else { return nil }
        guard let cjk = ChineseFontCandidate.zhuqueFangsong.font(size: size) else { return base }
        let descriptor = base.fontDescriptor.addingAttributes([
            .cascadeList: [cjk.fontDescriptor],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

/// CJK writing font for the session editor (fangsong, used as a cascade fallback).
enum ChineseFontCandidate: String, CaseIterable, Identifiable, Hashable {
    case zhuqueFangsong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zhuqueFangsong:
            "Zhuque Fangsong"
        }
    }

    @MainActor
    var isAvailable: Bool {
        return font(size: 12) != nil
    }

    @MainActor
    func font(size: CGFloat) -> NSFont? {
        return BundledFonts.registeredFont(postScriptName: BundledFonts.zhuquePostScript, size: size)
    }
}
