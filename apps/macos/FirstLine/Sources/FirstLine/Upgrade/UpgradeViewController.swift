/**
 * [INPUT]: AppKit, AppState, license activation state and DesignSystem tokens
 * [OUTPUT]: UpgradeViewController - exhausted-trial upsell and live license activation feedback
 * [POS]: writeitdown AppKit license gate; uses configured price and checkout via AppState
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit
import Observation

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
        refreshLicense()
        armLicenseObservation()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(appState.hasFullAccess ? activateButton : licenseField)
    }

    private func buildInterface() {
        let title = label("Trial complete", font: FirstLineTypography.titleNSFont, color: FirstLineColors.inkNSColor)
        let subtitle = label("Three writing sessions used.", font: FirstLineTypography.taglineNSFont, color: FirstLineColors.uiNSColor)
        let licenseName = label("writeitdown license", font: FirstLineTypography.bodyNSFont, color: FirstLineColors.inkNSColor)
        let pricing = label("One payment. 2 Macs. 14-day refund.", font: FirstLineTypography.bodyNSFont, color: FirstLineColors.uiNSColor)

        licenseField = NSTextField(string: "")
        licenseField.translatesAutoresizingMaskIntoConstraints = false
        licenseField.placeholderString = "Paste license key from Dodo email"
        licenseField.font = FirstLineTypography.bodyNSFont
        licenseField.target = self
        licenseField.action = #selector(activateTapped)

        activateButton = FirstLineButtons.primary(title: "Activate", target: self, action: #selector(activateTapped))
        feedbackLabel = label("", font: FirstLineTypography.microcopyNSFont, color: FirstLineColors.uiNSColor)
        feedbackLabel.isHidden = true

        let buyButton = FirstLineButtons.secondary(title: "Buy a license - \(AppState.displayPrice), one time", target: self, action: #selector(buyTapped))
        buyButton.isEnabled = AppState.checkoutURL != nil
        let checkoutStatus = label("Checkout is not available yet.", font: FirstLineTypography.microcopyNSFont, color: FirstLineColors.uiNSColor)
        checkoutStatus.isHidden = buyButton.isEnabled
        let backButton = FirstLineButtons.secondary(title: "Back to Home", target: self, action: #selector(backTapped))

        let stack = NSStackView(views: [title, subtitle, licenseName, pricing, licenseField, activateButton, feedbackLabel, buyButton, checkoutStatus, backButton])
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

    private func refreshLicense() {
        let active = appState.hasFullAccess
        activateButton.title = active ? "Start writing" : "Activate"
        activateButton.action = active ? #selector(startWritingTapped) : #selector(activateTapped)
        activateButton.isEnabled = !appState.licenseActivationInFlight
        if active {
            feedbackLabel.stringValue = "License active on this Mac."
        } else {
            feedbackLabel.stringValue = appState.licenseActivationError?.errorDescription ?? appState.trialStatusText
        }
        feedbackLabel.isHidden = !active && appState.licenseActivationError == nil &&
            appState.settings.licenseStatus == .trial
    }

    private func armLicenseObservation() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.appState.licenseValidationInFlight
            _ = self.appState.licenseActivationInFlight
            _ = self.appState.licenseActivationError
            _ = self.appState.settings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshLicense()
                self.armLicenseObservation()
            }
        }
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
            refreshLicense()
        }
    }

    @objc private func startWritingTapped() {
        appState.dismissLicenseSuccessFeedback()
        appState.goHome()
    }

    @objc private func backTapped() { appState.goHome() }
    @objc private func buyTapped() { appState.openCheckout() }
}
