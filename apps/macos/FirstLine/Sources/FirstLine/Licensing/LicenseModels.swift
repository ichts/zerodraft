/**
 * [INPUT]: 依赖 Foundation
 * [OUTPUT]: LicenseStatus、LicenseActivation、LicenseActivationError、LicenseValidationError，对照 Polar 公开 customer-portal license API 契约
 * [POS]: Licensing 模块的契约层，定义 Mac app 与 LicenseClient 之间共享的数据形状；含本地持久化失败的 storageFailure 错误
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import Foundation

/// Mac app 内部使用的 license 状态。比 Polar 的 granted / invalid 状态更细粒度：
/// `.trial` / `.active` / `.invalid` / `.revoked` / `.unknown` 分别对应不同 UI 行为与 trial gate 判定。
enum LicenseStatus: String, Codable, Sendable {
    case trial
    case active
    case invalid
    case revoked
    case unknown
}

/// Polar customer-portal activate 成功后保留的关键字段。历史字段名兼容本地状态模型。
struct LicenseActivation: Codable, Equatable, Sendable {
    /// Polar activation UUID。后续 deactivate 必填。
    let instanceID: String
    /// Polar license key UUID。
    let licenseKeyID: String
    /// 此激活实例的人类可读名，例如 "writeitdown Mac abcd1234"。
    let name: String
    /// Polar organization UUID。
    let businessID: String
    /// ISO8601 创建时间字符串。
    let createdAt: String
    /// Polar license-key benefit UUID；历史属性名保留以避免改变本地状态模型。
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

/// Polar customer-portal activate 失败原因。
enum LicenseActivationError: Error, Equatable, Sendable, LocalizedError {
    /// Key 不存在 / 已退款 / 已撤销。Polar 通常返回 403 或 404。
    case invalidKey
    /// 已达 2-Mac 激活上限。
    case activationLimitReached
    /// 网络故障、超时、5xx。
    case networkFailure
    /// 输入为空或全空白。
    case emptyKey
    /// Polar 返回了无法识别的错误。保留原始状态码以便诊断。
    case unexpected(statusCode: Int)
    /// 激活在 Polar 侧成功，但无法把 license 状态写盘（磁盘权限/空间等）。
    case storageFailure
    case productNotConfigured
    case wrongProduct
    case cleanupFailure

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "This license key is invalid, refunded, or revoked."
        case .activationLimitReached:
            return "This license has reached its 2-Mac activation limit."
        case .networkFailure:
            return "Could not reach Polar. Check your connection and try again."
        case .emptyKey:
            return "Enter the license key from your Polar purchase email."
        case .unexpected(let statusCode):
            return "Activation failed (HTTP \(statusCode))."
        case .storageFailure:
            return "Could not save the license on this Mac. Check disk permissions and try again."
        case .productNotConfigured:
            return "License activation is unavailable until the writeitdown Polar organization and benefit are configured."
        case .wrongProduct:
            return "This license is not for writeitdown."
        case .cleanupFailure:
            return "Activation could not be undone. Contact support with your receipt to free the device slot."
        }
    }
}

/// `/licenses/validate` 失败原因。比 activate 简单：只有 invalid / network / unexpected。
enum LicenseValidationError: Error, Equatable, Sendable {
    case networkFailure
    case unexpected(statusCode: Int)
}
