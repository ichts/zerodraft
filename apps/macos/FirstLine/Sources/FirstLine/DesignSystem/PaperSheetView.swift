/**
 * [INPUT]: the paper's laid-out size, the window's backing scale, the paper mode its appearance shows
 *          (FirstLineColors.mode(for:)), and the web's paper tokens (tokens.css v3: `--paper-tone`, `--paper-grain`,
 *          `--paper-cloud`, `--paper-light`, D-119).
 * [OUTPUT]: PaperSheetView - the writing sheet: the mode's tone, its grain and cloud and the lamp's light, rendered
 *           once into a cached CGImage per size and mode, with the sheet ring and rounded clip the room needs;
 *           PaperSheetCache - the small cache that lets the picker render the room's sheet off the main thread
 *           before Begin, so the room's first paint finds the finished paper instead of building it;
 *           PaperField - the renderer and PaperField.drawLight, the light the wash multiplies by as well.
 * [POS]: The Mac half of the sheet the web paints from tokens.css; the room, its failure screen and the kept sheet
 *        all sit on this one paper. Cards, fields and controls keep FirstLineColors.sheetNSColor.
 * [PROTOCOL]: Keep the renderer in step with tokens.css (same SVG filters, seeds, colours and gradient stops);
 *             paint on size or mode change only, never on typing. Then check FirstLine/AGENTS.md.
 *
 * What the web draws (`[data-paper]`): the tone; the grain, a 240 px stitched fractalNoise tile repeated from the
 * top-left; the cloud, one 1600x1100 fractalNoise image covering the sheet from its centre; then the light, a radial
 * gradient multiplied over the sheet. Lamp and Slate carry all three; Paper is its plain tone. The noise is the SVG
 * reference generator (Turbulence), sampled where the browser samples it, and its linearRGB colours are converted
 * to sRGB before compositing, as the browser does.
 *
 * Why a cached image: the field is ~5 M device pixels at 2x. One image per size costs a fraction of a second once
 * and is then free. The image is built synchronously on first draw, so the window's first paint already carries
 * the paper instead of flashing a flat tone; a live window drag reuses the previous image stretched and rebuilds it
 * when the drag ends. The picker warms the room's size ahead (D-096), so Begin finds it built.
 */

import AppKit
import CoreGraphics

@MainActor
final class PaperSheetView: NSView {
    /// The sheet's ring on the paper.
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

    private var paperImage: CGImage?
    private var imageKey = ""
    /// How many times the sheet has been drawn; typing and warn ticks must leave it unchanged.
    private(set) var paints = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateLayerShape()
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }

    /// A veil that never takes a click or a key (the room's entrance curtain, D-096).
    var passesHitTests = false
    override func hitTest(_ point: NSPoint) -> NSView? { passesHitTests ? nil : super.hitTest(point) }

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

    /// The sheet for the current size and mode, built on demand.
    private func currentPaper() -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 1, height > 1 else { return nil }
        let mode = FirstLineColors.mode(for: effectiveAppearance)
        let key = PaperSheetCache.key(width: width, height: height, scale: scale, mode: mode)
        if key == imageKey, let paperImage { return paperImage }
        guard let image = PaperSheetCache.shared.sheet(width: width, height: height, scale: scale, mode: mode) else { return nil }
        imageKey = key
        paperImage = image
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        paints += 1
        let rect = bounds
        ctx.saveGState()
        if cornerRadius > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.clip()
        }
        // A window drag reuses the last field stretched and rebuilds once when the drag ends, so the
        // ~5 M pixel field is never regenerated per drag frame.
        let image = inLiveResize ? paperImage : currentPaper()
        if let image {
            ctx.interpolationQuality = inLiveResize ? .high : .none
            ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        } else {
            effectiveAppearance.performAsCurrentDrawingAppearance { FirstLineColors.paperNSColor.setFill() }
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

/// One finished sheet kept for the next room. The image is immutable once rendered, so sharing it between the
/// render queue and the main thread is safe.
private struct RenderedSheet: @unchecked Sendable {
    let image: CGImage
}

/// The most recent rendered sheets, keyed by pixel size, scale and mode. Three entries cover the live window, one
/// resize behind it and the mode switched from; the oldest goes first.
@MainActor
final class PaperSheetCache {
    static let shared = PaperSheetCache()
    static let capacity = 3

    private var entries: [(key: String, image: CGImage)] = []
    private var warming: Set<String> = []
    private var builds: [String: Int] = [:]

    nonisolated static func key(width: Int, height: Int, scale: CGFloat, mode: PaperMode) -> String {
        "\(width)x\(height)@\(scale)-\(mode.rawValue)"
    }

    /// How many times this size was built on the caller's turn because the cache missed; tests assert it stays
    /// unchanged across a picker-to-room transition.
    func synchronousBuilds(width: Int, height: Int, scale: CGFloat, mode: PaperMode) -> Int {
        builds[Self.key(width: width, height: height, scale: scale, mode: mode)] ?? 0
    }

    /// True once the sheet for this size is cached.
    func holds(width: Int, height: Int, scale: CGFloat, mode: PaperMode) -> Bool {
        cached(Self.key(width: width, height: height, scale: scale, mode: mode)) != nil
    }

    /// The sheet for this size: the cached one when it matches, otherwise built now and remembered.
    func sheet(width: Int, height: Int, scale: CGFloat, mode: PaperMode) -> CGImage? {
        let wanted = Self.key(width: width, height: height, scale: scale, mode: mode)
        if let hit = cached(wanted) { return hit }
        builds[wanted, default: 0] += 1
        guard let built = PaperField.render(width: width, height: height, scale: scale, mode: mode) else { return nil }
        store(built, as: wanted)
        return built
    }

    /// Renders the sheet for this size off the main thread unless it is already cached or on its way.
    func prewarm(width: Int, height: Int, scale: CGFloat, mode: PaperMode) {
        guard width > 1, height > 1 else { return }
        let wanted = Self.key(width: width, height: height, scale: scale, mode: mode)
        guard cached(wanted) == nil, warming.insert(wanted).inserted else { return }
        Task.detached(priority: .userInitiated) {
            let built = PaperField.render(width: width, height: height, scale: scale, mode: mode).map(RenderedSheet.init)
            await MainActor.run {
                let cache = PaperSheetCache.shared
                cache.warming.remove(wanted)
                if let built, cache.cached(wanted) == nil { cache.store(built.image, as: wanted) }
            }
        }
    }

    private func cached(_ key: String) -> CGImage? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.image
    }

    private func store(_ image: CGImage, as key: String) {
        entries.append((key, image))
        if entries.count > Self.capacity { entries.removeFirst() }
    }
}

/// The renderer: tokens.css's paper, layer by layer.
enum PaperField {
    /// One fractalNoise layer: its feTurbulence and the colour matrix's constant colour (linearRGB) and alpha line.
    struct Noise: Sendable {
        let seed: Int
        let frequency: Double
        let colour: (r: Double, g: Double, b: Double)
        let gain: Double
        let offset: Double
    }

    /// One mode's paper; `nil` layers are `none`.
    struct Recipe: Sendable {
        let tone: UInt32
        let grain: Noise?
        let cloud: Noise?
        /// `--paper-light` stops, (position, sRGB hex).
        let light: [(CGFloat, UInt32)]
    }

    static let grainTile: Double = 240
    static let cloudSize = (width: 1600.0, height: 1100.0)
    /// The light's ellipse, `ellipse 90% 85% at 50% 35%`.
    static let lightRadii = (x: 0.90, y: 0.85)
    static let lightCentre = (x: 0.50, y: 0.35)

    static func recipe(_ mode: PaperMode) -> Recipe {
        let tone = FirstLineColors.Palette.of(mode).paper
        switch mode {
        case .paper:
            return Recipe(tone: tone, grain: nil, cloud: nil, light: [])
        case .lamp:
            return Recipe(tone: tone,
                          grain: Noise(seed: 4, frequency: 0.85, colour: (0.30, 0.24, 0.16), gain: 1.1, offset: -0.36),
                          cloud: Noise(seed: 11, frequency: 0.006, colour: (0.35, 0.28, 0.18), gain: 0.5, offset: -0.12),
                          light: [(0, 0xFFFCF4), (0.45, 0xFBF3E2), (0.78, 0xF4E9D3), (1, 0xF1E3C8)])
        case .slate:
            return Recipe(tone: tone,
                          grain: Noise(seed: 4, frequency: 0.85, colour: (0.10, 0.11, 0.12), gain: 1.1, offset: -0.36),
                          cloud: Noise(seed: 11, frequency: 0.006, colour: (0.14, 0.16, 0.17), gain: 0.5, offset: -0.12),
                          light: [(0, 0xFFFFFF), (0.50, 0xF8F6F2), (1, 0xEEEBE5)])
        }
    }

    private static func srgb(_ linear: Double) -> Double {
        linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// A noise layer as an image whose first row is its top: pixel (i, j) carries the colour matrix's output at
    /// the user-space point `sample(i, j)`, its alpha `clamp(gain * a + offset)`.
    private static func noiseImage(_ noise: Noise, width: Int, height: Int,
                                   tile: (x: Double, y: Double, width: Double, height: Double)?,
                                   sample: (Int, Int) -> (Double, Double)) -> CGImage? {
        guard width > 0, height > 0, let context = makeContext(width: width, height: height),
              let raw = context.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let turbulence = Turbulence(seed: noise.seed)
        let colour = (srgb(noise.colour.r), srgb(noise.colour.g), srgb(noise.colour.b))
        for j in 0..<height {
            for i in 0..<width {
                let (x, y) = sample(i, j)
                let a = min(1, max(0, turbulence.fractal(3, x: x, y: y, baseX: noise.frequency, baseY: noise.frequency,
                                                         octaves: 3, tile: tile)))
                let alpha = min(1, max(0, noise.gain * a + noise.offset))
                let index = (j * width + i) * 4
                pixels[index] = UInt8((colour.0 * alpha * 255).rounded())
                pixels[index + 1] = UInt8((colour.1 * alpha * 255).rounded())
                pixels[index + 2] = UInt8((colour.2 * alpha * 255).rounded())
                pixels[index + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return context.makeImage()
    }

    /// Multiplies the mode's light over `rect` of `context` (unflipped, origin bottom-left), the web's
    /// `[data-paper]::after`. The room's wash takes the same light, so a washed sheet is lit exactly like the sheet.
    static func drawLight(_ mode: PaperMode, in context: CGContext, rect: CGRect) {
        let stops = recipe(mode).light
        guard stops.count > 1 else { return }
        let colours = stops.map { stop -> CGColor in
            let rgb = stop.1
            return CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray,
                                        locations: stops.map(\.0)) else { return }
        context.saveGState()
        context.clip(to: rect)
        context.setBlendMode(.multiply)
        context.translateBy(x: rect.minX + rect.width * lightCentre.x, y: rect.maxY - rect.height * lightCentre.y)
        context.scaleBy(x: rect.width * lightRadii.x, y: rect.height * lightRadii.y)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1,
                                   options: [.drawsAfterEndLocation])
        context.restoreGState()
    }

    /// The finished sheet at `width` x `height` device pixels.
    static func render(width: Int, height: Int, scale: CGFloat, mode: PaperMode) -> CGImage? {
        guard width > 1, height > 1, let context = makeContext(width: width, height: height) else { return nil }
        let recipe = recipe(mode)
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let tone = recipe.tone
        context.setFillColor(CGColor(srgbRed: CGFloat((tone >> 16) & 255) / 255, green: CGFloat((tone >> 8) & 255) / 255,
                                     blue: CGFloat(tone & 255) / 255, alpha: 1))
        context.fill(full)
        let s = Double(scale)

        if let grain = recipe.grain {
            // One 240 px tile at device resolution, stitched over the filter region (-10%, 120%), repeated from
            // the sheet's top-left like `background-position: 0 0`.
            let side = Int((grainTile * s).rounded())
            let region = (x: -grainTile * 0.1, y: -grainTile * 0.1, width: grainTile * 1.2, height: grainTile * 1.2)
            if let tile = noiseImage(grain, width: side, height: side, tile: region, sample: { i, j in
                ((Double(i) + 0.5) / s + 0.5, (Double(j) + 0.5) / s + 0.5)
            }) {
                context.saveGState()
                context.interpolationQuality = .none
                context.draw(tile, in: CGRect(x: 0, y: CGFloat(height - side), width: CGFloat(side), height: CGFloat(side)),
                             byTiling: true)
                context.restoreGState()
            }
        }

        if let cloud = recipe.cloud {
            // The cloud covers the sheet from its centre (`background-size: cover`). It is a few-hundred-pixel
            // field, so it is evaluated on an 8-pixel grid and drawn smoothed.
            let cover = max(Double(width) / (cloudSize.width * s), Double(height) / (cloudSize.height * s))
            let drawn = (width: cloudSize.width * cover * s, height: cloudSize.height * cover * s)
            let step = 8.0
            let grid = (width: Int((drawn.width / step).rounded(.up)), height: Int((drawn.height / step).rounded(.up)))
            if let image = noiseImage(cloud, width: grid.width, height: grid.height, tile: nil, sample: { i, j in
                ((Double(i) + 0.5) * step / s / cover + 0.5, (Double(j) + 0.5) * step / s / cover + 0.5)
            }) {
                let origin = (x: (Double(width) - drawn.width) / 2, y: (Double(height) - drawn.height) / 2)
                context.saveGState()
                context.interpolationQuality = .high
                // The image's first row is its top: place that top `origin.y` under the sheet's top edge.
                let size = (width: Double(grid.width) * step, height: Double(grid.height) * step)
                context.draw(image, in: CGRect(x: origin.x, y: Double(height) - origin.y - size.height,
                                               width: size.width, height: size.height))
                context.restoreGState()
            }
        }

        drawLight(mode, in: context, rect: full)
        return context.makeImage()
    }
}
