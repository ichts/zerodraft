/**
 * [INPUT]: 依赖 LicenseClient、LicenseModels
 * [OUTPUT]: MockLicenseClient，Phase 3 期间在 Mac app 内替换真实 Dodo 调用
 * [POS]: Licensing 测试替身；让 UpgradeView / SettingsView / AppState 在 Dodo 产品尚未上线前可跑可测
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import Foundation

/// 测试与本地 QA 用的 LicenseClient 替身。
/// 通过 `activationBehavior` 控制激活分支；通过 `validationResult` 控制 validate 分支。
/// 不发起任何网络请求。
actor MockLicenseClient: LicenseClient {
    enum ActivationBehavior: Sendable {
        case success
        case invalidKey
        case activationLimitReached
        case networkFailure
    }

    private let activationBehavior: ActivationBehavior
    private let validationResult: Bool
    private let validationError: LicenseValidationError?
    private let artificialDelay: Duration?

    /// 测试可读取，确认 UI 传给 client 的 key 与 instance name 符合预期。
    private(set) var lastActivateArguments: (licenseKey: String, instanceName: String)?
    private(set) var lastValidatedKey: String?
    private(set) var lastDeactivateArguments: (licenseKey: String, instanceID: String)?

    init(
        activationBehavior: ActivationBehavior = .success,
        validationResult: Bool = true,
        validationError: LicenseValidationError? = nil,
        artificialDelay: Duration? = nil
    ) {
        self.activationBehavior = activationBehavior
        self.validationResult = validationResult
        self.validationError = validationError
        self.artificialDelay = artificialDelay
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        if let artificialDelay { try? await Task.sleep(for: artificialDelay) }
        lastActivateArguments = (licenseKey, instanceName)

        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LicenseActivationError.emptyKey
        }

        switch activationBehavior {
        case .success:
            return LicenseActivation(
                instanceID: "lki_mock_\(UUID().uuidString.prefix(8))",
                licenseKeyID: "lic_mock_\(UUID().uuidString.prefix(8))",
                name: instanceName,
                businessID: "biz_mock",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                productID: "prod_mock",
                productName: "First Line Early Bird License"
            )
        case .invalidKey:
            throw LicenseActivationError.invalidKey
        case .activationLimitReached:
            throw LicenseActivationError.activationLimitReached
        case .networkFailure:
            throw LicenseActivationError.networkFailure
        }
    }

    func validate(licenseKey: String) async throws -> Bool {
        if let artificialDelay { try? await Task.sleep(for: artificialDelay) }
        lastValidatedKey = licenseKey
        if let validationError { throw validationError }
        return validationResult
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        if let artificialDelay { try? await Task.sleep(for: artificialDelay) }
        lastDeactivateArguments = (licenseKey, instanceID)
    }
}
