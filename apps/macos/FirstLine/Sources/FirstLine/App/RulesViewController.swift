/**
 * [INPUT]: The shipped copy tokens, the type scale and the picker's silence limit (5, 8 or 12 seconds).
 * [OUTPUT]: The popover's own content, with no card inside it: three short rule lines at one level (forward only, the silence limit, reaching 0:00) and a Done action;
 *           body text is the scale's 15 pt at 1.5 leading, at most a 60ch measure wide, hugging its longest line.
 * [POS]: Opened from the picker's small "?" control as a popover that grows from it and closes back into it (D-097); Esc, Return, Done or a click outside dismisses it; light and dark follow the system popover surface.
 * [PROTOCOL]: `lines(silenceSeconds:)` is the one source of the three lines: apps/windows/scripts/gen_tokens.py reads it for the Windows sheet. Line 3 is the captain's pick (D-101).
 */
import AppKit

@MainActor
final class RulesViewController: NSViewController {
    /// The type scale's body role.
    static var bodyFont: NSFont { FirstLineTypography.uiNSFont }
    /// 15 pt at 1.5 leading, the scale's body ratio rather than the system default 1.27.
    static let bodyLeading: CGFloat = 1.5
    static var bodyLineHeight: CGFloat { bodyFont.pointSize * bodyLeading }
    /// A 60-character measure in the body face.
    static var bodyMeasure: CGFloat {
        let character = ("0" as NSString).size(withAttributes: [.font: bodyFont]).width
        return (60 * character).rounded()
    }
    /// The sheet is its longest line (never past the measure) plus the same 44 pt inset on both sides.
    static let cardInset: CGFloat = 44
    static func cardWidth(silenceSeconds: Int = SilenceLimit.standard.rawValue) -> CGFloat {
        let widest = lines(silenceSeconds: silenceSeconds)
            .map { lineWidth($0) }.max() ?? 0
        return min(bodyMeasure, widest.rounded(.up)) + cardInset * 2
    }
    /// A line's natural width as the label cell draws it, with the cell's own side insets.
    private static func lineWidth(_ line: String) -> CGFloat {
        let cell = NSTextFieldCell(textCell: line)
        cell.attributedStringValue = bodyText(line, color: .labelColor)
        return cell.cellSize.width
    }
    /// The three rules, in the order the writer meets them. The silence limit is the picker's setting, never a literal.
    /// One string per line, so a copy change is a one-line edit (D-101); Windows is generated from here.
    static func lines(silenceSeconds: Int) -> [String] {
        [
            "Forward only, no deleting.",
            "\(silenceSeconds) seconds of silence deletes the draft.",
            "Write to 0:00 and the text is yours.",
        ]
    }
    static let contentInsets = NSEdgeInsets(top: 40, left: cardInset, bottom: 36, right: cardInset)

    /// The popover this view is open in (D-097); nil when presented any other way.
    weak var popover: NSPopover?
    private let doneButton: NSButton
    private var rulesStack: NSStackView?
    /// The picker's silence limit in seconds: the one number the second rule states.
    private let silenceSeconds: Int

    init(silenceSeconds: Int = SilenceLimit.standard.rawValue) {
        self.silenceSeconds = silenceSeconds
        doneButton = FirstLineButtons.primary(title: "Done", target: nil, action: #selector(close))
        super.init(nibName: nil, bundle: nil)
        doneButton.target = self
        doneButton.action = #selector(close)
        doneButton.keyEquivalent = "\r"
        doneButton.setAccessibilityLabel("Close how it works")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        // The system sheet is the one rounded panel: the content sits directly on it, on the plain
        // surface fill, with no card of its own inside.
        view = FloodCanvasView(fillColor: .clear)

        let rules = NSStackView(views: Self.lines(silenceSeconds: silenceSeconds).map(ruleLine))
        rules.translatesAutoresizingMaskIntoConstraints = false
        rules.orientation = .vertical
        rules.alignment = .leading
        rules.spacing = 12
        rulesStack = rules

        let doneRow = NSView()
        doneRow.translatesAutoresizingMaskIntoConstraints = false
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneRow.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneButton.centerXAnchor.constraint(equalTo: doneRow.centerXAnchor),
            doneButton.topAnchor.constraint(equalTo: doneRow.topAnchor),
            doneButton.bottomAnchor.constraint(equalTo: doneRow.bottomAnchor),
        ])

        let stack = NSStackView(views: [rules, doneRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(32, after: rules)
        for line in rules.arrangedSubviews { line.widthAnchor.constraint(equalTo: rules.widthAnchor).isActive = true }
        view.addSubview(stack)
        // The sheet gives the lines its width up to the measure; past it, the lines stop and the extra width is empty.
        let trailing = stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.cardInset)
        trailing.priority = .defaultHigh
        trailing.isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.cardInset),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.contentInsets.top),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.contentInsets.bottom),
            doneRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rules.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: Self.bodyMeasure),
        ])
        // The sheet is exactly as tall as its content, so no empty band shows under Done.
        preferredContentSize = NSSize(width: Self.cardWidth(silenceSeconds: silenceSeconds),
                                      height: stack.fittingSize.height + Self.contentInsets.top + Self.contentInsets.bottom)
    }

    /// A wrapping line asks for the height of the width it was given, so a line longer than the sheet wraps instead of clipping.
    override func viewDidLayout() {
        super.viewDidLayout()
        for case let field as NSTextField in rulesStack?.arrangedSubviews ?? [] where field.preferredMaxLayoutWidth != field.frame.width {
            field.preferredMaxLayoutWidth = field.frame.width
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(doneButton)
        view.window?.defaultButtonCell = doneButton.cell as? NSButtonCell
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    @objc private func close() {
        if let popover { popover.performClose(nil); return }
        guard let presenter = presentingViewController else { return }
        presenter.dismiss(self)
    }

    /// One rule: a single body-face line in ink, the same level as its neighbours.
    private func ruleLine(_ text: String) -> NSView {
        body(text, color: FirstLineColors.inkNSColor)
    }

    /// Readable body text: the scale's body face, its 1.5 leading and the 60ch measure,
    /// left-aligned on the content edge.
    private func body(_ text: String, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.alignment = .left
        field.textColor = color
        field.font = Self.bodyFont
        field.attributedStringValue = Self.bodyText(text, color: color)
        return field
    }

    /// The one body run for this sheet: fixed 1.5 line box, no tracking, left aligned.
    static func bodyText(_ text: String, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.minimumLineHeight = bodyLineHeight
        paragraph.maximumLineHeight = bodyLineHeight
        paragraph.lineHeightMultiple = 1
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }
}
