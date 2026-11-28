/**
 * [INPUT]: AppKit, DesignSystem/Colors, DesignSystem/Spacing.
 * [OUTPUT]: FirstLineShadowView (the paper's shadow stack behind a surface, D-124) and FirstLineCardView (sheet + shadow + content insets).
 * [POS]: Shared page/sheet depth primitives; the only shadow in the app, matching the sheet-shadow token.
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 */

import AppKit

@MainActor
final class FirstLineShadowView: NSView {
    var cornerRadius: CGFloat = FirstLineRadius.card {
        didSet { updateLayers() }
    }

    var fillColor: NSColor = FirstLineColors.sheetNSColor {
        didSet { updateLayers() }
    }

    /// One CSS box-shadow layer: `0 offset blur spread colour`. CALayer blurs by `radius`, half the CSS blur, and the
    /// spread grows or shrinks the shadow path.
    private struct Spec {
        let opacity: CGFloat
        let radius: CGFloat
        let offset: CGSize
        let spread: CGFloat
        let inkTinted: Bool

        init(_ opacity: CGFloat, blur: CGFloat, y: CGFloat, spread: CGFloat, inkTinted: Bool) {
            self.opacity = opacity
            radius = blur / 2
            offset = CGSize(width: 0, height: -y)
            self.spread = spread
            self.inkTinted = inkTinted
        }

        init(opacity: CGFloat, radius: CGFloat, offset: CGSize, spread: CGFloat, inkTinted: Bool) {
            self.opacity = opacity
            self.radius = radius
            self.offset = offset
            self.spread = spread
            self.inkTinted = inkTinted
        }
    }

    /// The sheet's shadow per paper (D-124): the white sheet's ink-tinted stack (`--sheet-shadow`), a black one on black.
    private static func specs(black: Bool) -> [Spec] {
        black
            ? [Spec(0.30, blur: 0, y: 0, spread: 1, inkTinted: false),
               Spec(0.60, blur: 14, y: 6, spread: -4, inkTinted: false),
               Spec(0.60, blur: 48, y: 24, spread: -16, inkTinted: false)]
            : [Spec(0.07, blur: 0, y: 0, spread: 1, inkTinted: true),
               Spec(0.05, blur: 4, y: 2, spread: 0, inkTinted: true),
               Spec(0.12, blur: 24, y: 12, spread: -8, inkTinted: true),
               Spec(0.20, blur: 72, y: 36, spread: -24, inkTinted: true)]
    }
    private static let layerCount = 4
    private var shadowLayers: [CALayer] = []

    /// How far the shadow may reach past the sheet, in pt; nil leaves the approved spec untouched. A window with no
    /// ground of its own (D-102) clips the shadow at its edge, which is a hard step over a wallpaper, so the room's
    /// paper asks for the gutter it has and each layer's radius and offset shrink together until their reach fits.
    var reach: CGFloat? {
        didSet { updateLayers() }
    }

    /// The farthest any layer of the current appearance's shadow reaches below the sheet.
    var effectiveReach: CGFloat {
        Self.specs(black: FirstLineColors.showsBlack(effectiveAppearance))
            .map { fitted($0).radius + abs(fitted($0).offset.height) + fitted($0).spread }.max() ?? 0
    }

    private func fitted(_ spec: Spec) -> Spec {
        let natural = spec.radius + abs(spec.offset.height)
        guard let reach, natural > reach else { return spec }
        let scale = reach / natural
        return Spec(opacity: spec.opacity, radius: spec.radius * scale,
                    offset: CGSize(width: spec.offset.width * scale, height: spec.offset.height * scale),
                    spread: spec.spread, inkTinted: spec.inkTinted)
    }

    init(cornerRadius: CGFloat = FirstLineRadius.card, fillColor: NSColor = FirstLineColors.sheetNSColor) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        (0..<Self.layerCount).forEach { _ in
            let sublayer = CALayer()
            sublayer.masksToBounds = false
            layer?.addSublayer(sublayer)
            shadowLayers.append(sublayer)
        }
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        updateLayers()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayers()
    }

    private func updateLayers() {
        guard bounds.width > 0, bounds.height > 0, let parentLayer = layer else { return }
        let specs = Self.specs(black: FirstLineColors.showsBlack(effectiveAppearance))
        let visible = Array(shadowLayers.prefix(specs.count))
        // Hidden spare layers stay out of the render tree when the paper uses fewer layers.
        for sublayer in shadowLayers where !visible.contains(sublayer) { sublayer.isHidden = true }
        for (sublayer, natural) in zip(visible, specs) {
            let spec = fitted(natural)
            sublayer.isHidden = false
            sublayer.frame = bounds
            sublayer.cornerRadius = cornerRadius
            sublayer.backgroundColor = resolved(fillColor)
            let path = bounds.insetBy(dx: -spec.spread, dy: -spec.spread)
            let corner = max(cornerRadius + spec.spread, 0)
            sublayer.shadowPath = CGPath(roundedRect: path, cornerWidth: corner, cornerHeight: corner, transform: nil)
            sublayer.shadowColor = resolved(spec.inkTinted ? FirstLineColors.paperInkNSColor : .black)
            sublayer.shadowOpacity = Float(spec.opacity)
            sublayer.shadowRadius = spec.radius
            sublayer.shadowOffset = spec.offset
        }
        parentLayer.masksToBounds = false
    }

    private func resolved(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }
}

@MainActor
final class FirstLineCardView: NSView {
    let contentView = NSView()
    private let shadowView: FirstLineShadowView
    private let surface: FloodCanvasView

    init(cornerRadius: CGFloat = FirstLineRadius.card,
         contentInsets: NSEdgeInsets = NSEdgeInsets(top: 44, left: 48, bottom: 44, right: 48)) {
        shadowView = FirstLineShadowView(cornerRadius: cornerRadius)
        surface = FloodCanvasView(fillColor: FirstLineColors.sheetNSColor)
        surface.cornerRadius = cornerRadius
        surface.clipsContent = true
        surface.borderColor = FirstLineColors.sheetRingNSColor
        surface.borderWidth = 1
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        [shadowView, surface, contentView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            shadowView.topAnchor.constraint(equalTo: topAnchor),
            shadowView.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
