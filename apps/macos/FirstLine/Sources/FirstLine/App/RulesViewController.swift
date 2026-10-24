/**
 * [INPUT]: The shipped copy tokens and the landing page's "How it works" wording.
 * [OUTPUT]: A dedicated sheet: how it works, the landing's three rules in order, and a Done action.
 * [POS]: Opened from the picker's small "?" control; Esc or Return dismisses it; light and dark use the After card.
 * [PROTOCOL]: Keep the wording and order identical to writeitdown/index.html's How it works cards.
 */
import AppKit

@MainActor
final class RulesViewController: NSViewController {
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
        let card = FirstLineCardView(contentInsets: NSEdgeInsets(top: 40, left: 44, bottom: 36, right: 44))
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 620),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        let eyebrow = label("How it works", font: FirstLineTypography.smallSemiboldNSFont,
                            color: FirstLineColors.chromeNSColor)
        let heading = label("Forward only. Nothing kept.", font: FirstLineTypography.writingMediumNSFont(size: 34),
                            color: FirstLineColors.inkNSColor)
        heading.maximumNumberOfLines = 2
        let sub = wrappingLabel("Open it, start typing, say the thing you have been avoiding. The only way out is through.",
                                font: FirstLineTypography.subtitleNSFont(), color: FirstLineColors.muteNSColor)
        sub.preferredMaxLayoutWidth = 480

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
            sub.widthAnchor.constraint(equalToConstant: 480),
            rules.widthAnchor.constraint(equalToConstant: 480),
            doneRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        preferredContentSize = NSSize(width: 620, height: 640)
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

    private func rule(_ title: String, _ body: String) -> NSView {
        let titleLabel = label(title, font: FirstLineTypography.smallSemiboldNSFont,
                               color: FirstLineColors.inkNSColor)
        let bodyLabel = wrappingLabel(body, font: FirstLineTypography.subtitleNSFont(),
                                     color: FirstLineColors.muteNSColor)
        bodyLabel.preferredMaxLayoutWidth = 480
        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(0, after: titleLabel)
        bodyLabel.widthAnchor.constraint(equalToConstant: 480).isActive = true
        return stack
    }

    private func wrappingLabel(_ text: String, font: NSFont?, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        return field
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
