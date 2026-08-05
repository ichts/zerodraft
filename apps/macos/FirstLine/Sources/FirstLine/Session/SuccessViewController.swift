/**
 * [INPUT]: 依赖 AppKit、App/AppState、Session/SuccessText、DesignSystem
 * [OUTPUT]: SuccessViewController - 词数、可滚动草稿与 copy/download/discard actions
 * [POS]: First Line AppKit success surface；复刻退役 SwiftUI SuccessView 的纵向节奏与键盘焦点
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit

@MainActor
final class SuccessViewController: NSViewController {
    private let appState: AppState
    private var metricLabel: NSTextField!
    private var previewTextView: NSTextView!
    private var copyFullButton: NSButton!
    private var copyAIButton: NSButton!
    private var copiedResetWorkItem: DispatchWorkItem?
    private var copiedAction: CopiedAction?

    private enum CopiedAction: Equatable { case fullText, forAI }

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        buildInterface()
        updateContent()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        sizePreviewDocument()
        view.window?.makeFirstResponder(copyFullButton)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        sizePreviewDocument()
    }

    private func sizePreviewDocument() {
        guard let scrollView = previewTextView.enclosingScrollView,
              let textContainer = previewTextView.textContainer,
              let layoutManager = previewTextView.layoutManager else { return }
        let viewportSize = scrollView.contentSize
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }

        previewTextView.minSize = NSSize(width: 0, height: viewportSize.height)
        previewTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        previewTextView.isHorizontallyResizable = false
        previewTextView.isVerticallyResizable = true
        previewTextView.autoresizingMask = [.width]
        textContainer.containerSize = NSSize(
            width: viewportSize.width,
            height: .greatestFiniteMagnitude
        )

        var frame = previewTextView.frame
        let laidOutHeight = layoutManager.usedRect(for: textContainer).height
        let targetSize = NSSize(width: viewportSize.width, height: max(viewportSize.height, laidOutHeight))
        if abs(frame.width - targetSize.width) > 0.5 || abs(frame.height - targetSize.height) > 0.5 {
            frame.size = targetSize
            previewTextView.frame = frame
        }
    }

    private func buildInterface() {
        metricLabel = NSTextField(labelWithString: "")
        metricLabel.translatesAutoresizingMaskIntoConstraints = false
        metricLabel.font = FirstLineTypography.titleNSFont
        metricLabel.textColor = FirstLineColors.inkNSColor
        metricLabel.alignment = .center
        view.addSubview(metricLabel)

        previewTextView = NSTextView()
        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.drawsBackground = false
        previewTextView.font = FirstLineTypography.bodyNSFont
        previewTextView.textColor = FirstLineColors.inkNSColor
        previewTextView.textContainerInset = NSSize(width: 0, height: 0)
        previewTextView.textContainer?.lineFragmentPadding = 0
        previewTextView.textContainer?.widthTracksTextView = true
        previewTextView.textContainer?.heightTracksTextView = false

        let previewScroll = NSScrollView()
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.documentView = previewTextView
        previewScroll.drawsBackground = false
        previewScroll.borderType = .noBorder
        previewScroll.hasVerticalScroller = true
        previewScroll.autohidesScrollers = true
        view.addSubview(previewScroll)

        copyFullButton = FirstLineButtons.primary(
            title: "Copy full text", target: self, action: #selector(copyFullTapped)
        )
        copyAIButton = FirstLineButtons.secondary(
            title: "Copy for AI", target: self, action: #selector(copyAITapped)
        )
        let downloadButton = FirstLineButtons.secondary(
            title: "Download .md", target: self, action: #selector(downloadTapped)
        )
        let discardButton = FirstLineButtons.link(
            title: "Discard", target: self, action: #selector(discardTapped)
        )

        let secondaryRow = NSStackView(views: [copyAIButton, downloadButton])
        secondaryRow.orientation = .horizontal
        secondaryRow.spacing = FirstLineSpacing.sm
        secondaryRow.alignment = .centerY

        let actions = NSStackView(views: [copyFullButton, secondaryRow, discardButton])
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.orientation = .vertical
        actions.spacing = FirstLineSpacing.sm
        actions.alignment = .centerX
        view.addSubview(actions)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            metricLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 108),
            metricLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),

            previewScroll.topAnchor.constraint(equalTo: metricLabel.bottomAnchor, constant: FirstLineSpacing.md),
            previewScroll.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            previewScroll.widthAnchor.constraint(equalToConstant: 640),
            previewScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            previewScroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -FirstLineSpacing.md),

            actions.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            actions.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -92),
        ])
    }

    private func updateContent() {
        metricLabel.stringValue = "\(appState.sessionEngine.wordCount) words"
        previewTextView.string = appState.sessionEngine.text
        previewTextView.font = FirstLineTypography.bodyNSFont
        previewTextView.textColor = FirstLineColors.inkNSColor
    }

    @objc private func copyFullTapped() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appState.sessionEngine.text, forType: .string)
        flashCopied(.fullText)
    }

    @objc private func copyAITapped() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(SuccessText.copyForAIPayload(for: appState.sessionEngine.text), forType: .string)
        flashCopied(.forAI)
    }

    @objc private func downloadTapped() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        panel.nameFieldStringValue = "first-line-\(formatter.string(from: Date())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let created = ISO8601DateFormatter().string(from: Date())
        let body = appState.sessionEngine.text
        let words = appState.sessionEngine.wordCount
        let markdown = "---\ncreated: \(created)\nsource: First Line\nwords: \(words)\n---\n\n\(body)"
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    @objc private func discardTapped() { appState.abandonSession() }

    private func flashCopied(_ action: CopiedAction) {
        copiedResetWorkItem?.cancel()
        copiedAction = action
        applyCopyLabels()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.copiedAction = nil
            self.applyCopyLabels()
        }
        copiedResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func applyCopyLabels() {
        copyFullButton.title = copiedAction == .fullText ? "Copied." : "Copy full text"
        copyAIButton.title = copiedAction == .forAI ? "Copied." : "Copy for AI"
    }
}
