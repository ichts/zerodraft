import AppKit
import Testing
@testable import WriteItDown

/// The three sheets (D-119, D-120), measured: each mode's tone and roles, and the 7:1 floor of every word in the
/// rendered pixels under the lamp, on the sheet and both washes. The Mac half of the web's paper.spec.mjs.
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

    /// The ink composited at an alpha over the sheet, the way a faded history line actually renders.
    private func composited(_ ink: NSColor, alpha: Double, over paper: NSColor) -> NSColor {
        NSColor(srgbRed: ink.redComponent * alpha + paper.redComponent * (1 - alpha),
                green: ink.greenComponent * alpha + paper.greenComponent * (1 - alpha),
                blue: ink.blueComponent * alpha + paper.blueComponent * (1 - alpha),
                alpha: 1)
    }

    private static let sheet: [PaperMode: (tone: String, ink: String, quiet: String, danger: String, wash: String,
                                           deep: String, history: [CGFloat])] = [
        .lamp: ("#e9e2ce", "#1f1812", "#221a14", "#380904", "#e8cfbb", "#e6bca7", [1, 0.22, 0.07]),
        .paper: ("#fdfdfb", "#1c1917", "#3f3b36", "#63140b", "#fae7e2", "#f6d0c9", [1, 0.22, 0.07]),
        .slate: ("#363b3d", "#f7eedb", "#f4efe6", "#ffe8de", "#493e3d", "#5a403d", [1, 0.16, 0.05]),
    ]

    @Test(arguments: PaperMode.allCases)
    func eachModeHasItsLockedSheet(mode: PaperMode) throws {
        _ = NSApplication.shared
        let want = try #require(Self.sheet[mode])
        try withPaperMode(mode) { (appearance: NSAppearance.Name) throws in
            #expect(hex(try resolved(FirstLineColors.paperNSColor, appearance)) == want.tone)
            #expect(hex(try resolved(FirstLineColors.paperInkNSColor, appearance)) == want.ink)
            #expect(hex(try resolved(FirstLineColors.paperQuietNSColor, appearance)) == want.quiet)
            #expect(hex(try resolved(FirstLineColors.paperDangerNSColor, appearance)) == want.danger)
            #expect(hex(try resolved(FirstLineColors.paperWashNSColor, appearance)) == want.wash)
            #expect(hex(try resolved(FirstLineColors.paperWashDeepNSColor, appearance)) == want.deep)
            #expect(FirstLineColors.paperHistoryOpacities(for: NSAppearance(named: appearance)!) == want.history)
        }
    }

    /// The dimmed history (D-092): the steps are exempt from 7:1 and pinned to the same 1.57:1 and 1.15:1 on every
    /// sheet, so no mode's history reads louder than another's.
    @Test(arguments: PaperMode.allCases)
    func historyStepsReadTheSameOnEverySheet(mode: PaperMode) throws {
        let want = try #require(Self.sheet[mode])
        let paper = try #require(color(want.tone)), ink = try #require(color(want.ink))
        let faded = want.history.dropFirst().map { contrast(composited(ink, alpha: Double($0), over: paper), paper) }
        #expect(abs(faded[0] - 1.57) < 0.06, "\(mode): history step one reads \(faded[0]):1")
        #expect(abs(faded[1] - 1.15) < 0.03, "\(mode): history step two reads \(faded[1]):1")
    }

    /// One 40 pt patch of the rendered room sheet: its mean and its 2nd and 98th luminance percentile pixels.
    private struct Patch { let mean: [Double], dark: [Double], light: [Double] }

    private func patches(of image: CGImage, scale: Int) throws -> [String: Patch] {
        let width = image.width, height = image.height
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let px = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        let side = 40 * scale
        let w = width / scale, h = height / scale
        // paper.spec.mjs roomPatches: the centre under the writing line and the four corners inside the chrome.
        let origins: [String: (Int, Int)] = [
            "centre": (w / 2 - 20, Int(Double(h) * 0.62)), "topLeft": (8, 10), "topRight": (w - 48, 50),
            "bottomLeft": (8, h - 96), "bottomRight": (w - 48, h - 96),
        ]
        return origins.mapValues { origin in
            var values: [(Double, [Double])] = []
            var mean = [0.0, 0.0, 0.0]
            for y in origin.1 * scale..<origin.1 * scale + side {
                for x in origin.0 * scale..<origin.0 * scale + side {
                    let i = (y * width + x) * 4
                    let rgb = [Double(px[i]), Double(px[i + 1]), Double(px[i + 2])]
                    values.append((0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2], rgb))
                    for c in 0..<3 { mean[c] += rgb[c] / Double(side * side) }
                }
            }
            values.sort { $0.0 < $1.0 }
            let at = { (q: Double) in values[Int(q * Double(values.count - 1))].1 }
            return Patch(mean: mean, dark: at(0.02), light: at(0.98))
        }
    }

    /// The sheet as the room shows it: the rendered paper, and over it the wash at full strength under the light.
    private func roomSheet(_ mode: PaperMode, wash: String?) throws -> CGImage {
        let (width, height, scale) = (1376, 804, 1)
        let sheet = try #require(PaperField.render(width: width, height: height, scale: CGFloat(scale), mode: mode))
        guard let wash, let tint = color(wash) else { return sheet }
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(sheet, in: rect)
        context.setFillColor(tint.cgColor)
        context.fill(rect)
        PaperField.drawLight(mode, in: context, rect: rect)
        return try #require(context.makeImage())
    }

    /// Every word in the room clears 7:1 on the pixels it sits on: each role is lit by the light that shades the
    /// patch (paper.spec.mjs `lit`), and measured against the patch's worst grain pixel, on the plain sheet, the
    /// wash and the deep wash, at the centre and the four corners.
    @Test(arguments: PaperMode.allCases)
    func everyWordClearsSevenToOneInTheRenderedPixels(mode: PaperMode) throws {
        let want = try #require(Self.sheet[mode])
        let tone = try #require(color(want.tone)).rgb255
        for (ground, wash) in [("sheet", nil), ("wash", want.wash), ("deep", want.deep)] as [(String, String?)] {
            for (place, patch) in try patches(of: roomSheet(mode, wash: wash), scale: 1) {
                for (role, value) in [("ink", want.ink), ("quiet", want.quiet), ("danger", want.danger)] {
                    let ink = try #require(color(value)).rgb255
                    let seen = (0..<3).map { ink[$0] * min(1, patch.mean[$0] / tone[$0]) }
                    let worst = luminance(seen) < luminance(patch.mean) ? patch.dark : patch.light
                    let ratio = (max(luminance(seen), luminance(worst)) + 0.05) / (min(luminance(seen), luminance(worst)) + 0.05)
                    #expect(ratio >= 7, "\(mode) \(role) on the \(ground) at the \(place): \(ratio):1")
                }
            }
        }
    }

    /// The rendered sheet is the web's sheet: the same tone, grain, cloud and light. The reference is the web room's
    /// bare sheet at the Mac window's default size (976 x 656, Chromium at 1x, cf427c3 `#trial`, its words hidden),
    /// as 24 px patch means at nine points, within 2 levels. The Mac drew it within 0.5 when it was pinned.
    @Test(arguments: [PaperMode.lamp, .slate, .paper])
    func theRenderedSheetIsTheWebsSheet(mode: PaperMode) throws {
        let web: [PaperMode: [[Double]]] = [
            .lamp: [[211, 198, 168], [207, 195, 167], [209, 196, 165], [204, 188, 157], [209, 196, 165],
                    [206, 190, 159], [206, 189, 155], [201, 184, 151], [199, 182, 148]],
            .slate: [[62, 67, 68], [67, 72, 74], [63, 68, 70], [66, 71, 72], [63, 68, 70], [65, 69, 71],
                     [60, 64, 65], [64, 69, 70], [65, 69, 70]],
            .paper: Array(repeating: [253, 253, 251], count: 9),
        ]
        let (width, height) = (976, 656)
        let image = try #require(PaperField.render(width: width, height: height, scale: 1, mode: mode))
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let px = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        var index = 0
        for fy in [0.3, 0.6, 0.9] {
            for fx in [0.25, 0.5, 0.75] {
                // The bitmap's first row is the sheet's top, as in a screenshot.
                let (cx, cy) = (Int(fx * Double(width)), Int(fy * Double(height)))
                var mean = [0.0, 0.0, 0.0]
                for y in cy - 12..<cy + 12 {
                    for x in cx - 12..<cx + 12 {
                        let i = (y * image.width + x) * 4
                        for c in 0..<3 { mean[c] += Double(px[i + c]) / 576 }
                    }
                }
                let want = try #require(web[mode])[index]
                let drift = zip(mean, want).map { abs($0 - $1) }.max() ?? 0
                #expect(drift <= 2, "\(mode) at (\(fx), \(fy)): Mac \(mean.map { Int($0.rounded()) }), web \(want)")
                index += 1
            }
        }
    }

    /// Paper is plain: its tone, no grain, no cloud, no lamp. Lamp and Slate carry their grain and light.
    @Test(arguments: PaperMode.allCases)
    func onlyPaperIsPlain(mode: PaperMode) throws {
        let image = try roomSheet(mode, wash: nil)
        let all = try patches(of: image, scale: 1)
        let spread = all.values.map { luminance($0.light) - luminance($0.dark) }.max() ?? 0
        if mode == .paper {
            #expect(spread == 0, "the plain sheet carries a texture")
            #expect(all.values.allSatisfy { $0.mean.map { $0.rounded() } == [253, 253, 251] })
        } else {
            #expect(spread > 0.01, "\(mode) lost its grain")
        }
    }

    /// Slate's grain is even (round 006b): an isotropic grain, not the streaked stone it replaced, so the spread of
    /// the row means and of the column means stay within 3x of each other on the bare sheet.
    @Test func slateGrainIsEven() throws {
        let image = try #require(PaperField.render(width: 1376, height: 804, scale: 1, mode: .slate))
        let width = image.width, height = image.height
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let px = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        let region = (x: 368, y: 252, width: 640, height: 300)
        var rows = [Double](repeating: 0, count: region.height), columns = [Double](repeating: 0, count: region.width)
        for y in 0..<region.height {
            for x in 0..<region.width {
                let i = ((region.y + y) * width + region.x + x) * 4
                let luma = 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
                rows[y] += luma / Double(region.width)
                columns[x] += luma / Double(region.height)
            }
        }
        func spread(_ values: [Double]) -> Double {
            let mean = values.reduce(0, +) / Double(values.count)
            return (values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)).squareRoot()
        }
        let ratio = max(spread(rows) / spread(columns), spread(columns) / spread(rows))
        #expect(ratio <= 3, "Slate's grain runs one way: row/column spread ratio \(ratio)")
    }

    private func color(_ hex: String) -> NSColor? {
        guard let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    private func luminance(_ rgb: [Double]) -> Double {
        func channel(_ v: Double) -> Double {
            let c = v / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2])
    }

    @Test func theFieldIsDeterministic() throws {
        let first = try #require(PaperField.render(width: 240, height: 160, scale: 2, mode: .lamp))
        let second = try #require(PaperField.render(width: 240, height: 160, scale: 2, mode: .lamp))
        let a = try #require(first.dataProvider?.data) as Data
        let b = try #require(second.dataProvider?.data) as Data
        #expect(a == b, "the same size and mode must always produce the same sheet")
        let other = try #require(PaperField.render(width: 240, height: 160, scale: 2, mode: .slate))
        let c = try #require(other.dataProvider?.data) as Data
        #expect(a != c, "Lamp and Slate are different papers")
    }
}

private extension NSColor {
    var rgb255: [Double] {
        let c = usingColorSpace(.sRGB) ?? self
        return [Double(c.redComponent) * 255, Double(c.greenComponent) * 255, Double(c.blueComponent) * 255]
    }
}
