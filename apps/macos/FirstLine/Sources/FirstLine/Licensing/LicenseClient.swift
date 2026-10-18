/**
 * [INPUT]: LicenseModels
 * [OUTPUT]: LicenseClient activation, signed renewal, local verification and rollback
 * [POS]: Waffo-backed service boundary; no merchant credentials or second entitlement store
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the API boundary changes
 */
import Foundation

protocol LicenseClient: Sendable {
    var isConfigured: Bool { get }
    /// licenseKey is the opaque orderId credential; preserve its entered UTF-8 bytes.
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation
    /// Nil is explicit revocation. Transport failures must throw, not revoke.
    func validate(token: String) async throws -> String?
    func deactivate(token: String) async throws
    func permitsAccess(token: String, instanceID: String, installLabel: String, now: Date) -> Bool
}
