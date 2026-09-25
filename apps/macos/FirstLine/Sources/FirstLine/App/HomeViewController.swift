/*
 * [INPUT]: AppState choices and AppKit button focus.
 * [OUTPUT]: Cursor-ready, direct-start duration row and fixed silence choices.
 * [POS]: Pre-writing surface; selection persists before a session begins, no marketing copy.
 * [PROTOCOL]: Check nearest AGENTS.md when this contract changes.
 */
import AppKit

@MainActor
final class HomeViewController: NSViewController {
    private let appState: AppState
    private var durationButtons: [NSButton] = []
    private var silenceButtons: [NSButton] = []

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        buildInterface()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let index = SessionEngine.durationChoices.firstIndex(of: appState.selectedDuration) ?? 0
        view.window?.makeFirstResponder(durationButtons[index])
        view.window?.defaultButtonCell = durationButtons[index].cell as? NSButtonCell
    }

    private func buildInterface() {
        let title = NSTextField(labelWithString: "WRITE_IT_DOWN")
        title.font = FirstLineTypography.logotypeNSFont
        title.textColor = FirstLineColors.inkNSColor
        let durationTitle = caption("MINUTES")
        let durationRow = row(SessionEngine.durationChoices.map { duration in
            let button = FirstLineButtons.primary(title: "\(Int(duration / 60))", target: self, action: #selector(start(_:)))
            button.tag = Int(duration)
            button.setAccessibilityLabel("Start \(Int(duration / 60)) minute session")
            durationButtons.append(button)
            return button
        })
        let silenceTitle = caption("DELETE AFTER SILENCE")
        let silenceRow = row(SilenceLimit.allCases.map { limit in
            let button = NSButton(radioButtonWithTitle: limit.label, target: self, action: #selector(selectSilence(_:)))
            button.tag = limit.rawValue
            button.state = appState.settings.silenceLimit == limit ? .on : .off
            silenceButtons.append(button)
            return button
        })
        let status = caption(appState.trialStatusText)
        let stack = NSStackView(views: [title, durationTitle, durationRow, silenceTitle, silenceRow, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(32, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
        ])
    }

    private func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = FirstLineTypography.microcopyNSFont
        field.textColor = FirstLineColors.uiNSColor
        return field
    }

    private func row(_ buttons: [NSButton]) -> NSStackView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 12
        return stack
    }

    @objc private func selectSilence(_ sender: NSButton) {
        guard let limit = SilenceLimit(rawValue: sender.tag) else { return }
        appState.updateSilenceLimit(limit)
        for button in silenceButtons { button.state = button === sender ? .on : .off }
    }

    @objc private func start(_ sender: NSButton) {
        appState.updateDefaultDuration(TimeInterval(sender.tag))
        appState.startSession(duration: TimeInterval(sender.tag))
    }
}
