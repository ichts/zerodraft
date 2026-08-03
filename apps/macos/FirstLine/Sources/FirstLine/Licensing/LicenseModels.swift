/**
 * [INPUT]: 依赖 Foundation
 * [OUTPUT]: LicenseStatus、LicenseActivation、LicenseActivationError、LicenseValidationError，对照 Dodo 公开 license API 契约
 * [POS]: Licensing 模块的契约层，定义 Mac app 与 LicenseClient 之间共享的数据形状；含本地持久化失败的 storageFailure 错误
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation

/// Mac app 内部使用的 license 状态。比 Dodo 公开 endpoints 返回的 `valid: Bool` 更细粒度：
/// `.trial` / `.active` / `.invalid` / `.revoked` / `.unknown` 分别对应不同 UI 行为与 trial gate 判定。
enum LicenseStatus: String, Codable, Sendable {
    case trial
    case active
    case invalid
    case revoked
    case unknown
}

/// `/licenses/activate` 成功后保留的关键字段。
/// 对照 https://docs.dodopayments.com/api-reference/licenses/activate-license 的 response shape。
struct LicenseActivation: Codable, Equatable, Sendable {
    /// `lki_...` - Dodo 返回的 license key instance ID。后续 `/licenses/deactivate` 必填。
    let instanceID: String
    /// `lic_...` - 关联的 license key ID。
    let licenseKeyID: String
    /// 此激活实例的人类可读名，例如 "First Line Mac abcd1234"。
    let name: String
    /// `business_id`。仅作记录，不参与本地决策。
    let businessID: String
    /// ISO8601 创建时间字符串。Dodo 返回的是 string，本地保留原值。
    let createdAt: String
    /// 关联产品 ID（如有）。
    let productID: String?
    /// 关联产品名（如有）。
    let productName: String?

    init(
        instanceID: String,
        licenseKeyID: String,
        name: String,
        businessID: String,
        createdAt: String,
        productID: String? = nil,
        productName: String? = nil
    ) {
        self.instanceID = instanceID
        self.licenseKeyID = licenseKeyID
        self.name = name
        self.businessID = businessID
        self.createdAt = createdAt
        self.productID = productID
        self.productName = productName
    }
}

/// `/licenses/activate` 失败原因。映射 Dodo 错误响应到 UI 文案。
enum LicenseActivationError: Error, Equatable, Sendable, LocalizedError {
    /// Key 不存在 / 已退款 / 已撤销。Dodo 通常返回 4xx。
    case invalidKey
    /// 已达 2-Mac 激活上限。
    case activationLimitReached
    /// 网络故障、超时、5xx。
    case networkFailure
    /// 输入为空或全空白。
    case emptyKey
    /// Dodo 返回了无法识别的错误。保留原始状态码以便诊断。
    case unexpected(statusCode: Int)
    /// 激活在 Dodo 侧成功，但无法把 license 状态写盘（磁盘权限/空间等）。
    case storageFailure

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "This license key is invalid, refunded, or revoked."
        case .activationLimitReached:
            return "This license has reached its 2-Mac activation limit."
        case .networkFailure:
            return "Could not reach Dodo Payments. Check your connection and try again."
        case .emptyKey:
            return "Enter the license key from your Dodo receipt email."
        case .unexpected(let statusCode):
            return "Activation failed (HTTP \(statusCode))."
        case .storageFailure:
            return "Could not save the license on this Mac. Check disk permissions and try again."
        }
    }
}

/// `/licenses/validate` 失败原因。比 activate 简单：只有 invalid / network / unexpected。
enum LicenseValidationError: Error, Equatable, Sendable {
    case networkFailure
    case unexpected(statusCode: Int)
}
