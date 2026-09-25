/**
 * [INPUT]: AppKit, AppState, DesignSystem tokens and FirstLineButtons
 * [OUTPUT]: SettingsViewController - appearance, focus, alignment, font size, live license feedback
 * [POS]: AppKit Settings surface; live visual preferences do not reset engine, Done restores prior surface
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit
import Observation

@MainActor
final class SettingsViewController: NSViewController {
    private let appState: AppState
    private var licenseField: NSTextField?
    private var activateButton: NSButton?
    private var licenseStatusLabel: NSTextField!
    private var licenseEntryView: NSView?
    private var licenseExplanationLabel: NSTextField?
    private var buyPageButton: NSButton?
    private var checkoutStatusLabel: NSTextField?
    private var licenseDetails: [NSTextField] = []

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        buildInterface()
        refreshLicense()
        armLicenseObservation()
    }

    private func buildInterface() {
        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 28

        let header = horizontal(views: [heading("Settings"), spacer(), link("Done", #selector(doneTapped))])
        content.addArrangedSubview(header)
        content.addArrangedSubview(section("Appearance", rows: [
            settingRow("Theme", control: themePopup()),
            settingRow("Reduced Motion", control: motionPopup()),
            settingRow("Focus Mode", control: focusSwitch()),
            settingRow("Alignment", control: alignmentPopup()),
            settingRow("Font Size", control: sizePopup()),
        ]))
        content.addArrangedSubview(section("Trial & License", rows: licenseRows()))
        content.addArrangedSubview(section("About", rows: [
            settingRow("Write It Down", detail: "Version 0.1.0"),
        ]))

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
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
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 56),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 72),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -72),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            document.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 56),
            header.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])
    }

    private func licenseRows() -> [NSView] {
        licenseStatusLabel = muted(appState.trialStatusText)
        var rows: [NSView] = [licenseStatusLabel]

        licenseDetails = (0..<3).map { _ in muted("") }
        rows.append(contentsOf: licenseDetails)

        let explanation = muted("Three writing sessions included. Activate a license key to keep writing.")
        licenseExplanationLabel = explanation

        let field = NSTextField(string: "")
        field.placeholderString = "Paste license key"
        field.font = FirstLineTypography.microcopyNSFont
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        licenseField = field

        let button = primary("Activate", #selector(activateTapped))
        activateButton = button
        let entry = NSStackView(views: [field, button])
        entry.orientation = .horizontal
        entry.alignment = .centerY
        entry.spacing = 12
        licenseEntryView = entry

        let buy = link("Buy a license - \(AppState.displayPrice), one time", #selector(openBuyTapped))
        buy.isEnabled = AppState.checkoutURL != nil
        buyPageButton = buy
        rows.append(contentsOf: [explanation, entry, buy])
        if !buy.isEnabled {
            let unavailable = muted("Checkout is not available yet.")
            checkoutStatusLabel = unavailable
            rows.append(unavailable)
        }
        return rows
    }

    private func refreshLicense() {
        licenseStatusLabel.stringValue = appState.licenseActivationError?.errorDescription ?? appState.trialStatusText
        let values = [
            appState.settings.licenseActivatedAt.map { "Activated \(formatted($0))" },
            appState.settings.licenseInstanceID.map { "Instance: \($0)" },
            appState.settings.licenseLastValidatedAt.map { "Last validated \(formatted($0))" },
        ]
        for (label, value) in zip(licenseDetails, values) {
            label.stringValue = value ?? ""
            label.isHidden = !appState.hasFullAccess || value == nil
        }
        let showEntry = !appState.hasFullAccess
        licenseEntryView?.isHidden = !showEntry
        licenseExplanationLabel?.isHidden = !showEntry
        buyPageButton?.isHidden = !showEntry
        checkoutStatusLabel?.isHidden = !showEntry || AppState.checkoutURL != nil
    }

    private func armLicenseObservation() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.appState.licenseValidationInFlight
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
        let popup = NSPopUpButton()
        popup.font = FirstLineTypography.microcopyNSFont
        popup.addItems(withTitles: AppTheme.allCases.map(\.label))
        popup.selectItem(at: AppTheme.allCases.firstIndex(of: appState.settings.theme) ?? 0)
        popup.target = self
        popup.action = #selector(themeChanged(_:))
        return popup
    }

    private func motionPopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.font = FirstLineTypography.microcopyNSFont
        popup.addItems(withTitles: ReducedMotionOverride.allCases.map(\.label))
        popup.selectItem(at: ReducedMotionOverride.allCases.firstIndex(of: appState.settings.reducedMotion) ?? 0)
        popup.target = self
        popup.action = #selector(motionChanged(_:))
        return popup
    }

    private func focusSwitch() -> NSButton {
        let button = NSButton(checkboxWithTitle: "Fullscreen focus", target: self, action: #selector(focusChanged(_:)))
        button.state = appState.settings.focusMode ? .on : .off
        return button
    }

    private func alignmentPopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: WritingAlignment.allCases.map(\.label))
        popup.selectItem(at: WritingAlignment.allCases.firstIndex(of: appState.settings.writingAlignment) ?? 0)
        popup.target = self
        popup.action = #selector(alignmentChanged(_:))
        return popup
    }

    private func sizePopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: WritingFontSize.allCases.map(\.label))
        popup.selectItem(at: WritingFontSize.allCases.firstIndex(of: appState.settings.writingFontSize) ?? 1)
        popup.target = self
        popup.action = #selector(sizeChanged(_:))
        return popup
    }

    private func section(_ title: String, rows: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = FirstLineTypography.sessionStatusNSFont
        label.textColor = FirstLineColors.uiNSColor
        let stack = NSStackView(views: [label] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: label)
        return stack
    }

    private func settingRow(_ title: String, control: NSView? = nil, detail: String? = nil) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = FirstLineTypography.bodyNSFont
        titleLabel.textColor = FirstLineColors.inkNSColor
        let trailing: NSView = control ?? muted(detail ?? "")
        let row = horizontal(views: [titleLabel, spacer(), trailing])
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 640).isActive = true
        return row
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = FirstLineTypography.titleNSFont
        label.textColor = FirstLineColors.inkNSColor
        return label
    }

    private func muted(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = FirstLineTypography.microcopyNSFont
        label.textColor = FirstLineColors.uiNSColor
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

    private func link(_ title: String, _ action: Selector) -> NSButton {
        FirstLineButtons.link(title: title, target: self, action: action)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
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

    @objc private func focusChanged(_ sender: NSButton) {
        appState.updateFocusMode(sender.state == .on)
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

    @objc private func openBuyTapped() { appState.openCheckout() }
    @objc private func doneTapped() { appState.closeSettings() }
}
