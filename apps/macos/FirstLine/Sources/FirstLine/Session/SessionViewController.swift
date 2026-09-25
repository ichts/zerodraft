/*
 * [INPUT]: AppState preferences, SessionEngine, AppendOnlyTextView, RoomPresentation and site tokens.
 * [OUTPUT]: One AppKit room for rest, writing, warning, wipe, and kept copy/restart.
 * [POS]: Window-relative writing anchor, editor focus and session-ID-bound reset, hover-only chrome, live typography, deadline visuals, Escape and deny; no draft persistence.
 * [PROTOCOL]: Keep copy and wash timing aligned with writeitdown/room.js; check nearest AGENTS.md.
 */
import AppKit

private final class RoomWashView: NSView {
    var fillColor: NSColor { didSet { needsDisplay = true } }
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
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = FirstLineColors.dangerNSColor.cgColor
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
    private var wallWash: RoomWashView!
    private var paperWash: RoomWashView!
    private var outline: RoomWashView!
    private var timerLabel: NSTextField!
    private var countLabel: NSTextField!
    private var reportLabel: NSTextField!
    private var placeholderLabel: NSTextField!
    private var numeralLabel: NSTextField!
    private var warningLabel: NSTextField!
    private var exitButton: NSButton!
    private var keptView: NSView!
    private var keptText: NSTextView!
    private var keptScrollView: NSScrollView!
    private var receiptLabel: NSTextField!
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
        view = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
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
        cutWork?.cancel()
        denyWork?.cancel()
    }

    private func label(_ text: String = "", font: NSFont? = FirstLineTypography.sessionStatusNSFont,
                       color: NSColor = FirstLineColors.inkNSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.alignment = .center
        return field
    }

    private func buildRoom() {
        wallWash = RoomWashView(fillColor: FirstLineColors.washWallNSColor)
        wallWash.translatesAutoresizingMaskIntoConstraints = false
        wallWash.alphaValue = 0
        view.addSubview(wallWash)

        paper = FloodCanvasView(fillColor: FirstLineColors.paperNSColor)
        paper.translatesAutoresizingMaskIntoConstraints = false
        paper.shadow = NSShadow()
        paper.layer?.shadowOpacity = 0.08
        paper.layer?.shadowRadius = 24
        paper.layer?.shadowOffset = NSSize(width: 0, height: 12)
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
        textView.configureSessionTypography(size: appState.settings.writingFontSize.points, alignment: appState.settings.writingAlignment)
        textView.setAccessibilityHelp("Clock and word count remain accessible in Focus Mode.")
        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        paper.addSubview(scrollView)

        paperWash = RoomWashView(fillColor: FirstLineColors.washPaperNSColor)
        paperWash.translatesAutoresizingMaskIntoConstraints = false
        paperWash.alphaValue = 0
        paper.addSubview(paperWash, positioned: .below, relativeTo: scrollView)

        outline = RoomWashView(fillColor: .clear)
        outline.translatesAutoresizingMaskIntoConstraints = false
        outline.wantsLayer = true
        outline.layer?.borderWidth = 1
        outline.alphaValue = 0
        paper.addSubview(outline)

        timerLabel = label()
        timerLabel.alignment = .right
        timerLabel.setAccessibilityRole(.staticText)
        timerLabel.setAccessibilityElement(true)
        timerLabel.setAccessibilityHidden(false)
        countLabel = label()
        countLabel.alignment = .right
        countLabel.setAccessibilityRole(.staticText)
        countLabel.setAccessibilityElement(true)
        countLabel.setAccessibilityHidden(false)
        reportLabel = label()
        reportLabel.isHidden = true
        placeholderLabel = label("Start typing.", font: FirstLineTypography.bodyNSFont, color: FirstLineColors.dimNSColor)
        paper.addSubview(placeholderLabel)
        numeralLabel = label(font: NSFont.monospacedSystemFont(ofSize: 104, weight: .semibold),
                             color: FirstLineColors.dangerNSColor)
        warningLabel = label("KEEP TYPING OR THE DRAFT IS DELETED.")
        numeralLabel.isHidden = true
        warningLabel.isHidden = true
        exitButton = NSButton(title: "ESC - EXIT", target: self, action: #selector(exitRoom))
        exitButton.isBordered = false
        exitButton.font = FirstLineTypography.sessionStatusNSFont
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        for element in [timerLabel!, countLabel!, reportLabel!, numeralLabel!, warningLabel!, exitButton!] {
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
        keptText.font = FirstLineTypography.bodyNSFont
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
        preview.drawsBackground = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        receiptLabel = label()
        copyButton = FirstLineButtons.primary(title: "COPY TEXT", target: self, action: #selector(copyText))
        let restart = FirstLineButtons.link(title: "RUN IT AGAIN", target: self, action: #selector(restart))
        let actions = NSStackView(views: [copyButton, restart])
        actions.orientation = .horizontal
        actions.spacing = 24
        let stack = NSStackView(views: [preview, receiptLabel, actions])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        keptView = stack
        keptView.isHidden = true
        paper.addSubview(keptView)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: paper.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: paper.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: paper.widthAnchor, constant: -80),
            stack.widthAnchor.constraint(equalTo: paper.widthAnchor, constant: -96),
            stack.heightAnchor.constraint(lessThanOrEqualTo: paper.heightAnchor, constant: -140),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
    }

    private func installConstraints() {
        let safe = view.safeAreaLayoutGuide
        paperWidth = paper.widthAnchor.constraint(equalToConstant: appState.settings.writingAlignment == .centered ? 720 : 920)
        paperWidth.priority = .defaultHigh
        placeholderAnchor = placeholderLabel.centerYAnchor.constraint(equalTo: scrollView.topAnchor)
        NSLayoutConstraint.activate([
            wallWash.leadingAnchor.constraint(equalTo: view.leadingAnchor), wallWash.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wallWash.topAnchor.constraint(equalTo: view.topAnchor), wallWash.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            paper.centerXAnchor.constraint(equalTo: safe.centerXAnchor), paperWidth,
            paper.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 32),
            paper.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -32),
            paper.topAnchor.constraint(equalTo: safe.topAnchor, constant: 20),
            paper.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -20),
            scrollView.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 36),
            scrollView.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -36),
            scrollView.topAnchor.constraint(equalTo: paper.topAnchor, constant: 72),
            scrollView.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -76),
            paperWash.leadingAnchor.constraint(equalTo: paper.leadingAnchor), paperWash.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            paperWash.topAnchor.constraint(equalTo: paper.topAnchor), paperWash.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
            outline.leadingAnchor.constraint(equalTo: paper.leadingAnchor), outline.trailingAnchor.constraint(equalTo: paper.trailingAnchor),
            outline.topAnchor.constraint(equalTo: paper.topAnchor), outline.bottomAnchor.constraint(equalTo: paper.bottomAnchor),
            timerLabel.topAnchor.constraint(equalTo: paper.topAnchor, constant: 24), timerLabel.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -28),
            countLabel.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -24), countLabel.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -28),
            exitButton.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -20), exitButton.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 28),
            reportLabel.centerXAnchor.constraint(equalTo: paper.centerXAnchor), reportLabel.bottomAnchor.constraint(equalTo: paper.bottomAnchor, constant: -80),
            placeholderLabel.centerXAnchor.constraint(equalTo: paper.centerXAnchor), placeholderAnchor,
            numeralLabel.centerXAnchor.constraint(equalTo: paper.centerXAnchor), numeralLabel.centerYAnchor.constraint(equalTo: paper.bottomAnchor, constant: -170),
            warningLabel.centerXAnchor.constraint(equalTo: paper.centerXAnchor), warningLabel.topAnchor.constraint(equalTo: numeralLabel.bottomAnchor, constant: 8),
        ])
    }

    private func configureEditor() {
        if !engine.text.isEmpty { textView.loadRestoredText(engine.text) }
        textView.onPrepareInput = { [weak self] in
            guard let self else { return false }
            let sessionID = self.engine.sessionID
            let allowed = self.appState.prepareSessionInput()
            if self.engine.sessionID != sessionID || self.engine.phase == .failure { self.textView.clearWipedText() }
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
        guard let container = keptText.textContainer, let layout = keptText.layoutManager else { return }
        let size = keptScrollView.contentSize
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
            receiptLabel.stringValue = RoomPresentation.keptReceipt(words: engine.wordCount)
            copyButton.title = "COPY TEXT"
            DispatchQueue.main.async { [weak self] in
                self?.sizeKeptDocument()
                self?.focusForPhase()
            }
        }
        if phase == .danger, lastPhase != .danger {
            announce("Keep typing or the draft is deleted. Three seconds left.")
        }
        if phase == .failure, lastPhase != .failure,
           let unused = engine.unusedSeconds {
            announce(RoomPresentation.wipeReport(unused: unused))
        }
        if phase == .success, lastPhase != .success {
            announce("Draft kept. Copy your text before closing.")
        }
        lastPhase = phase
        let isKept = phase == .success
        keptView.isHidden = !isKept
        scrollView.isHidden = isKept
        textView.isEditable = !isKept
        if sessionChanged, phase == .writing {
            DispatchQueue.main.async { [weak self] in self?.focusForPhase() }
        }
        if phase == .failure, !textView.string.isEmpty { textView.clearWipedText() }
        reportLabel.isHidden = phase != .failure
        placeholderLabel.isHidden = phase != .writing || !engine.text.isEmpty || !textView.string.isEmpty
        if let unused = engine.unusedSeconds, phase == .failure {
            reportLabel.stringValue = RoomPresentation.wipeReport(unused: unused)
        }
        let seconds = max(0, Int(ceil(engine.remaining)))
        timerLabel.stringValue = RoomPresentation.clock(seconds)
        countLabel.stringValue = RoomPresentation.wordLabel(engine.wordCount)
        timerLabel.setAccessibilityLabel("Time remaining \(timerLabel.stringValue)")
        countLabel.setAccessibilityLabel("\(countLabel.stringValue) written")
        let warning = phase == .danger
        numeralLabel.isHidden = !warning
        warningLabel.isHidden = !warning
        if warning { numeralLabel.stringValue = "\(engine.secondsUntilDeletion)" }
        let strength = warning ? RoomPresentation.washOpacity(idle: engine.idleSeconds, reducesMotion: reducesMotion, limit: engine.silenceLimit) : 0
        if cutWork == nil { setWash(strength, cut: false) }
        if !textView.hasMarkedText(), !engine.text.isEmpty, textView.string.isEmpty { textView.loadRestoredText(engine.text) }
        placeholderLabel.isHidden = phase != .writing || !engine.text.isEmpty || !textView.string.isEmpty
        if !textView.hasMarkedText() { prepareViewport() }
    }

    private func applyVisualSettings() {
        let settings = appState.settings
        let width: CGFloat = settings.writingAlignment == .centered ? 720 : 920
        if paperWidth.constant != width { paperWidth.constant = width }
        textView.configureSessionTypography(size: settings.writingFontSize.points, alignment: settings.writingAlignment)
        if keptText.font?.pointSize != settings.writingFontSize.points {
            keptText.font = BundledFonts.registeredFont(postScriptName: BundledFonts.newsreaderUprightPostScript,
                                                        size: settings.writingFontSize.points)
                ?? NSFont.systemFont(ofSize: settings.writingFontSize.points)
        }
        let alignment: NSTextAlignment = settings.writingAlignment == .centered ? .center : .left
        if keptText.alignment != alignment { keptText.alignment = alignment }
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
            wallWash.fillColor = cut ? FirstLineColors.deepWallNSColor : FirstLineColors.washWallNSColor
            paperWash.fillColor = cut ? FirstLineColors.deepPaperNSColor : FirstLineColors.washPaperNSColor
        }
        if wallWash.alphaValue != opacity { wallWash.alphaValue = opacity }
        if paperWash.alphaValue != opacity { paperWash.alphaValue = opacity }
    }

    private func showCut() {
        setWash(1, cut: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cutWork = nil
            self.setWash(0, cut: false)
        }
        cutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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
        copyButton.title = RoomPresentation.copy(engine.text, to: pasteboard) ? "COPIED" : "TRY COPY AGAIN"
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
