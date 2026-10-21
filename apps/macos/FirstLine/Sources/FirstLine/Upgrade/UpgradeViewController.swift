/**
 * [INPUT]: AppKit, AppState, license activation state and DesignSystem tokens
 * [OUTPUT]: UpgradeViewController - post-trial access screen and live license activation feedback
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
        if appState.licenseActivationError != .cleanupFailure {
            appState.clearLicenseActivationError()
        }
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
        let title = label("Activate Write It Down", font: FirstLineTypography.titleNSFont, color: FirstLineColors.inkNSColor)
        let subtitle = label("After 3 free sessions, a license is required to keep writing.", font: FirstLineTypography.taglineNSFont, color: FirstLineColors.uiNSColor)
        let pricing = label("One payment. 2 Macs. 14-day refund.", font: FirstLineTypography.bodyNSFont, color: FirstLineColors.uiNSColor)

        licenseField = NSTextField(string: "")
        licenseField.translatesAutoresizingMaskIntoConstraints = false
        licenseField.placeholderString = "Order number or activation code"
        licenseField.font = FirstLineTypography.bodyNSFont
        licenseField.target = self
        licenseField.action = #selector(activateTapped)
        licenseField.cell?.sendsActionOnEndEditing = false

        activateButton = FirstLineButtons.primary(title: "Activate", target: self, action: #selector(activateTapped))
        feedbackLabel = label("", font: FirstLineTypography.microcopyNSFont, color: FirstLineColors.uiNSColor)
        feedbackLabel.isHidden = true

        let buyButton = FirstLineButtons.secondary(title: "Buy a license - \(AppState.displayPrice), one time", target: self, action: #selector(buyTapped))
        buyButton.isEnabled = AppState.checkoutURL != nil
        let checkoutStatus = label("Checkout is not available yet.", font: FirstLineTypography.microcopyNSFont, color: FirstLineColors.uiNSColor)
        checkoutStatus.isHidden = buyButton.isEnabled
        let webTrialButton = FirstLineButtons.link(title: "Try the full web app at writeitdown.app", target: self, action: #selector(webTrialTapped))

        let stack = NSStackView(views: [title, subtitle, pricing, licenseField, activateButton, feedbackLabel, buyButton, checkoutStatus, webTrialButton])
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
            if appState.licenseActivationError == .cleanupFailure {
                feedbackLabel.stringValue += "\n\(LicenseActivationError.cleanupFailure.errorDescription ?? "")"
            }
        } else {
            feedbackLabel.stringValue = appState.licenseActivationError?.errorDescription ?? appState.accessStatusText
        }
        feedbackLabel.isHidden = !active && appState.licenseActivationError == nil &&
            appState.settings.licenseStatus == .inactive && appState.trialAccessError == nil
    }

    private func armLicenseObservation() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.appState.licenseValidationInFlight
            _ = self.appState.licenseActivationInFlight
            _ = self.appState.licenseActivationError
            _ = self.appState.settings
            _ = self.appState.trialAccessError
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
        let key = licenseField.stringValue
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !appState.licenseActivationInFlight else {
            feedbackLabel.stringValue = "Enter your order number or activation code first."
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

    @objc private func webTrialTapped() { appState.openWebTrial() }
    @objc private func buyTapped() { appState.openCheckout() }
}
