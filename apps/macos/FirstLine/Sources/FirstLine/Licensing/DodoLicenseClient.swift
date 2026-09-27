/*
 * [INPUT]: LicenseClient, Dodo public license API, injected URLSession
 * [OUTPUT]: DodoLicenseClient activate/validate/deactivate without developer credentials
 * [POS]: Network boundary for licensing; debug defaults to Dodo test mode, release to live
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the API boundary changes
 */
import Foundation

struct DodoLicenseClient: LicenseClient {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL? = nil) {
        self.session = session
        #if DEBUG
        self.baseURL = baseURL ?? URL(string: "https://test.dodopayments.com")!
        #else
        self.baseURL = baseURL ?? URL(string: "https://live.dodopayments.com")!
        #endif
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        let data: Data
        do {
            data = try await post("activate", body: ["license_key": licenseKey, "name": instanceName])
        } catch let error as HTTPFailure {
            switch error.code {
            case "LICENSE_KEY_LIMIT_REACHED": throw LicenseActivationError.activationLimitReached
            case "LICENSE_KEY_NOT_FOUND", "INACTIVE_LICENSE_KEY": throw LicenseActivationError.invalidKey
            default:
                if error.status == 429 || error.status >= 500 { throw LicenseActivationError.networkFailure }
                throw LicenseActivationError.unexpected(statusCode: error.status)
            }
        } catch { throw LicenseActivationError.networkFailure }
        guard let response = try? JSONDecoder().decode(ActivationResponse.self, from: data) else {
            throw LicenseActivationError.unexpected(statusCode: 200)
        }
        return LicenseActivation(instanceID: response.id, licenseKeyID: response.licenseKeyID,
                                 name: response.name, businessID: response.businessID,
                                 createdAt: response.createdAt, productID: response.product?.productID,
                                 productName: response.product?.name)
    }

    func validate(licenseKey: String) async throws -> Bool {
        do {
            let data = try await post("validate", body: ["license_key": licenseKey])
            return try JSONDecoder().decode(ValidationResponse.self, from: data).valid
        } catch let error as HTTPFailure {
            if error.code == "LICENSE_KEY_NOT_FOUND" || error.code == "INACTIVE_LICENSE_KEY" { return false }
            if error.status >= 500 || error.status == 429 { throw LicenseValidationError.networkFailure }
            throw LicenseValidationError.unexpected(statusCode: error.status)
        } catch { throw LicenseValidationError.networkFailure }
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        _ = try await post("deactivate", body: ["license_key": licenseKey, "license_key_instance_id": instanceID])
    }

    private func post(_ endpoint: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("licenses/\(endpoint)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(APIError.self, from: data))?.code
            throw HTTPFailure(status: http.statusCode, code: code)
        }
        return data
    }
}

private struct HTTPFailure: Error {
    let status: Int
    let code: String?
}
private struct APIError: Decodable { let code: String }
private struct ValidationResponse: Decodable { let valid: Bool }
private struct ActivationResponse: Decodable {
    let id: String
    let licenseKeyID: String
    let name: String
    let businessID: String
    let createdAt: String
    let product: Product?
    struct Product: Decodable { let productID: String; let name: String }
    enum CodingKeys: String, CodingKey {
        case id, name, product
        case licenseKeyID = "license_key_id"
        case businessID = "business_id"
        case createdAt = "created_at"
    }
}

extension ActivationResponse.Product {
    enum CodingKeys: String, CodingKey { case name; case productID = "product_id" }
}
