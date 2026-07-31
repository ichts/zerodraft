/**
 * [INPUT]: 依赖 AppState、LicenseModels、DesignSystem token
 * [OUTPUT]: 提供 Mac trial 用尽后的 UpgradeView，含 license key 输入与激活流程
 * [POS]: Upgrade surface，负责在 Dodo 产品上线前以 mock client 完成 UI 全链路；checkout URL 就绪后切换 Buy 按钮状态
 * [PROTOCOL]: 变更时更新此头部和 FirstLine/CLAUDE.md
 */

import SwiftUI

struct UpgradeView: View {
    @Bindable var appState: AppState
    @State private var licenseKeyInput: String = ""
    @State private var hasInteracted: Bool = false
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: FirstLineSpacing.md) {
                headerBlock
                pricingBlock
                activationBlock
                footerActions
            }
            .padding(FirstLineSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(FirstLineColors.paper)
        .onAppear {
            appState.clearLicenseActivationError()
            appState.dismissLicenseSuccessFeedback()
            keyFieldFocused = true
        }
    }

    private var headerBlock: some View {
        VStack(spacing: FirstLineSpacing.xs) {
            Text("Trial complete")
                .font(FirstLineTypography.title)
                .foregroundStyle(FirstLineColors.ink)
            Text("You used the three free Mac writing sessions.")
                .font(FirstLineTypography.tagline)
                .foregroundStyle(FirstLineColors.ui)
                .multilineTextAlignment(.center)
        }
    }

    private var pricingBlock: some View {
        VStack(spacing: 6) {
            Text("First Line Early Bird License")
                .font(FirstLineTypography.body)
                .foregroundStyle(FirstLineColors.ink)
            Text("One-time $5. 2 Macs. No subscription. 14-day refund.")
                .font(FirstLineTypography.body)
                .foregroundStyle(FirstLineColors.ui)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, FirstLineSpacing.xs)
    }

    @ViewBuilder
    private var activationBlock: some View {
        VStack(spacing: FirstLineSpacing.xs) {
            if appState.licenseActivationJustSucceeded {
                successState
            } else {
                entryState
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var entryState: some View {
        VStack(spacing: FirstLineSpacing.xs) {
            TextField("Paste license key from Dodo email", text: $licenseKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(FirstLineTypography.body)
                .focused($keyFieldFocused)
                .disableAutocorrection(true)
                .textContentType(.username)
                .submitLabel(.go)
                .onSubmit {
                    Task { await appState.activateLicense(key: licenseKeyInput) }
                }

            Button {
                hasInteracted = true
                Task { await appState.activateLicense(key: licenseKeyInput) }
            } label: {
                if appState.licenseActivationInFlight {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Activating")
                    }
                } else {
                    Text("Activate")
                }
            }
            .buttonStyle(FirstLinePrimaryButtonStyle())
            .disabled(!canActivate)

            activationFeedback
        }
    }

    private var successState: some View {
        VStack(spacing: FirstLineSpacing.sm) {
            Text("License active. Thank you.")
                .font(FirstLineTypography.body)
                .foregroundStyle(FirstLineColors.success)
            Text("First Line is unlocked on this Mac.")
                .font(FirstLineTypography.microcopy)
                .foregroundStyle(FirstLineColors.ui)
            Button("Start writing") {
                appState.dismissLicenseSuccessFeedback()
                appState.goHome()
            }
            .buttonStyle(FirstLinePrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var activationFeedback: some View {
        if let error = appState.licenseActivationError {
            VStack(spacing: 4) {
                Text(error.errorDescription ?? "Activation failed.")
                    .font(FirstLineTypography.microcopy)
                    .foregroundStyle(FirstLineColors.ink)
                    .multilineTextAlignment(.center)
                if hasInteracted {
                    Text("Try again, or use a different key.")
                        .font(FirstLineTypography.microcopy)
                        .foregroundStyle(FirstLineColors.ui)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footerActions: some View {
        VStack(spacing: FirstLineSpacing.xs) {
            Button {
                appState.openLaunchWebsite()
            } label: {
                VStack(spacing: 2) {
                    Text("Buy a license")
                        .font(FirstLineTypography.buttonLabel)
                    Text("Checkout coming soon")
                        .font(FirstLineTypography.microcopy)
                        .foregroundStyle(FirstLineColors.ui)
                }
            }
            .buttonStyle(FirstLineSecondaryButtonStyle())
            .disabled(true)
            .help("Dodo Payments checkout opens after review is complete.")

            Button("Back to Home") {
                appState.goHome()
            }
            .buttonStyle(FirstLineSecondaryButtonStyle())
        }
        .padding(.top, FirstLineSpacing.sm)
    }

    private var canActivate: Bool {
        !appState.licenseActivationInFlight
            && !licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
