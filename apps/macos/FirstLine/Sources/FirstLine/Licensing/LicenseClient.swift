/**
 * [INPUT]: LicenseModels
 * [OUTPUT]: LicenseClient protocol for Polar public activate / validate / deactivate
 * [POS]: Licensing boundary shared by the real network client and test substitute
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the API boundary changes
 */

import Foundation

/// Public customer-portal endpoints need no merchant access token. Never log the key or request body.
protocol LicenseClient: Sendable {
    /// Activate this install and return the allocation ID for later validation or deactivation.
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation

    /// Validate the cached activation, not merely the key. False means the entitlement was revoked.
    func validate(licenseKey: String, instanceID: String) async throws -> Bool

    /// Undo a rejected activation so a device slot is not consumed.
    func deactivate(licenseKey: String, instanceID: String) async throws
}
