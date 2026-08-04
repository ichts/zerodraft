/**
 * [INPUT]: 依赖 AppKit、App/AppState、Session/SessionEngine、Editor/AppendOnlyTextView、DesignSystem
 * [OUTPUT]: SessionViewController - AppKit 主写作界面（Phase 2a 真实现）
 * [POS]: FirstLine 重写核心 surface，负责 append-only 编辑器、稳焦点（beep 根治）、
 *        danger/failure/success 循环驱动、Flood 白纸列与 chrome。接管退役 SwiftUI SessionView。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 焦点修复（beep 根治）：SwiftUI 版的 EditorViewRepresentable 在 updateNSView 里用
 * 「phase==.writing 且 window!=nil 且未激活」一次性 DispatchQueue.main.async 抓 first responder，
 * 成功前置 hasActivatedForSession=true → 一枪打空（window 还不是 key）就永不重试 → 敲键 NSBeep。
 * 本控制器在 viewDidAppear 稳健重试，校验 firstResponder===textView 才停，并监听 didBecomeKey 兜底。
 *
 * Phase 2a 不含：FossilLayer、deny shake+红 hairline、failure wiped-text fossil、多行顶部 fade、
 * veil/countdown 进出动画（留 Phase 2b）。
 */

import AppKit

@MainActor
final class SessionViewController: NSViewController, NSTextViewDelegate {

    private let appState: AppState
    private var engine: SessionEngine { appState.sessionEngine }

    // 焦点重试
    private var focusRetryCount = 0
    private let focusRetryLimit = 12
    private var didBecomeKeyObserver: NSObjectProtocol?
    private var denyFlashActive = false
    private var denyResetWorkItem: DispatchWorkItem?
    private var lastObservedDenyAt: TimeInterval?
    private var tickTimer: Timer?
    private var finishKeyMonitor: Any?
    private var denyShakeOffset: CGFloat = 0
    private var denyShakeWorkItem: DispatchWorkItem?
    private var denyHairlineActive = false
    private var denyHairlineWorkItem: DispatchWorkItem?

    // 子视图
    private var scrollView: NSScrollView!
    private var textView: AppendOnlyTextView!
    private var progressTrack: NSView!
    private var progressFill: NSView!
    private var finishButton: NSButton!
    private var timerLabel: NSTextField!
    private var topChrome: NSView!
    private var paperContainer: NSView!
    private var veilView: NSView!
    private var fossilLayer: FossilLayerView!
    private var denyHairlineView: NSView!
    private var failureFossilLabel: NSTextField!
    private var countdownLabel: NSTextField!
    private var countdownHint: NSTextField!
    private var narratorLabel: NSTextField!
    private var abandonButton: NSButton!
    private var wordCountLabel: NSTextField!

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func loadView() {
        let root = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root
        buildInterface()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureEditor()
        applyPhaseUI()
        applyNarrator()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyReducedMotionToFossils()
        startTicker()
        installFinishKeyMonitor()
        installDidBecomeKeyObserver()
        grabFocus()
    }

    private func applyReducedMotionToFossils() {
        let reduces: Bool
        switch appState.settings.reducedMotion {
        case .system: reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case .always: reduces = true
        case .never: reduces = false
        }
        fossilLayer.setDanger(engine.phase == .danger, reducesMotion: reduces)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopTicker()
        if let monitor = finishKeyMonitor {
            NSEvent.removeMonitor(monitor)
            finishKeyMonitor = nil
        }
        if let obs = didBecomeKeyObserver {
            NotificationCenter.default.removeObserver(obs)
            didBecomeKeyObserver = nil
        }
        denyResetWorkItem?.cancel()
    }

    deinit {
        // viewWillDisappear 已停 timer 与 observer；deinit 非 isolated 不能访问非 Sendable Timer，
        // 仅做无 observer-self 风险的清理。
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Interface

    private func buildInterface() {
        // 1. 白纸列容器
        paperContainer = FloodCanvasView(fillColor: FirstLineColors.paperNSColor)
        paperContainer.translatesAutoresizingMaskIntoConstraints = false
        paperContainer.wantsLayer = true
        paperContainer.layer?.cornerRadius = 6
        paperContainer.layer?.borderWidth = 1
        paperContainer.layer?.borderColor = FirstLineColors.faintNSColor.withAlphaComponent(0.5).cgColor
        paperContainer.shadow = NSShadow()
        paperContainer.layer?.shadowOpacity = 0.06
        paperContainer.layer?.shadowRadius = 24
        paperContainer.layer?.shadowOffset = NSSize(width: 0, height: 12)
        paperContainer.layer?.masksToBounds = false
        view.addSubview(paperContainer)

        // 2. 编辑器（纸内）：照搬 EditorViewRepresentable.makeNSView 配置
        textView = AppendOnlyTextView()
        textView.delegate = self
        textView.onCommittedText = { [weak self] inserted in
            self?.engine.registerCommittedText(inserted)
        }
        textView.onMarkedTextActivity = { [weak self] in
            self?.engine.registerMarkedTextActivity()
        }
        textView.onDeny = { [weak self] in
            self?.engine.registerDeny()
        }
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
        textView.selectedTextAttributes = [:]
        textView.insertionPointColor = FirstLineColors.inkNSColor
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        textView.configureSessionTypography()

        scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        paperContainer.addSubview(scrollView)

        // 3. topChrome
        topChrome = NSView()
        topChrome.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topChrome)

        progressTrack = FloodCanvasView(fillColor: FirstLineColors.uiLightNSColor.withAlphaComponent(0.4))
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.wantsLayer = true
        topChrome.addSubview(progressTrack)

        progressFill = FloodCanvasView(fillColor: FirstLineColors.uiNSColor)
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.wantsLayer = true
        topChrome.addSubview(progressFill)

        finishButton = NSButton(title: "Finish", target: self, action: #selector(finishTapped))
        finishButton.translatesAutoresizingMaskIntoConstraints = false
        finishButton.bezelStyle = .inline
        finishButton.isBordered = false
        finishButton.keyEquivalent = "\r"
        finishButton.keyEquivalentModifierMask = [.command]
        finishButton.font = FirstLineTypography.buttonLabelNSFont
        finishButton.contentTintColor = FirstLineColors.inkNSColor
        finishButton.setAccessibilityLabel("Finish")
        finishButton.wantsLayer = true
        finishButton.layer?.cornerRadius = 8
        finishButton.layer?.borderWidth = 1
        finishButton.layer?.borderColor = FirstLineColors.uiLightNSColor.cgColor
        topChrome.addSubview(finishButton)

        timerLabel = NSTextField(labelWithString: "")
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.font = FirstLineTypography.sessionStatusNSFont
        timerLabel.textColor = FirstLineColors.uiNSColor
        topChrome.addSubview(timerLabel)

        // 4. danger veil + countdown
        veilView = FloodCanvasView(fillColor: FirstLineColors.dangerNSColor.withAlphaComponent(0.07))
        veilView.translatesAutoresizingMaskIntoConstraints = false
        veilView.isHidden = true
        view.addSubview(veilView)

        // Fossil soul layer：铺满 bone，只在 gutter，不接事件。
        fossilLayer = FossilLayerView(paperColumnWidth: 720)
        fossilLayer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fossilLayer, positioned: .below, relativeTo: paperContainer)

        countdownLabel = NSTextField(labelWithString: "")
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel.font = NSFont.monospacedSystemFont(ofSize: 104, weight: .regular)
        countdownLabel.textColor = FirstLineColors.dangerNSColor
        countdownLabel.alignment = .center
        countdownLabel.isHidden = true
        view.addSubview(countdownLabel)

        countdownHint = NSTextField(labelWithString: "KEEP TYPING OR THE DRAFT IS DELETED")
        countdownHint.translatesAutoresizingMaskIntoConstraints = false
        countdownHint.font = FirstLineTypography.sessionStatusNSFont
        countdownHint.textColor = FirstLineColors.uiNSColor
        countdownHint.alignment = .center
        countdownHint.isHidden = true
        view.addSubview(countdownHint)

        // failure wiped-text fossil（被删除草稿的前 64 字作为 margin fossil）
        failureFossilLabel = NSTextField(labelWithString: "")
        failureFossilLabel.translatesAutoresizingMaskIntoConstraints = false
        failureFossilLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        failureFossilLabel.textColor = FirstLineColors.inkNSColor.withAlphaComponent(0.14)
        failureFossilLabel.alignment = .center
        failureFossilLabel.isHidden = true
        view.addSubview(failureFossilLabel)

        // deny hairline：闪现的红纸边（90ms），独立 overlay 在纸容器上。
        denyHairlineView = NSView()
        denyHairlineView.translatesAutoresizingMaskIntoConstraints = false
        denyHairlineView.wantsLayer = true
        denyHairlineView.layer?.cornerRadius = 6
        denyHairlineView.layer?.borderWidth = 1
        denyHairlineView.layer?.borderColor = FirstLineColors.dangerNSColor.cgColor
        denyHairlineView.layer?.opacity = 0
        paperContainer.addSubview(denyHairlineView)

        // 5. narrator strip
        narratorLabel = NSTextField(labelWithString: "")
        narratorLabel.translatesAutoresizingMaskIntoConstraints = false
        narratorLabel.font = FirstLineTypography.sessionStatusNSFont
        narratorLabel.textColor = FirstLineColors.uiNSColor
        view.addSubview(narratorLabel)

        abandonButton = NSButton(title: "Abandon - the text is lost", target: self, action: #selector(abandonTapped))
        abandonButton.translatesAutoresizingMaskIntoConstraints = false
        abandonButton.isBordered = false
        abandonButton.font = FirstLineTypography.sessionStatusNSFont
        view.addSubview(abandonButton)
        abandonButton.attributedTitle = attributedAbandonTitle()

        wordCountLabel = NSTextField(labelWithString: "")
        wordCountLabel.translatesAutoresizingMaskIntoConstraints = false
        wordCountLabel.font = FirstLineTypography.sessionStatusNSFont
        wordCountLabel.textColor = FirstLineColors.uiNSColor
        view.addSubview(wordCountLabel)

        installConstraints()
    }

    private func attributedAbandonTitle() -> NSAttributedString {
        NSAttributedString(
            string: "Abandon - the text is lost",
            attributes: [
                .font: FirstLineTypography.sessionStatusNSFont as Any,
                .foregroundColor: FirstLineColors.dangerNSColor,
            ]
        )
    }

    private func installConstraints() {
        let g = view.safeAreaLayoutGuide

        // countdown 比例定位：centerY = view 顶 + view 高*0.62
        let countdownY = NSLayoutConstraint(
            item: countdownLabel!, attribute: .centerY,
            relatedBy: .equal,
            toItem: view, attribute: .bottom,
            multiplier: 0.62, constant: 0
        )

        let paperPreferredWidth = paperContainer.widthAnchor.constraint(equalToConstant: 720)
        paperPreferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // 白纸
            paperContainer.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            paperContainer.leadingAnchor.constraint(greaterThanOrEqualTo: g.leadingAnchor, constant: 48),
            paperContainer.trailingAnchor.constraint(lessThanOrEqualTo: g.trailingAnchor, constant: -48),
            paperContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            paperPreferredWidth,
            paperContainer.topAnchor.constraint(equalTo: g.topAnchor, constant: 48),
            paperContainer.bottomAnchor.constraint(lessThanOrEqualTo: g.bottomAnchor, constant: -120),
            paperContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 520),

            // 编辑器填满纸
            scrollView.topAnchor.constraint(equalTo: paperContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: paperContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: paperContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: paperContainer.bottomAnchor),

            // deny hairline 贴纸边
            denyHairlineView.topAnchor.constraint(equalTo: paperContainer.topAnchor),
            denyHairlineView.leadingAnchor.constraint(equalTo: paperContainer.leadingAnchor),
            denyHairlineView.trailingAnchor.constraint(equalTo: paperContainer.trailingAnchor),
            denyHairlineView.bottomAnchor.constraint(equalTo: paperContainer.bottomAnchor),

            // topChrome
            topChrome.topAnchor.constraint(equalTo: g.topAnchor),
            topChrome.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            topChrome.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            topChrome.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),

            progressTrack.topAnchor.constraint(equalTo: topChrome.topAnchor),
            progressTrack.leadingAnchor.constraint(equalTo: topChrome.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: topChrome.trailingAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 2),

            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.heightAnchor.constraint(equalToConstant: 2),

            finishButton.topAnchor.constraint(equalTo: topChrome.topAnchor, constant: CGFloat(FirstLineSpacing.sm)),
            finishButton.trailingAnchor.constraint(equalTo: topChrome.trailingAnchor, constant: -24),
            finishButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            timerLabel.centerYAnchor.constraint(equalTo: finishButton.centerYAnchor),
            timerLabel.trailingAnchor.constraint(equalTo: finishButton.leadingAnchor, constant: -CGFloat(FirstLineSpacing.sm)),

            // veil 铺满
            veilView.topAnchor.constraint(equalTo: view.topAnchor),
            veilView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            veilView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            veilView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // fossil 铺满（在 veil 之下、paper 之下）
            fossilLayer.topAnchor.constraint(equalTo: view.topAnchor),
            fossilLayer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fossilLayer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fossilLayer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // failure wiped-text fossil：右侧 margin，纵向居中偏下
            failureFossilLabel.widthAnchor.constraint(equalToConstant: 220),
            failureFossilLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -150),
            failureFossilLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // countdown
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownY,
            countdownHint.topAnchor.constraint(equalTo: countdownLabel.bottomAnchor, constant: CGFloat(FirstLineSpacing.xs)),
            countdownHint.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // narrator strip
            narratorLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 24),
            narratorLabel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -CGFloat(FirstLineSpacing.xs)),

            abandonButton.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -CGFloat(FirstLineSpacing.xs)),
            abandonButton.trailingAnchor.constraint(equalTo: wordCountLabel.leadingAnchor, constant: -CGFloat(FirstLineSpacing.sm)),

            wordCountLabel.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -24),
            wordCountLabel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -CGFloat(FirstLineSpacing.xs)),
        ])
    }

    private func configureEditor() {
        if textView.string != engine.text {
            textView.string = engine.text
            textView.applySessionTypographyToExistingText()
        }
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        if textView.selectedRange() != end { textView.setSelectedRange(end) }
    }

    // MARK: - Focus (beep fix)

    private func installDidBecomeKeyObserver() {
        guard didBecomeKeyObserver == nil else { return }
        didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.engine.phase == .writing || self.engine.phase == .danger,
                   let window = self.view.window,
                   window.firstResponder !== self.textView {
                    self.grabFocus()
                }
            }
        }
    }

    private func grabFocus() {
        guard let window = view.window else {
            scheduleFocusRetry()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        if window.firstResponder === textView {
            focusRetryCount = 0
            return
        }
        scheduleFocusRetry()
    }

    private func scheduleFocusRetry() {
        guard focusRetryCount < focusRetryLimit else { return }
        focusRetryCount += 1
        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in self?.grabFocus() }
        }
    }

    // MARK: - Session loop

    private func startTicker() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        appState.handleTick()
        applyPhaseUI()
        if engine.lastDenyAt != nil && engine.lastDenyAt != lastObservedDenyAt {
            lastObservedDenyAt = engine.lastDenyAt
            denyFlashActive = true
            denyResetWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.denyFlashActive = false
                    self.applyNarrator()
                }
            }
            denyResetWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
            triggerDenyFeedback()
        }
        applyNarrator()
    }

    // MARK: - UI application

    private func applyPhaseUI() {
        let phase = engine.phase
        let isDanger = phase == .danger

        textView.isEditable = phase == .writing || phase == .danger

        let totalSeconds = max(Int(ceil(engine.remaining)), 0)
        timerLabel.stringValue = String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
        timerLabel.textColor = timerColor

        let prog = engine.duration > 0 ? min(max(engine.elapsed / engine.duration, 0), 1) : 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let w = self.progressTrack.bounds.width * prog
            var f = self.progressFill.frame
            f.size.width = max(0, w)
            f.origin = .zero
            self.progressFill.frame = f
        }

        let topOpacity: CGFloat = isDanger ? 0.92 : 0.42
        topChrome.alphaValue = topOpacity

        let canFinish = (phase == .writing || phase == .danger) && engine.wordCount > 0
        finishButton.isHidden = !canFinish

        veilView.isHidden = !isDanger
        countdownLabel.isHidden = !isDanger
        countdownHint.isHidden = !isDanger
        if isDanger {
            countdownLabel.stringValue = "\(engine.secondsUntilDeletion)"
        }

        let live = phase == .writing || phase == .danger
        abandonButton.isHidden = !live

        wordCountLabel.stringValue = "\(engine.wordCount) words"

        if textView.hasMarkedText() == false && textView.string != engine.text {
            textView.string = engine.text
            textView.applySessionTypographyToExistingText()
            let end = NSRange(location: (textView.string as NSString).length, length: 0)
            if textView.selectedRange() != end { textView.setSelectedRange(end) }
        }
        if textView.hasMarkedText() == false {
            let end = NSRange(location: (textView.string as NSString).length, length: 0)
            if textView.selectedRange() != end { textView.setSelectedRange(end) }
        }

        if (phase == .writing || phase == .danger),
           let window = view.window,
           window.firstResponder !== textView {
            grabFocus()
        }

        // fossil danger 色
        let reduces: Bool
        switch appState.settings.reducedMotion {
        case .system: reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case .always: reduces = true
        case .never: reduces = false
        }
        fossilLayer.setDanger(isDanger, reducesMotion: reduces)

        // failure wiped-text fossil
        if phase == .failure {
            let collapsed = engine.wipedText
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .joined(separator: " ")
            failureFossilLabel.stringValue = String(collapsed.prefix(64))
            failureFossilLabel.isHidden = collapsed.isEmpty
        } else {
            failureFossilLabel.isHidden = true
        }
    }

    private func applyNarrator() {
        narratorLabel.stringValue = narratorText.uppercased()
        narratorLabel.textColor = narratorColor
    }

    private var narratorText: String {
        if denyFlashActive { return "no going back." }
        switch engine.phase {
        case .failure: return "draft deleted. it joined the pile."
        case .danger: return "keep typing or the draft is deleted"
        default: return "forward only. don't stop."
        }
    }

    private var narratorColor: NSColor {
        if denyFlashActive || engine.phase == .failure { return FirstLineColors.dangerNSColor }
        return FirstLineColors.uiNSColor
    }

    private var timerColor: NSColor {
        switch engine.phase {
        case .danger: return FirstLineColors.dangerNSColor
        case .success: return FirstLineColors.successNSColor
        default: return FirstLineColors.uiNSColor
        }
    }

    // MARK: - Actions

    @objc private func finishTapped() { engine.finish() }
    @objc private func abandonTapped() { appState.abandonSession() }

    // Cmd+Return must be caught before NSTextView consumes the key-equivalent chain.
    private func installFinishKeyMonitor() {
        guard finishKeyMonitor == nil else { return }
        finishKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command), event.keyCode == 36 else { return event }
            Task { @MainActor [weak self] in
                guard let self,
                      self.engine.phase == .writing || self.engine.phase == .danger else { return }
                self.engine.finish()
            }
            return nil
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 {
            engine.finish()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Deny feedback (shake + hairline)

    private func triggerDenyFeedback() {
        // 红 hairline 闪 90ms（色/透明度变化，reduce-motion 下仍允许）。
        denyHairlineActive = true
        denyHairlineView.layer?.opacity = 1
        denyHairlineWorkItem?.cancel()
        let hairline = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.denyHairlineActive = false
                self.denyHairlineView.layer?.opacity = 0
            }
        }
        denyHairlineWorkItem = hairline
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: hairline)

        let reduces: Bool
        switch appState.settings.reducedMotion {
        case .system: reduces = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case .always: reduces = true
        case .never: reduces = false
        }
        guard reduces == false else { return }
        // 2px 水平摇 ~160ms：-2 -> +2 -> 0
        denyShakeWorkItem?.cancel()
        denyShakeOffset = -2
        paperContainer.layer?.setAffineTransform(CGAffineTransform(translationX: -2, y: 0))
        let half = 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + half) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.paperContainer.layer?.setAffineTransform(CGAffineTransform(translationX: 2, y: 0))
            }
        }
        let reset = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.denyShakeOffset = 0
                self.paperContainer.layer?.setAffineTransform(.identity)
            }
        }
        denyShakeWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + half * 2, execute: reset)
    }

    // MARK: - NSTextViewDelegate（照搬 Coordinator 守卫）

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let blocked: [Selector] = [
            #selector(UndoManager.undo),
            Selector(("redo:")),
            #selector(NSText.paste(_:)),
            #selector(NSText.cut(_:)),
            #selector(NSResponder.deleteWordBackward(_:)),
            #selector(NSResponder.deleteWordForward(_:)),
            #selector(NSResponder.deleteToBeginningOfLine(_:)),
            #selector(NSResponder.deleteToEndOfLine(_:)),
            #selector(NSResponder.deleteToBeginningOfParagraph(_:)),
            #selector(NSResponder.deleteToEndOfParagraph(_:)),
            #selector(NSResponder.yank(_:)),
            #selector(NSResponder.transpose(_:)),
        ]
        if blocked.contains(commandSelector) {
            engine.registerDeny()
            return true
        }
        let deleteSelectors: [Selector] = [
            #selector(NSResponder.deleteBackward(_:)),
            #selector(NSResponder.deleteForward(_:)),
        ]
        if deleteSelectors.contains(commandSelector) {
            if textView.hasMarkedText() { return false }
            engine.registerDeny()
            return true
        }
        return false
    }

    func textView(_ textView: NSTextView,
                  willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                  toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
        if textView.hasMarkedText() { return newSelectedCharRange }
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        if newSelectedCharRange == end { return newSelectedCharRange }
        engine.registerDeny()
        return end
    }
}
