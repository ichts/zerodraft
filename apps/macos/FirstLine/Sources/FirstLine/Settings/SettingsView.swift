/**
 * [INPUT]: 依赖 AppState、DesignSystem token
 * [OUTPUT]: 提供真实 SettingsView，包含原生 trial 状态
 * [POS]: Settings surface，负责持久化主题、默认时长、immersive mode、reduced motion、trial 状态展示与 library reveal 动作
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var settingsLicenseKeyInput: String = ""

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { appState.settings.theme },
                    set: { appState.updateTheme($0) }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }

                Picker("Reduced Motion", selection: Binding(
                    get: { appState.settings.reducedMotion },
                    set: { appState.updateReducedMotion($0) }
                )) {
                    ForEach(ReducedMotionOverride.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section("Session") {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text("60 seconds. Fixed.")
                        .foregroundStyle(FirstLineColors.ui)
                }

                Toggle("Immersive Session Mode", isOn: Binding(
                    get: { appState.settings.immersiveSessionMode },
                    set: { appState.updateImmersiveMode($0) }
                ))
            }

            Section("Trial & License") {
                Text(appState.trialStatusText)

                if appState.settings.licenseStatus != .active {
                    Text("The Mac trial includes three real writing sessions. Starting a session consumes one trial use. After the trial, activate a license key to keep writing.")
                        .font(FirstLineTypography.microcopy)
                        .foregroundStyle(FirstLineColors.ui)

                    licenseEntryRow
                }

                if appState.settings.licenseStatus == .active {
                    if let activated = appState.settings.licenseActivatedAt {
                        Text("Activated \(activated.formatted(date: .abbreviated, time: .shortened))")
                            .font(FirstLineTypography.microcopy)
                            .foregroundStyle(FirstLineColors.ui)
                    }
                    if let instance = appState.settings.licenseInstanceID {
                        Text("Instance: \(instance)")
                            .font(FirstLineTypography.microcopy)
                            .foregroundStyle(FirstLineColors.ui)
                    }
                    if let validated = appState.settings.licenseLastValidatedAt {
                        Text("Last validated \(validated.formatted(date: .abbreviated, time: .shortened))")
                            .font(FirstLineTypography.microcopy)
                            .foregroundStyle(FirstLineColors.ui)
                    }
                }
            }

            Section("Storage") {
                Button("Reveal Library Folder") {
                    appState.revealLibraryFolder()
                }
                Text(AppPaths.libraryDirectory.path)
                    .font(FirstLineTypography.microcopy)
                    .foregroundStyle(FirstLineColors.ui)
            }

            Section("About") {
                Text("First Line")
                Text("Version 0.1.0")
            }
        }
        .formStyle(.grouped)
        .padding(FirstLineSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var licenseEntryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Paste license key", text: $settingsLicenseKeyInput)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            HStack(spacing: 8) {
                Button("Activate") {
                    Task { await appState.activateLicense(key: settingsLicenseKeyInput) }
                }
                .buttonStyle(FirstLinePrimaryButtonStyle())
                .disabled(
                    appState.licenseActivationInFlight
                        || settingsLicenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if appState.licenseActivationInFlight {
                    ProgressView().controlSize(.small)
                }
            }

            if let error = appState.licenseActivationError {
                Text(error.errorDescription ?? "Activation failed.")
                    .font(FirstLineTypography.microcopy)
                    .foregroundStyle(FirstLineColors.ink)
            }

            if appState.licenseActivationJustSucceeded {
                Text("License active. Return to writing.")
                    .font(FirstLineTypography.microcopy)
                    .foregroundStyle(FirstLineColors.ink)
            }

            Button("Open Buy page") {
                appState.openLaunchWebsite()
            }
            .buttonStyle(.link)
            .font(FirstLineTypography.microcopy)
        }
    }
}
