import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct LivePolarAcceptanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WID_POLAR_E2E"] == "1"))
    func sandboxActivationAndWrongBenefitRefusal() async throws {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/writeitdown/polar-sandbox.env")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        let values = Dictionary(uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        let organization = try #require(values["POLAR_SANDBOX_ORGANIZATION_ID"])
        let benefit = try #require(values["POLAR_SANDBOX_BENEFIT_ID"])
        let key = try #require(values["POLAR_SANDBOX_LICENSE_KEY"])
        let client = PolarLicenseClient(organizationID: organization, benefitID: benefit,
                                        baseURL: URL(string: "https://sandbox-api.polar.sh/v1")!)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let accepted = AppState(settingsStore: SettingsStore(configDirectory: root.appendingPathComponent("accepted")),
                                licenseClient: client,
                                installIDStore: InstallIDStore(configDirectory: root.appendingPathComponent("accepted")),
                                productID: benefit, organizationID: organization)
        await accepted.activateLicense(key: key)
        #expect(accepted.hasFullAccess, "Sandbox key must show License active through the real Polar client")
        #expect(accepted.licenseActivationError == nil)

        let rejected = AppState(settingsStore: SettingsStore(configDirectory: root.appendingPathComponent("rejected")),
                                licenseClient: client,
                                installIDStore: InstallIDStore(configDirectory: root.appendingPathComponent("rejected")),
                                productID: "00000000-0000-4000-8000-000000000000", organizationID: organization)
        await rejected.activateLicense(key: key)
        #expect(!rejected.hasFullAccess)
        #expect(rejected.licenseActivationError == .wrongProduct)
    }
}
