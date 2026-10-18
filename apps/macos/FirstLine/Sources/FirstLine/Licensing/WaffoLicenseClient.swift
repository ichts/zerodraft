/**
 * [INPUT]: URLSession, configured service URL/product/public key, LicenseTokenVerifier
 * [OUTPUT]: Waffo-backed activation, token renewal and deactivation
 * [POS]: Stateless HTTP boundary; no Waffo merchant API or embedded secret; refuses redirects
 * [PROTOCOL]: Update this header and FirstLine/AGENTS.md when the wire contract changes
 */
import Foundation

struct WaffoLicenseClient: LicenseClient {
    private let session: URLSession
    private let baseURL: URL?
    private let verifier: LicenseTokenVerifier?
    private let clock: @Sendable () -> Date

    var isConfigured: Bool { baseURL != nil && verifier?.productID.isEmpty == false }

    init(baseURL: URL?, productID: String, publicKey: Data,
         session: URLSession = .shared, clock: @escaping @Sendable () -> Date = Date.init) {
        self.baseURL = Self.allowedURL(baseURL) ? baseURL : nil
        self.verifier = try? LicenseTokenVerifier(publicKey: publicKey, productID: productID)
        self.session = session
        self.clock = clock
    }

    static func allowedURL(_ url: URL?) -> Bool {
        guard let url, let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return false }
        return url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "[::1]"].contains(host))
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        guard isConfigured, let verifier else { throw LicenseActivationError.productNotConfigured }
        let data: Data
        do {
            data = try await post("activate", body: ["orderId": licenseKey, "installLabel": instanceName, "platform": "macos"])
        } catch let failure as HTTPFailure {
            switch failure.status {
            case 403, 404: throw LicenseActivationError.invalidKey
            case 409 where failure.detail.trimmingCharacters(in: .whitespacesAndNewlines) == "device limit reached":
                throw LicenseActivationError.activationLimitReached
            case 429, 500...599: throw LicenseActivationError.networkFailure
            default: throw LicenseActivationError.unexpected(statusCode: failure.status)
            }
        } catch { throw LicenseActivationError.networkFailure }
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw LicenseActivationError.invalidToken
        }
        let claims = try verifier.verify(response.token, installLabel: instanceName, now: clock())
        return LicenseActivation(instanceID: claims.activationId, productID: claims.product, token: response.token)
    }

    func validate(token: String) async throws -> String? {
        guard isConfigured else { throw LicenseValidationError.invalidToken }
        let data: Data
        do { data = try await post("validate", body: ["token": token]) }
        catch let failure as HTTPFailure {
            switch failure.status {
            case 403: return nil
            case 429, 500...599: throw LicenseValidationError.networkFailure
            default: throw LicenseValidationError.unexpected(statusCode: failure.status)
            }
        } catch { throw LicenseValidationError.networkFailure }
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw LicenseValidationError.invalidToken
        }
        return response.token
    }

    func permitsAccess(token: String, instanceID: String, installLabel: String, now: Date) -> Bool {
        guard isConfigured, let claims = try? verifier?.verify(token, installLabel: installLabel, now: now) else { return false }
        return claims.activationId == instanceID
    }

    func deactivate(token: String) async throws {
        _ = try await post("deactivate", body: ["token": token])
    }

    private func post(_ endpoint: String, body: [String: String]) async throws -> Data {
        guard isConfigured, let baseURL else { throw LicenseActivationError.productNotConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/licenses/\(endpoint)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request, delegate: NoLicenseRedirects())
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            throw HTTPFailure(status: http.statusCode, detail: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

private struct TokenResponse: Decodable { let token: String }
private struct HTTPFailure: Error { let status: Int; let detail: String }
private final class NoLicenseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
