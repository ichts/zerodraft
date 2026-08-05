/**
 * [INPUT]: AppKit, AppState, LibrarySession and DesignSystem tokens
 * [OUTPUT]: LibraryViewController - saved-session list, markdown detail and session actions
 * [POS]: First Line AppKit Library surface; browsing and destructive confirmation stay UI-only while AppState owns persistence
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit

@MainActor
final class LibraryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let appState: AppState
    private var tableView: NSTableView!
    private var detailTitle: NSTextField!
    private var metadataLabel: NSTextField!
    private var bodyLabel: NSTextField!
    private var actionRow: NSStackView!
    private var moreButton: NSButton!

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        buildInterface()
        reloadSelection()
    }

    private func buildInterface() {
        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.isVertical = true
        split.dividerStyle = .thin
        view.addSubview(split)

        let sidebar = buildSidebar()
        let detail = buildDetail()
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(detail)
        sidebar.widthAnchor.constraint(equalToConstant: 330).isActive = true

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: view.topAnchor),
            split.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func buildSidebar() -> NSView {
        let container = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        let title = heading("Library")
        let done = FirstLineButtons.link(title: "Done", target: self, action: #selector(doneTapped))
        let header = NSStackView(views: [title, flexibleSpacer(), done])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = 62
        tableView.delegate = self
        tableView.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        container.addSubview(header)
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 36),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
        return container
    }

    private func buildDetail() -> NSView {
        let container = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        detailTitle = heading("Select a saved session.")
        detailTitle.translatesAutoresizingMaskIntoConstraints = false
        detailTitle.maximumNumberOfLines = 2
        detailTitle.lineBreakMode = .byWordWrapping
        detailTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metadataLabel = muted("")
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = FirstLineTypography.bodyNSFont
        bodyLabel.textColor = FirstLineColors.inkNSColor
        bodyLabel.isSelectable = true
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(bodyLabel)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            bodyLabel.topAnchor.constraint(equalTo: document.topAnchor),
            bodyLabel.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        moreButton = FirstLineButtons.secondary(title: "More", target: self, action: #selector(moreTapped))
        moreButton.setAccessibilityLabel("More")
        actionRow = NSStackView(views: [
            FirstLineButtons.primary(title: "Copy Text", target: self, action: #selector(copyTapped)),
            moreButton,
        ])
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 12

        container.addSubview(detailTitle)
        container.addSubview(metadataLabel)
        container.addSubview(scroll)
        container.addSubview(actionRow)
        NSLayoutConstraint.activate([
            detailTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            detailTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 48),
            detailTitle.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -48),
            metadataLabel.topAnchor.constraint(equalTo: detailTitle.bottomAnchor, constant: 12),
            metadataLabel.leadingAnchor.constraint(equalTo: detailTitle.leadingAnchor),
            metadataLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -48),
            scroll.topAnchor.constraint(equalTo: metadataLabel.bottomAnchor, constant: 28),
            scroll.leadingAnchor.constraint(equalTo: detailTitle.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -48),
            scroll.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -24),
            actionRow.leadingAnchor.constraint(equalTo: detailTitle.leadingAnchor),
            actionRow.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -48),
            actionRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -40),
        ])
        return container
    }

    private func reloadSelection() {
        tableView.reloadData()
        if let selected = appState.selectedLibrarySession,
           let index = appState.librarySessions.firstIndex(where: { $0.id == selected.id }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !appState.librarySessions.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            appState.selectLibrarySession(appState.librarySessions[0])
        }
        updateDetail()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { appState.librarySessions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard appState.librarySessions.indices.contains(row) else { return nil }
        let session = appState.librarySessions[row]
        let snippet = NSTextField(labelWithString: session.snippet)
        snippet.font = FirstLineTypography.bodyNSFont
        snippet.textColor = FirstLineColors.inkNSColor
        snippet.lineBreakMode = .byTruncatingTail
        let summary = muted(summaryText(session))
        let stack = NSStackView(views: [snippet, summary])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard appState.librarySessions.indices.contains(row) else { return }
        appState.selectLibrarySession(appState.librarySessions[row])
        updateDetail()
    }

    private func updateDetail() {
        guard let session = appState.selectedLibrarySession else {
            detailTitle.stringValue = "Library"
            metadataLabel.stringValue = "No completed sessions yet."
            bodyLabel.stringValue = ""
            actionRow.isHidden = true
            return
        }
        detailTitle.stringValue = session.snippet
        metadataLabel.stringValue = "Completed \(formatted(session.completedAt))  /  \(session.durationSeconds / 60) min  /  \(session.wordCount) words  /  v\(session.appVersion)"
        bodyLabel.stringValue = session.body
        bodyLabel.font = FirstLineTypography.bodyNSFont
        bodyLabel.textColor = FirstLineColors.inkNSColor
        actionRow.isHidden = false
    }

    private func heading(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = FirstLineTypography.titleNSFont
        field.textColor = FirstLineColors.inkNSColor
        return field
    }

    private func muted(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = FirstLineTypography.microcopyNSFont
        field.textColor = FirstLineColors.uiNSColor
        return field
    }

    private func flexibleSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func summaryText(_ session: LibrarySession) -> String {
        "\(formatted(session.completedAt))  /  \(session.wordCount) words"
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @objc private func copyTapped() {
        guard let session = appState.selectedLibrarySession else { return }
        appState.copyLibrarySessionText(session)
    }

    @objc private func moreTapped() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open in Default Editor", action: #selector(openTapped), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealTapped), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(deleteTapped), keyEquivalent: "")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.maxY + 4), in: moreButton)
    }

    @objc private func openTapped() {
        guard let session = appState.selectedLibrarySession else { return }
        appState.openLibrarySessionInDefaultEditor(session)
    }

    @objc private func revealTapped() {
        guard let session = appState.selectedLibrarySession else { return }
        appState.revealLibrarySessionInFinder(session)
    }

    @objc private func deleteTapped() {
        guard let session = appState.selectedLibrarySession else { return }
        let alert = NSAlert()
        alert.messageText = "Delete session?"
        alert.informativeText = "This removes the markdown file from the library."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appState.requestDelete(session)
        appState.confirmDelete()
        reloadSelection()
    }

    @objc private func doneTapped() { appState.goHome() }
}

/// Scroll documents are top-left based so saved drafts read downward from the detail header.
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
