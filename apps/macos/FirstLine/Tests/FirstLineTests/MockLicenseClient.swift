/**
 * [INPUT]: 依赖 LicenseClient、LicenseModels
 * [OUTPUT]: MockLicenseClient，用于状态机测试，不证明签名或真实付款
 * [POS]: 仅测试目标的许可替身，真实协议另由 HTTP stub 和签名测试验证
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import Foundation
@testable import WriteItDown

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
    private let productID: String?
    private let deactivateFails: Bool
    private let activationInstanceID: String?

    /// 测试可读取，确认 UI 传给 client 的 key 与 instance name 符合预期。
    private(set) var lastActivateArguments: (licenseKey: String, instanceName: String)?
    private(set) var lastValidatedToken: String?
    private(set) var lastDeactivatedToken: String?
    nonisolated let isConfigured = true

    nonisolated func permitsAccess(token: String, instanceID: String, installLabel: String, now: Date) -> Bool {
        token == "mock-token"
    }

    init(
        activationBehavior: ActivationBehavior = .success,
        validationResult: Bool = true,
        validationError: LicenseValidationError? = nil,
        artificialDelay: Duration? = nil,
        productID: String? = "prod_mock",
        deactivateFails: Bool = false,
        activationInstanceID: String? = nil
    ) {
        self.activationBehavior = activationBehavior
        self.validationResult = validationResult
        self.validationError = validationError
        self.artificialDelay = artificialDelay
        self.productID = productID
        self.deactivateFails = deactivateFails
        self.activationInstanceID = activationInstanceID
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
                instanceID: activationInstanceID ?? "lki_mock_\(UUID().uuidString.prefix(8))",
                productID: productID,
                token: "mock-token"
            )
        case .invalidKey:
            throw LicenseActivationError.invalidKey
        case .activationLimitReached:
            throw LicenseActivationError.activationLimitReached
        case .networkFailure:
            throw LicenseActivationError.networkFailure
        }
    }

    func validate(token: String) async throws -> String? {
        if let artificialDelay { try? await Task.sleep(for: artificialDelay) }
        lastValidatedToken = token
        if let validationError { throw validationError }
        return validationResult ? "mock-token" : nil
    }

    func deactivate(token: String) async throws {
        if let artificialDelay { try? await Task.sleep(for: artificialDelay) }
        lastDeactivatedToken = token
        if deactivateFails { throw LicenseValidationError.networkFailure }
    }
}
