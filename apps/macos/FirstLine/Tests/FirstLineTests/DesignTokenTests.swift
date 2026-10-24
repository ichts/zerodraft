import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct DesignTokenTests {
    @Test func lightTokensResolveToBackgroundA() {
        assertPalette(.aqua, expected: [
            (FirstLineColors.pageNSColor, 0xF7F7F5), (FirstLineColors.sheetNSColor, 0xFFFFFF),
            (FirstLineColors.inkNSColor, 0x1C1917), (FirstLineColors.muteNSColor, 0x6B655C),
            (FirstLineColors.chromeNSColor, 0x5C564D), (FirstLineColors.tagBackgroundNSColor, 0xF2F2F0),
            (FirstLineColors.redNSColor, 0xB02A1E), (FirstLineColors.redSoftNSColor, 0xF6E2DC),
            (FirstLineColors.redDeepNSColor, 0xEBC8BD), (FirstLineColors.onInkNSColor, 0xFFFFFF),
        ])
    }

    @Test func darkTokensResolveToLandingDarkTheme() {
        assertPalette(.darkAqua, expected: [
            (FirstLineColors.pageNSColor, 0x15140F), (FirstLineColors.sheetNSColor, 0x26231C),
            (FirstLineColors.inkNSColor, 0xECE7D9), (FirstLineColors.muteNSColor, 0xA39D8E),
            (FirstLineColors.chromeNSColor, 0xA39D8E), (FirstLineColors.tagBackgroundNSColor, 0x2E2A22),
            (FirstLineColors.redNSColor, 0xE4604A), (FirstLineColors.redSoftNSColor, 0x3A1C15),
            (FirstLineColors.redDeepNSColor, 0x4A2318), (FirstLineColors.onInkNSColor, 0x15140F),
        ])
    }

    @Test func uiIsSystemSansAndWritingIsNewsreader() throws {
        let system = NSFont.systemFont(ofSize: 15)
        #expect(FirstLineTypography.uiNSFont.familyName == system.familyName)
        #expect(FirstLineTypography.displayNSFont().familyName == system.familyName)
        let writing = try #require(FirstLineTypography.writingNSFont(size: 28))
        #expect(writing.fontName.localizedCaseInsensitiveContains("Newsreader"))
    }

    @Test func redIsThePenInBothAppearances() {
        assertPalette(.aqua, expected: [(FirstLineColors.redNSColor, 0xB02A1E)])
        assertPalette(.darkAqua, expected: [(FirstLineColors.redNSColor, 0xE4604A)])
    }

    private func assertPalette(_ appearance: NSAppearance.Name, expected: [(NSColor, Int)]) {
        for (token, hex) in expected {
            var actual: [Int] = []
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let resolved = token.usingColorSpace(.deviceRGB)!
                actual = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
                    .map { Int(($0 * 255).rounded()) }
            }
            #expect(actual == [(hex >> 16) & 255, (hex >> 8) & 255, hex & 255])
        }
    }
}
