import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct DesignTokenTests {
    @Test func lightTokensResolveToSiteColors() {
        assertPalette(.aqua, expected: [
            (FirstLineColors.canvasNSColor, 0xd8d2c3), (FirstLineColors.paperNSColor, 0xf7f4ea),
            (FirstLineColors.inkNSColor, 0x1a1813), (FirstLineColors.dimNSColor, 0x6f6a5d),
            (FirstLineColors.faintNSColor, 0xb3ada0), (FirstLineColors.washWallNSColor, 0xd1c1ac),
            (FirstLineColors.washPaperNSColor, 0xebdfce), (FirstLineColors.deepWallNSColor, 0xc6b095),
            (FirstLineColors.deepPaperNSColor, 0xdecab3),
        ])
    }

    @Test func darkTokensResolveToSiteColors() {
        assertPalette(.darkAqua, expected: [
            (FirstLineColors.canvasNSColor, 0x15140f), (FirstLineColors.paperNSColor, 0x211f18),
            (FirstLineColors.inkNSColor, 0xece7d9), (FirstLineColors.dimNSColor, 0x8f897a),
            (FirstLineColors.faintNSColor, 0x5c574c), (FirstLineColors.washWallNSColor, 0x2e1712),
            (FirstLineColors.washPaperNSColor, 0x3a1c15), (FirstLineColors.deepWallNSColor, 0x3d1d15),
            (FirstLineColors.deepPaperNSColor, 0x4a2318),
        ])
    }

    @Test func alarmResolvesToSiteColorInBothAppearances() {
        assertPalette(.aqua, expected: [(FirstLineColors.dangerNSColor, 0x8f4405)])
        assertPalette(.darkAqua, expected: [(FirstLineColors.dangerNSColor, 0xf2a93b)])
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
