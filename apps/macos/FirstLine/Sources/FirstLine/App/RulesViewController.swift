/**
 * [INPUT]: The shipped copy tokens, the type scale and the landing page's "How it works" wording.
 * [OUTPUT]: The popover's own content, with no card inside it: how it works, the landing's three rules in order, and a Done action; body text is the
 *           scale's 15 pt at 1.5 leading on a 60ch measure, and each rule title is one step up in weight, not down in size.
 * [POS]: Opened from the picker's small "?" control as a popover that grows from it and closes back into it (D-097); Esc, Return, Done or a click outside dismisses it; light and dark follow the system popover surface.
 * [PROTOCOL]: Keep the wording and order identical to writeitdown/index.html's How it works cards.
 */
import AppKit

@MainActor
final class RulesViewController: NSViewController {
    /// The type scale's body role and its one-step-up subhead role.
    static var bodyFont: NSFont { FirstLineTypography.uiNSFont }
    static var subheadFont: NSFont { FirstLineTypography.uiSemiboldNSFont }
    /// 15 pt at 1.5 leading, the scale's body ratio rather than the system default 1.27.
    static let bodyLeading: CGFloat = 1.5
    static var bodyLineHeight: CGFloat { bodyFont.pointSize * bodyLeading }
    /// A 60-character measure in the body face.
    static var bodyMeasure: CGFloat {
        let character = ("0" as NSString).size(withAttributes: [.font: bodyFont]).width
        return (60 * character).rounded()
    }
    /// The sheet is the measure plus the same 44 pt inset on both sides.
    static let cardInset: CGFloat = 44
    static var cardWidth: CGFloat { bodyMeasure + cardInset * 2 }
    static let contentInsets = NSEdgeInsets(top: 40, left: cardInset, bottom: 36, right: cardInset)

    /// The popover this view is open in (D-097); nil when presented any other way.
    weak var popover: NSPopover?
    private let doneButton: NSButton
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

        let eyebrow = label("How it works", font: FirstLineTypography.smallSemiboldNSFont,
                            color: FirstLineColors.chromeNSColor)
        let heading = label("Forward only. Nothing kept.", font: FirstLineTypography.writingMediumNSFont(size: 34),
                            color: FirstLineColors.inkNSColor)
        heading.maximumNumberOfLines = 2
        let measure = Self.bodyMeasure

        let rules = NSStackView(views: [
            rule("No way back", "You can only add the next word."),
            rule("Silence deletes it", "Stop for \(silenceSeconds) seconds and the draft is deleted."),
            rule("Reach zero, keep it", "The text is yours to copy."),
        ])
        rules.translatesAutoresizingMaskIntoConstraints = false
        rules.orientation = .vertical
        rules.alignment = .leading
        rules.spacing = 18

        let doneRow = NSView()
        doneRow.translatesAutoresizingMaskIntoConstraints = false
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneRow.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneButton.centerXAnchor.constraint(equalTo: doneRow.centerXAnchor),
            doneButton.topAnchor.constraint(equalTo: doneRow.topAnchor),
            doneButton.bottomAnchor.constraint(equalTo: doneRow.bottomAnchor),
        ])

        let stack = NSStackView(views: [eyebrow, heading, rules, doneRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(10, after: eyebrow)
        stack.setCustomSpacing(24, after: heading)
        stack.setCustomSpacing(28, after: rules)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.cardInset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.cardInset),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.contentInsets.top),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.contentInsets.bottom),
            rules.widthAnchor.constraint(equalToConstant: measure),
            doneRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        // The sheet is exactly as tall as its content, so no empty band shows under Done.
        preferredContentSize = NSSize(width: Self.cardWidth,
                                      height: stack.fittingSize.height + Self.contentInsets.top + Self.contentInsets.bottom)
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

    private func rule(_ title: String, _ text: String) -> NSView {
        // The subhead is one step up in weight at the same size as its paragraph, never
        // smaller than the text it introduces (problem 21).
        let titleLabel = label(title, font: Self.subheadFont, color: FirstLineColors.inkNSColor)
        let bodyLabel = body(text, color: FirstLineColors.muteNSColor)
        bodyLabel.preferredMaxLayoutWidth = Self.bodyMeasure
        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(4, after: titleLabel)
        bodyLabel.widthAnchor.constraint(equalToConstant: Self.bodyMeasure).isActive = true
        return stack
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

    private func label(_ text: String, font: NSFont?, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        return field
    }
}
