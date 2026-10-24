/**
 * [INPUT]: AppKit, DesignSystem/Colors, DesignSystem/Spacing, DesignSystem/SurfaceViews.
 * [OUTPUT]: Segmented control and status line used by the picker, activation, settings and kept sheet.
 * [POS]: Shared After-language controls; native focus rings and keyboard reachability stay AppKit's.
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
        font = .systemFont(ofSize: 14, weight: .medium)
        inkFocusRingInset = 2
        inkFocusRingCornerRadius = 19
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
/// A hairline room bar drawn by one fill layer. The caller can animate the fill
/// width over the remaining session time; the layer runs off the main thread, so
/// the bar stays smooth even when the room is re-laying out.
final class FirstLineFillBar: NSView {
    private static let fractionAnimationKey = "fraction"
    private let fillLayer = CALayer()

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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityElement(false)
        fillLayer.anchorPoint = .zero
        fillLayer.position = .zero
        fillLayer.masksToBounds = true
        layer?.addSublayer(fillLayer)
        applyFillColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        fillLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
    }

    /// Set the target fraction. With a duration and motion enabled, one linear
    /// animation runs from the current presentation width to the target; repeated
    /// calls from a tick do not restart it.
    func setFraction(_ value: CGFloat, animatedOver duration: TimeInterval? = nil, reducesMotion: Bool = false) {
        let target = min(max(value, 0), 1)
        let targetWidth = bounds.width * target
        let currentWidth = fillLayer.presentation()?.bounds.width ?? fillLayer.bounds.width
        let hadAnimation = fillLayer.animation(forKey: Self.fractionAnimationKey) != nil
        fraction = target
        fillLayer.removeAnimation(forKey: Self.fractionAnimationKey)
        fillLayer.frame = CGRect(x: 0, y: 0, width: targetWidth, height: bounds.height)
        guard let duration, duration > 0.01, !reducesMotion,
              bounds.width > 0, (!hadAnimation || abs(currentWidth - targetWidth) > 0.5) else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        animation.fromValue = hadAnimation ? currentWidth : targetWidth
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
            fillLayer.backgroundColor = fillColor.cgColor
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
    private let dot = NSView()
    private var tone: Tone = .neutral

    init(text: String = "", tone: Tone = .neutral) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.tone = tone

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.stringValue = text
        addSubview(dot)
        addSubview(label)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
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
        return NSSize(width: labelSize.width + 16, height: max(18, labelSize.height))
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
        let color = tone == .bad ? FirstLineColors.redNSColor : FirstLineColors.inkNSColor
        label.textColor = tone == .bad ? FirstLineColors.redNSColor : FirstLineColors.chromeNSColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = color.withAlphaComponent(tone == .bad ? 1 : 0.35).cgColor
        }
    }
}
