import Foundation
import Testing
@testable import WriteItDown

private final class LockedResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    func set(_ value: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        handler = value
    }
    func get() -> (@Sendable (URLRequest) throws -> (Int, Data))? {
        lock.lock(); defer { lock.unlock() }
        return handler
    }
}

private final class StubLicenseProtocol: URLProtocol, @unchecked Sendable {
    static let response = LockedResponse()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.response.get()!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct PolarLicenseClientTests {
    private func client() -> PolarLicenseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLicenseProtocol.self]
        return PolarLicenseClient(organizationID: "org", benefitID: "benefit", session: URLSession(configuration: config),
                                  baseURL: URL(string: "https://sandbox-api.polar.sh/v1")!)
    }

    private func body(_ request: URLRequest) throws -> [String: String] {
        let stream = try #require(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let length = stream.read(&bytes, maxLength: bytes.count)
        return try #require(JSONSerialization.jsonObject(with: Data(bytes.prefix(length))) as? [String: String])
    }

    private static func activation(benefit: String = "benefit") -> Data {
        Data(#"{"id":"instance","license_key_id":"key-id","label":"Mac","created_at":"2026-01-01T00:00:00Z","license_key":{"organization_id":"org","benefit_id":"\#(benefit)","status":"granted"}}"#.utf8)
    }

    @Test func validKeyActivatesWithoutCredentials() async throws {
        StubLicenseProtocol.response.set { request in
            #expect(request.url?.absoluteString == "https://sandbox-api.polar.sh/v1/customer-portal/license-keys/activate")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let json = try body(request)
            #expect(json == ["key": "KEY", "organization_id": "org", "label": "Mac"])
            return (200, Self.activation())
        }
        let result = try await client().activate(licenseKey: "KEY", instanceName: "Mac")
        #expect(result.instanceID == "instance")
        #expect(result.productID == "benefit")
    }

    @MainActor
    @Test func wrongBenefitIsRejectedAndRemoteSlotFreed() async throws {
        StubLicenseProtocol.response.set { request in
            if request.url?.path.hasSuffix("/deactivate") == true {
                let json = try body(request)
                #expect(json == ["key": "KEY", "organization_id": "org", "activation_id": "instance"])
                return (204, Data())
            }
            return (200, Self.activation(benefit: "other"))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), licenseClient: client(),
                             installIDStore: InstallIDStore(configDirectory: root), productID: "benefit", organizationID: "org")
        await state.activateLicense(key: "KEY")
        #expect(state.licenseActivationError == .wrongProduct)
        #expect(!state.hasFullAccess)
    }

    @Test func thirdDeviceAndRevokedKeyAreDenied() async throws {
        StubLicenseProtocol.response.set { _ in (403, Data(#"{"error":"NotPermitted","detail":"Activation limit reached"}"#.utf8)) }
        do {
            _ = try await client().activate(licenseKey: "KEY", instanceName: "third Mac")
            Issue.record("Third activation should fail")
        } catch let error as LicenseActivationError { #expect(error == .activationLimitReached) }
        StubLicenseProtocol.response.set { _ in (403, Data(#"{"error":"NotPermitted","detail":"License key revoked or refunded"}"#.utf8)) }
        do {
            _ = try await client().activate(licenseKey: "KEY", instanceName: "Mac")
            Issue.record("Revoked activation should fail")
        } catch let error as LicenseActivationError { #expect(error == .invalidKey) }
    }

    @Test func validationIsScopedToActivationAndBenefit() async throws {
        StubLicenseProtocol.response.set { request in
            let json = try body(request)
            #expect(json == ["key": "KEY", "organization_id": "org", "activation_id": "instance", "benefit_id": "benefit"])
            return (200, Data(#"{"organization_id":"org","benefit_id":"other","status":"granted","activation":{"id":"instance"}}"#.utf8))
        }
        #expect(try await client().validate(licenseKey: "KEY", instanceID: "instance") == false)
        StubLicenseProtocol.response.set { _ in (404, Data(#"{"error":"ResourceNotFound","detail":"Key revoked"}"#.utf8)) }
        #expect(try await client().validate(licenseKey: "KEY", instanceID: "instance") == false)
    }

    @Test func networkFailureRemainsRetryable() async throws {
        StubLicenseProtocol.response.set { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client().validate(licenseKey: "KEY", instanceID: "instance")
            Issue.record("Offline validation should throw")
        } catch let error as LicenseValidationError { #expect(error == .networkFailure) }
    }
}
