/**
 * [INPUT]: AppKit, PaperMode, DesignSystem/Colors (paper roles), Typography, InkFocus.
 * [OUTPUT]: PaperModeSwitch - the room's mode switch: `Lamp`, `Paper`, `Slate` as one radio group named `Paper`,
 *           the current mode underlined in ink, the others quiet, hover in ink; it reports a choice through
 *           `onChoose` and never keeps focus for itself.
 * [POS]: The Mac twin of the web room header's `.modes` fieldset (site.css `.modes`, room.js roomModes); the room
 *        places it in the sheet's top-left corner, across the clock row (D-120).
 * [PROTOCOL]: Keep the labels, legend, sizes and states in step with writeitdown/site.css `.modes`; then check
 *             FirstLine/AGENTS.md.
 *
 * Choosing a paper is not input: the room hands focus straight back to the writing, and the draft, the phase and
 * the silence clock carry on. A click never takes focus (an NSButton click does not), and with Full Keyboard
 * Access a focused label takes Space, Return and the arrow keys, as a native radio group does.
 */

import AppKit

@MainActor
final class PaperModeSwitch: NSView {
    static let legend = "Paper"
    /// `.modes label`: 44 x 44 at least, 9 pt each side, 2 pt apart, 400 13 pt.
    static let minimumSide: CGFloat = 44
    static let padding: CGFloat = 9
    static let gap: CGFloat = 2
    static let underlineOffset: CGFloat = 5

    var onChoose: ((PaperMode) -> Void)?
    var mode: PaperMode {
        didSet { if mode != oldValue { options.forEach { $0.refresh() } } }
    }

    private(set) var options: [PaperModeOption] = []
    private let stack = NSStackView()

    init(mode: PaperMode) {
        self.mode = mode
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = Self.gap
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for choice in PaperMode.allCases {
            let option = PaperModeOption(choice: choice, owner: self)
            options.append(option)
            stack.addArrangedSubview(option)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(Self.legend)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    fileprivate func choose(_ choice: PaperMode) {
        guard choice != mode else { return }
        mode = choice
        onChoose?(choice)
    }

    fileprivate func step(from choice: PaperMode, by offset: Int) {
        let all = PaperMode.allCases
        guard let index = all.firstIndex(of: choice) else { return }
        let next = all[(index + offset + all.count) % all.count]
        window?.makeFirstResponder(options.first { $0.choice == next })
        choose(next)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        options.forEach { $0.refresh() }
    }
}

/// One label of the switch.
@MainActor
final class PaperModeOption: FirstLineInkFocusButton {
    let choice: PaperMode
    private weak var owner: PaperModeSwitch?
    private var hover = false
    private var tracking: NSTrackingArea?
    /// The chosen label's underline. The button draws through its layer (`wantsUpdateLayer`), so `draw(_:)` never
    /// runs; the line is its own sublayer, placed in `layout()` and coloured in `updateLayer()`.
    private let underline = CALayer()

    var isChosen: Bool { owner?.mode == choice }

    /// The colour the label is drawn in: ink when chosen or under the pointer, otherwise the quiet role.
    var labelColor: NSColor {
        isChosen || hover ? FirstLineColors.paperInkNSColor : FirstLineColors.paperQuietNSColor
    }

    init(choice: PaperMode, owner: PaperModeSwitch) {
        self.choice = choice
        self.owner = owner
        super.init(frame: .zero)
        title = choice.label
        target = self
        action = #selector(chosen)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .inline
        font = FirstLineTypography.smallNSFont
        onPaper = true
        // `outline: 2px solid; outline-offset: -4px; border-radius: var(--r-ctl)`: the ring's centre line sits
        // 5 pt inside the label, its corner the control radius less that inset.
        inkFocusRingInset = -5
        inkFocusRingCornerRadius = FirstLineRadius.control - 5
        setAccessibilityRole(.radioButton)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        wantsLayer = true
        underline.actions = ["frame": NSNull(), "position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull(),
                             "hidden": NSNull()]
        layer?.addSublayer(underline)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: FirstLineTypography.smallNSFont])
        return NSSize(width: max(PaperModeSwitch.minimumSide, ceil(text.width) + PaperModeSwitch.padding * 2),
                      height: PaperModeSwitch.minimumSide)
    }

    @objc private func chosen() { owner?.choose(choice) }

    func refresh() {
        let color = labelColor
        contentTintColor = color
        attributedTitle = NSAttributedString(string: choice.label, attributes: [
            .font: FirstLineTypography.smallNSFont, .foregroundColor: color,
        ])
        setAccessibilityValue(isChosen)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if underline.superlayer == nil { layer?.addSublayer(underline) }
        underline.isHidden = underlineRect == nil
        underline.frame = underlineRect ?? .zero
    }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            underline.backgroundColor = labelColor.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        refresh()
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?, .upArrow?: owner?.step(from: choice, by: -1)
        case .rightArrow?, .downArrow?: owner?.step(from: choice, by: 1)
        default: super.keyDown(with: event)
        }
    }

    /// The baseline of the label, in this view's coordinates, for the underline and for tests.
    var labelBaseline: CGFloat {
        let font = FirstLineTypography.smallNSFont
        let lineHeight = font.ascender - font.descender
        let top = (bounds.height - lineHeight) / 2
        return isFlipped ? top + font.ascender : bounds.height - top - font.ascender
    }

    /// The chosen mode's 1 pt underline, 5 pt under the baseline (`text-underline-offset: 5px`), across the word.
    var underlineRect: NSRect? {
        guard isChosen else { return nil }
        let width = ceil((title as NSString).size(withAttributes: [.font: FirstLineTypography.smallNSFont]).width)
        let x = ((bounds.width - width) / 2).rounded()
        let offset = PaperModeSwitch.underlineOffset
        let y = isFlipped ? labelBaseline + offset : labelBaseline - offset - 1
        return NSRect(x: x, y: y.rounded(), width: width, height: 1)
    }

}
