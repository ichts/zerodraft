/**
 * [INPUT]: 依赖 LicenseModels
 * [OUTPUT]: LicenseClient protocol，覆盖 activate / validate / deactivate 三个 Dodo 公开 license endpoint
 * [POS]: Licensing 抽象层，让 Mac app 在没有真实 Dodo 网络调用时也能测试与运行
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import Foundation

/// Mac app 与 Dodo 公开 license API 之间的契约。
/// 所有方法都是 async，便于 mock 与真实 HTTP 实现共享同一签名。
///
/// 实现注意：
/// - activate / validate / deactivate 都不需要 developer API key（Dodo 文档明确为公开端点）
/// - 实现层不得在请求体里夹带任何开发者密钥；license_key 自身就是认证因子
/// - 不得在日志中输出 license_key 全文
protocol LicenseClient: Sendable {
    /// 对应 `POST /licenses/activate`。
    /// - Parameters:
    ///   - licenseKey: 用户粘贴的 key，已 trim。
    ///   - instanceName: 传给 Dodo 的 `name` 字段。推荐 "First Line Mac <short-install-id>"。
    /// - Returns: 激活后的实例信息（含 `instanceID`，需要持久化以便将来 deactivate）。
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation

    /// 对应 `POST /licenses/validate`。
    /// - Parameter licenseKey: 已持久化的 key。
    /// - Returns: true 表示仍然有效；false 表示已退款/撤销/失效。
    /// - Throws: 网络或非预期 HTTP 状态码时抛 `LicenseValidationError`。
    func validate(licenseKey: String) async throws -> Bool

    /// 对应 `POST /licenses/deactivate`。
    /// v1 UI 不暴露此操作，但 API 契约留位，便于将来加 self-serve device management。
    /// - Parameters:
    ///   - licenseKey: 同上。
    ///   - instanceID: 来自 activate 返回的 `LicenseActivation.instanceID`。
    func deactivate(licenseKey: String, instanceID: String) async throws
}
