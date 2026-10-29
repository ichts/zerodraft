/*
 * [INPUT]: The bundled chip glyph layer (writeitdown/logo/write-it-down-lockup.svg: the split W and wordmark on the plate's viewBox), the After colour tokens (page plate, ink glyphs, hair-2 edge) and a type size.
 * [OUTPUT]: The A mark chip: the app icon's squircle plate with the split W on it, followed by the wordmark on the same baseline, in the web header's 7.467 x 1.046 em box.
 * [POS]: The native chip-and-wordmark lockup; the Mac picker uses it so the front door shows the same mark the web header shows (D-075).
 * [PROTOCOL]: Keep the em ratios and the theme roles aligned with design/DESIGN.md section 11.6.
 */
import AppKit

@MainActor
final class BrandChipLockupView: NSView {
    /// The web header lockup box, in ems (`design/DESIGN.md` 11.3).
    static let emWidth: CGFloat = 7.467
    static let emHeight: CGFloat = 1.046
    /// The chip is the app icon's 824/1024 squircle: corner radius 22.33% of the plate.
    static let plateCornerShare: CGFloat = 0.2233
    static let pickerTypeSize: CGFloat = 21
    /// The two theme roles the chip draws with. The web header's plate is the sheet token
    /// on the page wall; the picker's lockup sits on the sheet card, so the plate takes
    /// the page token instead and keeps the same plate-against-wall relation the header
    /// has (a barely tinted plate in light, a clearly darker one in dark, D-075).
    static var plateFillColor: NSColor { FirstLineColors.pageNSColor }
    static var plateEdgeColor: NSColor { FirstLineColors.hairStrongNSColor }

    private let plate = PlateView()
    private let wordmark = NSImageView()
    private(set) var typeSize: CGFloat

    init(typeSize: CGFloat = BrandChipLockupView.pickerTypeSize) {
        self.typeSize = typeSize
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Write It Down")

        plate.translatesAutoresizingMaskIntoConstraints = true
        addSubview(plate)

        wordmark.translatesAutoresizingMaskIntoConstraints = true
        wordmark.imageScaling = .scaleProportionallyUpOrDown
        wordmark.image = Self.wordmarkImage()
        wordmark.image?.isTemplate = true
        wordmark.contentTintColor = FirstLineColors.inkNSColor
        addSubview(wordmark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var chipFrame: NSRect { plate.frame }
    var wordmarkFrame: NSRect { wordmark.frame }
    var chipCornerRadius: CGFloat { bounds.height * Self.plateCornerShare }
    var wordmarkImage: NSImage? { wordmark.image }

    override var intrinsicContentSize: NSSize {
        NSSize(width: typeSize * Self.emWidth, height: typeSize * Self.emHeight)
    }

    override func layout() {
        super.layout()
        let side = bounds.height
        plate.frame = NSRect(x: 0, y: 0, width: side, height: side)
        wordmark.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        plate.needsDisplay = true
    }

    /// The chip plate: the page token as fill, the hair-2 edge as its one 1 pt boundary,
    /// the same two roles the web header uses (11.6).
    private final class PlateView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let radius = bounds.height * BrandChipLockupView.plateCornerShare
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: radius, yRadius: radius)
            BrandChipLockupView.plateFillColor.setFill()
            path.fill()
            BrandChipLockupView.plateEdgeColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private static func wordmarkImage() -> NSImage? {
        guard let url = BundledResources.bundle.url(forResource: "write-it-down-lockup", withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
