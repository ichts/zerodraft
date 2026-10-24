/**
 * [INPUT]: The configured license-service origin and URLSession; no buyer credential or secret.
 * [OUTPUT]: POST /api/v1/checkout -> the validated https checkout.stripe.com URL.
 * [POS]: Native hosted-checkout boundary used by the in-app Buy action; mac.html remains the error fallback.
 * [PROTOCOL]: Update this header, LICENSE_PAYMENT_SPEC.md and FirstLine/AGENTS.md when the wire contract changes.
 */
import Foundation

protocol CheckoutClient: Sendable {
    var isConfigured: Bool { get }
    /// Creates a hosted checkout session. Callers fall back to the public Mac page on any error.
    func createCheckoutSession() async throws -> URL
}

enum CheckoutError: Error, Equatable {
    case unavailable
    case invalidResponse
    case invalidDestination
}

struct HostedCheckoutClient: CheckoutClient {
    private let baseURL: URL?
    private let session: URLSession

    init(baseURL: URL?, session: URLSession? = nil) {
        self.baseURL = WaffoLicenseClient.allowedURL(baseURL) ? baseURL : nil
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    var isConfigured: Bool { baseURL != nil }

    func createCheckoutSession() async throws -> URL {
        guard let baseURL else { throw CheckoutError.unavailable }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/checkout"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoCheckoutRedirects())
        } catch {
            throw CheckoutError.unavailable
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CheckoutError.unavailable
        }
        guard let payload = try? JSONDecoder().decode(CheckoutResponse.self, from: data),
              let destination = URL(string: payload.url),
              destination.scheme == "https",
              destination.host == "checkout.stripe.com",
              destination.user == nil,
              destination.password == nil else {
            throw CheckoutError.invalidDestination
        }
        return destination
    }
}

private struct CheckoutResponse: Decodable {
    let url: String
}

private final class NoCheckoutRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
