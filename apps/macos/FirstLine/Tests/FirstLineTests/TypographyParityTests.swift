import AppKit
import CoreText
import Foundation
import Testing
@testable import WriteItDown

/// The Mac half of the shared type set (D-057). The web half is
/// `writeitdown/qa/typography.spec.mjs`; both read `writeitdown/qa/shared-type-baseline.json`, so a
/// face, size or tracking change on one surface fails the other surface's test with a readable
/// number instead of a captain noticing that the two do not look alike.
@MainActor
struct TypographyParityTests {
    private struct Role: Decodable {
        let role: String
        let string: String
        let size: CGFloat
        let face: String
        let advancePt: CGFloat
    }

    private struct Baseline: Decodable {
        let tolerance: CGFloat
        let roles: [Role]
    }

    private let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // FirstLineTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // FirstLine

    private func baseline() throws -> Baseline {
        let fixture = packageRoot
            .deletingLastPathComponent()  // macos
            .deletingLastPathComponent()  // apps
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("writeitdown/qa/shared-type-baseline.json")
        return try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: fixture))
    }

    /// The advance the room itself would draw: no kern attribute, so the face's own kerning is live.
    private func advance(_ text: String, font: NSFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// The writing stack the room and the kept sheet share: Allo over Resource Han Rounded, as the room has it once
    /// Chinese has asked for the Chinese face.
    private func writingFont(size: CGFloat) throws -> NSFont {
        BundledFonts.ensureCJKRegistered()
        return try #require(FirstLineTypography.writingNSFont(size: size))
    }

    /// The axes a variable font is drawn at, by four-letter tag.
    private func axes(_ font: NSFont) -> [String: Double] {
        let variation = CTFontCopyVariation(font) as? [Int: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: variation.map { tag, value in
            let bytes = [24, 16, 8, 0].map { UInt8((tag >> $0) & 255) }
            return (String(decoding: bytes, as: UTF8.self), value)
        })
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    /// One face for every role (D-119, D-120): Allo at the web's weights, Resource Han Rounded for Chinese, and no
    /// system or mono face anywhere.
    @Test func everyTypeRoleResolvesToTheSharedSet() throws {
        let roles: [(String, NSFont?, Double)] = [
            ("writing", FirstLineTypography.writingNSFont(size: 28), 410),
            ("numeral", FirstLineTypography.numeralNSFont(size: 162), 360),
            ("heading", FirstLineTypography.writingMediumNSFont(size: 48), 540),
            ("ui", FirstLineTypography.uiNSFont, 400),
            ("uiSemibold", FirstLineTypography.uiSemiboldNSFont, 600),
            ("small", FirstLineTypography.smallNSFont, 400),
            ("smallMedium", FirstLineTypography.smallMediumNSFont, 500),
            ("smallSemibold", FirstLineTypography.smallSemiboldNSFont, 600),
            ("field", FirstLineTypography.fieldNSFont, 400),
            ("clock", FirstLineTypography.clockNSFont, 600),
            ("display", FirstLineTypography.displayNSFont(), 540),
            ("subtitle", FirstLineTypography.subtitleNSFont(), 400),
        ]
        for (name, font, weight) in roles {
            let font = try #require(font, "\(name) has no font")
            #expect(font.fontName.hasPrefix(BundledFonts.alloPostScript), "\(name) is \(font.fontName), not Allo")
            // A variable font reports only the axes moved off their defaults; Allo's wght default is 400.
            let drawn = axes(font)["wght"] ?? 400
            #expect(drawn == weight, "\(name) draws at \(drawn), not \(weight)")
            #expect(!font.fontName.localizedCaseInsensitiveContains("Mono"))
        }
        #expect(try #require(BundledFonts.cjk(size: 28)).fontName == BundledFonts.cjkPostScript)
    }

    /// Only Chinese asks for the 1.2 MB Chinese face; Latin writing, digits and punctuation never do (D-109).
    @Test func theChineseFaceWaitsForChinese() {
        #expect(!BundledFonts.asksForCJK("promotion. i want time 1:00"))
        #expect(BundledFonts.asksForCJK("我"))
        #expect(BundledFonts.asksForCJK("wo 们"))
    }

    @Test func theBundleCarriesOnlyTheSharedFaces() throws {
        // The target's declared resource directory is what ships; the incremental debug bundle can
        // keep files a previous build copied, so it is not the source of truth.
        let resources = packageRoot.appendingPathComponent("Sources/FirstLine/Resources")
        let names = try FileManager.default.contentsOfDirectory(atPath: resources.path)
        #expect(Set(names.filter { [".ttf", ".otf", ".woff", ".woff2"].contains(where: $0.hasSuffix) })
            == [BundledFonts.latinFile, BundledFonts.cjkFile])
        #expect(Set(names.filter { $0.hasPrefix("OFL-") }) == ["OFL-Allo.txt", "OFL-ResourceHanRounded.txt"])
    }

    @Test func chineseCascadesToResourceHanRounded() throws {
        let font = try writingFont(size: 28)
        let cascade = CTFontCopyAttribute(font, kCTFontCascadeListAttribute) as? [CTFontDescriptor] ?? []
        let names = cascade.map { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        #expect(names == [BundledFonts.cjkPostScript], "the writing face's CJK cascade moved: \(names)")
    }

    @Test func theClockUsesTabularDigitsAtTheMacsSize() {
        let font = FirstLineTypography.clockNSFont
        #expect(font.pointSize == 15)
        #expect(abs(advance("1:00", font: font) - advance("0:59", font: font)) < 0.001,
                "the clock changes width as the session counts down")
    }

    @Test func sharedRolesAdvanceLikeTheWeb() throws {
        let shared = try baseline()
        for role in shared.roles {
            let font: NSFont
            var face = ""
            switch role.role {
            case "writing-cjk":
                // Chinese draws through the cascade, so the face is the cascade's, not the base font's.
                font = try writingFont(size: role.size)
                let cascade = CTFontCopyAttribute(font, kCTFontCascadeListAttribute) as? [CTFontDescriptor] ?? []
                face = (cascade.first.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) } as? String) ?? ""
            case "warning-numeral":
                font = FirstLineTypography.numeralNSFont(size: role.size)
                face = font.fontName
            case "kept-heading":
                font = try #require(FirstLineTypography.writingMediumNSFont(size: role.size))
                face = font.fontName
            default:
                font = try #require(FirstLineTypography.writingNSFont(size: role.size))
                face = font.fontName
            }
            // A variable instance is named after its base face plus the axes it moved (`…_opsz_wght…`).
            #expect(face.hasPrefix(role.face), "\(role.role) resolves to \(face), not \(role.face)")
            let measured = advance(role.string, font: font)
            let drift = abs(measured - role.advancePt) / role.advancePt
            #expect(drift <= shared.tolerance,
                    "\(role.role) \"\(role.string)\" at \(role.size): the Mac draws \(measured), the shared baseline says \(role.advancePt)")
        }
    }

    /// Web draws plain grey-scale glyphs (`-webkit-font-smoothing: antialiased`); the Mac must switch CoreText's
    /// stem thickening off the same way or the same text reads heavier (D-098).
    @Test func glyphSmoothingIsOffLikeTheWeb() throws {
        let suite = try #require(UserDefaults(suiteName: "wid-text-smoothing-\(UUID().uuidString)"))
        #expect(suite.object(forKey: TextSmoothing.key) == nil)
        TextSmoothing.matchWeb(suite)
        #expect(suite.object(forKey: TextSmoothing.key) != nil)
        #expect(suite.integer(forKey: TextSmoothing.key) == 0)
    }
}
