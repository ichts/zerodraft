/**
 * [INPUT]: Foundation and the Waffo-backed license service contract
 * [OUTPUT]: LicenseStatus, LicenseActivation and typed activation/validation errors
 * [POS]: Shared licensing values; the order number remains licenseKey in persisted settings
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the contract changes
 */
import Foundation

enum LicenseStatus: String, Codable, Sendable {
    case trial, active, invalid, revoked, unknown
}

struct LicenseActivation: Equatable, Sendable {
    let instanceID: String
    let productID: String?
    let token: String
}

enum LicenseActivationError: Error, Equatable, Sendable, LocalizedError {
    case invalidKey
    case activationLimitReached
    case networkFailure
    case emptyKey
    case unexpected(statusCode: Int)
    case storageFailure
    case productNotConfigured
    case wrongProduct
    case invalidToken
    case cleanupFailure

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Order not available. Check the order number or contact support if you just paid."
        case .activationLimitReached:
            return "This license has reached its 2-Mac activation limit."
        case .networkFailure:
            return "Could not reach the license service. Check your connection and try again."
        case .emptyKey:
            return "Enter your Waffo order number."
        case .unexpected(let statusCode):
            return "Activation failed (HTTP \(statusCode))."
        case .storageFailure:
            return "Could not save the license on this Mac. Check disk permissions and try again."
        case .productNotConfigured:
            return "License activation is not configured in this build."
        case .wrongProduct:
            return "This license is not for writeitdown."
        case .invalidToken:
            return "The license could not be verified. Reconnect and activate again."
        case .cleanupFailure:
            return "Activation could not be undone. Contact support with your receipt to free the device slot."
        }
    }
}

enum LicenseValidationError: Error, Equatable, Sendable {
    case networkFailure
    case unexpected(statusCode: Int)
    case invalidToken
}
