/*
 * [INPUT]: Engine text, word count, real session duration, writing/heading fonts, copied state callbacks, and the live kept-measure constant.
 * [OUTPUT]: The kept sheet: a fixed top block (the "You wrote it down." heading, the small-caps duration/count receipt, copy/restart controls) and a scrollable draft below; the copy pill hugs its label, the restart is a quiet secondary outline, and both labels sit on the row's optical centre.
 * [POS]: One cohesive AppKit view for the room's completed state; the actions are always reachable without scrolling, the draft keeps the live measure and CJK fallback.
 * [PROTOCOL]: Keep strings, measure and centring aligned with the kept contract; check nearest AGENTS.md.
 */
import AppKit

@MainActor
final class SessionKeptView: NSView {
    /// The live `#kept` block: `max-width:62ch` resolved against its 15 pt UI font.
    static let measure: CGFloat = 586
    static let verticalInset: CGFloat = 72

    private final class DocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    let scrollView = NSScrollView()
    let copyButton: NSButton
    let restartButton: NSButton
    private let header = NSStackView()
    private let document = DocumentView(frame: .zero)
    private let heading = NSTextField(labelWithString: "You wrote it down.")
    private let body = NSTextField(wrappingLabelWithString: "")
    private let receipt = NSTextField(labelWithString: "")
    /// The kept action labels sit on the row's optical centre, not on the lower
    /// 1.6 line-box baseline; both 15 pt titles share the same lift.
    private static let actionOpticalLift: CGFloat = 5.25

    private final class PassThroughLabel: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let copyTitleLabel = PassThroughLabel(labelWithString: "")
    private let restartTitleLabel = PassThroughLabel(labelWithString: "")
    private var selectedDraft = ""
    private var renderedWordCount: Int?
    private var renderedDuration: TimeInterval?
    private let reducesMotion: () -> Bool

    init(copyTarget: AnyObject?, copyAction: Selector, restartTarget: AnyObject?, restartAction: Selector,
         reducesMotion: @escaping () -> Bool) {
        copyButton = FirstLineButtons.roomPrimary(title: "COPY TEXT", target: copyTarget, action: copyAction,
                                                  reducesMotion: reducesMotion)
        copyButton.font = .systemFont(ofSize: 15, weight: .medium)
        restartButton = FirstLineButtons.secondary(title: "RUN IT AGAIN", target: restartTarget,
                                                   action: restartAction, height: 48)
        self.reducesMotion = reducesMotion
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for (button, label) in [(copyButton, copyTitleLabel), (restartButton, restartTitleLabel)] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isEditable = false
            label.isSelectable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byClipping
            label.setAccessibilityElement(false)
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor,
                                               constant: -Self.actionOpticalLift),
            ])
        }

        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.alignment = .center
        heading.maximumNumberOfLines = 2
        heading.lineBreakMode = .byWordWrapping
        body.translatesAutoresizingMaskIntoConstraints = true
        body.isSelectable = true
        body.isEditable = false
        body.isBezeled = false
        body.drawsBackground = false
        body.alignment = .center
        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping
        receipt.translatesAutoresizingMaskIntoConstraints = false
        receipt.alignment = .center
        receipt.maximumNumberOfLines = 1
        receipt.toolTip = RoomPresentation.countRule
        receipt.setAccessibilityHelp(RoomPresentation.countRule)

        // The action row is fixed at the top so a long draft never hides COPY TEXT.
        let actions = NSStackView(views: [copyButton, restartButton])
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 24

        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 0
        header.addArrangedSubview(heading)
        header.setCustomSpacing(12, after: heading)
        header.addArrangedSubview(receipt)
        header.setCustomSpacing(20, after: receipt)
        header.addArrangedSubview(actions)
        addSubview(header)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = document
        addSubview(scrollView)
        document.addSubview(body)

        // The pill hugs its label; the title change may resize it (the row re-centres).
        setCopyTitle("COPY TEXT")
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.centerXAnchor.constraint(equalTo: centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        styleRestart()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var draft: String { selectedDraft }

    func setContent(text: String, wordCount: Int, duration: TimeInterval, writingFont: NSFont) {
        guard selectedDraft != text || renderedWordCount != wordCount
                || renderedDuration != duration || body.font != writingFont else { return }
        selectedDraft = text
        renderedWordCount = wordCount
        renderedDuration = duration
        body.font = writingFont
        body.attributedStringValue = FirstLineTypography.trackedText(
            text.isEmpty ? " " : text, font: writingFont, color: FirstLineColors.inkNSColor,
            kernEm: 0, lineHeightMultiple: 1.6, fixedLineHeight: true)
        updateHeadingFont()
        heading.stringValue = "You wrote it down."
        receipt.isHidden = false
        receipt.font = FirstLineTypography.smallMediumNSFont
        receipt.attributedStringValue = FirstLineTypography.trackedText(
            RoomPresentation.keptReceipt(wordCount: wordCount, duration: duration),
            font: FirstLineTypography.smallMediumNSFont,
            color: FirstLineColors.paperQuietNSColor, kernEm: 0.02)
        header.setCustomSpacing(12, after: heading)
        header.setCustomSpacing(20, after: receipt)
        header.needsLayout = true
        needsLayout = true
    }

    func reset() {
        selectedDraft = ""
        renderedWordCount = nil
        renderedDuration = nil
        body.stringValue = ""
        heading.stringValue = "You wrote it down."
        setCopyTitle("COPY TEXT")
    }

    /// The copy label keeps the pill's 1.6 line box and sits on the pill's optical
    /// centre. It is a pass-through label so it can sit there while the button's own
    /// transparent title keeps its width and AX name; the pill hugs the label, so the
    /// row re-centres when the title changes.
    func setCopyTitle(_ title: String) {
        copyButton.title = title
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        copyButton.attributedTitle = transparentTitle(title, font: font, kernEm: 0.04)
        copyTitleLabel.attributedStringValue = FirstLineTypography.trackedText(
            title, font: font, color: FirstLineColors.onInkNSColor, kernEm: 0.04,
            lineHeightMultiple: 1.6)
        copyButton.invalidateIntrinsicContentSize()
        copyTitleLabel.invalidateIntrinsicContentSize()
    }

    private func transparentTitle(_ title: String, font: NSFont, kernEm: CGFloat) -> NSAttributedString {
        FirstLineTypography.trackedText(
            title, font: font, color: .clear, kernEm: kernEm, lineHeightMultiple: 1.6)
    }

    override func layout() {
        super.layout()
        // A window resize changes this view's bounds without necessarily re-running
        // the room's viewDidLayout; re-lay the draft here so it stays centred.
        layoutContent()
    }

    /// Lays the draft in a scrollable document under the fixed action block. A short
    /// draft is centred; a long one starts at the top and scrolls.
    func layoutContent() {
        updateHeadingFont()
        let clip = scrollView.contentSize
        guard clip.width > 0, clip.height > 0 else { return }
        let width = round(min(Self.measure, clip.width - 48))
        body.preferredMaxLayoutWidth = width
        body.frame.size.width = width
        body.invalidateIntrinsicContentSize()
        body.layoutSubtreeIfNeeded()
        let fitting = body.fittingSize
        let bodyHeight = max(fitting.height, 1)
        let documentHeight = max(clip.height, bodyHeight + 48)
        document.frame = NSRect(x: 0, y: 0, width: clip.width, height: documentHeight)
        let y = round(max((documentHeight - bodyHeight) / 2, 24))
        body.frame = NSRect(x: round((clip.width - width) / 2), y: y, width: width, height: bodyHeight)
    }

    /// The live heading is `clamp(32px, 5vw, 48px)` against the window viewport.
    private func updateHeadingFont() {
        let width = window?.contentView?.bounds.width ?? superview?.bounds.width ?? 720
        let size = round(min(max(width * 0.05, 32), 48))
        heading.preferredMaxLayoutWidth = max(bounds.width - 16, 0)
        guard heading.font?.pointSize != size,
              let font = FirstLineTypography.writingMediumNSFont(size: size) else { return }
        heading.font = font
    }

    private func styleRestart() {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        restartButton.title = "RUN IT AGAIN"
        restartButton.font = font
        restartButton.attributedTitle = transparentTitle("RUN IT AGAIN", font: font, kernEm: 0.04)
        restartTitleLabel.attributedStringValue = FirstLineTypography.trackedText(
            "RUN IT AGAIN", font: font, color: FirstLineColors.inkNSColor, kernEm: 0.04,
            lineHeightMultiple: 1.6)
        restartButton.invalidateIntrinsicContentSize()
    }
}
