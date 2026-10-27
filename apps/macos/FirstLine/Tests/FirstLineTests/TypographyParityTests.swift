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

    /// The writing stack the room and the kept sheet share: Newsreader over the bundled CJK cascade.
    private func writingFont(size: CGFloat) throws -> NSFont {
        try #require(WritingFontCandidate.pitchLight.fontWithCJKFallback(size: size))
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    @Test func everyTypeRoleResolvesToTheSharedSet() throws {
        #expect(try #require(FirstLineTypography.writingNSFont(size: 28)).fontName == "Newsreader16pt-Regular")
        #expect(try #require(FirstLineTypography.writingItalicNSFont(size: 162)).fontName == "Newsreader16pt-Italic")
        #expect(try #require(FirstLineTypography.writingMediumNSFont(size: 48)).fontName == "NewsreaderRoman-Medium")
        #expect(try #require(ChineseFontCandidate.zhuqueFangsong.font(size: 28)).fontName == "ZhuqueFangsong-Regular")

        let system = NSFont.systemFont(ofSize: 15).familyName
        for (name, font) in [("ui", FirstLineTypography.uiNSFont),
                             ("uiSemibold", FirstLineTypography.uiSemiboldNSFont),
                             ("small", FirstLineTypography.smallNSFont),
                             ("smallMedium", FirstLineTypography.smallMediumNSFont),
                             ("smallSemibold", FirstLineTypography.smallSemiboldNSFont),
                             ("field", FirstLineTypography.fieldNSFont),
                             ("clock", FirstLineTypography.clockNSFont),
                             ("display", FirstLineTypography.displayNSFont()),
                             ("subtitle", FirstLineTypography.subtitleNSFont())] {
            #expect(font.familyName == system, "\(name) left the system sans")
        }
        // The mono chrome layer is retired on both surfaces: no role may resolve to a mono face.
        for font in [FirstLineTypography.uiNSFont, FirstLineTypography.smallNSFont,
                     FirstLineTypography.clockNSFont, FirstLineTypography.displayNSFont()] {
            #expect(!font.fontName.localizedCaseInsensitiveContains("Mono"))
            #expect(!(font.familyName ?? "").localizedCaseInsensitiveContains("Plex"))
        }
    }

    @Test func theBundleCarriesOnlyTheSharedFaces() throws {
        // The target's declared resource directory is what ships; the incremental debug bundle can
        // keep files a previous build copied, so it is not the source of truth.
        let resources = packageRoot.appendingPathComponent("Sources/FirstLine/Resources")
        let names = try FileManager.default.contentsOfDirectory(atPath: resources.path)
        #expect(Set(names.filter { $0.hasSuffix(".ttf") })
            == ["Newsreader-Variable.ttf", "Newsreader-Italic-Variable.ttf", "ZhuqueFangsong-Regular.ttf"])
        #expect(Set(names.filter { $0.hasPrefix("OFL-") }) == ["OFL-Newsreader.txt", "OFL-ZhuqueFangsong.txt"])
    }

    @Test func chineseCascadesToTheMacRoomsFangsong() throws {
        let font = try writingFont(size: 28)
        let cascade = CTFontCopyAttribute(font, kCTFontCascadeListAttribute) as? [CTFontDescriptor] ?? []
        #expect(cascade.count == 1)
        let names = cascade.map { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        #expect(names == ["ZhuqueFangsong-Regular"], "the writing face's CJK cascade moved: \(names)")
    }

    @Test func theClockUsesTabularDigitsAtTheMacsSize() {
        let font = FirstLineTypography.clockNSFont
        #expect(font.pointSize == 15)
        #expect(abs(advance("1:00", font: font) - advance("0:59", font: font)) < 0.001,
                "the clock changes width as the session counts down")
    }

    @Test func keptHeadingAndReceiptCarryTheMacsTracking() throws {
        let kept = SessionKeptView(copyTarget: nil, copyAction: NSSelectorFromString("copy:"),
                                   restartTarget: nil, restartAction: NSSelectorFromString("restart:"),
                                   reducesMotion: { false })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = kept
        let writing = try writingFont(size: 28)
        kept.setContent(text: "the draft that survived", wordCount: 4, duration: 60, writingFont: writing)

        let heading = try #require(descendants(kept, of: NSTextField.self)
            .first { $0.stringValue == "You wrote it down." })
        #expect(heading.font?.fontName == "NewsreaderRoman-Medium")
        #expect(heading.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) == nil,
                "the kept heading must stay untracked: the web now matches this value")
        // The heading is clamp(32px, 5vw, 48px) against the window viewport, the web's --t-kept.
        for (width, expected) in [(1040.0, 48.0), (800.0, 40.0), (600.0, 32.0)] {
            window.setContentSize(NSSize(width: width, height: 720))
            kept.layoutContent()
            #expect(abs((heading.font?.pointSize ?? 0) - expected) < 0.001,
                    "at a \(width) pt viewport the kept heading draws \(heading.font?.pointSize ?? 0) pt, not \(expected)")
        }

        let receipt = try #require(descendants(kept, of: NSTextField.self)
            .first { $0.font == FirstLineTypography.smallMediumNSFont && !$0.stringValue.isEmpty })
        #expect(receipt.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat == 0.26,
                "the receipt keeps the live trial's 0.02em tracking")
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
                font = try #require(FirstLineTypography.writingItalicNSFont(size: role.size))
                face = font.fontName
            case "kept-heading":
                font = try #require(FirstLineTypography.writingMediumNSFont(size: role.size))
                face = font.fontName
            default:
                font = try #require(FirstLineTypography.writingNSFont(size: role.size))
                face = font.fontName
            }
            #expect(face == role.face, "\(role.role) resolves to \(face), not \(role.face)")
            let measured = advance(role.string, font: font)
            let drift = abs(measured - role.advancePt) / role.advancePt
            #expect(drift <= shared.tolerance,
                    "\(role.role) \"\(role.string)\" at \(role.size): the Mac draws \(measured), the shared baseline says \(role.advancePt)")
        }
    }
}
