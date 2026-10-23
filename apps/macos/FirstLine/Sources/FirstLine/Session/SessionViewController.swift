/*
 * [INPUT]: AppState preferences, SessionEngine, AppendOnlyTextView, RoomPresentation and the After tokens.
 * [OUTPUT]: One AppKit room: page, white sheet with the sheet shadow, clock/count, centered zen writing with the live gradient line fade, wash and numeral, live deletion sentence, kept heading/copy receipt, two-step exit.
 * [POS]: Centered writing at 39% of the sheet, editor focus, first-input trial reservation and signed-license gate, session-ID-bound reset, wipe or denied-restart clears the editor, unused-time wipe report, hover-only chrome, live typography, deadline visuals, confirmed escape/click exit and deny; no draft persistence and no room pill.
 * [PROTOCOL]: Keep wash timing, strings and geometry aligned with writeitdown/room.js and the live trial; check nearest AGENTS.md.
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
    /// The live trial's kept block is `max-width:62ch` resolved against its 15 pt UI font.
    private static let roomInset: CGFloat = 22
    private static let footerHeight: CGFloat = 44
    private static let exitHintText = "Press Esc again to leave. The draft is deleted."

    private let appState: AppState
    private let pasteboard: NSPasteboard
    var confirmationClock: () -> TimeInterval
    private var engine: SessionEngine { appState.sessionEngine }
    private var copyButton: NSButton { keptView.copyButton }
    private var textView: AppendOnlyTextView!
    private var scrollView: NSScrollView!
    private let lineFadeMask = CAGradientLayer()
    private var paper: FloodCanvasView!
    private var paperShadow: FirstLineShadowView!
    private var paperWash: RoomWashView!
    private var outline: RoomWashView!
    private var timerLabel: NSTextField!
    private var countLabel: NSTextField!
    private var reportLabel: NSTextField!
    private var placeholderLabel: NSTextField!
    private var numeralLabel: NSTextField!
    private var warningHint: NSTextField!
    private var warningStack: NSStackView!
    private var exitButton: NSButton!
    private var exitHintLabel: NSTextField!
    private var keptView: SessionKeptView!
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
    private var warningCenter: NSLayoutConstraint!
    private var chromeHover = false
    var exitConfirmation = ExitConfirmation()
    private var exitHintWork: DispatchWorkItem?
    private var quietLinkMuted: Bool?

    init(appState: AppState, pasteboard: NSPasteboard = .general,
         confirmationNow: @escaping () -> TimeInterval = { SessionEngine.continuousNowSeconds() }) {
        self.appState = appState
        self.pasteboard = pasteboard
        self.confirmationClock = confirmationNow
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
        layoutWarning()
        keptView?.layoutContent()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        ticker?.invalidate()
        ticker = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver); self.keyObserver = nil }
        endCutAnimation()
        denyWork?.cancel()
        exitHintWork?.cancel()
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
        paper.borderColor = FirstLineColors.sheetRingNSColor
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
        scrollView.wantsLayer = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.layer?.mask = lineFadeMask
        // NSScrollView is flipped, so its layer geometry is flipped too: location 0 is the top.
        lineFadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        lineFadeMask.endPoint = CGPoint(x: 0.5, y: 1)
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

        timerLabel = label(font: FirstLineTypography.clockNSFont, color: FirstLineColors.inkNSColor)
        timerLabel.alignment = .right
        timerLabel.setAccessibilityRole(.staticText)
        timerLabel.setAccessibilityElement(true)
        timerLabel.setAccessibilityHidden(false)
        countLabel = label(font: FirstLineTypography.smallNSFont, color: FirstLineColors.muteNSColor)
        countLabel.alignment = .right
        countLabel.setAccessibilityRole(.staticText)
        countLabel.setAccessibilityElement(true)
        countLabel.setAccessibilityHidden(false)
        reportLabel = label(font: FirstLineTypography.smallMediumNSFont, color: FirstLineColors.redNSColor)
        reportLabel.maximumNumberOfLines = 0
        reportLabel.isHidden = true
        placeholderLabel = label("Start typing.",
                                 font: FirstLineTypography.writingItalicNSFont(size: appState.settings.writingFontSize.points),
                                 color: FirstLineColors.muteNSColor)
        numeralLabel = label(font: FirstLineTypography.writingItalicNSFont(size: 130),
                             color: FirstLineColors.redNSColor)
        warningHint = label(font: FirstLineTypography.smallMediumNSFont, color: FirstLineColors.inkNSColor)
        warningHint.maximumNumberOfLines = 0
        warningStack = NSStackView(views: [numeralLabel, warningHint])
        warningStack.translatesAutoresizingMaskIntoConstraints = false
        warningStack.orientation = .vertical
        warningStack.alignment = .centerX
        warningStack.spacing = 20
        warningStack.isHidden = true

        exitButton = FirstLineButtons.link(title: "ESC - EXIT", target: self, action: #selector(exitTapped))
        styleQuietLink(exitButton, title: "ESC - EXIT", muted: false)
        exitHintLabel = label(Self.exitHintText, font: FirstLineTypography.smallMediumNSFont, color: FirstLineColors.redNSColor)
        exitHintLabel.maximumNumberOfLines = 1
        exitHintLabel.lineBreakMode = .byTruncatingTail
        exitHintLabel.isHidden = true

        for element in [timerLabel!, countLabel!, reportLabel!, placeholderLabel!, warningStack!, exitButton!, exitHintLabel!] {
            paper.addSubview(element)
        }
        buildKeptView()
        installConstraints()
    }

    private func buildKeptView() {
        keptView = SessionKeptView(copyTarget: self, copyAction: #selector(copyText),
                                   restartTarget: self, restartAction: #selector(restart))
        paper.addSubview(keptView)
        keptView.isHidden = true
    }

    private func installConstraints() {
        let safe = view.safeAreaLayoutGuide
        paperWidth = paper.widthAnchor.constraint(equalToConstant: appState.settings.writingAlignment == .centered ? 720 : 880)
        paperWidth.priority = .defaultHigh
        placeholderAnchor = placeholderLabel.centerYAnchor.constraint(equalTo: scrollView.topAnchor)
        warningCenter = warningStack.centerYAnchor.constraint(equalTo: paper.topAnchor)
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
            timerLabel.topAnchor.constraint(equalTo: paper.topAnchor, constant: 18),
            timerLabel.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -Self.roomInset),
            exitButton.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: Self.roomInset),
            exitButton.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -16),
            exitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.footerHeight),
            countLabel.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -Self.roomInset),
            countLabel.centerYAnchor.constraint(equalTo: exitButton.centerYAnchor),
            exitHintLabel.leadingAnchor.constraint(equalTo: exitButton.trailingAnchor, constant: 12),
            exitHintLabel.centerYAnchor.constraint(equalTo: exitButton.centerYAnchor),
            exitHintLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
            warningStack.centerXAnchor.constraint(equalTo: paper.centerXAnchor),
            warningCenter,
            warningStack.leadingAnchor.constraint(greaterThanOrEqualTo: paper.leadingAnchor, constant: 20),
            warningStack.trailingAnchor.constraint(lessThanOrEqualTo: paper.trailingAnchor, constant: -20),
            reportLabel.centerXAnchor.constraint(equalTo: paper.centerXAnchor),
            reportLabel.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -76),
            reportLabel.widthAnchor.constraint(lessThanOrEqualTo: paper.widthAnchor, constant: -44),
            placeholderLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            placeholderAnchor,
            keptView.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 36),
            keptView.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -36),
            keptView.topAnchor.constraint(equalTo: paper.topAnchor, constant: SessionKeptView.verticalInset),
            keptView.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -SessionKeptView.verticalInset),
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
            guard let self else { return }
            self.dismissExitConfirmation()
            self.engine.registerCommittedText(text)
            self.applyPhase()
        }
        textView.onMarkedTextActivity = { [weak self] in
            guard let self else { return }
            self.dismissExitConfirmation()
            self.engine.registerMarkedTextActivity()
            self.applyPhase()
        }
        textView.onDeny = { [weak self] in self?.engine.registerDeny() }
    }

    // MARK: - Writing geometry

    private func prepareViewport() {
        let size = scrollView.contentSize
        guard size.width > 0, size.height > 0, paper.bounds.height > 0, view.bounds.height > 0 else { return }
        // The live trial centres the current line at 39% of the sheet.
        let anchorFromPaperTop = round(paper.bounds.height * 0.39)
        let scrollTopInPaper = paper.bounds.height - paper.convert(scrollView.bounds, from: scrollView).maxY
        let anchor = round(anchorFromPaperTop - scrollTopInPaper)
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
        layoutLineFade(centre: anchor + (textView.currentLineInkOffsetY() ?? 0))
    }

    /// The live `#editor` mask, applied to the rendered line centres: solid on the current
    /// line, 22% one line up, 7% two lines up, gone beyond.
    private func layoutLineFade(centre: CGFloat) {
        let height = scrollView.bounds.height
        guard height > 1 else { return }
        lineFadeMask.frame = scrollView.bounds
        let line = CGFloat(appState.settings.writingFontSize.points) * 1.6
        var stops: [(position: CGFloat, alpha: CGFloat)] = []
        func add(_ y: CGFloat, _ alpha: CGFloat) {
            let position = min(max(y / height, 0), 1)
            if let last = stops.last, position <= last.position { return }
            stops.append((position, alpha))
        }
        add(centre - 2.5 * line, 0)
        add(centre - 2 * line, 0.07)
        add(centre - line, 0.22)
        add(centre - 0.5 * line, 1)
        add(centre + 0.5 * line, 1)
        add(centre + line, 0.22)
        add(centre + 2 * line, 0.07)
        add(centre + 2.5 * line, 0)
        add(height, 0)
        guard stops.count >= 2 else { return }
        lineFadeMask.colors = stops.map { NSColor.black.withAlphaComponent($0.alpha).cgColor }
        lineFadeMask.locations = stops.map { NSNumber(value: Double($0.position)) }
    }

    private func layoutWarning() {
        guard paper.bounds.height > 0 else { return }
        // The live numeral/caption group is centred between 68% of the sheet and 76 pt above its bottom.
        warningCenter.constant = round(paper.bounds.height * 0.84 - 38)
        let numeralSize = round(min(view.bounds.height * 0.18, 170))
        if numeralLabel.font?.pointSize != numeralSize {
            numeralLabel.font = FirstLineTypography.writingItalicNSFont(size: numeralSize)
        }
    }

    // MARK: - State

    private func installInputMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.view.window, event.keyCode == 53,
                  RoomPresentation.handlesEscape(isComposing: self.textView.hasMarkedText()) else { return event }
            self.requestExit()
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
            keptView.reset()
            dismissExitConfirmation()
        }
        if phase == .failure, lastPhase != .failure { showCut() }
        if phase == .success, lastPhase != .success {
            updateKeptContent()
            DispatchQueue.main.async { [weak self] in
                self?.keptView.layoutContent()
                self?.focusForPhase()
            }
        }
        if phase == .danger, lastPhase != .danger {
            announce("Keep typing or the draft is deleted. Three seconds left.")
        }
        if phase == .failure, lastPhase != .failure {
            announce(wipeReport)
        }
        if phase == .success, lastPhase != .success {
            announce("You wrote it down. Copy your text before you leave. Nothing is saved.")
        }
        lastPhase = phase
        let isKept = phase == .success
        keptView.isHidden = !isKept
        scrollView.isHidden = isKept
        textView.isEditable = !isKept
        if sessionChanged, phase == .writing {
            DispatchQueue.main.async { [weak self] in self?.focusForPhase() }
        }
        if (phase == .failure || phase == .idle), !textView.string.isEmpty { textView.clearWipedText() }
        reportLabel.isHidden = phase != .failure
        if phase == .failure {
            reportLabel.attributedStringValue = FirstLineTypography.trackedText(
                wipeReport, font: FirstLineTypography.smallMediumNSFont,
                color: FirstLineColors.redNSColor, kernEm: 0.02)
        }
        let seconds = max(0, Int(ceil(phase == .failure ? engine.duration : engine.remaining)))
        timerLabel.stringValue = RoomPresentation.clock(seconds)
        countLabel.stringValue = RoomPresentation.wordLabel(engine.wordCount)
        timerLabel.setAccessibilityLabel("Time remaining \(timerLabel.stringValue)")
        countLabel.setAccessibilityLabel("\(countLabel.stringValue) written")
        let writing = phase == .writing
        let chrome = writing ? FirstLineColors.muteNSColor : FirstLineColors.chromeNSColor
        countLabel.textColor = chrome
        refreshQuietLinks(muted: writing)
        let warning = phase == .danger
        warningStack.isHidden = !warning
        if warning {
            numeralLabel.stringValue = "\(engine.secondsUntilDeletion)"
            warningHint.attributedStringValue = FirstLineTypography.trackedText(
                "KEEP TYPING OR THE DRAFT IS DELETED.", font: FirstLineTypography.smallMediumNSFont,
                color: FirstLineColors.inkNSColor, kernEm: 0.04, lineHeightMultiple: 1.5)
        }
        let strength = warning ? RoomPresentation.washOpacity(idle: engine.idleSeconds, reducesMotion: reducesMotion, limit: engine.silenceLimit) : 0
        if cutWork == nil { setWash(strength, cut: false) }
        if !textView.hasMarkedText(), !engine.text.isEmpty, textView.string.isEmpty { textView.loadRestoredText(engine.text) }
        placeholderLabel.isHidden = isKept || !engine.text.isEmpty || !textView.string.isEmpty
        if !textView.hasMarkedText() { prepareViewport() }
    }

    private var wipeReport: String {
        RoomPresentation.wipeReport(unused: engine.unusedSeconds ?? 0, canRestart: appState.canStartSession)
    }

    private func updateKeptContent() {
        let size = appState.settings.writingFontSize.points
        let writingFont = FirstLineTypography.writingNSFont(size: size) ?? .systemFont(ofSize: size)
        keptView.setContent(text: engine.text, wordCount: engine.wordCount, writingFont: writingFont)
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

    private func refreshQuietLinks(muted: Bool) {
        guard quietLinkMuted != muted else { return }
        quietLinkMuted = muted
        styleQuietLink(exitButton, title: "ESC - EXIT", muted: muted)
    }

    private func applyVisualSettings() {
        let settings = appState.settings
        let width: CGFloat = settings.writingAlignment == .centered ? 720 : 880
        if paperWidth.constant != width { paperWidth.constant = width }
        textView.configureSessionTypography(size: settings.writingFontSize.points)
        placeholderLabel.font = FirstLineTypography.writingItalicNSFont(size: settings.writingFontSize.points)
        placeholderLabel.alignment = .center
        if engine.phase == .success {
            updateKeptContent()
        } else if let writingFont = FirstLineTypography.writingNSFont(size: settings.writingFontSize.points) {
            keptView.setBodyFont(writingFont)
        }
        let showChrome = !settings.focusMode || chromeHover
        timerLabel.alphaValue = showChrome ? 1 : 0
        countLabel.alphaValue = showChrome ? 1 : 0
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

    // MARK: - Two-step exit

    /// First Escape/click arms the inline confirmation; a second one inside two seconds leaves.
    func requestExit() {
        if exitConfirmation.request(now: confirmationClock()) {
            leaveRoom()
            return
        }
        showExitHint()
    }

    private func showExitHint() {
        setExitHint(visible: true)
        announce(Self.exitHintText)
        exitHintWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.exitConfirmation.dismiss()
            self.setExitHint(visible: false)
        }
        exitHintWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + exitConfirmation.window, execute: work)
    }

    private func dismissExitConfirmation() {
        exitHintWork?.cancel()
        exitHintWork = nil
        exitConfirmation.dismiss()
        setExitHint(visible: false)
    }

    private func setExitHint(visible: Bool) {
        if exitHintLabel.isHidden == visible { exitHintLabel.isHidden = !visible }
    }

    private func leaveRoom() { appState.abandonSession() }

    @objc private func exitTapped() { requestExit() }

    @objc private func restart() {
        dismissExitConfirmation()
        appState.abandonSession()
        appState.startSession(duration: engine.duration)
    }

    func copyKeptText() {
        guard engine.phase == .success else { return }
        copyText()
    }

    @objc private func copyText() {
        let copied = RoomPresentation.copy(engine.text, to: pasteboard)
        copyButton.title = copied ? "COPIED" : "TRY COPY AGAIN"
        announce(copied ? "Copied." : "Copy failed. Select your kept text and copy it manually.")
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
