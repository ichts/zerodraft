import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// The Mac palette is the three-paper token set kept in `design/paper-tokens.css`, read from the file itself: a role
/// changed in the file without the Mac, or the other way round, fails here with the role and both values (D-120).
/// The file is the v3 set writeitdown.app shipped under D-119; the web landing went back to its earlier look (D-121).
@MainActor
struct DesignTokenTests {
    private static let tokens: String = {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // FirstLine
            .appendingPathComponent("design/paper-tokens.css")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }()

    /// The declarations of one mode's block: Lamp is `:root`, the others `:root[data-theme="…"]`, each inheriting
    /// what it leaves out from Lamp, as the cascade does.
    private static func declarations(_ mode: PaperMode) -> [String: String] {
        func block(_ selector: String) -> [String: String] {
            guard let start = tokens.range(of: selector + "{"),
                  let end = tokens.range(of: "\n}", range: start.upperBound..<tokens.endIndex) else { return [:] }
            var values: [String: String] = [:]
            let body = tokens[start.upperBound..<end.lowerBound]
            let pattern = try! NSRegularExpression(pattern: #"(--[a-z0-9-]+)\s*:\s*([^;]+);"#)
            let text = String(body)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let name = String(text[Range(match.range(at: 1), in: text)!])
                let value = String(text[Range(match.range(at: 2), in: text)!]).trimmingCharacters(in: .whitespaces)
                values[name] = value
            }
            return values
        }
        let lamp = block(":root")
        guard mode != .lamp else { return lamp }
        return lamp.merging(block(":root[data-theme=\"\(mode.rawValue)\"]")) { $1 }
    }

    private static func hex(_ value: String?) -> UInt32? {
        guard let value, value.hasPrefix("#"), value.count == 7 else { return nil }
        return UInt32(value.dropFirst(), radix: 16)
    }

    @Test(arguments: PaperMode.allCases)
    func everyRoleIsTheWebsToken(mode: PaperMode) throws {
        let css = Self.declarations(mode)
        try #require(css["--paper-tone"] != nil, "paper-tokens.css has no \(mode) block")
        let palette = FirstLineColors.Palette.of(mode)
        let colours: [(String, UInt32)] = [
            ("--page", palette.page), ("--sheet", palette.sheet), ("--tag-bg", palette.tagBackground),
            ("--ink", palette.ink), ("--mute", palette.mute), ("--chrome", palette.mute), ("--on-ink", palette.onInk),
            ("--red", palette.red), ("--red-text-small", palette.redText),
            ("--paper-tone", palette.paper), ("--paper-ink", palette.paperInk), ("--paper-quiet", palette.paperQuiet),
            ("--paper-danger", palette.paperDanger), ("--paper-wash", palette.paperWash),
            ("--paper-wash-deep", palette.paperWashDeep),
        ]
        for (token, mac) in colours {
            let web = try #require(Self.hex(css[token]), "\(mode) \(token) is \(css[token] ?? "missing")")
            #expect(web == mac, "\(mode) \(token): web \(String(web, radix: 16)), Mac \(String(mac, radix: 16))")
        }
        #expect(css["--paper-history-1"].flatMap(Double.init) == Double(palette.history[1]))
        #expect(css["--paper-history-2"].flatMap(Double.init) == Double(palette.history[2]))
    }

    /// Each role resolves to its mode through the window's appearance and the stored mode, so one window shows one
    /// mode at a time.
    @Test(arguments: PaperMode.allCases)
    func rolesResolveToTheShowingMode(mode: PaperMode) {
        withPaperMode(mode) { appearance in
            let palette = FirstLineColors.Palette.of(mode)
            assertPalette(appearance, expected: [
                (FirstLineColors.pageNSColor, palette.page), (FirstLineColors.inkNSColor, palette.ink),
                (FirstLineColors.paperNSColor, palette.paper), (FirstLineColors.paperInkNSColor, palette.paperInk),
                (FirstLineColors.paperQuietNSColor, palette.paperQuiet),
                (FirstLineColors.paperDangerNSColor, palette.paperDanger),
                (FirstLineColors.paperWashNSColor, palette.paperWash),
            ])
            #expect(FirstLineColors.mode(for: NSAppearance(named: appearance)!) == mode)
        }
    }

    private func assertPalette(_ appearance: NSAppearance.Name, expected: [(NSColor, UInt32)]) {
        for (token, hex) in expected {
            var actual: [UInt32] = []
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let resolved = token.usingColorSpace(.sRGB)!
                actual = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
                    .map { UInt32(($0 * 255).rounded()) }
            }
            #expect(actual == [(hex >> 16) & 255, (hex >> 8) & 255, hex & 255])
        }
    }
}
