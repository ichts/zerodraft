import Foundation
import Testing
@testable import WriteItDown

private final class CheckoutStubHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var responder: (@Sendable (URLRequest) -> (Int, [String: String], Data))?

    func set(_ responder: @escaping @Sendable (URLRequest) -> (Int, [String: String], Data)) {
        lock.lock()
        defer { lock.unlock() }
        requests.removeAll()
        self.responder = responder
    }

    func record(_ request: URLRequest) -> (Int, [String: String], Data) {
        lock.lock()
        requests.append(request)
        let responder = self.responder
        lock.unlock()
        guard let responder else { return (503, [:], Data()) }
        return responder(request)
    }

    var recorded: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class CheckoutHTTPStub: URLProtocol, @unchecked Sendable {
    static let handler = CheckoutStubHandler()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, headers, data) = Self.handler.record(request)
        var fields = headers
        fields["Content-Type"] = fields["Content-Type"] ?? "application/json"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: fields)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func checkoutSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CheckoutHTTPStub.self]
    return URLSession(configuration: configuration)
}

private func checkoutClient() -> HostedCheckoutClient {
    HostedCheckoutClient(baseURL: URL(string: "https://license.invalid"), session: checkoutSession())
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

@Suite(.serialized)
struct CheckoutClientTests {
    @Test func successPostsToTheServiceAndReturnsTheHostedURL() async throws {
        CheckoutHTTPStub.handler.set { _ in
            (200, [:], Data(#"{"url":"https://checkout.stripe.com/c/pay/test"}"#.utf8))
        }
        let client = checkoutClient()
        #expect(client.isConfigured)
        let url = try await client.createCheckoutSession()
        #expect(url.absoluteString == "https://checkout.stripe.com/c/pay/test")

        let request = try #require(CheckoutHTTPStub.handler.recorded.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://license.invalid/api/v1/checkout")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try requestBody(request).isEmpty)
    }

    @Test func errorStatusIsUnavailable() async {
        CheckoutHTTPStub.handler.set { _ in (503, [:], Data(#"{"error":"checkout_not_configured"}"#.utf8)) }
        await #expect(throws: CheckoutError.unavailable) {
            try await checkoutClient().createCheckoutSession()
        }
    }

    @Test func nonStripeDestinationIsRejected() async {
        CheckoutHTTPStub.handler.set { _ in (200, [:], Data(#"{"url":"https://example.com/c/pay/test"}"#.utf8)) }
        await #expect(throws: CheckoutError.invalidDestination) {
            try await checkoutClient().createCheckoutSession()
        }
    }

    @Test func malformedResponseIsRejected() async {
        CheckoutHTTPStub.handler.set { _ in (200, [:], Data("not json".utf8)) }
        await #expect(throws: CheckoutError.invalidDestination) {
            try await checkoutClient().createCheckoutSession()
        }
    }

    @Test func redirectsAreNotFollowed() async {
        CheckoutHTTPStub.handler.set { _ in
            (302, ["Location": "https://evil.example/pay"], Data())
        }
        await #expect(throws: CheckoutError.unavailable) {
            try await checkoutClient().createCheckoutSession()
        }
        #expect(CheckoutHTTPStub.handler.recorded.count == 1)
    }

    @Test @MainActor func appStateOpensHostedCheckoutAndUsesFallbackOnlyOnError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var opened: [URL] = []
        let success = MockCheckoutClient(result: .success(URL(string: "https://checkout.stripe.com/c/pay/test")!))
        let state = AppState(settingsStore: SettingsStore(configDirectory: root),
                             licenseClient: MockLicenseClient(), checkoutClient: success,
                             installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock", openExternalURL: { opened.append($0) })
        await state.openCheckout()
        #expect(opened.map(\.absoluteString) == ["https://checkout.stripe.com/c/pay/test"])
        #expect(success.calls == 1)
        #expect(!state.checkoutInFlight)

        let failing = MockCheckoutClient(result: .failure(CheckoutError.unavailable))
        let fallbackRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fallbackRoot) }
        opened = []
        let fallbackState = AppState(settingsStore: SettingsStore(configDirectory: fallbackRoot),
                                     licenseClient: MockLicenseClient(), checkoutClient: failing,
                                     installIDStore: InstallIDStore(configDirectory: fallbackRoot),
                                     productID: "prod_mock", openExternalURL: { opened.append($0) })
        await fallbackState.openCheckout()
        #expect(opened.map(\.absoluteString) == AppState.checkoutURL.map { [$0.absoluteString] })
        #expect(failing.calls == 1)
        #expect(!fallbackState.checkoutInFlight)
    }

    @Test @MainActor func checkoutAvailabilityRequiresTheServiceAndTheFallback() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configured = AppState(settingsStore: SettingsStore(configDirectory: root),
                                  licenseClient: MockLicenseClient(), checkoutClient: MockCheckoutClient(),
                                  installIDStore: InstallIDStore(configDirectory: root),
                                  productID: "prod_mock")
        #expect(configured.checkoutAvailable == (AppState.checkoutURL != nil))
        let unconfigured = AppState(settingsStore: SettingsStore(configDirectory: root),
                                    licenseClient: MockLicenseClient(),
                                    checkoutClient: HostedCheckoutClient(baseURL: nil),
                                    installIDStore: InstallIDStore(configDirectory: root),
                                    productID: "prod_mock")
        #expect(!unconfigured.checkoutAvailable)
    }
}
