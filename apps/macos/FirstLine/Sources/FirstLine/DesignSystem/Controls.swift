/**
 * [INPUT]: AppKit, DesignSystem/Colors, DesignSystem/Spacing, DesignSystem/SurfaceViews.
 * [OUTPUT]: Segmented control, tag, status line and fill bar used by the picker, activation and room.
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
private final class FirstLineSegmentButton: NSButton {
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
        focusRingType = .default
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

// MARK: - Tag

@MainActor
final class FirstLineTagView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let dotBackground = FloodCanvasView(fillColor: FirstLineColors.redNSColor)
    private let background = FloodCanvasView(fillColor: FirstLineColors.tagBackgroundNSColor)

    init(text: String = "") {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        background.translatesAutoresizingMaskIntoConstraints = false
        background.cornerRadius = 12
        background.clipsContent = true
        background.borderColor = FirstLineColors.hairNSColor
        background.borderWidth = 1
        addSubview(background)

        dotBackground.translatesAutoresizingMaskIntoConstraints = false
        dotBackground.cornerRadius = 3
        dotBackground.clipsContent = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = FirstLineColors.chromeNSColor
        label.stringValue = text
        label.lineBreakMode = .byTruncatingTail
        addSubview(dotBackground)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            dotBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dotBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotBackground.widthAnchor.constraint(equalToConstant: 6),
            dotBackground.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dotBackground.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setText(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + 23, height: max(24, labelSize.height))
    }

    func setText(_ text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        setAccessibilityLabel(text)
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Status

@MainActor
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

// MARK: - Fill bar

@MainActor
final class FirstLineFillBar: NSView {
    var fraction: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var fillColor: NSColor = FirstLineColors.inkNSColor {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let width = bounds.width * min(max(fraction, 0), 1)
        guard width > 0 else { return }
        fillColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: bounds.height)).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
