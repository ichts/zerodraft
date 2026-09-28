import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct LiveDodoAcceptanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WID_DODO_E2E"] == "1"))
    func testModeActivationAndWrongProductRefusal() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = home.appendingPathComponent(".config/writeitdown/dodo.env")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        let values = Dictionary(uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        let productID = try #require(values["DODO_TEST_PRODUCT_ID"])
        let key = try #require(values["DODO_TEST_LICENSE_KEY"])
        let client = DodoLicenseClient(baseURL: URL(string: "https://test.dodopayments.com")!)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let accepted = AppState(
            settingsStore: SettingsStore(configDirectory: root.appendingPathComponent("accepted")),
            licenseClient: client,
            installIDStore: InstallIDStore(configDirectory: root.appendingPathComponent("accepted")),
            productID: productID
        )
        await accepted.activateLicense(key: key)
        #expect(accepted.hasFullAccess, "The test key must show License active through the real Dodo client")
        #expect(accepted.licenseActivationError == nil)

        let rejected = AppState(
            settingsStore: SettingsStore(configDirectory: root.appendingPathComponent("rejected")),
            licenseClient: client,
            installIDStore: InstallIDStore(configDirectory: root.appendingPathComponent("rejected")),
            productID: "pdt_wrong_product"
        )
        await rejected.activateLicense(key: key)
        #expect(!rejected.hasFullAccess)
        #expect(rejected.licenseActivationError == .wrongProduct)
    }
}
