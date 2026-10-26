/**
 * [INPUT]: AppKit, AppState, license activation state, checkout state and DesignSystem tokens.
 * [OUTPUT]: Activation/paywall white card with key field, Activate, Buy, price line and live states.
 * [POS]: writeitdown AppKit license gate; POST checkout via AppState with mac.html fallback.
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit
import Observation

@MainActor
final class UpgradeViewController: NSViewController {
    private let appState: AppState
    private var licenseField: NSTextField!
    private var fieldLabel: NSTextField!
    private var activateButton: NSButton!
    private var buyButton: NSButton!
    private var feedbackLabel: NSTextField!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var pricingView: FirstLineStatusView!
    private var checkoutStatus: NSTextField!
    private var webTrialButton: NSButton!

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = FloodCanvasView(fillColor: FirstLineColors.pageNSColor)
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
        let card = FirstLineCardView()
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 560),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])

        titleLabel = label("Activate Write It Down", font: FirstLineTypography.displayNSFont(), color: FirstLineColors.inkNSColor)
        titleLabel.maximumNumberOfLines = 0
        subtitleLabel = label("A license is required to keep writing on this Mac.",
                              font: FirstLineTypography.subtitleNSFont(), color: FirstLineColors.muteNSColor)
        subtitleLabel.maximumNumberOfLines = 0

        fieldLabel = label("Order number or activation code",
                           font: FirstLineTypography.smallSemiboldNSFont, color: FirstLineColors.chromeNSColor)
        fieldLabel.alignment = .left

        licenseField = NSTextField(string: "")
        licenseField.translatesAutoresizingMaskIntoConstraints = false
        licenseField.placeholderString = "WID-XXXX-XXXX"
        licenseField.font = FirstLineTypography.fieldNSFont
        licenseField.textColor = FirstLineColors.inkNSColor
        licenseField.backgroundColor = FirstLineColors.sheetNSColor
        licenseField.drawsBackground = true
        licenseField.isBezeled = true
        licenseField.bezelStyle = .roundedBezel
        licenseField.focusRingType = .default
        licenseField.target = self
        licenseField.action = #selector(activateTapped)
        licenseField.cell?.sendsActionOnEndEditing = false
        licenseField.heightAnchor.constraint(equalToConstant: 44).isActive = true

        activateButton = FirstLineButtons.primary(title: "Activate", target: self, action: #selector(activateTapped))
        feedbackLabel = label("", font: FirstLineTypography.smallNSFont, color: FirstLineColors.chromeNSColor)
        feedbackLabel.maximumNumberOfLines = 0
        feedbackLabel.isHidden = true

        // Same 48 pt height as Activate: the pair is one row, not a pill beside a
        // smaller outline button.
        buyButton = FirstLineButtons.secondary(title: "Buy a license, \(AppState.displayPrice) once",
                                              target: self, action: #selector(buyTapped), height: 48)
        let buy = buyButton!
        // The action row spans the card content with two equal flexible spacers.
        // A hidden sibling (Buy) can therefore never push the remaining control
        // to the leading edge; the visible group stays centred as a unit.
        let leadingSpacer = NSView()
        let trailingSpacer = NSView()
        for spacer in [leadingSpacer, trailingSpacer] {
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let actions = NSStackView(views: [leadingSpacer, activateButton, buy, trailingSpacer])
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 12
        actions.distribution = .fill

        pricingView = FirstLineStatusView(text: "One payment. 2 Macs. 14-day refund.")
        checkoutStatus = label("Checkout is not available yet.", font: FirstLineTypography.smallNSFont, color: FirstLineColors.chromeNSColor)
        checkoutStatus.maximumNumberOfLines = 0
        // The free route is the card's only working path when checkout is down, so it
        // is a real 48 pt outline control with a hit area and the ink focus ring, not
        // a caption-shaped link (problem 9).
        webTrialButton = FirstLineButtons.secondary(title: "Try the free web room",
                                                    target: self, action: #selector(webTrialTapped),
                                                    height: 48)

        let stack = NSStackView(views: [titleLabel, subtitleLabel, fieldLabel, licenseField, actions,
                                        feedbackLabel, pricingView, checkoutStatus, webTrialButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(26, after: subtitleLabel)
        stack.setCustomSpacing(8, after: fieldLabel)
        stack.setCustomSpacing(16, after: licenseField)
        stack.setCustomSpacing(14, after: actions)
        stack.setCustomSpacing(14, after: feedbackLabel)
        stack.setCustomSpacing(14, after: pricingView)
        stack.setCustomSpacing(6, after: checkoutStatus)
        stack.setCustomSpacing(20, after: webTrialButton)
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor),
            licenseField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fieldLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            feedbackLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            pricingView.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            checkoutStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
        ])
    }

    private func refreshLicense() {
        let active = appState.hasFullAccess
        titleLabel.stringValue = active ? "Write It Down" : "Activate Write It Down"
        subtitleLabel.stringValue = active
            ? "This Mac is licensed."
            : "A license is required to keep writing on this Mac."
        pricingView.isHidden = active
        activateButton.title = appState.licenseActivationInFlight
            ? "Activating"
            : (active ? "Start writing" : "Activate")
        activateButton.action = active ? #selector(startWritingTapped) : #selector(activateTapped)
        activateButton.isEnabled = !appState.licenseActivationInFlight
        let checking = appState.licenseValidationInFlight || appState.licenseActivationInFlight
        if active {
            if appState.licenseActivationError == .cleanupFailure {
                feedbackLabel.stringValue = "License active on this Mac.\n\(LicenseActivationError.cleanupFailure.errorDescription ?? "")"
                feedbackLabel.isHidden = false
            } else {
                feedbackLabel.stringValue = ""
                feedbackLabel.isHidden = true
            }
        } else if appState.licenseActivationInFlight {
            feedbackLabel.stringValue = "Checking your key..."
            feedbackLabel.isHidden = false
        } else {
            feedbackLabel.stringValue = appState.licenseActivationError?.errorDescription ?? appState.accessStatusText
            feedbackLabel.isHidden = appState.licenseActivationError == nil &&
                appState.settings.licenseStatus == .inactive && appState.trialAccessError == nil
        }
        let badStatus = appState.licenseActivationError != nil || appState.trialAccessError != nil ||
            appState.settings.licenseStatus == .revoked || appState.settings.licenseStatus == .invalid
        feedbackLabel.textColor = checking || !badStatus
            ? FirstLineColors.muteNSColor : FirstLineColors.redNSColor
        let showEntry = !active
        fieldLabel.isHidden = !showEntry
        licenseField.isHidden = !showEntry
        webTrialButton.isHidden = !showEntry
        checkoutStatus.isHidden = !showEntry || appState.checkoutAvailable
        // No disabled Buy: when checkout is not configured the card would otherwise
        // offer a paid action that cannot complete (problem 9).
        buyButton.isHidden = !showEntry || !appState.checkoutAvailable
        // A check still running (launch validation or key activation) means the paid
        // path is not settled yet; never present it as available before then.
        buyButton.isEnabled = appState.checkoutAvailable && !appState.checkoutInFlight && !checking
        buyButton.title = appState.checkoutInFlight
            ? "Opening checkout..."
            : "Buy a license, \(AppState.displayPrice) once"
    }

    private func armLicenseObservation() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.appState.licenseValidationInFlight
            _ = self.appState.licenseActivationInFlight
            _ = self.appState.checkoutInFlight
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
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.maximumNumberOfLines = 0
        return field
    }

    @objc private func activateTapped() {
        let key = licenseField.stringValue
        guard !AppSettings.trimmedLicenseKey(key).isEmpty, !appState.licenseActivationInFlight else {
            feedbackLabel.stringValue = "Enter your order number or activation code first."
            feedbackLabel.textColor = FirstLineColors.redNSColor
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
    @objc private func buyTapped() { Task { @MainActor in await appState.openCheckout() } }
}
