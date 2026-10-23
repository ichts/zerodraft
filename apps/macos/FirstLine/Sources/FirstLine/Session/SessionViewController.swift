/*
 * [INPUT]: AppState preferences, SessionEngine, AppendOnlyTextView, RoomPresentation and the After tokens.
 * [OUTPUT]: One AppKit room: page, white sheet with the sheet shadow, tag/clock/bar/meter, wash and numeral, deleted sentence, kept copy/restart.
 * [POS]: Fixed writing origin, editor focus, first-input trial reservation and signed-license gate, session-ID-bound reset, wipe or denied-restart clears the editor, elapsed wipe report with next-action copy, hover-only chrome, live typography, deadline visuals, Escape and deny; no draft persistence.
 * [PROTOCOL]: Keep wash timing aligned with writeitdown/room.js; native receipts live in RoomPresentation; check nearest AGENTS.md.
 */
import AppKit

private final class RoomWashView: NSView {
    var fillColor: NSColor { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }
    init(fillColor: NSColor) {
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
            layer?.cornerRadius = cornerRadius
            layer?.masksToBounds = cornerRadius > 0
            layer?.borderColor = FirstLineColors.redNSColor.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class SessionViewController: NSViewController, NSTextViewDelegate {
    private let appState: AppState
    private let pasteboard: NSPasteboard
    private var engine: SessionEngine { appState.sessionEngine }
    private var textView: AppendOnlyTextView!
    private var scrollView: NSScrollView!
    private var paper: FloodCanvasView!
    private var paperShadow: FirstLineShadowView!
    private var paperWash: RoomWashView!
    private var outline: RoomWashView!
    private var progressBar: FirstLineFillBar!
    private var meter: FirstLineFillBar!
    private var tagView: FirstLineTagView!
    private var timerLabel: NSTextField!
    private var countLabel: NSTextField!
    private var reportLabel: NSTextField!
    private var placeholderLabel: NSTextField!
    private var numeralLabel: NSTextField!
    private var warningHint: NSTextField!
    private var exitButton: NSButton!
    private var keptText: NSTextView!
    private var keptScrollView: NSScrollView!
    private var keptFooter: NSView!
    private var receiptStatus: FirstLineStatusView!
    private var copyButton: NSButton!
    private var keyMonitor: Any?
    private var keyObserver: NSObjectProtocol?
    private var ticker: Timer?
    private var focusAttempts = 0
    private var lastDenyAt: TimeInterval?
    private var deny = DenyFeedbackState()
    private var lastPhase: SessionPhase = .idle
    private var renderedSessionID: UUID?
    private var cutWork: DispatchWorkItem?
    private var washIsCut = false
    /// The <=200 ms sheet cut; a zero duration is a settled state for snapshots/restoration.
    var cutFlashDuration: TimeInterval = 0.2
    private var denyWork: DispatchWorkItem?
    private var paperWidth: NSLayoutConstraint!
    private var placeholderAnchor: NSLayoutConstraint!
    private var chromeHover = false

    init(appState: AppState, pasteboard: NSPasteboard = .general) {
        self.appState = appState
        self.pasteboard = pasteboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = FloodCanvasView(fillColor: FirstLineColors.pageNSColor)
        buildRoom()
        configureEditor()
        applyPhase()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installInputMonitor()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        view.addTrackingArea(NSTrackingArea(rect: view.bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        applyVisualSettings()
        prepareViewport()
        NSApp.activate(ignoringOtherApps: true)
        view.window?.makeKeyAndOrderFront(nil)
        focusForPhase()
        // A window can arrive under a stationary pointer; do not let that first placement
        // count as an intentional hover and reveal Focus Mode chrome.
        chromeHover = false
        applyVisualSettings()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        prepareViewport()
        sizeKeptDocument()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        ticker?.invalidate()
        ticker = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver); self.keyObserver = nil }
        endCutAnimation()
        denyWork?.cancel()
    }

    private func label(_ text: String = "", font: NSFont? = FirstLineTypography.smallNSFont,
                       color: NSColor = FirstLineColors.inkNSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.alignment = .center
        return field
    }

    private func buildRoom() {
        paperShadow = FirstLineShadowView(cornerRadius: FirstLineRadius.sheet, fillColor: FirstLineColors.sheetNSColor)
        paperShadow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(paperShadow)

        paper = FloodCanvasView(fillColor: FirstLineColors.sheetNSColor)
        paper.translatesAutoresizingMaskIntoConstraints = false
        paper.cornerRadius = FirstLineRadius.sheet
        paper.clipsContent = true
        paper.borderColor = FirstLineColors.hairNSColor
        paper.borderWidth = 1
        view.addSubview(paper)

        textView = AppendOnlyTextView()
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.importsGraphics = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 24, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.configureSessionTypography(size: appState.settings.writingFontSize.points)
        textView.setAccessibilityHelp("Clock and word count remain accessible in Focus Mode.")
        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        paper.addSubview(scrollView)

        paperWash = RoomWashView(fillColor: FirstLineColors.redSoftNSColor)
        paperWash.translatesAutoresizingMaskIntoConstraints = false
        paperWash.cornerRadius = FirstLineRadius.sheet
        paperWash.alphaValue = 0
        paper.addSubview(paperWash, positioned: .below, relativeTo: scrollView)

        outline = RoomWashView(fillColor: .clear)
        outline.translatesAutoresizingMaskIntoConstraints = false
        outline.cornerRadius = FirstLineRadius.sheet
        outline.wantsLayer = true
        outline.layer?.borderWidth = 1
        outline.alphaValue = 0
        paper.addSubview(outline)

        progressBar = FirstLineFillBar(frame: .zero)
        progressBar.fillColor = FirstLineColors.inkNSColor
        paper.addSubview(progressBar)

        meter = FirstLineFillBar(frame: .zero)
        meter.fillColor = FirstLineColors.redNSColor
        paper.addSubview(meter)

        tagView = FirstLineTagView()
        paper.addSubview(tagView)

        timerLabel = label(font: FirstLineTypography.clockNSFont, color: FirstLineColors.inkNSColor)
        timerLabel.alignment = .right
        timerLabel.setAccessibilityRole(.staticText)
        timerLabel.setAccessibilityElement(true)
        timerLabel.setAccessibilityHidden(false)
        countLabel = label(font: FirstLineTypography.smallNSFont, color: FirstLineColors.chromeNSColor)
        countLabel.alignment = .right
        countLabel.setAccessibilityRole(.staticText)
        countLabel.setAccessibilityElement(true)
        countLabel.setAccessibilityHidden(false)
        reportLabel = label(font: .systemFont(ofSize: 15, weight: .medium), color: FirstLineColors.redNSColor)
        reportLabel.isHidden = true
        placeholderLabel = label("Start typing.",
                                 font: FirstLineTypography.writingItalicNSFont(size: appState.settings.writingFontSize.points),
                                 color: FirstLineColors.muteNSColor)
        numeralLabel = label(font: FirstLineTypography.writingItalicNSFont(size: 150),
                             color: FirstLineColors.redNSColor)
        warningHint = label("Keep typing", font: FirstLineTypography.smallNSFont, color: FirstLineColors.chromeNSColor)
        warningHint.isHidden = true
        numeralLabel.isHidden = true
        exitButton = FirstLineButtons.link(title: "Esc to leave", target: self, action: #selector(exitRoom))

        for element in [tagView!, timerLabel!, countLabel!, reportLabel!, placeholderLabel!, numeralLabel!, warningHint!, exitButton!] {
            paper.addSubview(element)
        }
        buildKeptView()
        installConstraints()
    }

    private func buildKeptView() {
        keptText = NSTextView()
        keptText.isEditable = false
        keptText.isSelectable = true
        keptText.drawsBackground = false
        keptText.textColor = FirstLineColors.inkNSColor
        keptText.textContainerInset = .zero
        keptText.textContainer?.lineFragmentPadding = 0
        keptText.textContainer?.widthTracksTextView = true
        keptText.textContainer?.heightTracksTextView = false
        keptText.isHorizontallyResizable = false
        keptText.isVerticallyResizable = true
        keptText.autoresizingMask = [.width]
        let preview = NSScrollView()
        keptScrollView = preview
        preview.documentView = keptText
        preview.hasVerticalScroller = true
        preview.autohidesScrollers = true
        preview.drawsBackground = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        paper.addSubview(preview)

        receiptStatus = FirstLineStatusView(text: "")
        let restart = FirstLineButtons.link(title: "Run it again", target: self, action: #selector(restart))
        let left = NSStackView(views: [receiptStatus, restart])
        left.orientation = .horizontal
        left.alignment = .centerY
        left.spacing = 20
        copyButton = FirstLineButtons.primary(title: "Copy text", target: self, action: #selector(copyText))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [left, spacer, copyButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 16
        footer.translatesAutoresizingMaskIntoConstraints = false
        paper.addSubview(footer)
        keptFooter = footer
        primaryKeptTypography()
        keptScrollView.isHidden = true
        keptFooter.isHidden = true

        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 36),
            preview.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -36),
            preview.topAnchor.constraint(equalTo: paper.topAnchor, constant: 64),
            preview.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 22),
            footer.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -22),
            footer.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -52),
            footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            receiptStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
        ])
    }

    private func installConstraints() {
        let safe = view.safeAreaLayoutGuide
        paperWidth = paper.widthAnchor.constraint(equalToConstant: appState.settings.writingAlignment == .centered ? 720 : 880)
        paperWidth.priority = .defaultHigh
        placeholderAnchor = placeholderLabel.centerYAnchor.constraint(equalTo: scrollView.topAnchor)
        NSLayoutConstraint.activate([
            paperShadow.leadingAnchor.constraint(equalTo: paper.leadingAnchor),
            paperShadow.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            paperShadow.topAnchor.constraint(equalTo: paper.topAnchor),
            paperShadow.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
            paper.centerXAnchor.constraint(equalTo: safe.centerXAnchor), paperWidth,
            paper.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 32),
            paper.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -32),
            paper.topAnchor.constraint(equalTo: safe.topAnchor, constant: 36),
            paper.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -28),
            scrollView.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 36),
            scrollView.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -36),
            scrollView.topAnchor.constraint(equalTo: paper.topAnchor, constant: 72),
            scrollView.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -76),
            paperWash.leadingAnchor.constraint(equalTo: paper.leadingAnchor), paperWash.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            paperWash.topAnchor.constraint(equalTo: paper.topAnchor), paperWash.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
            outline.leadingAnchor.constraint(equalTo: paper.leadingAnchor), outline.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            outline.topAnchor.constraint(equalTo: paper.topAnchor), outline.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: paper.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: paper.topAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
            meter.leadingAnchor.constraint(equalTo: paper.leadingAnchor),
            meter.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            meter.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
            meter.heightAnchor.constraint(equalToConstant: 3),
            tagView.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 22),
            tagView.topAnchor.constraint(equalTo: paper.topAnchor, constant: 18),
            timerLabel.topAnchor.constraint(equalTo: paper.topAnchor, constant: 18),
            timerLabel.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -22),
            countLabel.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -18),
            countLabel.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -22),
            exitButton.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -16),
            exitButton.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 22),
            warningHint.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -18),
            warningHint.centerXAnchor.constraint(equalTo: paper.centerXAnchor),
            reportLabel.centerXAnchor.constraint(equalTo: paper.centerXAnchor),
            reportLabel.centerYAnchor.constraint(equalTo: paper.centerYAnchor),
            reportLabel.widthAnchor.constraint(lessThanOrEqualTo: paper.widthAnchor, constant: -80),
            placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            placeholderAnchor,
            numeralLabel.centerXAnchor.constraint(equalTo: paper.centerXAnchor),
            numeralLabel.centerYAnchor.constraint(equalTo: paper.bottomAnchor, constant: -170),
        ])
    }

    private func configureEditor() {
        if !engine.text.isEmpty { textView.loadRestoredText(engine.text) }
        textView.onPrepareInput = { [weak self] isActivity in
            guard let self else { return false }
            if !isActivity && self.engine.phase == .failure { return true }
            let sessionID = self.engine.sessionID
            let allowed = self.appState.prepareSessionInput(isActivity: isActivity)
            if !allowed || self.engine.sessionID != sessionID || self.engine.phase == .failure || self.engine.phase == .idle {
                self.textView.clearWipedText()
            }
            return allowed
        }
        textView.onCommittedText = { [weak self] text in
            self?.engine.registerCommittedText(text)
            self?.applyPhase()
        }
        textView.onMarkedTextActivity = { [weak self] in
            self?.engine.registerMarkedTextActivity()
            self?.applyPhase()
        }
        textView.onDeny = { [weak self] in self?.engine.registerDeny() }
    }

    private func prepareViewport() {
        let size = scrollView.contentSize
        guard size.width > 0, size.height > 0, view.bounds.height > 0 else { return }
        let scrollTop = view.bounds.height - view.convert(scrollView.bounds, from: scrollView).maxY
        let anchor = round(view.bounds.height * 0.39 - scrollTop)
        textView.setCompositionAnchor(anchor)
        placeholderAnchor.constant = anchor
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if abs(textView.frame.width - size.width) > 0.5 || textView.frame.height < size.height {
            textView.frame.size = NSSize(width: size.width, height: max(size.height, textView.frame.height))
        }
        if !textView.hasMarkedText(), textView.pendingCompositionRefresh {
            textView.scrollCaretToCompositionAnchor()
            textView.clearPendingCompositionRefresh()
        }
    }

    private func sizeKeptDocument() {
        guard let container = keptText?.textContainer, let layout = keptText?.layoutManager,
              let scroll = keptScrollView else { return }
        let size = scroll.contentSize
        guard size.width > 0, size.height > 0 else { return }
        keptText.minSize = NSSize(width: 0, height: size.height)
        keptText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        container.containerSize = NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude)
        let height = max(size.height, layout.usedRect(for: container).height)
        if abs(keptText.frame.width - size.width) > 0.5 || abs(keptText.frame.height - height) > 0.5 {
            keptText.frame.size = NSSize(width: size.width, height: height)
        }
    }

    private func installInputMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.view.window, event.keyCode == 53,
                  RoomPresentation.shouldExitOnEscape(isComposing: self.textView.hasMarkedText()) else { return event }
            self.exitRoom()
            return nil
        }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                               object: view.window, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.focusForPhase() }
        }
    }

    private func focusForPhase() {
        guard let window = view.window else { return }
        let target: NSResponder = engine.phase == .success ? copyButton : textView
        guard window.firstResponder !== target else { focusAttempts = 0; return }
        window.makeFirstResponder(target)
        guard window.firstResponder !== target, focusAttempts < 12 else { return }
        focusAttempts += 1
        DispatchQueue.main.async { [weak self] in self?.focusForPhase() }
    }

    private var reducesMotion: Bool {
        switch appState.settings.reducedMotion {
        case .system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case .always: true
        case .never: false
        }
    }

    func refreshRoom() { applyPhase() }

    func tick() {
        appState.handleTick()
        applyVisualSettings()
        applyPhase()
        if let deniedAt = engine.lastDenyAt, deniedAt != lastDenyAt {
            lastDenyAt = deniedAt
            showDeny()
        }
    }

    private func applyPhase() {
        let phase = engine.phase
        let sessionChanged = renderedSessionID != nil && renderedSessionID != engine.sessionID
        renderedSessionID = engine.sessionID
        if sessionChanged {
            textView.clearWipedText()
            keptText.string = ""
        }
        if phase == .failure, lastPhase != .failure { showCut() }
        if phase == .success, lastPhase != .success {
            keptText.string = engine.text
            primaryKeptTypography()
            receiptStatus.setText("Not saved. Copy it before you leave.")
            copyButton.title = "Copy text"
            DispatchQueue.main.async { [weak self] in
                self?.applyKeptTypography(force: true)
                self?.sizeKeptDocument()
                self?.focusForPhase()
            }
        }
        if phase == .danger, lastPhase != .danger {
            announce("Keep typing or the draft is deleted. Three seconds left.")
        }
        if phase == .failure, lastPhase != .failure,
           let elapsed = engine.deletionElapsedSeconds {
            announce(RoomPresentation.wipeReport(elapsed: elapsed, canRestart: appState.canStartSession))
        }
        if phase == .success, lastPhase != .success {
            announce("Draft kept. Copy your text before closing.")
        }
        lastPhase = phase
        let isKept = phase == .success
        keptScrollView.isHidden = !isKept
        keptFooter.isHidden = !isKept
        scrollView.isHidden = isKept
        textView.isEditable = !isKept
        if sessionChanged, phase == .writing {
            DispatchQueue.main.async { [weak self] in self?.focusForPhase() }
        }
        if (phase == .failure || phase == .idle), !textView.string.isEmpty { textView.clearWipedText() }
        reportLabel.isHidden = phase != .failure
        if let elapsed = engine.deletionElapsedSeconds, phase == .failure {
            reportLabel.stringValue = RoomPresentation.wipeReport(elapsed: elapsed, canRestart: appState.canStartSession)
        }
        let seconds = max(0, Int(ceil(phase == .failure ? engine.duration : engine.remaining)))
        timerLabel.stringValue = RoomPresentation.clock(seconds)
        countLabel.stringValue = RoomPresentation.wordLabel(engine.wordCount)
        timerLabel.setAccessibilityLabel("Time remaining \(timerLabel.stringValue)")
        countLabel.setAccessibilityLabel("\(countLabel.stringValue) written")
        tagView.setText(RoomPresentation.sessionTag(duration: engine.duration, phase: phase))
        let warning = phase == .danger
        numeralLabel.isHidden = !warning
        if warning { numeralLabel.stringValue = "\(engine.secondsUntilDeletion)" }
        warningHint.isHidden = !warning
        countLabel.isHidden = isKept
        progressBar.isHidden = phase == .failure || phase == .success
        meter.isHidden = phase == .failure || phase == .success
        if engine.duration > 0 {
            progressBar.fraction = min(max(engine.remaining / engine.duration, 0), 1)
        }
        meter.fraction = warning ? min(max(engine.idleSeconds / Double(engine.silenceLimit.rawValue), 0), 1) : 0
        let strength = warning ? RoomPresentation.washOpacity(idle: engine.idleSeconds, reducesMotion: reducesMotion, limit: engine.silenceLimit) : 0
        if cutWork == nil { setWash(strength, cut: false) }
        if !textView.hasMarkedText(), !engine.text.isEmpty, textView.string.isEmpty { textView.loadRestoredText(engine.text) }
        placeholderLabel.isHidden = phase != .writing || !engine.text.isEmpty || !textView.string.isEmpty
        if !textView.hasMarkedText() { prepareViewport() }
    }

    private func primaryKeptTypography() {
        applyKeptTypography(force: true)
    }

    private func applyKeptTypography(force: Bool = false) {
        let settings = appState.settings
        let size = settings.writingFontSize.points
        // The kept screen is a reading/copy surface: left aligned like the approved After screen,
        // independent of the writing paper's narrow/wide alignment.
        let alignment: NSTextAlignment = .left
        guard force || keptText.font?.pointSize != size || keptText.alignment != alignment else { return }
        let font = FirstLineTypography.writingNSFont(size: size) ?? .systemFont(ofSize: size)
        keptText.font = font
        keptText.alignment = alignment
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineHeightMultiple = 1.6
        keptText.defaultParagraphStyle = paragraph
        guard let storage = keptText.textStorage, storage.length > 0 else { return }
        storage.addAttributes([.font: font, .foregroundColor: FirstLineColors.inkNSColor, .paragraphStyle: paragraph],
                              range: NSRange(location: 0, length: storage.length))
    }

    private func applyVisualSettings() {
        let settings = appState.settings
        let width: CGFloat = settings.writingAlignment == .centered ? 720 : 880
        if paperWidth.constant != width { paperWidth.constant = width }
        textView.configureSessionTypography(size: settings.writingFontSize.points)
        applyKeptTypography()
        placeholderLabel.font = FirstLineTypography.writingItalicNSFont(size: settings.writingFontSize.points)
        placeholderLabel.alignment = .left
        let showChrome = !settings.focusMode || chromeHover
        timerLabel.alphaValue = showChrome ? 1 : 0
        countLabel.alphaValue = showChrome ? 1 : 0
        tagView.alphaValue = showChrome ? 1 : 0
    }

    override func mouseMoved(with event: NSEvent) {
        let position = paper.convert(event.locationInWindow, from: nil)
        chromeHover = position.y > paper.bounds.height - 90 || position.y < 90
        applyVisualSettings()
    }

    override func mouseExited(with event: NSEvent) {
        chromeHover = false
        applyVisualSettings()
    }

    private func setWash(_ opacity: CGFloat, cut: Bool) {
        if washIsCut != cut {
            washIsCut = cut
            paperWash.fillColor = cut ? FirstLineColors.redDeepNSColor : FirstLineColors.redSoftNSColor
        }
        if paperWash.alphaValue != opacity { paperWash.alphaValue = opacity }
    }

    private func showCut() {
        guard cutFlashDuration > 0 else {
            setWash(0, cut: false)
            return
        }
        setWash(1, cut: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cutWork = nil
            self.setWash(0, cut: false)
        }
        cutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cutFlashDuration, execute: work)
    }

    /// Ends the transient <=200 ms cut without leaving a stale tint on the sheet.
    /// The room calls this on disappear; snapshot/state restoration can settle it too.
    func endCutAnimation() {
        cutWork?.cancel()
        cutWork = nil
        setWash(0, cut: false)
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: textView as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func showDeny() {
        guard deny.begin(reducesMotion: reducesMotion) else { return }
        outline.alphaValue = 1
        announce("Blocked. Forward only.")
        if deny.shakeOffset != 0 {
            paper.layer?.setAffineTransform(CGAffineTransform(translationX: deny.shakeOffset, y: 0))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self, self.deny.outlineVisible, self.deny.shakeOffset != 0 else { return }
            self.paper.layer?.setAffineTransform(CGAffineTransform(translationX: -self.deny.shakeOffset, y: 0))
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.deny.end()
            self.outline.alphaValue = 0
            self.paper.layer?.setAffineTransform(.identity)
        }
        denyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    @objc private func exitRoom() { appState.abandonSession() }
    @objc private func restart() {
        appState.abandonSession()
        appState.startSession(duration: engine.duration)
    }
    func copyKeptText() {
        guard engine.phase == .success else { return }
        copyText()
    }

    @objc private func copyText() {
        copyButton.title = RoomPresentation.copy(engine.text, to: pasteboard) ? "Copied" : "Try copy again"
        focusForPhase()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let denied = AppendOnlyInputPolicy.shouldDenyCommand(selector, hasMarkedText: textView.hasMarkedText())
        if denied { engine.registerDeny() }
        return denied
    }

    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                  toCharacterRange proposed: NSRange) -> NSRange {
        if let end = AppendOnlyInputPolicy.redirectedSelection(proposed: proposed,
            fullLength: (textView.string as NSString).length,
            markedRange: textView.hasMarkedText() ? textView.markedRange() : nil) {
            engine.registerDeny()
            return end
        }
        return proposed
    }
}
