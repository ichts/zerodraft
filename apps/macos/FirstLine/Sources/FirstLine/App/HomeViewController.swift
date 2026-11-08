/*
 * [INPUT]: AppState choices, observable access status (free-trial count or license), the chip-and-wordmark lockup
 *          and AppKit focus.
 * [OUTPUT]: Untitled white card (the "Minutes" label carries the meaning, D-096) with the A mark chip and wordmark, minute/silence segmented controls, Begin, the card's 560 pt resting (not fixed) width, and
 *           the live access line.
 * [POS]: Pre-writing surface in the After language with the chip-and-wordmark lockup; selections persist, Begin enters
 *        the room.
 * [PROTOCOL]: Check nearest AGENTS.md when this contract changes.
 */
import AppKit

@MainActor
final class HomeViewController: NSViewController, NSPopoverDelegate {
    private let appState: AppState
    private var durationControl: FirstLineSegmentedControl!
    private var silenceControl: FirstLineSegmentedControl!
    private var statusView: FirstLineStatusView!
    private var beginButton: NSButton!
    private var card: FirstLineCardView!
    private var rulesButton: NSButton!
    /// The how-it-works popover while it is open (D-097); it grows from the `?` and closes back into it.
    private(set) var rulesPopover: NSPopover?
    /// The card's frame in the picker's own coordinates, the rect the room's paper grows out of (D-096).
    var cardFrame: NSRect { card.frame }
    private var liveResizeObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = FloodCanvasView(fillColor: FirstLineColors.pageNSColor)
        buildInterface()
        armLicenseObservation()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(beginButton)
        view.window?.defaultButtonCell = beginButton.cell as? NSButtonCell
        prewarmRoomPaper()
        liveResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: view.window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.prewarmRoomPaper() }
        }
    }

    /// Closing the rules hands focus back to the `?` that opened them, so a keyboard writer is not stranded.
    func popoverDidClose(_ notification: Notification) {
        view.window?.makeFirstResponder(rulesButton)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !view.inLiveResize { prewarmRoomPaper() }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // The rules popover is not a sheet: it would stay over the room if the picker left under it.
        rulesPopover?.close()
        if let liveResizeObserver { NotificationCenter.default.removeObserver(liveResizeObserver) }
        liveResizeObserver = nil
    }

    /// The room's paper is the content area inset 32 pt on every side (SessionViewController.buildRoom). The
    /// picker renders that sheet in the background while the writer chooses, so Begin shows the finished
    /// paper on its first frame instead of building the texture on the click (D-096).
    func prewarmRoomPaper() {
        guard let window = view.window else { return }
        let area = view.safeAreaRect.insetBy(dx: 32, dy: 32)
        let scale = window.backingScaleFactor
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        PaperSheetCache.shared.prewarm(width: Int((area.width * scale).rounded()),
                                       height: Int((area.height * scale).rounded()), scale: scale, dark: dark)
    }

    private func buildInterface() {
        card = FirstLineCardView(contentInsets: NSEdgeInsets(top: 44, left: 48, bottom: 44, right: 48))
        view.addSubview(card)
        // 560 is the resting width; a longer label widens the card instead of squeezing a segment.
        let restingWidth = card.widthAnchor.constraint(equalToConstant: 560)
        restingWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            restingWidth,
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])

        // The same A mark chip the web header opens with: the plate around the split W,
        // then the wordmark on the same baseline (D-075).
        let lockup = BrandChipLockupView(typeSize: BrandChipLockupView.pickerTypeSize)

        rulesButton = FirstLineButtons.iconCircle(title: "?", target: self, action: #selector(showRules))
        rulesButton.setAccessibilityLabel("How it works")
        durationControl = FirstLineSegmentedControl(
            items: SessionEngine.durationChoices.map { duration in
                let minutes = Int(duration / 60)
                return .init(title: "\(minutes)", tag: Int(duration),
                             accessibilityLabel: minutes == 1 ? "1 minute" : "\(minutes) minutes")
            },
            selectedTag: Int(appState.selectedDuration)
        )
        durationControl.setAccessibilityLabel("Session length")
        durationControl.onChange = { [weak self] tag in
            self?.appState.updateDefaultDuration(TimeInterval(tag))
        }

        // Both picker groups use one label role: semibold, chrome, centred above
        // its control with the same gap. The old "minutes" was regular and below.
        let minutes = label("Minutes", font: FirstLineTypography.smallSemiboldNSFont, color: FirstLineColors.chromeNSColor)

        let silenceLabel = label("Delete after silence", font: FirstLineTypography.smallSemiboldNSFont, color: FirstLineColors.chromeNSColor)
        silenceControl = FirstLineSegmentedControl(
            items: SilenceLimit.allCases.map { limit in
                .init(title: limit.label, tag: limit.rawValue, accessibilityLabel: limit.label)
            },
            selectedTag: appState.settings.silenceLimit.rawValue
        )
        silenceControl.setAccessibilityLabel("Delete after silence")
        silenceControl.onChange = { [weak self] tag in
            guard let limit = SilenceLimit(rawValue: tag) else { return }
            self?.appState.updateSilenceLimit(limit)
        }

        beginButton = FirstLineButtons.primary(title: "Begin", target: self, action: #selector(beginTapped))
        beginButton.setAccessibilityLabel("Begin writing")
        statusView = FirstLineStatusView(text: appState.accessStatusText,
                                         tone: appState.trialAccessError == nil ? .neutral : .bad)
        // The picker keeps the trial/session line only; a licensed Mac shows no access line.
        statusView.isHidden = appState.hasFullAccess

        let stack = NSStackView(views: [lockup, minutes, durationControl,
                                        silenceLabel, silenceControl, beginButton, statusView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        // The "Minutes" label carries the meaning (D-096), so the lockup row opens straight onto the controls with one
        // gap, larger than the 20 pt between the picker groups so the brand row still reads as the card's header.
        stack.setCustomSpacing(32, after: lockup)
        stack.setCustomSpacing(8, after: minutes)
        stack.setCustomSpacing(20, after: durationControl)
        stack.setCustomSpacing(8, after: silenceLabel)
        stack.setCustomSpacing(26, after: silenceControl)
        stack.setCustomSpacing(18, after: beginButton)
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            statusView.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])
        // The help button sits on the logo row's centre line, flush with the card's inner padding (D-091).
        card.contentView.addSubview(rulesButton)
        NSLayoutConstraint.activate([
            rulesButton.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            rulesButton.centerYAnchor.constraint(equalTo: lockup.centerYAnchor),
        ])
    }

    private func armLicenseObservation() {
        withObservationTracking {
            _ = appState.settings
            _ = appState.licenseValidationInFlight
            _ = appState.trialAccessError
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusView.setText(self.appState.accessStatusText,
                                        tone: self.appState.trialAccessError == nil ? .neutral : .bad)
                self.statusView.isHidden = self.appState.hasFullAccess
                self.armLicenseObservation()
            }
        }
    }

    private func label(_ text: String, font: NSFont?, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.maximumNumberOfLines = 1
        return field
    }

    @objc private func beginTapped() {
        appState.startSession(duration: appState.selectedDuration)
    }

    @objc private func showRules() {
        if let rulesPopover, rulesPopover.isShown { rulesPopover.performClose(nil); return }
        let popover = NSPopover()
        let rules = RulesViewController(silenceSeconds: appState.settings.silenceLimit.rawValue)
        rules.popover = popover
        popover.contentViewController = rules
        popover.behavior = .transient
        popover.delegate = self
        let reduce = switch appState.settings.reducedMotion {
        case .system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case .always: true
        case .never: false
        }
        popover.animates = !reduce
        rulesPopover = popover
        popover.show(relativeTo: rulesButton.bounds, of: rulesButton, preferredEdge: .maxY)
    }
}
