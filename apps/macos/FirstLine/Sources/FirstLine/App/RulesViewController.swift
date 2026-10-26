/**
 * [INPUT]: The shipped copy tokens, the type scale and the landing page's "How it works" wording.
 * [OUTPUT]: A dedicated sheet: how it works, the landing's three rules in order, and a Done action; body text is the
 *           scale's 15 pt at 1.5 leading on a 60ch measure, and each rule title is one step up in weight, not down in size.
 * [POS]: Opened from the picker's small "?" control; Esc or Return dismisses it; light and dark use the After card.
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
    /// The card carries the measure plus the same 44 pt inset on both sides.
    static let cardInset: CGFloat = 44
    static var cardWidth: CGFloat { bodyMeasure + cardInset * 2 }

    private let doneButton: NSButton

    init() {
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
        view = FloodCanvasView(fillColor: FirstLineColors.pageNSColor)
        let card = FirstLineCardView(contentInsets: NSEdgeInsets(top: 40, left: Self.cardInset, bottom: 36,
                                                                right: Self.cardInset))
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: Self.cardWidth),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        let eyebrow = label("How it works", font: FirstLineTypography.smallSemiboldNSFont,
                            color: FirstLineColors.chromeNSColor)
        let heading = label("Forward only. Nothing kept.", font: FirstLineTypography.writingMediumNSFont(size: 34),
                            color: FirstLineColors.inkNSColor)
        heading.maximumNumberOfLines = 2
        let measure = Self.bodyMeasure
        let sub = body("Open it, start typing, say the thing you have been avoiding. The only way out is through.",
                       color: FirstLineColors.muteNSColor)
        sub.preferredMaxLayoutWidth = measure

        let rules = NSStackView(views: [
            rule("No way back",
                 "Deleting, pasting, cutting and undo are blocked. You can only add the next word."),
            rule("Eight seconds of silence",
                 "Stop typing for eight seconds and the draft is deleted. A warning appears at five. On the Mac: Strict 5 s, Standard 8 s or Relaxed 12 s."),
            rule("Reach zero, keep it",
                 "Make it to the end of the clock and the text is yours to copy. Nothing is uploaded."),
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

        let stack = NSStackView(views: [eyebrow, heading, sub, rules, doneRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(10, after: eyebrow)
        stack.setCustomSpacing(12, after: heading)
        stack.setCustomSpacing(24, after: sub)
        stack.setCustomSpacing(28, after: rules)
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            sub.widthAnchor.constraint(equalToConstant: measure),
            rules.widthAnchor.constraint(equalToConstant: measure),
            doneRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        preferredContentSize = NSSize(width: Self.cardWidth, height: 640)
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
    /// left-aligned on the card's content edge.
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
