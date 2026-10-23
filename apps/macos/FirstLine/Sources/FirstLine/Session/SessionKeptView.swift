/*
 * [INPUT]: Engine text and word count, writing/heading fonts, copied state callbacks, and the live kept-measure constant.
 * [OUTPUT]: The kept sheet block: "You wrote it down.", centred selectable draft, "0:00 - N WORDS KEPT.", COPY TEXT and RUN IT AGAIN, centred when short and scrollable when tall.
 * [POS]: One cohesive AppKit view for the room's completed state, matching the live trial's kept layout; the room owns phase routing and copy actions.
 * [PROTOCOL]: Keep strings, measure and centring aligned with writeitdown/index.html (#kept) and the consistency table; check nearest AGENTS.md.
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
    private let document = DocumentView(frame: .zero)
    private let stack = NSStackView()
    private let heading = NSTextField(labelWithString: "You wrote it down.")
    private let body = NSTextField(wrappingLabelWithString: "")
    private let receipt = NSTextField(labelWithString: "")
    private var bodyWidth: NSLayoutConstraint!
    private var selectedDraft = ""
    private var renderedWordCount: Int?

    init(copyTarget: AnyObject?, copyAction: Selector, restartTarget: AnyObject?, restartAction: Selector) {
        copyButton = FirstLineButtons.primary(title: "COPY TEXT", target: copyTarget, action: copyAction)
        copyButton.font = .systemFont(ofSize: 15, weight: .medium)
        restartButton = FirstLineButtons.link(title: "RUN IT AGAIN", target: restartTarget, action: restartAction)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = document
        addSubview(scrollView)

        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.alignment = .center
        heading.maximumNumberOfLines = 1
        body.translatesAutoresizingMaskIntoConstraints = false
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

        let actions = NSStackView(views: [copyButton, restartButton])
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 24

        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        [heading, body, receipt, actions].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(24, after: heading)
        stack.setCustomSpacing(20, after: body)
        stack.setCustomSpacing(20, after: receipt)
        document.addSubview(stack)

        bodyWidth = body.widthAnchor.constraint(equalToConstant: Self.measure)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bodyWidth,
        ])
        styleQuietLink(restartButton, title: "RUN IT AGAIN", muted: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var draft: String { selectedDraft }

    func setContent(text: String, wordCount: Int, writingFont: NSFont) {
        guard selectedDraft != text || renderedWordCount != wordCount || body.font != writingFont else { return }
        selectedDraft = text
        renderedWordCount = wordCount
        body.font = writingFont
        body.preferredMaxLayoutWidth = bodyWidth.constant
        body.attributedStringValue = FirstLineTypography.trackedText(
            text.isEmpty ? " " : text, font: writingFont, color: FirstLineColors.inkNSColor,
            kernEm: 0, lineHeightMultiple: 1.6)
        body.invalidateIntrinsicContentSize()
        updateHeadingFont()
        receipt.font = FirstLineTypography.smallMediumNSFont
        receipt.attributedStringValue = FirstLineTypography.trackedText(
            RoomPresentation.keptReceipt(wordCount: wordCount), font: FirstLineTypography.smallMediumNSFont,
            color: FirstLineColors.muteNSColor, kernEm: 0.02)
        stack.needsLayout = true
    }

    func reset() {
        selectedDraft = ""
        renderedWordCount = nil
        body.stringValue = ""
        copyButton.title = "COPY TEXT"
    }

    /// Centres the block when it is shorter than the writing area and scrolls it when taller.
    func layoutContent() {
        updateHeadingFont()
        let clip = scrollView.contentSize
        guard clip.width > 0, clip.height > 0 else { return }
        let width = round(min(Self.measure, clip.width - 48))
        if bodyWidth.constant != width {
            bodyWidth.constant = width
            body.preferredMaxLayoutWidth = width
            body.invalidateIntrinsicContentSize()
        }
        stack.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        let stackHeight = max(fitting.height, 1)
        let stackWidth = max(fitting.width, 1)
        let documentHeight = max(clip.height, stackHeight + 48)
        document.frame = NSRect(x: 0, y: 0, width: clip.width, height: documentHeight)
        stack.frame = NSRect(x: round((clip.width - stackWidth) / 2),
                             y: round((documentHeight - stackHeight) / 2),
                             width: stackWidth, height: stackHeight)
    }

    /// The live heading is `clamp(32px, 5vw, 48px)` against the window viewport.
    private func updateHeadingFont() {
        let width = window?.contentView?.bounds.width ?? superview?.bounds.width ?? 720
        let size = round(min(max(width * 0.05, 32), 48))
        guard heading.font?.pointSize != size,
              let font = FirstLineTypography.writingMediumNSFont(size: size) else { return }
        heading.font = font
    }

    private func styleQuietLink(_ button: NSButton, title: String, muted: Bool) {
        let color = muted ? FirstLineColors.muteNSColor : FirstLineColors.chromeNSColor
        button.title = title
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = color
        button.attributedTitle = FirstLineTypography.trackedText(
            title, font: .systemFont(ofSize: 13, weight: .medium), color: color,
            kernEm: 0.04, lineHeightMultiple: 1.5)
    }
}
