/*
 * [INPUT]: Engine text, word count and real session duration, writing/heading fonts, copied state callbacks, and the live kept-measure constant.
 * [OUTPUT]: The kept sheet: a fixed top block (heading, duration receipt, copy/restart actions) and a scrollable draft below; ink-focused COPY TEXT with live motion.
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
    private var copyWidth: NSLayoutConstraint!
    private var selectedDraft = ""
    private var renderedWordCount: Int?
    private var renderedDuration: TimeInterval?

    init(copyTarget: AnyObject?, copyAction: Selector, restartTarget: AnyObject?, restartAction: Selector,
         reducesMotion: @escaping () -> Bool) {
        copyButton = FirstLineButtons.roomPrimary(title: "COPY TEXT", target: copyTarget, action: copyAction,
                                                  reducesMotion: reducesMotion)
        copyButton.font = .systemFont(ofSize: 15, weight: .medium)
        restartButton = FirstLineButtons.link(title: "RUN IT AGAIN", target: restartTarget, action: restartAction)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.alignment = .center
        heading.maximumNumberOfLines = 1
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
        restartButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
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

        // Fixed copy width across COPY TEXT / COPIED / TRY COPY AGAIN: the title
        // change must not resize the pill or slide RUN IT AGAIN.
        var widest: CGFloat = 0
        for title in ["COPY TEXT", "COPIED", "TRY COPY AGAIN"] {
            setCopyTitle(title)
            widest = max(widest, copyButton.intrinsicContentSize.width)
        }
        setCopyTitle("COPY TEXT")
        copyWidth = copyButton.widthAnchor.constraint(equalToConstant: ceil(widest))
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.centerXAnchor.constraint(equalTo: centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            copyWidth,
        ])
        styleQuietLink(restartButton, title: "RUN IT AGAIN", muted: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var draft: String { selectedDraft }

    func setContent(text: String, wordCount: Int, duration: TimeInterval, writingFont: NSFont) {
        guard selectedDraft != text || renderedWordCount != wordCount || renderedDuration != duration
                || body.font != writingFont else { return }
        selectedDraft = text
        renderedWordCount = wordCount
        renderedDuration = duration
        body.font = writingFont
        body.attributedStringValue = FirstLineTypography.trackedText(
            text.isEmpty ? " " : text, font: writingFont, color: FirstLineColors.inkNSColor,
            kernEm: 0, lineHeightMultiple: 1.6, fixedLineHeight: true)
        updateHeadingFont()
        receipt.font = FirstLineTypography.smallMediumNSFont
        receipt.attributedStringValue = FirstLineTypography.trackedText(
            RoomPresentation.keptReceipt(wordCount: wordCount, duration: duration),
            font: FirstLineTypography.smallMediumNSFont,
            color: FirstLineColors.muteNSColor, kernEm: 0.02)
        header.needsLayout = true
        needsLayout = true
    }

    func reset() {
        selectedDraft = ""
        renderedWordCount = nil
        renderedDuration = nil
        body.stringValue = ""
        setCopyTitle("COPY TEXT")
    }

    /// The copy label keeps the pill's 1.6 line box and a fixed width across states.
    func setCopyTitle(_ title: String) {
        copyButton.title = title
        copyButton.attributedTitle = FirstLineTypography.trackedText(
            title, font: .systemFont(ofSize: 15, weight: .medium),
            color: FirstLineColors.onInkNSColor, kernEm: 0.04, lineHeightMultiple: 1.6)
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
            kernEm: 0.04, lineHeightMultiple: 1.6)
    }
}
