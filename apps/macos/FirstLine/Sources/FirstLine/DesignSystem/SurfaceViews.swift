/**
 * [INPUT]: AppKit, DesignSystem/Colors, DesignSystem/Spacing.
 * [OUTPUT]: FirstLineShadowView (ink ladder behind a surface) and FirstLineCardView (sheet + shadow + content insets).
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

    private struct Spec {
        let opacity: CGFloat
        let radius: CGFloat
        let offset: CGSize
        let inkTinted: Bool
    }

    // Approved tokens.swift SheetShadow: black 5% contact, ink 12% and 20% layers.
    private let lightSpecs = [
        Spec(opacity: 0.05, radius: 0.5, offset: CGSize(width: 0, height: -1), inkTinted: false),
        Spec(opacity: 0.12, radius: 12, offset: CGSize(width: 0, height: -12), inkTinted: true),
        Spec(opacity: 0.20, radius: 36, offset: CGSize(width: 0, height: -36), inkTinted: true),
    ]
    private let darkSpecs = [
        Spec(opacity: 0.25, radius: 0.5, offset: CGSize(width: 0, height: -1), inkTinted: false),
        Spec(opacity: 0.60, radius: 28, offset: CGSize(width: 0, height: -28), inkTinted: false),
    ]
    private var shadowLayers: [CALayer] = []

    /// How far the shadow may reach past the sheet, in pt; nil leaves the approved spec untouched. A window with no
    /// ground of its own (D-102) clips the shadow at its edge, which is a hard step over a wallpaper, so the room's
    /// paper asks for the gutter it has and each layer's radius and offset shrink together until their reach fits.
    var reach: CGFloat? {
        didSet { updateLayers() }
    }

    /// The farthest any layer of the current appearance's shadow reaches below the sheet.
    var effectiveReach: CGFloat {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return (dark ? darkSpecs : lightSpecs).map { fitted($0).radius + abs(fitted($0).offset.height) }.max() ?? 0
    }

    private func fitted(_ spec: Spec) -> Spec {
        let natural = spec.radius + abs(spec.offset.height)
        guard let reach, natural > reach else { return spec }
        let scale = reach / natural
        return Spec(opacity: spec.opacity, radius: spec.radius * scale,
                    offset: CGSize(width: spec.offset.width * scale, height: spec.offset.height * scale),
                    inkTinted: spec.inkTinted)
    }

    init(cornerRadius: CGFloat = FirstLineRadius.card, fillColor: NSColor = FirstLineColors.sheetNSColor) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        (lightSpecs + darkSpecs).forEach { _ in
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
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let specs = dark ? darkSpecs : lightSpecs
        let visible = Array(shadowLayers.prefix(specs.count))
        // Hidden spare layers stay out of the render tree when the mode uses fewer layers.
        for sublayer in shadowLayers where !visible.contains(sublayer) { sublayer.isHidden = true }
        for (sublayer, natural) in zip(visible, specs) {
            let spec = fitted(natural)
            sublayer.isHidden = false
            sublayer.frame = bounds
            sublayer.cornerRadius = cornerRadius
            sublayer.backgroundColor = resolved(fillColor)
            sublayer.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                         cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            sublayer.shadowColor = resolved(spec.inkTinted ? FirstLineColors.inkNSColor : .black)
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
