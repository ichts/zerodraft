/*
 * [INPUT]: AppState choices, observable access status (free-trial count or license) and AppKit focus.
 * [OUTPUT]: "How long?" white card with minute/silence segmented controls, Begin, and the live access line.
 * [POS]: Pre-writing surface in the After language; selections persist, Begin enters the room.
 * [PROTOCOL]: Check nearest AGENTS.md when this contract changes.
 */
import AppKit

@MainActor
final class HomeViewController: NSViewController {
    private let appState: AppState
    private var durationControl: FirstLineSegmentedControl!
    private var silenceControl: FirstLineSegmentedControl!
    private var statusView: FirstLineStatusView!
    private var beginButton: NSButton!

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
    }

    private func buildInterface() {
        let card = FirstLineCardView(contentInsets: NSEdgeInsets(top: 44, left: 48, bottom: 44, right: 48))
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 560),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])

        let title = label("How long?", font: FirstLineTypography.displayNSFont(), color: FirstLineColors.inkNSColor)
        let subtitle = label("Forward only. Nothing is saved.", font: FirstLineTypography.subtitleNSFont(), color: FirstLineColors.muteNSColor)
        subtitle.maximumNumberOfLines = 0

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

        let minutes = label("minutes", font: FirstLineTypography.smallNSFont, color: FirstLineColors.chromeNSColor)

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

        let stack = NSStackView(views: [title, subtitle, durationControl, minutes, silenceLabel, silenceControl, beginButton, statusView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(26, after: subtitle)
        stack.setCustomSpacing(6, after: durationControl)
        stack.setCustomSpacing(14, after: minutes)
        stack.setCustomSpacing(8, after: silenceLabel)
        stack.setCustomSpacing(26, after: silenceControl)
        stack.setCustomSpacing(18, after: beginButton)
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            statusView.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
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
}
