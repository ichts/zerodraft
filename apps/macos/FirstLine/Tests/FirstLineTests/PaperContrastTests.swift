import AppKit
import Testing
@testable import WriteItDown

/// The locked paper and ink (D-056), measured: the sheet's tone, the ink, and the contrast floor of every
/// text role on the sheet in both appearances. These assertions are the Mac's half of the web's paper.spec.mjs.
@MainActor
struct PaperContrastTests {
    private func resolved(_ color: NSColor, _ name: NSAppearance.Name) throws -> NSColor {
        var value: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            value = color.usingColorSpace(.sRGB)
        }
        return try #require(value)
    }

    private func hex(_ color: NSColor) -> String {
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        func channel(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }

    private func contrast(_ foreground: NSColor, _ background: NSColor) -> Double {
        let a = relativeLuminance(foreground)
        let b = relativeLuminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// How warm a colour reads: red ahead of green. The sheet's own tone is slightly cool, so this delta
    /// is what "the paper turns red" means on a paper that is not white.
    private func warmth(_ color: NSColor) -> Double {
        Double(color.redComponent - color.greenComponent)
    }

    /// The ink composited at an alpha over the sheet, the way a faded history line actually renders.
    private func composited(_ ink: NSColor, alpha: Double, over paper: NSColor) -> NSColor {
        NSColor(srgbRed: ink.redComponent * alpha + paper.redComponent * (1 - alpha),
                green: ink.greenComponent * alpha + paper.greenComponent * (1 - alpha),
                blue: ink.blueComponent * alpha + paper.blueComponent * (1 - alpha),
                alpha: 1)
    }

    @Test func lockedTonesAreThePaperAndTheInk() throws {
        _ = NSApplication.shared
        let light = try resolved(FirstLineColors.paperNSColor, .aqua)
        let dark = try resolved(FirstLineColors.paperNSColor, .darkAqua)
        #expect(hex(light) == "#dbe6ec", "the light sheet is the locked Note tone")
        #expect(hex(dark) == "#21272a", "the dark sheet is the lamp version, not an inversion")

        #expect(hex(try resolved(FirstLineColors.inkNSColor, .aqua)) == "#1c1917")
        #expect(hex(try resolved(FirstLineColors.inkNSColor, .darkAqua)) == "#ece7d9")

        #expect(hex(try resolved(FirstLineColors.paperQuietNSColor, .aqua)) == "#464746")
        #expect(hex(try resolved(FirstLineColors.paperQuietNSColor, .darkAqua)) == "#b8b5ac")
        #expect(hex(try resolved(FirstLineColors.paperDangerNSColor, .aqua)) == "#63140b")
        #expect(hex(try resolved(FirstLineColors.paperDangerNSColor, .darkAqua)) == "#ffb4a2")
    }

    @Test func everyTextRoleClearsSevenToOneOnTheSheet() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let name = appearance == .aqua ? "light" : "dark"
            let paper = try resolved(FirstLineColors.paperNSColor, appearance)
            let ink = try resolved(FirstLineColors.inkNSColor, appearance)
            let quiet = try resolved(FirstLineColors.paperQuietNSColor, appearance)
            let danger = try resolved(FirstLineColors.paperDangerNSColor, appearance)

            // The words: the active line, and the two faded lines above it.
            #expect(contrast(ink, paper) >= 7, "\(name): the ink on the sheet")
            for (index, alpha) in FirstLineColors.paperHistoryAlphas(for: NSAppearance(named: appearance)!).enumerated() {
                let line = composited(ink, alpha: Double(alpha), over: paper)
                let target = index == 0 ? 9.0 : 7.0
                #expect(contrast(line, paper) >= target,
                        "\(name): history step \(index + 1) is \(contrast(line, paper)):1, wanted \(target):1")
            }
            // The quiet chrome (clock, count, exit link, receipt) and the pen red (numeral, wipe report).
            #expect(contrast(quiet, paper) >= 7, "\(name): the quiet chrome on the sheet")
            #expect(contrast(danger, paper) >= 7, "\(name): the pen red on the sheet")
        }
    }

    @Test func thePenRedAlsoClearsSevenOnItsWarnWash() throws {
        // The numeral is never drawn on the plain sheet alone: warn washes the paper under it. The red is
        // measured against the deepest wash the numeral can sit on, so the alarm cannot sink into its tint.
        let washes: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for entry in washes {
            let paper = try resolved(FirstLineColors.paperNSColor, entry.appearance)
            let deep = try resolved(FirstLineColors.paperWashDeepNSColor, entry.appearance)
            let danger = try resolved(FirstLineColors.paperDangerNSColor, entry.appearance)
            #expect(contrast(danger, deep) >= 7,
                    "\(entry.name): the pen red on its deepest wash is \(contrast(danger, deep)):1")
            #expect(contrast(danger, paper) >= 7, "\(entry.name): the pen red on the sheet")
        }
    }

    /// The wash is not a second palette: it is the web's `color-mix(in oklab, paper 88%, #C8392F)` (76%
    /// at the cut), so the Mac and the browser land on the same colour under the same alarm (D-056).
    @Test func theWashIsTheWebsPaperMixNotAPalePink() throws {
        #expect(hex(try resolved(FirstLineColors.paperWashNSColor, .aqua)) == "#ddd3d5")
        #expect(hex(try resolved(FirstLineColors.paperWashNSColor, .darkAqua)) == "#352c2c")
        #expect(hex(try resolved(FirstLineColors.paperWashDeepNSColor, .aqua)) == "#ddc0be")
        #expect(hex(try resolved(FirstLineColors.paperWashDeepNSColor, .darkAqua)) == "#49302e")
        // The wash is a tint of the sheet's own hue family, warmer than the paper and warmer still at the cut.
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let paper = try resolved(FirstLineColors.paperNSColor, appearance)
            let wash = try resolved(FirstLineColors.paperWashNSColor, appearance)
            let deep = try resolved(FirstLineColors.paperWashDeepNSColor, appearance)
            #expect(warmth(wash) > warmth(paper) + 0.05, "the wash does not warm the paper")
            #expect(warmth(deep) > warmth(wash), "the cut is not deeper than the ramp")
        }
    }

    @Test func theFieldIsDeterministic() throws {
        let first = try #require(PaperField.render(width: 240, height: 160, scale: 2, dark: false))
        let second = try #require(PaperField.render(width: 240, height: 160, scale: 2, dark: false))
        let a = try #require(first.dataProvider?.data) as Data
        let b = try #require(second.dataProvider?.data) as Data
        #expect(a == b, "the same size and tone must always produce the same sheet")
        let other = try #require(PaperField.render(width: 240, height: 160, scale: 2, dark: true))
        let c = try #require(other.dataProvider?.data) as Data
        #expect(a != c, "light and dark are different papers")
    }
}
