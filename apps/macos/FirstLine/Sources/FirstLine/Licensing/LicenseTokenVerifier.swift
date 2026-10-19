/**
 * [INPUT]: CryptoKit Ed25519 public key, service token, expected product/install and clock
 * [OUTPUT]: Authenticated LicenseClaims or invalidToken
 * [POS]: Local entitlement boundary; verifies the encoded payload before reading claims
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the token contract changes
 */
import CryptoKit
import Foundation

struct LicenseClaims: Codable, Equatable, Sendable {
    let licenseId: String
    let activationId: String
    let installLabel: String
    let product: String
    let issuedAt: Int64
    let expiresAt: Int64
}

struct LicenseTokenVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey
    let productID: String
    static let lifetime: Int64 = 7 * 24 * 60 * 60

    init(publicKey: Data, productID: String) throws {
        self.publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        self.productID = productID
    }

    func verify(_ token: String, installLabel: String, now: Date) throws -> LicenseClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let signature = Self.decode(parts[1]),
              publicKey.isValidSignature(signature, for: Data(parts[0].utf8)),
              let payload = Self.decode(parts[0]),
              let claims = try? JSONDecoder().decode(LicenseClaims.self, from: payload),
              !productID.isEmpty, claims.product == productID,
              !installLabel.isEmpty, claims.installLabel == installLabel,
              !claims.licenseId.isEmpty, !claims.activationId.isEmpty,
              claims.issuedAt >= 0,
              Double(claims.issuedAt) <= now.timeIntervalSince1970 + 60,
              Double(claims.expiresAt) > now.timeIntervalSince1970,
              claims.expiresAt > claims.issuedAt,
              claims.expiresAt - claims.issuedAt == Self.lifetime else {
            throw LicenseActivationError.invalidToken
        }
        return claims
    }

    private static func decode(_ value: Substring) -> Data? {
        guard !value.isEmpty, value.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
    }
}
