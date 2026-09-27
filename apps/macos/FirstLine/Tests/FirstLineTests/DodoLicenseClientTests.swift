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
            let responder = Self.response.get()
            let (status, data) = try responder!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct DodoLicenseClientTests {
    private func client() -> DodoLicenseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLicenseProtocol.self]
        return DodoLicenseClient(session: URLSession(configuration: config), baseURL: URL(string: "https://test.dodopayments.com")!)
    }

    @Test func activateBuildsPublicRequestWithoutAuthHeader() async throws {
        StubLicenseProtocol.response.set { request in
            #expect(request.url?.absoluteString == "https://test.dodopayments.com/licenses/activate")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let stream = try #require(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let length = stream.read(&bytes, maxLength: bytes.count)
            let body = Data(bytes.prefix(length))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json == ["license_key": "KEY", "name": "writeitdown Mac abcd1234"])
            return (200, Data(#"{"id":"lki_123","license_key_id":"lic_123","name":"writeitdown Mac abcd1234","business_id":"biz","created_at":"2024-01-01T00:00:00Z","product":{"product_id":"prod","name":"Write It Down"}}"#.utf8))
        }
        let result = try await client().activate(licenseKey: "KEY", instanceName: "writeitdown Mac abcd1234")
        #expect(result.instanceID == "lki_123")
        #expect(result.productName == "Write It Down")
        #expect(result.productID == "prod")
    }

    @MainActor
    @Test(arguments: ["prod", "other", ""])
    func productIdentityControlsEntitlement(responseProductID: String) async throws {
        StubLicenseProtocol.response.set { request in
            if request.url?.path == "/licenses/deactivate" {
                #expect(responseProductID != "prod")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                let stream = try #require(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let length = stream.read(&bytes, maxLength: bytes.count)
                let json = try #require(JSONSerialization.jsonObject(with: Data(bytes.prefix(length))) as? [String: String])
                #expect(json == ["license_key": "KEY", "license_key_instance_id": "lki_1"])
                return (200, Data())
            }
            #expect(request.url?.path == "/licenses/activate")
            let product = responseProductID.isEmpty ? "null" : #"{"product_id":"\#(responseProductID)","name":"Test"}"#
            return (200, Data(#"{"id":"lki_1","license_key_id":"lic_1","name":"Mac","business_id":"biz","created_at":"2024-01-01T00:00:00Z","product":\#(product)}"#.utf8))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        let state = AppState(settingsStore: store, licenseClient: client(),
                             installIDStore: InstallIDStore(configDirectory: root), productID: "prod")
        state.settings.trialSessionsUsed = AppState.trialSessionLimit
        await state.activateLicense(key: "KEY")
        state.startSession()
        if responseProductID == "prod" {
            #expect(state.settings.licenseProductID == "prod")
            #expect(state.selectedSurface == .session)
            #expect(try store.load().licenseProductID == "prod")
        } else {
            #expect(state.licenseActivationError == .wrongProduct)
            #expect(state.selectedSurface == .upgrade)
            #expect(state.settings.licenseProductID == nil)
        }
    }

    @Test(arguments: [("LICENSE_KEY_LIMIT_REACHED", LicenseActivationError.activationLimitReached), ("LICENSE_KEY_NOT_FOUND", .invalidKey), ("INACTIVE_LICENSE_KEY", .invalidKey)])
    func errorCodesMapToLicenseActivationError(code: String, expected: LicenseActivationError) async {
        StubLicenseProtocol.response.set { _ in (422, Data("{\"code\":\"\(code)\",\"message\":\"No\"}".utf8)) }
        do {
            _ = try await client().activate(licenseKey: "KEY", instanceName: "Mac")
            Issue.record("Expected activation failure")
        } catch let error as LicenseActivationError {
            #expect(error == expected)
        } catch { Issue.record("Wrong error: \(error)") }
    }
}
