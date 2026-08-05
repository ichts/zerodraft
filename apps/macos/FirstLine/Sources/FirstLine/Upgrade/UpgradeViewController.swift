/**
 * [INPUT]: AppKit, AppState, license activation state and DesignSystem tokens
 * [OUTPUT]: UpgradeViewController - exhausted-trial upsell and license activation flow
 * [POS]: First Line AppKit Upgrade surface; consumes existing AppState license APIs without owning business logic
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit

@MainActor
final class UpgradeViewController: NSViewController {
    private let appState: AppState
    private var licenseField: NSTextField!
    private var activateButton: NSButton!
    private var feedbackLabel: NSTextField!

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        appState.clearLicenseActivationError()
        appState.dismissLicenseSuccessFeedback()
        buildInterface()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(licenseField)
    }

    private func buildInterface() {
        let title = label("Trial complete", font: FirstLineTypography.titleNSFont, color: FirstLineColors.inkNSColor)
        let subtitle = label("You used the three free Mac writing sessions.", font: FirstLineTypography.taglineNSFont, color: FirstLineColors.uiNSColor)
        let licenseName = label("First Line Early Bird License", font: FirstLineTypography.bodyNSFont, color: FirstLineColors.inkNSColor)
        let pricing = label("One-time $5. 2 Macs. No subscription. 14-day refund.", font: FirstLineTypography.bodyNSFont, color: FirstLineColors.uiNSColor)

        licenseField = NSTextField(string: "")
        licenseField.translatesAutoresizingMaskIntoConstraints = false
        licenseField.placeholderString = "Paste license key from Dodo email"
        licenseField.font = FirstLineTypography.bodyNSFont
        licenseField.target = self
        licenseField.action = #selector(activateTapped)

        activateButton = FirstLineButtons.primary(title: "Activate", target: self, action: #selector(activateTapped))
        feedbackLabel = label("", font: FirstLineTypography.microcopyNSFont, color: FirstLineColors.uiNSColor)
        feedbackLabel.isHidden = true

        let buyButton = FirstLineButtons.secondary(title: "Buy a license - Checkout coming soon", target: nil, action: #selector(noop))
        buyButton.isEnabled = false
        let backButton = FirstLineButtons.secondary(title: "Back to Home", target: self, action: #selector(backTapped))

        let stack = NSStackView(views: [title, subtitle, licenseName, pricing, licenseField, activateButton, feedbackLabel, buyButton, backButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(32, after: subtitle)
        stack.setCustomSpacing(32, after: pricing)
        stack.setCustomSpacing(32, after: feedbackLabel)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 560),
            licenseField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            activateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            buyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -48),
        ])
    }

    private func label(_ text: String, font: NSFont?, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        return field
    }

    @objc private func activateTapped() {
        let key = licenseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !appState.licenseActivationInFlight else {
            feedbackLabel.stringValue = "Paste a license key first."
            feedbackLabel.isHidden = false
            return
        }
        activateButton.isEnabled = false
        activateButton.title = "Activating"
        feedbackLabel.isHidden = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await appState.activateLicense(key: key)
            activateButton.isEnabled = true
            activateButton.title = "Activate"
            if appState.licenseActivationJustSucceeded {
                feedbackLabel.stringValue = "License active. First Line is unlocked on this Mac."
                feedbackLabel.textColor = FirstLineColors.inkNSColor
                feedbackLabel.isHidden = false
                activateButton.title = "Start writing"
                activateButton.action = #selector(startWritingTapped)
            } else if let error = appState.licenseActivationError {
                feedbackLabel.stringValue = error.errorDescription ?? "Activation failed."
                feedbackLabel.textColor = FirstLineColors.inkNSColor
                feedbackLabel.isHidden = false
            }
        }
    }

    @objc private func startWritingTapped() {
        appState.dismissLicenseSuccessFeedback()
        appState.goHome()
    }

    @objc private func backTapped() { appState.goHome() }
    @objc private func noop() {}
}
