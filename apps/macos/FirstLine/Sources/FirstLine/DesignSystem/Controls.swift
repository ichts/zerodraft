/**
 * [INPUT]: AppKit, DesignSystem/Colors, DesignSystem/Spacing, DesignSystem/SurfaceViews.
 * [OUTPUT]: After-language segmented control (a segment never compresses below its label), rounded top-edge fill bar and status line used by the picker, room, activation, settings and kept sheet.
 * [POS]: Shared After-language controls; keyboard reachability stays AppKit's, focus rings come from InkFocus.
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 */

import AppKit

// MARK: - Segmented control

@MainActor
final class FirstLineSegmentedControl: NSView {
    struct Item {
        let title: String
        let tag: Int
        let accessibilityLabel: String
    }

    var onChange: ((Int) -> Void)?
    private(set) var selectedTag: Int
    private let items: [Item]
    private var buttons: [FirstLineSegmentButton] = []
    private let track = FloodCanvasView(fillColor: FirstLineColors.segmentTrackNSColor)

    init(items: [Item], selectedTag: Int) {
        self.items = items
        self.selectedTag = selectedTag
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityRole(.radioGroup)

        track.translatesAutoresizingMaskIntoConstraints = false
        track.cornerRadius = 20
        track.clipsContent = true
        addSubview(track)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        for item in items {
            let button = FirstLineSegmentButton(segmentTitle: item.title, target: self, action: #selector(select(_:)))
            button.tag = item.tag
            button.setAccessibilityLabel(item.accessibilityLabel)
            button.setAccessibilityTitle(item.accessibilityLabel)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let widths = buttons.map(\.intrinsicContentSize.width).reduce(0, +)
        let spacing = CGFloat(max(0, buttons.count - 1)) * 2
        return NSSize(width: widths + spacing + 6, height: 40)
    }

    func button(forTag tag: Int) -> NSButton? {
        buttons.first { $0.tag == tag }
    }

    func select(tag: Int) {
        guard items.contains(where: { $0.tag == tag }) else { return }
        selectedTag = tag
        updateSelection()
    }

    @objc private func select(_ sender: FirstLineSegmentButton) {
        select(tag: sender.tag)
        onChange?(sender.tag)
    }

    private func updateSelection() {
        for button in buttons {
            button.isChosen = button.tag == selectedTag
        }
    }
}

@MainActor
private final class FirstLineSegmentButton: FirstLineInkFocusButton {
    var isChosen = false {
        didSet {
            state = isChosen ? .on : .off
            setAccessibilityValue(isChosen ? 1 : 0)
            refreshAppearance()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentTintColor = isChosen ? FirstLineColors.inkNSColor : FirstLineColors.chromeNSColor
        }
        needsDisplay = true
    }

    init(segmentTitle: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = segmentTitle
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .inline
        font = FirstLineTypography.smallMediumNSFont
        inkFocusRingInset = 2
        inkFocusRingCornerRadius = 19
        setContentCompressionResistancePriority(.required, for: .horizontal)
        wantsLayer = true
        setAccessibilityRole(.radioButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(52, super.intrinsicContentSize.width + 28), height: 34)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = 17
        var background: CGColor = NSColor.clear.cgColor
        var border: CGColor?
        var shadow: CGColor = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            background = isChosen ? FirstLineColors.sheetNSColor.cgColor : NSColor.clear.cgColor
            border = isChosen ? FirstLineColors.hairNSColor.cgColor : nil
            shadow = FirstLineColors.shadowNSColor.cgColor
        }
        layer?.borderWidth = isChosen ? 1 : 0
        layer?.borderColor = border
        layer?.backgroundColor = background
        layer?.shadowColor = shadow
        layer?.shadowOpacity = isChosen ? 0.12 : 0
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 17, yRadius: 17).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}

// MARK: - Status

@MainActor
/// A 2 pt top border following the paper corners. An animated width mask reveals
/// the fixed border, so the corners never stretch as the remaining time drains.
final class FirstLineFillBar: NSView {
    private static let fractionAnimationKey = "fraction"
    private let fillLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    var cornerRadius: CGFloat = FirstLineRadius.sheet { didSet { needsLayout = true } }
    var borderPath: CGPath? { borderLayer.path }

    /// The model target, readable by tests and snapshot fixtures. While a live
    /// session animates, the presentation layer shows the current fraction.
    private(set) var fraction: CGFloat = 0

    var fillColor: NSColor = FirstLineColors.inkNSColor {
        didSet { applyFillColor() }
    }

    /// Test-facing: the running fraction animation, if any.
    var fractionAnimation: CABasicAnimation? {
        fillLayer.animation(forKey: Self.fractionAnimationKey) as? CABasicAnimation
    }

    /// Test-facing: the width the render tree is actually presenting, nil before
    /// the first commit. This is the bar a person sees, not the model target.
    var presentedWidth: CGFloat? { fillLayer.presentation()?.bounds.width }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityElement(false)
        fillLayer.anchorPoint = .zero
        fillLayer.position = .zero
        fillLayer.masksToBounds = true
        fillLayer.backgroundColor = NSColor.black.cgColor
        borderLayer.mask = fillLayer
        layer?.addSublayer(borderLayer)
        applyFillColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        borderLayer.frame = bounds
        borderLayer.path = topBorderPath()
        fillLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
    }

    // CSS border-top with zero-width side borders: both arcs taper to the side edge.
    private func topBorderPath() -> CGPath {
        let r = min(cornerRadius, bounds.width / 2, bounds.height)
        let inner = max(0, r - 2)
        let w = bounds.width
        let h = bounds.height
        let k: CGFloat = 0.5522847498
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h - r))
        path.addCurve(to: CGPoint(x: r, y: h), control1: CGPoint(x: 0, y: h - r + k * r),
                      control2: CGPoint(x: r - k * r, y: h))
        path.addLine(to: CGPoint(x: w - r, y: h))
        path.addCurve(to: CGPoint(x: w, y: h - r), control1: CGPoint(x: w - r + k * r, y: h),
                      control2: CGPoint(x: w, y: h - r + k * r))
        path.addCurve(to: CGPoint(x: w - r, y: h - 2), control1: CGPoint(x: w, y: h - r + k * inner),
                      control2: CGPoint(x: w - r + k * r, y: h - 2))
        path.addLine(to: CGPoint(x: r, y: h - 2))
        path.addCurve(to: CGPoint(x: 0, y: h - r), control1: CGPoint(x: r - k * r, y: h - 2),
                      control2: CGPoint(x: 0, y: h - r + k * inner))
        path.closeSubpath()
        return path
    }

    /// Set the target fraction. With a duration and motion enabled, one linear
    /// animation runs from the current presentation width to the target; repeated
    /// calls from a tick do not restart it.
    func setFraction(_ value: CGFloat, animatedOver duration: TimeInterval? = nil,
                     reducesMotion: Bool = false, from startFraction: CGFloat? = nil) {
        let target = min(max(value, 0), 1)
        let targetWidth = bounds.width * target
        let hadAnimation = fillLayer.animation(forKey: Self.fractionAnimationKey) != nil
        let currentWidth = startFraction.map { bounds.width * min(max($0, 0), 1) }
            ?? fillLayer.presentation()?.bounds.width
            ?? fillLayer.bounds.width
        fraction = target
        fillLayer.removeAnimation(forKey: Self.fractionAnimationKey)
        fillLayer.frame = CGRect(x: 0, y: 0, width: targetWidth, height: bounds.height)
        guard let duration, duration > 0.01, !reducesMotion,
              bounds.width > 0, (!hadAnimation || abs(currentWidth - targetWidth) > 0.5) else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        // Start from what is on screen. A fresh run has no animation yet, so the
        // current width is the model width set by the caller (the full bar); using
        // targetWidth here animated 0 -> 0 and drew no bar at all.
        animation.fromValue = currentWidth
        animation.toValue = targetWidth
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = true
        fillLayer.add(animation, forKey: Self.fractionAnimationKey)
    }

    /// Snaps the fill to a fraction for a static capture without starting an animation.
    func settleForRendering(_ value: CGFloat) {
        fillLayer.removeAllAnimations()
        fraction = min(max(value, 0), 1)
        fillLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
    }

    private func applyFillColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            borderLayer.fillColor = fillColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyFillColor()
    }
}

final class FirstLineStatusView: NSView {
    enum Tone { case neutral, bad }

    private let label = NSTextField(labelWithString: "")
    private var tone: Tone = .neutral

    init(text: String = "", tone: Tone = .neutral) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.tone = tone

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.stringValue = text
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyTone()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setText(_ text: String, tone: Tone = .neutral) {
        guard label.stringValue != text || self.tone != tone else { return }
        self.tone = tone
        label.stringValue = text
        applyTone()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width, height: max(18, labelSize.height))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTone()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTone()
    }

    private func applyTone() {
        label.textColor = tone == .bad ? FirstLineColors.redTextNSColor : FirstLineColors.chromeNSColor
    }
}
