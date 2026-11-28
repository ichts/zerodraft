import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// The Mac palette is writeitdown.app's own `tokens.css`, read from the file itself: a role changed on the web without
/// the Mac, or the other way round, fails here with the role and both values (D-124). The white paper is the light
/// `.home` block; the black paper is that block with the dark overrides on top, as the cascade applies them.
@MainActor
struct DesignTokenTests {
    private static let tokens: String = {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // FirstLine
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // repository root
            .appendingPathComponent("writeitdown/tokens.css")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }()

    /// The declarations inside the first `selector{ ... }` block of the file.
    private static func block(_ selector: String) -> [String: String] {
        guard let start = tokens.range(of: selector + "{"),
              let end = tokens.range(of: "}", range: start.upperBound..<tokens.endIndex) else { return [:] }
        let text = String(tokens[start.upperBound..<end.lowerBound])
        let pattern = try! NSRegularExpression(pattern: #"(--[a-z0-9-]+)\s*:\s*([^;]+);?"#)
        var values: [String: String] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let name = String(text[Range(match.range(at: 1), in: text)!])
            values[name] = String(text[Range(match.range(at: 2), in: text)!]).trimmingCharacters(in: .whitespaces)
        }
        return values
    }

    private static func declarations(_ paper: TestPaper) -> [String: String] {
        let white = block(":root").merging(block(".home")) { $1 }
        guard paper == .black else { return white }
        let dark = ":root:not([data-theme=\"light\"])"
        return white.merging(block(dark)) { $1 }.merging(block(dark + " .home")) { $1 }
    }

    private static func hex(_ value: String?) -> UInt32? {
        guard let value, value.hasPrefix("#"), value.count == 7 else { return nil }
        return UInt32(value.dropFirst(), radix: 16)
    }

    @Test(arguments: TestPaper.allCases)
    func everyRoleIsTheWebsToken(paper: TestPaper) throws {
        let css = Self.declarations(paper)
        try #require(css["--paper-tone"] != nil, "writeitdown/tokens.css has no \(paper) sheet")
        let palette = paper.palette
        let colours: [(String, UInt32)] = [
            ("--page", palette.page), ("--sheet", palette.sheet), ("--tag-bg", palette.tagBackground),
            ("--ink", palette.ink), ("--mute", palette.mute), ("--on-ink", palette.onInk),
            ("--red", palette.red), ("--red", palette.redText), ("--red", palette.paperDanger),
            ("--paper-tone", palette.paper), ("--ink", palette.paperInk), ("--paper-quiet", palette.paperQuiet),
            ("--paper-wash", palette.paperWash), ("--paper-wash-deep", palette.paperWashDeep),
        ]
        for (token, mac) in colours {
            let web = try #require(Self.hex(css[token]), "\(paper) \(token) is \(css[token] ?? "missing")")
            #expect(web == mac, "\(paper) \(token): web \(String(web, radix: 16)), Mac \(String(mac, radix: 16))")
        }
        #expect(css["--paper-history-1"].flatMap(Double.init) == Double(palette.history[1]))
        #expect(css["--paper-history-2"].flatMap(Double.init) == Double(palette.history[2]))
    }

    /// Each role resolves to its paper through the window's appearance alone: aqua shows white, darkAqua black.
    @Test(arguments: TestPaper.allCases)
    func rolesResolveToTheShowingPaper(paper: TestPaper) {
        let palette = paper.palette
        assertPalette(paper.appearance, expected: [
            (FirstLineColors.pageNSColor, palette.page), (FirstLineColors.inkNSColor, palette.ink),
            (FirstLineColors.paperNSColor, palette.paper), (FirstLineColors.paperInkNSColor, palette.paperInk),
            (FirstLineColors.paperQuietNSColor, palette.paperQuiet),
            (FirstLineColors.paperDangerNSColor, palette.paperDanger),
            (FirstLineColors.paperWashNSColor, palette.paperWash),
        ])
        #expect(FirstLineColors.showsBlack(NSAppearance(named: paper.appearance)!) == (paper == .black))
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
