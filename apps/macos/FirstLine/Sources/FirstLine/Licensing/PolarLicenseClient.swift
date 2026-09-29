/*
 * [INPUT]: LicenseClient, Polar public customer-portal license API, injected URLSession
 * [OUTPUT]: PolarLicenseClient activate/validate/deactivate without an access token
 * [POS]: Licensing network boundary; debug defaults to sandbox, release to production
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the API boundary changes
 */
import Foundation

struct PolarLicenseClient: LicenseClient {
    private let session: URLSession
    private let baseURL: URL
    private let organizationID: String
    private let benefitID: String

    init(organizationID: String, benefitID: String, session: URLSession = .shared, baseURL: URL? = nil) {
        self.organizationID = organizationID
        self.benefitID = benefitID
        self.session = session
        #if DEBUG
        self.baseURL = baseURL ?? URL(string: "https://sandbox-api.polar.sh/v1")!
        #else
        self.baseURL = baseURL ?? URL(string: "https://api.polar.sh/v1")!
        #endif
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        let data: Data
        do {
            data = try await post("activate", body: ["key": licenseKey, "organization_id": organizationID, "label": instanceName])
        } catch let failure as HTTPFailure {
            if failure.status == 404 { throw LicenseActivationError.invalidKey }
            if failure.status == 403 {
                let detail = failure.detail.lowercased()
                if detail.contains("limit") && detail.contains("activation") {
                    throw LicenseActivationError.activationLimitReached
                }
                throw LicenseActivationError.invalidKey
            }
            if failure.status == 429 || failure.status >= 500 { throw LicenseActivationError.networkFailure }
            throw LicenseActivationError.unexpected(statusCode: failure.status)
        } catch { throw LicenseActivationError.networkFailure }
        guard let result = try? JSONDecoder().decode(ActivationResponse.self, from: data),
              result.licenseKey.status == "granted",
              result.licenseKey.organizationID == organizationID else {
            throw LicenseActivationError.unexpected(statusCode: 200)
        }
        return LicenseActivation(instanceID: result.id, licenseKeyID: result.licenseKeyID,
                                 name: result.label, businessID: result.licenseKey.organizationID,
                                 createdAt: result.createdAt, productID: result.licenseKey.benefitID)
    }

    func validate(licenseKey: String, instanceID: String) async throws -> Bool {
        let body = ["key": licenseKey, "organization_id": organizationID,
                    "activation_id": instanceID, "benefit_id": benefitID]
        let data: Data
        do {
            data = try await post("validate", body: body)
        } catch let failure as HTTPFailure {
            if failure.status == 404 { return false }
            if failure.status == 429 || failure.status >= 500 { throw LicenseValidationError.networkFailure }
            throw LicenseValidationError.unexpected(statusCode: failure.status)
        } catch { throw LicenseValidationError.networkFailure }
        guard let result = try? JSONDecoder().decode(ValidationResponse.self, from: data) else {
            throw LicenseValidationError.unexpected(statusCode: 200)
        }
        return result.status == "granted" && result.organizationID == organizationID &&
            result.benefitID == benefitID && result.activation?.id == instanceID
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        _ = try await post("deactivate", body: ["key": licenseKey,
                                                "organization_id": organizationID,
                                                "activation_id": instanceID])
    }

    private func post(_ endpoint: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("customer-portal/license-keys/\(endpoint)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIError.self, from: data))?.detail ?? ""
            throw HTTPFailure(status: http.statusCode, detail: detail)
        }
        return data
    }
}

private struct HTTPFailure: Error { let status: Int; let detail: String }
private struct APIError: Decodable { let detail: String }
private struct ActivationResponse: Decodable {
    let id: String
    let licenseKeyID: String
    let label: String
    let createdAt: String
    let licenseKey: Key
    struct Key: Decodable {
        let organizationID: String
        let benefitID: String
        let status: String
        enum CodingKeys: String, CodingKey {
            case status
            case organizationID = "organization_id"
            case benefitID = "benefit_id"
        }
    }
    enum CodingKeys: String, CodingKey {
        case id, label
        case licenseKeyID = "license_key_id"
        case createdAt = "created_at"
        case licenseKey = "license_key"
    }
}
private struct ValidationResponse: Decodable {
    let organizationID: String
    let benefitID: String
    let status: String
    let activation: Activation?
    struct Activation: Decodable { let id: String }
    enum CodingKeys: String, CodingKey {
        case status, activation
        case organizationID = "organization_id"
        case benefitID = "benefit_id"
    }
}
