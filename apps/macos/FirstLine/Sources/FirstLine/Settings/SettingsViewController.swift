/**
 * [INPUT]: AppKit, AppState, Update/UpdateController (UpdateSettings), DesignSystem tokens and FirstLineButtons.
 * [OUTPUT]: Settings white card: appearance, updates, motion, focus, alignment, font size, license and about.
 * [POS]: Native settings surface in the After language; changes stay live and Done restores the prior surface.
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit
import Observation

@MainActor
final class SettingsViewController: NSViewController {
    private let appState: AppState
    private let updateSettings: (any UpdateSettings)?
    private var updateSwitch: NSSwitch?
    private var licenseField: NSTextField?
    private var activateButton: NSButton?
    private var licenseStatusLabel: NSTextField!
    private var licenseCleanupWarningLabel: NSTextField!
    private var licenseEntryView: NSView?
    private var licenseExplanationLabel: NSTextField?
    private var buyPageButton: NSButton?
    private var checkoutStatusLabel: NSTextField?
    private var licenseDetails: [NSTextField] = []

    init(appState: AppState, updateSettings: (any UpdateSettings)? = nil) {
        self.appState = appState
        self.updateSettings = updateSettings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = FloodCanvasView(fillColor: FirstLineColors.pageNSColor)
        buildInterface()
        refreshLicense()
        armLicenseObservation()
    }

    private func buildInterface() {
        let card = FirstLineCardView(contentInsets: NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32))
        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 28

        let headerRow = header()
        content.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        let appearance = section("Appearance", rows: [
            settingRow("Theme", control: themePopup()),
            settingRow("Reduced Motion", control: motionPopup()),
            settingRow("Focus Mode", control: focusSwitch()),
            settingRow("Alignment", control: alignmentPopup()),
            settingRow("Font Size", control: sizePopup()),
        ])
        content.addArrangedSubview(appearance)
        appearance.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        // The updates section exists only when the app really has an updater (a .app bundle).
        if let section = updatesSection() {
            content.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let license = licenseSection()
        content.addArrangedSubview(license)
        license.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        let version = AppState.displayVersion
        let about = section("About", rows: [
            settingRow("Write It Down", detail: version.isEmpty ? "Version unknown" : "Version \(version)"),
        ])
        content.addArrangedSubview(about)
        about.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        card.contentView.addSubview(content)

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(card)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            card.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            card.topAnchor.constraint(greaterThanOrEqualTo: document.topAnchor, constant: 40),
            card.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -40),
            card.widthAnchor.constraint(equalToConstant: 680),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 32),
            card.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -32),
            content.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
        ])
        let center = card.centerYAnchor.constraint(equalTo: document.centerYAnchor)
        center.priority = .defaultHigh
        center.isActive = true
        document.heightAnchor.constraint(greaterThanOrEqualTo: card.heightAnchor, constant: 80).isActive = true
        let fill = document.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor)
        fill.priority = .defaultLow
        fill.isActive = true
    }

    private func header() -> NSView {
        let heading = NSTextField(labelWithString: "Settings")
        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.font = FirstLineTypography.displayNSFont(size: 28)
        heading.textColor = FirstLineColors.inkNSColor
        let done = FirstLineButtons.link(title: "Done", target: self, action: #selector(doneTapped))
        return horizontal(views: [heading, spacer(), done])
    }

    private func updatesSection() -> NSView? {
        guard updateSettings != nil else { return nil }
        let toggle = FirstLineInkSwitch(frame: .zero)
        toggle.target = self
        toggle.action = #selector(automaticChecksChanged(_:))
        toggle.state = updateSettings?.automaticallyChecksForUpdates == true ? .on : .off
        toggle.setAccessibilityLabel("Check for updates automatically")
        updateSwitch = toggle
        return section("Updates", rows: [settingRow("Check for updates automatically", control: toggle)])
    }

    private func licenseSection() -> NSView {
        let title = NSTextField(labelWithString: "License")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = FirstLineTypography.smallSemiboldNSFont
        title.textColor = FirstLineColors.chromeNSColor

        let block = NSStackView()
        block.translatesAutoresizingMaskIntoConstraints = false
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 0
        block.addArrangedSubview(title)
        block.setCustomSpacing(10, after: title)

        // The status and the details are one left-aligned block. No per-line hairlines:
        // the old generic row separators touched the 13 pt text and read as a broken table.
        licenseStatusLabel = muted("")
        licenseStatusLabel.font = FirstLineTypography.smallNSFont
        block.addArrangedSubview(licenseStatusLabel)

        licenseCleanupWarningLabel = muted("")
        licenseCleanupWarningLabel.textColor = FirstLineColors.redNSColor
        block.addArrangedSubview(licenseCleanupWarningLabel)

        licenseDetails = (0..<2).map { _ in muted("") }
        for detail in licenseDetails {
            block.addArrangedSubview(detail)
            block.setCustomSpacing(2, after: detail)
        }

        // The activation entry is one group, hidden as a unit for a licensed Mac.
        let entry = NSStackView()
        entry.translatesAutoresizingMaskIntoConstraints = false
        entry.orientation = .vertical
        entry.alignment = .leading
        entry.spacing = 0
        let topGap = NSView()
        topGap.translatesAutoresizingMaskIntoConstraints = false
        topGap.heightAnchor.constraint(equalToConstant: 14).isActive = true
        entry.addArrangedSubview(topGap)
        let divider = FloodCanvasView(fillColor: FirstLineColors.hairNSColor)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        entry.addArrangedSubview(divider)
        entry.setCustomSpacing(14, after: divider)

        let explanation = muted("Enter your order number or activation code to activate this Mac.")
        licenseExplanationLabel = explanation
        entry.addArrangedSubview(explanation)
        entry.setCustomSpacing(10, after: explanation)

        let field = NSTextField(string: "")
        field.placeholderString = "Order number or activation code"
        field.font = FirstLineTypography.uiNSFont
        field.focusRingType = .default
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
        licenseField = field
        entry.addArrangedSubview(field)
        entry.setCustomSpacing(12, after: field)

        let activate = FirstLineButtons.primary(title: "Activate", target: self, action: #selector(activateTapped))
        activateButton = activate
        // Buy is a real control on the same 48 pt row as Activate, not body text.
        let buy = FirstLineButtons.secondary(title: "Buy a license, \(AppState.displayPrice) once",
                                             target: self, action: #selector(openBuyTapped), height: 48)
        buyPageButton = buy
        let actionRow = horizontal(views: [spacer(), activate, buy])
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        entry.addArrangedSubview(actionRow)

        checkoutStatusLabel = muted("Checkout is not available yet.")
        entry.addArrangedSubview(checkoutStatusLabel!)
        block.addArrangedSubview(entry)
        licenseEntryView = entry

        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalTo: block.widthAnchor),
            entry.widthAnchor.constraint(equalTo: block.widthAnchor),
            licenseStatusLabel.widthAnchor.constraint(lessThanOrEqualTo: block.widthAnchor),
            field.widthAnchor.constraint(equalTo: block.widthAnchor),
            actionRow.widthAnchor.constraint(equalTo: block.widthAnchor),
            checkoutStatusLabel!.widthAnchor.constraint(lessThanOrEqualTo: block.widthAnchor),
        ])
        return block
    }

    private func refreshLicense() {
        let active = appState.hasFullAccess
        let checking = appState.licenseValidationInFlight || appState.licenseActivationInFlight
        let badStatus = appState.licenseActivationError != nil || appState.trialAccessError != nil ||
            appState.settings.licenseStatus == .revoked || appState.settings.licenseStatus == .invalid
        let statusText = active ? appState.licenseStatusText :
            (appState.licenseActivationError?.errorDescription ?? appState.accessStatusText)
        licenseStatusLabel.stringValue = statusText
        licenseStatusLabel.textColor = (checking || active || !badStatus)
            ? FirstLineColors.chromeNSColor : FirstLineColors.redNSColor
        licenseCleanupWarningLabel.stringValue = LicenseActivationError.cleanupFailure.errorDescription ?? ""
        licenseCleanupWarningLabel.isHidden = !active || appState.licenseActivationError != .cleanupFailure
        // Activation dates only; the instance id is an implementation detail.
        let values = [
            appState.settings.licenseActivatedAt.map { "Activated \(formatted($0))" },
            appState.settings.licenseLastValidatedAt.map { "Last validated \(formatted($0))" },
        ]
        for (label, value) in zip(licenseDetails, values) {
            label.stringValue = value ?? ""
            label.isHidden = !active || value == nil
        }
        licenseEntryView?.isHidden = active
        licenseExplanationLabel?.isHidden = !active ? false : true
        buyPageButton?.isHidden = active
        buyPageButton?.isEnabled = appState.checkoutAvailable && !appState.checkoutInFlight
        buyPageButton?.title = appState.checkoutInFlight
            ? "Opening checkout..."
            : "Buy a license, \(AppState.displayPrice) once"
        checkoutStatusLabel?.isHidden = !active && appState.checkoutAvailable
        activateButton?.isEnabled = !checking
    }

    private func armLicenseObservation() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.appState.licenseValidationInFlight
            _ = self.appState.licenseActivationInFlight
            _ = self.appState.checkoutInFlight
            _ = self.appState.settings
            _ = self.appState.licenseActivationError
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshLicense()
                self.armLicenseObservation()
            }
        }
    }

    private func themePopup() -> NSPopUpButton {
        let popup = FirstLineInkPopUpButton(frame: .zero, pullsDown: false)
        popup.font = FirstLineTypography.smallNSFont
        popup.addItems(withTitles: AppTheme.allCases.map(\.label))
        popup.selectItem(at: AppTheme.allCases.firstIndex(of: appState.settings.theme) ?? 0)
        popup.target = self
        popup.action = #selector(themeChanged(_:))
        return popup
    }

    private func motionPopup() -> NSPopUpButton {
        let popup = FirstLineInkPopUpButton(frame: .zero, pullsDown: false)
        popup.font = FirstLineTypography.smallNSFont
        popup.addItems(withTitles: ReducedMotionOverride.allCases.map(\.label))
        popup.selectItem(at: ReducedMotionOverride.allCases.firstIndex(of: appState.settings.reducedMotion) ?? 0)
        popup.target = self
        popup.action = #selector(motionChanged(_:))
        return popup
    }

    private func focusSwitch() -> NSSwitch {
        let toggle = FirstLineInkSwitch(frame: .zero)
        toggle.target = self
        toggle.action = #selector(focusChanged(_:))
        toggle.state = appState.settings.focusMode ? .on : .off
        // The row's leading label names the control; a second title on the switch
        // gave the same row two names (problem 10).
        toggle.setAccessibilityLabel("Focus Mode")
        return toggle
    }

    private func alignmentPopup() -> NSPopUpButton {
        let popup = FirstLineInkPopUpButton(frame: .zero, pullsDown: false)
        popup.font = FirstLineTypography.smallNSFont
        popup.addItems(withTitles: WritingAlignment.allCases.map(\.label))
        popup.selectItem(at: WritingAlignment.allCases.firstIndex(of: appState.settings.writingAlignment) ?? 0)
        popup.target = self
        popup.action = #selector(alignmentChanged(_:))
        return popup
    }

    private func sizePopup() -> NSPopUpButton {
        let popup = FirstLineInkPopUpButton(frame: .zero, pullsDown: false)
        popup.font = FirstLineTypography.smallNSFont
        popup.addItems(withTitles: WritingFontSize.allCases.map(\.label))
        popup.selectItem(at: WritingFontSize.allCases.firstIndex(of: appState.settings.writingFontSize) ?? 1)
        popup.target = self
        popup.action = #selector(sizeChanged(_:))
        return popup
    }

    private func section(_ title: String, rows: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = FirstLineTypography.smallSemiboldNSFont
        label.textColor = FirstLineColors.chromeNSColor
        let stack = NSStackView(views: [label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(10, after: label)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = FloodCanvasView(fillColor: FirstLineColors.hairNSColor)
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func settingRow(_ title: String, control: NSView? = nil, detail: String? = nil) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = FirstLineTypography.uiNSFont
        titleLabel.textColor = FirstLineColors.inkNSColor
        let trailing: NSView = control ?? muted(detail ?? "")
        let row = horizontal(views: [titleLabel, spacer(), trailing])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return row
    }

    private func muted(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = FirstLineTypography.smallNSFont
        label.textColor = FirstLineColors.chromeNSColor
        label.maximumNumberOfLines = 0
        return label
    }

    private func horizontal(views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func primary(_ title: String, _ action: Selector) -> NSButton {
        FirstLineButtons.primary(title: title, target: self, action: action)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard AppTheme.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        appState.updateTheme(AppTheme.allCases[sender.indexOfSelectedItem])
    }

    @objc private func motionChanged(_ sender: NSPopUpButton) {
        guard ReducedMotionOverride.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        appState.updateReducedMotion(ReducedMotionOverride.allCases[sender.indexOfSelectedItem])
    }

    @objc private func focusChanged(_ sender: NSSwitch) {
        appState.updateFocusMode(sender.state == .on)
    }

    @objc private func automaticChecksChanged(_ sender: NSSwitch) {
        updateSettings?.automaticallyChecksForUpdates = sender.state == .on
    }

    @objc private func alignmentChanged(_ sender: NSPopUpButton) {
        guard WritingAlignment.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        appState.updateAlignment(WritingAlignment.allCases[sender.indexOfSelectedItem])
    }

    @objc private func sizeChanged(_ sender: NSPopUpButton) {
        guard WritingFontSize.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        appState.updateFontSize(WritingFontSize.allCases[sender.indexOfSelectedItem])
    }

    @objc private func activateTapped() {
        guard let licenseField, let activateButton else { return }
        activateButton.isEnabled = false
        licenseStatusLabel.stringValue = "Activating..."
        Task { @MainActor [weak self] in
            guard let self else { return }
            await appState.activateLicense(key: licenseField.stringValue)
            activateButton.isEnabled = true
            if appState.licenseActivationJustSucceeded { licenseField.stringValue = "" }
            refreshLicense()
        }
    }

    @objc private func openBuyTapped() { Task { @MainActor in await appState.openCheckout() } }
    @objc private func doneTapped() { appState.closeSettings() }
}
