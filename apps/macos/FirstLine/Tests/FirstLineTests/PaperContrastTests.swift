import AppKit
import Testing
@testable import WriteItDown

/// The two sheets (D-124, values D-130), measured: each paper's tone and roles, the 7:1 floor of every word on the sheet and on
/// both washes, the numeral's large-text floor, and a rendered sheet that is one flat tone. The Mac half of the web's
/// paper.spec.mjs.
@MainActor
struct PaperContrastTests {
    private func resolved(_ color: NSColor, _ paper: TestPaper) throws -> NSColor {
        var value: NSColor?
        NSAppearance(named: paper.appearance)?.performAsCurrentDrawingAppearance {
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

    /// The ink composited at an alpha over the sheet, the way a faded history line actually renders.
    private func composited(_ ink: NSColor, alpha: Double, over paper: NSColor) -> NSColor {
        NSColor(srgbRed: ink.redComponent * alpha + paper.redComponent * (1 - alpha),
                green: ink.greenComponent * alpha + paper.greenComponent * (1 - alpha),
                blue: ink.blueComponent * alpha + paper.blueComponent * (1 - alpha),
                alpha: 1)
    }

    private static let sheet: [TestPaper: (tone: String, ink: String, quiet: String, red: String, wash: String,
                                           deep: String, history: [CGFloat])] = [
        .white: ("#fcfcfa", "#45433d", "#4b4943", "#9a5255", "#f4f3f0", "#eae9e5", [1, 0.26, 0.084]),
        .black: ("#1c1c1a", "#dcdad3", "#bdbbb3", "#d08a8c", "#232321", "#2a2a27", [1, 0.172, 0.061]),
    ]

    @Test(arguments: TestPaper.allCases)
    func everyRoleIsThePapersToken(paper: TestPaper) throws {
        let want = try #require(Self.sheet[paper])
        #expect(hex(try resolved(FirstLineColors.paperNSColor, paper)) == want.tone)
        #expect(hex(try resolved(FirstLineColors.paperInkNSColor, paper)) == want.ink)
        #expect(hex(try resolved(FirstLineColors.paperQuietNSColor, paper)) == want.quiet)
        #expect(hex(try resolved(FirstLineColors.paperDangerNSColor, paper)) == want.red)
        #expect(hex(try resolved(FirstLineColors.paperWashNSColor, paper)) == want.wash)
        #expect(hex(try resolved(FirstLineColors.paperWashDeepNSColor, paper)) == want.deep)
        var history: [CGFloat] = []
        NSAppearance(named: paper.appearance)?.performAsCurrentDrawingAppearance {
            history = FirstLineColors.paperHistoryOpacities(for: NSAppearance.currentDrawing())
        }
        #expect(history == want.history)
    }

    /// The dimmed history (D-092): the steps are exempt from 7:1 and pinned to the same 1.57:1 and 1.15:1 on both
    /// papers, so neither paper's history reads louder than the other's.
    @Test(arguments: TestPaper.allCases)
    func historyStepsReadTheSameOnBothPapers(paper: TestPaper) throws {
        let want = try #require(Self.sheet[paper])
        let tone = try #require(color(want.tone)), ink = try #require(color(want.ink))
        let faded = want.history.dropFirst().map { contrast(composited(ink, alpha: Double($0), over: tone), tone) }
        #expect(abs(faded[0] - 1.57) < 0.06, "\(paper): history step one reads \(faded[0]):1")
        #expect(abs(faded[1] - 1.15) < 0.03, "\(paper): history step two reads \(faded[1]):1")
    }

    /// Every word clears 7:1 on the sheet and on both washes; the numeral is large text and clears 3:1 on the
    /// deepest wash (D-124). The wash is visible: one step off the sheet, the cut one step further.
    @Test(arguments: TestPaper.allCases)
    func everyWordClearsItsFloorAtTheDeepestWash(paper: TestPaper) throws {
        let want = try #require(Self.sheet[paper])
        let grounds = try [want.tone, want.wash, want.deep].map { try #require(color($0)) }
        for ground in grounds {
            for (role, value) in [("ink", want.ink), ("quiet", want.quiet)] {
                let ratio = contrast(try #require(color(value)), ground)
                #expect(ratio >= 7, "\(paper) \(role) on \(hex(ground)) reads \(ratio):1")
            }
        }
        let numeral = contrast(try #require(color(want.red)), grounds[2])
        #expect(numeral >= 3, "\(paper) numeral on the deepest wash reads \(numeral):1")
        let step = contrast(grounds[1], grounds[0])
        #expect(step > 1.05, "\(paper) wash is \(step):1 off the sheet")
        #expect(contrast(grounds[2], grounds[0]) > step, "\(paper) cut is not past the ramp")
    }

    /// The sheet the room draws is one flat tone: no grain, cloud or lamp (D-124), in both papers.
    @Test(arguments: TestPaper.allCases)
    func theRenderedSheetIsOneFlatTone(paper: TestPaper) throws {
        let want = try #require(Self.sheet[paper])
        let sheet = PaperSheetView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        sheet.appearance = NSAppearance(named: paper.appearance)
        let rep = try #require(sheet.bitmapImageRepForCachingDisplay(in: sheet.bounds))
        sheet.cacheDisplay(in: sheet.bounds, to: rep)
        var seen = Set<String>()
        for y in stride(from: 40, to: 160, by: 7) {
            for x in stride(from: 40, to: 280, by: 7) {
                if let pixel = renderedPixel(rep, x: x, y: y) { seen.insert(hex(pixel)) }
            }
        }
        #expect(seen.count == 1, "\(paper) sheet is not one flat tone: \(seen.sorted())")
        // The cached bitmap round-trips through the display colour space, which may move a channel by one level.
        let drawn = try #require(seen.first.flatMap { color($0) }), tone = try #require(color(want.tone))
        for (a, b) in [(drawn.redComponent, tone.redComponent), (drawn.greenComponent, tone.greenComponent),
                       (drawn.blueComponent, tone.blueComponent)] {
            #expect(abs(a - b) * 255 <= 1.01, "\(paper) sheet paints \(hex(drawn)), not \(want.tone)")
        }
    }

    private func color(_ hex: String) -> NSColor? {
        guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
