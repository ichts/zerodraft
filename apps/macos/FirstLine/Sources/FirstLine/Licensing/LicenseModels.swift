/**
 * [INPUT]: Foundation and the Waffo-backed license service contract
 * [OUTPUT]: LicenseStatus, LicenseActivation and typed activation/validation errors
 * [POS]: Shared licensing values; the order number remains licenseKey in persisted settings
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the contract changes
 */
import Foundation

enum LicenseStatus: String, Codable, Sendable {
    case inactive, active, invalid, revoked, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .inactive
    }
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
            return "We could not find that license key, so check it or contact support if you have just paid."
        case .activationLimitReached:
            return "This license key is already on 2 Macs, so contact support to move it to this one."
        case .networkFailure:
            return "We could not connect, so check your internet connection and try again."
        case .emptyKey:
            return "Enter your license key."
        case .unexpected:
            return "Activation did not work, so try again in a moment or contact support if it keeps happening."
        case .storageFailure:
            return "We could not save your license on this Mac, so check your disk and try again."
        case .productNotConfigured:
            return "This copy of Write It Down cannot activate a license, so download it again from writeitdown.app."
        case .wrongProduct:
            return "This license key is for a different app, so use the one from your Write It Down purchase."
        case .invalidToken:
            return "We could not verify your license, so connect to the internet and activate again."
        case .cleanupFailure:
            return "This Mac could not be activated and still counts toward your 2 Macs, so contact support with your receipt to free it."
        }
    }
}

enum LicenseValidationError: Error, Equatable, Sendable {
    case networkFailure
    case unexpected(statusCode: Int)
    case invalidToken
}
