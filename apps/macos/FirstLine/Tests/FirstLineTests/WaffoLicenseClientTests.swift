import AppKit
import CryptoKit
import Foundation
import Testing
@testable import WriteItDown

private final class StubHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    func set(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    func respond(_ request: URLRequest) throws -> (Int, Data) {
        lock.lock()
        let callback = handler
        lock.unlock()
        guard let callback else { throw URLError(.notConnectedToInternet) }
        return try callback(request)
    }
}

private final class LicenseHTTPStub: URLProtocol, @unchecked Sendable {
    static let handler = StubHandler()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

struct SignedLicenseFixture: Sendable {
    let key = Curve25519.Signing.PrivateKey()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let product = "test-product"
    let install = "B524775D-398B-4804-A465-E9B65062EC80"

    func token(product: String? = nil, install: String? = nil, issued: Int64? = nil,
               expires: Int64? = nil, activation: String = "activation-test", license: String = "license-test") throws -> String {
        let start = issued ?? Int64(now.timeIntervalSince1970)
        let claims = LicenseClaims(licenseId: license, activationId: activation, installLabel: install ?? self.install,
                                   product: product ?? self.product, issuedAt: start,
                                   expiresAt: expires ?? start + LicenseTokenVerifier.lifetime)
        let payload = Self.encode(try JSONEncoder().encode(claims))
        return payload + "." + Self.encode(try key.signature(for: Data(payload.utf8)))
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func verifier() throws -> LicenseTokenVerifier {
        try LicenseTokenVerifier(publicKey: key.publicKey.rawRepresentation, productID: product)
    }

    func client() -> WaffoLicenseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LicenseHTTPStub.self]
        return WaffoLicenseClient(baseURL: URL(string: "https://license.invalid"), productID: product,
                                  publicKey: key.publicKey.rawRepresentation, session: URLSession(configuration: configuration),
                                  clock: { now })
    }
}

struct LicenseTokenVerifierTests {
    @Test func signatureAndBoundClaimsAreRequired() throws {
        let f = SignedLicenseFixture()
        let verifier = try f.verifier()
        #expect(try verifier.verify(f.token(), installLabel: f.install, now: f.now).product == f.product)
        let badTokens = try [
            f.token(product: "other"), f.token(install: "another-device"), f.token(activation: ""), f.token(license: ""),
            f.token(issued: Int64(f.now.timeIntervalSince1970) + 61),
            f.token(expires: Int64(f.now.timeIntervalSince1970) + LicenseTokenVerifier.lifetime + 1),
            f.token(expires: Int64(f.now.timeIntervalSince1970)),
            f.token(issued: -1, expires: Int64.max),
            SignedLicenseFixture().token(), "", "payload.signature.extra", "e30.AA"
        ]
        for token in badTokens {
            #expect(throws: LicenseActivationError.invalidToken) {
                try verifier.verify(token, installLabel: f.install, now: f.now)
            }
        }
        let original = try f.token().split(separator: ".")
        let tampered = SignedLicenseFixture.encode(Data("{\"product\":\"other\"}".utf8)) + "." + original[1]
        #expect(throws: LicenseActivationError.invalidToken) {
            try verifier.verify(tampered, installLabel: f.install, now: f.now)
        }
    }

    @Test func sevenDaysAndClockRollbackAreHardBoundaries() throws {
        let f = SignedLicenseFixture()
        let verifier = try f.verifier()
        let token = try f.token()
        #expect(throws: Never.self) {
            try verifier.verify(token, installLabel: f.install, now: f.now.addingTimeInterval(604_799))
        }
        for offset in [604_800.0, 604_801.0, -61.0] {
            #expect(throws: LicenseActivationError.invalidToken) {
                try verifier.verify(token, installLabel: f.install, now: f.now.addingTimeInterval(offset))
            }
        }
    }
}

@Suite(.serialized)
@MainActor
struct WaffoLicenseClientTests {
    nonisolated private static func body(_ request: URLRequest) throws -> [String: String] {
        if let data = request.httpBody { return try JSONDecoder().decode([String: String].self, from: data) }
        let stream = try #require(request.httpBodyStream)
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
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    nonisolated private static func reply(_ token: String) throws -> (Int, Data) {
        (200, try JSONEncoder().encode(["token": token]))
    }

    @Test func requestContractAndSignedResponse() async throws {
        let f = SignedLicenseFixture()
        let token = try f.token()
        LicenseHTTPStub.handler.set { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try Self.body(request)
            switch request.url?.path {
            case "/api/v1/licenses/activate":
                #expect(body == ["orderId": " test-order-123 ", "installLabel": f.install, "platform": "macos"])
                return try Self.reply(token)
            case "/api/v1/licenses/validate":
                #expect(body == ["token": token])
                return try Self.reply(token)
            case "/api/v1/licenses/deactivate":
                #expect(body == ["token": token])
                return (200, Data("{}".utf8))
            default: throw URLError(.badURL)
            }
        }
        let client = f.client()
        let activated = try await client.activate(licenseKey: " test-order-123 ", instanceName: f.install)
        #expect(activated.instanceID == "activation-test")
        #expect(activated.token == token)
        #expect(try await client.validate(token: token) == token)
        try await client.deactivate(token: token)
    }

    @Test func serviceErrorsAreNotConfusedWithTransportFailures() async throws {
        let f = SignedLicenseFixture()
        for (code, detail, expected) in [
            (403, "license unavailable", LicenseActivationError.invalidKey),
            (409, "device limit reached\n", .activationLimitReached),
            (409, "installation platform mismatch", .unexpected(statusCode: 409)),
            (500, "storage error", .networkFailure), (429, "", .networkFailure),
            (302, "", .unexpected(statusCode: 302))
        ] {
            LicenseHTTPStub.handler.set { _ in (code, Data(detail.utf8)) }
            await #expect(throws: expected) {
                try await f.client().activate(licenseKey: "test-order-123", instanceName: f.install)
            }
        }
        LicenseHTTPStub.handler.set { _ in (403, Data()) }
        #expect(try await f.client().validate(token: "cached") == nil)
        LicenseHTTPStub.handler.set { _ in (404, Data()) }
        await #expect(throws: LicenseValidationError.unexpected(statusCode: 404)) {
            try await f.client().validate(token: "cached")
        }
        LicenseHTTPStub.handler.set { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: LicenseValidationError.networkFailure) {
            try await f.client().validate(token: "cached")
        }
    }

    @Test func activationSendsTheTrimmedCredentialWithoutRewritingItsBytes() async throws {
        let f = SignedLicenseFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // Surrounding paste noise is dropped; internal bytes (a decomposed accent, an inner space) stay verbatim.
        let canonical = "order-cafe\u{0301} 42"
        let state = makeState(f, root: root, clock: { f.now })
        LicenseHTTPStub.handler.set { request in
            let body = try Self.body(request)
            #expect(body["orderId"]?.utf8.elementsEqual(canonical.utf8) == true)
            let label = try #require(body["installLabel"])
            return try Self.reply(f.token(install: label))
        }
        await state.activateLicense(key: " \t\(canonical)\r\n")
        #expect(state.licenseActivationError == nil)
        #expect(state.settings.licenseKey?.utf8.elementsEqual(canonical.utf8) == true)
        #expect(state.hasFullAccess)
    }

    @Test func activationRefusesInvalidSignatureProductDeviceAndPayload() async throws {
        let f = SignedLicenseFixture()
        for token in try [SignedLicenseFixture().token(), f.token(product: "other"), f.token(install: "other"), "bad"] {
            LicenseHTTPStub.handler.set { _ in try Self.reply(token) }
            await #expect(throws: LicenseActivationError.invalidToken) {
                try await f.client().activate(licenseKey: "test-order-123", instanceName: f.install)
            }
        }
        LicenseHTTPStub.handler.set { _ in (200, Data("{}".utf8)) }
        await #expect(throws: LicenseActivationError.invalidToken) {
            try await f.client().activate(licenseKey: "test-order-123", instanceName: f.install)
        }
    }

    @Test func missingOrUnsafeConfigurationCannotContactServer() async throws {
        let f = SignedLicenseFixture()
        #expect(!WaffoLicenseClient.allowedURL(URL(string: "http://license.example.com")))
        #expect(!WaffoLicenseClient.allowedURL(URL(string: "https://user:secret@example.com")))
        #expect(!WaffoLicenseClient.allowedURL(URL(string: "https://example.com?token=secret")))
        #expect(WaffoLicenseClient.allowedURL(URL(string: "http://127.0.0.1:8060")))
        for client in [WaffoLicenseClient(baseURL: nil, productID: f.product, publicKey: f.key.publicKey.rawRepresentation),
                       WaffoLicenseClient(baseURL: URL(string: "https://license.invalid"), productID: f.product, publicKey: Data())] {
            #expect(!client.isConfigured)
            await #expect(throws: LicenseActivationError.productNotConfigured) {
                try await client.activate(licenseKey: "test-order-123", instanceName: f.install)
            }
        }
    }

    private func makeState(_ f: SignedLicenseFixture, root: URL, clock: @escaping () -> Date) -> AppState {
        AppState(settingsStore: SettingsStore(configDirectory: root), licenseClient: f.client(),
                 installIDStore: InstallIDStore(configDirectory: root), clock: clock, productID: f.product)
    }

    private func input(_ state: AppState) throws {
        func editor(_ view: NSView) -> AppendOnlyTextView? {
            (view as? AppendOnlyTextView) ?? view.subviews.lazy.compactMap(editor).first
        }
        let field = try #require(editor(SessionViewController(appState: state).view))
        field.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.sessionEngine.text == "draft")
    }

    private func acceptActivations(_ f: SignedLicenseFixture) {
        LicenseHTTPStub.handler.set { request in
            let body = try Self.body(request)
            let label = try #require(body["installLabel"])
            #expect(UUID(uuidString: label) != nil)
            return try Self.reply(f.token(install: label))
        }
    }

    @Test func activationRequiredAfterTrialAndAfterRefundOrExpiry() async throws {
        let f = SignedLicenseFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var now = f.now
        var exhausted = AppSettings.defaultValue
        exhausted.trialSessionsUsed = 3
        try SettingsStore(configDirectory: root).save(exhausted)
        let state = makeState(f, root: root, clock: { now })
        #expect(state.selectedSurface == .upgrade)
        state.startSession()
        #expect(state.selectedSurface == .upgrade)
        acceptActivations(f)
        await state.activateLicense(key: "test-order-123")
        #expect(state.hasFullAccess)
        state.startSession()
        try input(state)
        state.abandonSession()

        LicenseHTTPStub.handler.set { _ in throw URLError(.notConnectedToInternet) }
        // A restart with a stored token opens on the picker: the in-flight revalidation is
        // silent and never holds access (the launch flash regression).
        let offline = makeState(f, root: root, clock: { now })
        #expect(offline.hasFullAccess)
        #expect(offline.selectedSurface == .home)
        await offline.validateLicenseIfNeeded()
        #expect(offline.hasFullAccess)
        #expect(offline.selectedSurface == .home)
        now = f.now.addingTimeInterval(604_799)
        #expect(offline.hasFullAccess)
        now = f.now.addingTimeInterval(604_800)
        #expect(!offline.hasFullAccess)
        offline.startSession()
        #expect(offline.selectedSurface == .upgrade)
        now = f.now.addingTimeInterval(-61)
        #expect(!offline.hasFullAccess)
        now = f.now
        LicenseHTTPStub.handler.set { _ in (403, Data("license unavailable".utf8)) }
        #expect(await offline.validateLicenseIfNeeded() == false)
        #expect(offline.settings.licenseStatus == .revoked)
        #expect(!offline.hasFullAccess)
        offline.startSession()
        #expect(offline.selectedSurface == .upgrade)
        #expect(!makeState(f, root: root, clock: { f.now }).hasFullAccess)
    }

    @Test func revocationBeforeFirstInputClosesAnAlreadyOpenedRoom() async throws {
        let f = SignedLicenseFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(f, root: root, clock: { f.now })
        acceptActivations(f)
        await state.activateLicense(key: "test-order-123")
        state.startSession()
        #expect(state.selectedSurface == .session)
        LicenseHTTPStub.handler.set { _ in (403, Data()) }
        await state.validateLicenseIfNeeded()
        #expect(!state.prepareSessionInput())
        #expect(state.selectedSurface == .upgrade)
        #expect(state.sessionEngine.text.isEmpty)
    }

    @Test func invalidRenewalCannotUseGraceAndValidRenewalPersists() async throws {
        let f = SignedLicenseFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(f, root: root, clock: { f.now })
        acceptActivations(f)
        await state.activateLicense(key: "test-order-123")
        let renewed = try f.token(install: state.installLabel, issued: Int64(f.now.timeIntervalSince1970) - 1)
        LicenseHTTPStub.handler.set { _ in try Self.reply(renewed) }
        #expect(await state.validateLicenseIfNeeded() == true)
        #expect(try SettingsStore(configDirectory: root).load().licenseToken == renewed)
        for token in try [SignedLicenseFixture().token(install: state.installLabel),
                          f.token(install: state.installLabel, activation: "other-activation"),
                          f.token(install: "other-device")] {
            state.settings.licenseStatus = .active
            LicenseHTTPStub.handler.set { _ in try Self.reply(token) }
            #expect(await state.validateLicenseIfNeeded() == false)
            #expect(state.settings.licenseStatus == .invalid)
            #expect(!state.hasFullAccess)
        }
        LicenseHTTPStub.handler.set { request in
            if request.url?.path == "/api/v1/licenses/validate" { return (403, Data()) }
            let label = try #require(Self.body(request)["installLabel"])
            return try Self.reply(f.token(install: label))
        }
        await state.activateLicense(key: "test-order-123")
        #expect(state.hasFullAccess)
        #expect(state.licenseActivationError == nil)
    }

    @Test func legacyFlagsAndTamperedCacheDoNotAuthorizeWriting() async throws {
        let f = SignedLicenseFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        let state = makeState(f, root: root, clock: { f.now })
        acceptActivations(f)
        await state.activateLicense(key: "test-order-123")
        let signed = state.settings
        LicenseHTTPStub.handler.set { _ in throw URLError(.notConnectedToInternet) }
        for mutation in 0..<5 {
            var cached = signed
            switch mutation {
            case 0: cached.licenseToken = nil
            case 1: cached.licenseToken = "forged"
            case 2: cached.licenseKey = " \n"
            case 3: cached.licenseInstanceID = "other"
            default: cached.licenseToken = try f.token(install: "copied-from-another-Mac")
            }
            try store.save(cached)
            let restarted = makeState(f, root: root, clock: { f.now })
            await restarted.validateLicenseIfNeeded()
            #expect(!restarted.hasFullAccess)
            restarted.startSession()
            #expect(restarted.selectedSurface == .upgrade)
        }
    }
}
