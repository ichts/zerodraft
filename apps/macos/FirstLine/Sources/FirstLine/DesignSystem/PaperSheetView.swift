/**
 * [INPUT]: the paper's laid-out size, the window's backing scale, the effective appearance (light/dark),
 *          and the locked paper constants (D-056: tone Note #dbe6ec / #21272a, grain 70 of 100, size 1.00).
 * [OUTPUT]: PaperSheetView - the writing sheet: the locked tone, two-scale mottle and grain, rendered once
 *           into a cached CGImage per size and appearance, with the sheet ring and rounded clip the room needs.
 * [POS]: The Mac half of the sheet the web renders in writeitdown/paper.js; the room, its failure screen and
 *        the kept sheet all sit on this one paper. Cards, fields and controls keep FirstLineColors.sheetNSColor.
 * [PROTOCOL]: Keep the generator in step with writeitdown/paper.js (same seeds, amplitudes and light model);
 *             paint on size/appearance change only, never on typing. Then check FirstLine/AGENTS.md.
 *
 * Why a cached image: the field is ~5 M device pixels at 2x. Drawing it in draw(_:) each frame would
 * re-generate it under every keystroke; one image per size costs about a tenth of a second once and is then
 * free. The image is built synchronously on first draw, so the window's first paint already carries the paper
 * instead of flashing a flat tone; a live window drag reuses the previous image stretched and rebuilds it when
 * the drag ends.
 */

import AppKit
import CoreGraphics

@MainActor
final class PaperSheetView: NSView {
    /// The sheet's ring on the paper (ink 7% light / hair 10% dark, the same ring the plain sheet takes).
    var borderColor: NSColor? {
        didSet { needsDisplay = true }
    }
    var borderWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = FirstLineRadius.sheet {
        didSet { updateLayerShape() }
    }
    /// Clip content (cards and the room paper) to the corner radius.
    var clipsContent: Bool = false {
        didSet { updateLayerShape() }
    }

    /// The paper's image and the grain layer inside it. The wash draws the grain again above its tint,
    /// so a washed sheet is still textured paper instead of a flat panel (D-056).
    private var paperImage: CGImage?
    private var grainImage: CGImage?
    private var imageKey = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateLayerShape()
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }

    private func updateLayerShape() {
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = clipsContent
        invalidatePaper()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidatePaper()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidatePaper()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        invalidatePaper()
    }

    func invalidatePaper() {
        imageKey = ""
        needsDisplay = true
    }

    /// The texture for the current size and appearance, built on demand.
    private func currentPaper() -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 1, height > 1 else { return nil }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key = "\(width)x\(height)@\(scale)-\(dark ? "dark" : "light")"
        if key == imageKey, let paperImage { return paperImage }
        guard let sheet = PaperField.sheet(width: width, height: height, scale: scale, dark: dark) else { return nil }
        imageKey = key
        paperImage = sheet.image
        grainImage = sheet.grain
        return sheet.image
    }

    /// The grain layer of the current sheet, for a state wash that must not flatten the paper.
    func grainForWash() -> CGImage? {
        _ = currentPaper()
        return grainImage
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds
        ctx.saveGState()
        if cornerRadius > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.clip()
        }
        // The field is generated bottom-left-up; flip once so the image and the sheet share one origin.
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 1, y: -1)
        // A window drag reuses the last field stretched and rebuilds once when the drag ends, so the
        // ~5 M pixel field is never regenerated per drag frame.
        let image = inLiveResize ? paperImage : currentPaper()
        if let image {
            ctx.interpolationQuality = inLiveResize ? .high : .none
            ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        } else {
            FirstLineColors.paperNSColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: rect.size))
        }
        ctx.restoreGState()

        if let borderColor, borderWidth > 0 {
            ctx.saveGState()
            ctx.setStrokeColor(borderColor.cgColor)
            ctx.setLineWidth(borderWidth)
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
                               cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}

/// The generator. Every constant here is the locked paper (D-056 / writeitdown/paper.js).
enum PaperField {
    static let lightTone = (r: 219.0, g: 230.0, b: 236.0)
    static let darkTone = (r: 33.0, g: 39.0, b: 42.0)
    static let grain = 0.70
    static let size = 1.00
    static let tooth = 44.0
    static let pulp = 24.0

    /// mulberry32, the web renderer's generator; the same seed yields the same field.
    struct Random {
        private var state: UInt32
        init(seed: UInt32) { state = seed }

        mutating func next() -> Double {
            state = state &+ 0x6d2b_79f5
            var t = state
            t = (t ^ (t >> 15)) &* (1 | state)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296.0
        }
    }

    /// FNV-1a over the seed's bytes, matching the web renderer's seed derivation.
    static func seed(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash
    }

    private static func tone(dark: Bool) -> (r: Double, g: Double, b: Double) {
        dark ? darkTone : lightTone
    }

    private static func hex(_ tone: (r: Double, g: Double, b: Double)) -> String {
        String(format: "#%02x%02x%02x", Int(tone.r), Int(tone.g), Int(tone.b))
    }

    /// A deviation becomes an alpha over black or white that shifts the sheet's own channel by exactly that
    /// much, so pale and dark specks weigh the same in sRGB and the sheet's mean stays on the locked tone as
    /// the grain is layered on (D-058).
    private static func alpha(delta: Double, tone: (r: Double, g: Double, b: Double)) -> Double {
        let average = (tone.r + tone.g + tone.b) / 3
        let room = delta > 0 ? 255 - average : average
        return min(1, abs(delta) / max(10, room))
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// One noise layer drawn into its own image, so the caller can scale it with smoothing.
    private static func noiseImage(width: Int, height: Int, amount: Double,
                                   tone: (r: Double, g: Double, b: Double),
                                   random: inout Random) -> CGImage? {
        guard width > 1, height > 1, let context = makeContext(width: width, height: height),
              let raw = context.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for index in 0..<(width * height) {
            let value = ((random.next() + random.next() + random.next()) - 1.5) / 1.5 * amount
            let byte = UInt8((alpha(delta: value, tone: tone) * 255).rounded())
            // Premultiplied: a deviation is full black or full white, so the colour scales with the alpha.
            let colour: UInt8 = value < 0 ? 0 : byte
            pixels[index * 4] = colour
            pixels[index * 4 + 1] = colour
            pixels[index * 4 + 2] = colour
            pixels[index * 4 + 3] = byte
        }
        return context.makeImage()
    }

    /// One rendered sheet: the paper itself and, separately, the grain layer composited into it.
    struct Sheet {
        let image: CGImage
        let grain: CGImage?
    }

    static func render(width: Int, height: Int, scale: CGFloat, dark: Bool) -> CGImage? {
        sheet(width: width, height: height, scale: scale, dark: dark)?.image
    }

    static func sheet(width: Int, height: Int, scale: CGFloat, dark: Bool) -> Sheet? {
        let colour = tone(dark: dark)
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        guard let paper = makeContext(width: width, height: height) else { return nil }
        paper.setShouldAntialias(true)
        paper.setFillColor(CGColor(srgbRed: colour.r / 255, green: colour.g / 255, blue: colour.b / 255, alpha: 1))
        paper.fill(full)

        // Two scales of mottle, each generated small and upscaled with smoothing.
        var coarse = Random(seed: seed("coarse" + hex(colour)))
        var fine = Random(seed: seed("fine" + hex(colour)))
        let mottle: [(cell: Int, amount: Double)] = [
            (max(2, Int((34.0 * scale).rounded())), 9.0),
            (max(2, Int((9.0 * scale).rounded())), 4.5),
        ]
        for (index, layer) in mottle.enumerated() {
            let smallWidth = max(2, (width + layer.cell - 1) / layer.cell)
            let smallHeight = max(2, (height + layer.cell - 1) / layer.cell)
            let image = index == 0
                ? noiseImage(width: smallWidth, height: smallHeight, amount: layer.amount, tone: colour, random: &coarse)
                : noiseImage(width: smallWidth, height: smallHeight, amount: layer.amount, tone: colour, random: &fine)
            guard let image else { continue }
            paper.interpolationQuality = .high
            paper.draw(image, in: full)
        }

        // The grain is one layer, composited at the locked strength so the tone stays the base layer's.
        guard let grainContext = makeContext(width: width, height: height), let plain = paper.makeImage() else { return nil }
        var random = Random(seed: seed("tooth" + hex(colour) + "1.0"))
        let lift = dark ? 0.4 : 1.0

        if let toothImage = noiseImage(width: width, height: height, amount: tooth * lift,
                                       tone: colour, random: &random) {
            grainContext.interpolationQuality = .none
            grainContext.draw(toothImage, in: full)
        }
        let pulpCell = max(2, Int((Double(scale) * 0.8).rounded()))
        let pulpWidth = max(2, (width + pulpCell - 1) / pulpCell)
        let pulpHeight = max(2, (height + pulpCell - 1) / pulpCell)
        if let pulpImage = noiseImage(width: pulpWidth, height: pulpHeight, amount: pulp * lift,
                                      tone: colour, random: &random) {
            grainContext.interpolationQuality = .high
            grainContext.draw(pulpImage, in: full)
        }
        drawFibres(into: grainContext, width: width, height: height, scale: scale,
                   tone: colour, random: &random, dark: dark)
        drawFlecks(into: grainContext, width: width, height: height, scale: scale,
                   tone: colour, random: &random, dark: dark)

        guard let grainLayer = grainContext.makeImage() else { return Sheet(image: plain, grain: nil) }
        paper.saveGState()
        paper.setAlpha(grain)
        paper.interpolationQuality = .none
        paper.draw(grainLayer, in: full)
        paper.restoreGState()
        correctMean(of: paper, to: colour, in: full)
        guard let image = paper.makeImage() else { return nil }
        return Sheet(image: image, grain: grainLayer)
    }

    /// The locked tone wins over the texture: the finished sheet is shifted by whatever the noise layers moved
    /// its mean, so what reaches the screen measures the token itself and not a slightly warmer or greyer paper
    /// (D-058). The shift is one additive and one subtractive flat fill, so the grain's own contrast is untouched.
    private static func correctMean(of context: CGContext, to tone: (r: Double, g: Double, b: Double),
                                    in rect: CGRect) {
        guard let raw = context.data else { return }
        let width = context.width
        let height = context.height
        guard width > 1, height > 1 else { return }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var sums = (r: 0.0, g: 0.0, b: 0.0)
        for index in 0..<(width * height) {
            let alpha = Double(pixels[index * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            sums.r += Double(pixels[index * 4])
            sums.g += Double(pixels[index * 4 + 1])
            sums.b += Double(pixels[index * 4 + 2])
        }
        let count = Double(width * height)
        let delta = (r: tone.r - sums.r / count, g: tone.g - sums.g / count, b: tone.b - sums.b / count)
        guard abs(delta.r) + abs(delta.g) + abs(delta.b) > 0.05 else { return }
        let up = (r: max(delta.r, 0) / 255, g: max(delta.g, 0) / 255, b: max(delta.b, 0) / 255)
        if up.r + up.g + up.b > 0 {
            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.setFillColor(CGColor(srgbRed: up.r, green: up.g, blue: up.b, alpha: 1))
            context.fill(rect)
            context.restoreGState()
        }
        let down = (r: max(-delta.r, 0) / 255, g: max(-delta.g, 0) / 255, b: max(-delta.b, 0) / 255)
        if down.r + down.g + down.b > 0 {
            context.saveGState()
            context.setBlendMode(.plusDarker)
            context.setFillColor(CGColor(srgbRed: 1 - down.r, green: 1 - down.g, blue: 1 - down.b, alpha: 1))
            context.fill(rect)
            context.restoreGState()
        }
    }

    /// Short pulp fibres: a dense, low-contrast hair mat rather than a few long scratches.
    private static func drawFibres(into ctx: CGContext, width: Int, height: Int, scale: CGFloat,
                                   tone: (r: Double, g: Double, b: Double), random: inout Random, dark: Bool) {
        let dpr = Double(scale)
        let count = Int((Double(width * height) / (dpr * dpr) * 0.0026).rounded())
        ctx.setLineCap(.round)
        for _ in 0..<count {
            let pale = random.next() < (dark ? 0.2 : 0.44)
            let spread = (12 + random.next() * 34) * (dark ? 0.32 : 1) * (pale ? 0.7 : 1)
            ctx.setAlpha(alpha(delta: (pale ? 1.0 : -1.0) * spread, tone: tone) * (0.55 + random.next() * 0.45))
            ctx.setStrokeColor(CGColor(srgbRed: pale ? 1 : 0, green: pale ? 1 : 0, blue: pale ? 1 : 0, alpha: 1))
            ctx.setLineWidth((0.5 + random.next() * 0.7) * dpr)
            let x = random.next() * Double(width)
            let y = random.next() * Double(height)
            let length = (2 + random.next() * 7) * size * dpr
            let angle = random.next() * .pi * 2
            let bow = (random.next() - 0.5) * 2.2 * dpr
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                             control: CGPoint(x: x + cos(angle) * length * 0.5 - sin(angle) * bow,
                                              y: y + sin(angle) * length * 0.5 + cos(angle) * bow))
            ctx.strokePath()
        }
        ctx.setAlpha(1)
    }

    /// Flecks: pigment, not shading. Sparse, crisp, irregular, mostly dark, a few pale chalk ones.
    private static func drawFlecks(into ctx: CGContext, width: Int, height: Int, scale: CGFloat,
                                   tone: (r: Double, g: Double, b: Double), random: inout Random, dark: Bool) {
        let dpr = Double(scale)
        let count = Int((Double(width * height) / (dpr * dpr) * 0.0030 * (dark ? 0.22 : 1)).rounded())
        for _ in 0..<count {
            let x = random.next() * Double(width)
            let y = random.next() * Double(height)
            let pale = random.next() < 0.14
            let pigment: (r: Double, g: Double, b: Double) = pale
                ? (255, 255, 255)
                : (random.next() < 0.7 ? (26, 26, 26) : (74, 74, 74))
            ctx.setFillColor(CGColor(srgbRed: pigment.r / 255, green: pigment.g / 255, blue: pigment.b / 255, alpha: 1))
            ctx.setAlpha((pale ? 0.16 + random.next() * 0.24 : 0.26 + random.next() * 0.46) * (dark ? 0.5 : 1))
            let radius = (0.4 + random.next() * 1.0) * dpr * max(0.7, size * 0.85)
            let lobes = random.next() < 0.7 ? 1 : 2
            for _ in 0..<lobes {
                let offsetX = (random.next() - 0.5) * radius * 1.6
                let offsetY = (random.next() - 0.5) * radius * 1.6
                let rx = radius * (0.45 + random.next() * 0.7)
                let ry = radius * (0.28 + random.next() * 0.5)
                let rotation = random.next() * .pi
                ctx.saveGState()
                ctx.translateBy(x: x + offsetX, y: y + offsetY)
                ctx.rotate(by: rotation)
                ctx.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
        ctx.setAlpha(1)
    }
}
