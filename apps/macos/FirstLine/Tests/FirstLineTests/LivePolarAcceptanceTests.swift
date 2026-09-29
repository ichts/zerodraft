import Foundation
import Testing
@testable import WriteItDown

private struct SandboxEnv {
    let organization: String
    let benefit: String
    let values: [String: String]

    init() throws {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/writeitdown/polar-sandbox.env")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        values = Dictionary(uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        organization = try #require(values["POLAR_SANDBOX_ORGANIZATION_ID"])
        benefit = try #require(values["POLAR_SANDBOX_BENEFIT_ID"])
    }

    var client: PolarLicenseClient {
        PolarLicenseClient(organizationID: organization, benefitID: benefit,
                           baseURL: URL(string: "https://sandbox-api.polar.sh/v1")!)
    }

    @MainActor func state(dir: URL, client: LicenseClient? = nil, benefit override: String? = nil) -> AppState {
        AppState(settingsStore: SettingsStore(configDirectory: dir), licenseClient: client ?? self.client,
                 installIDStore: InstallIDStore(configDirectory: dir),
                 productID: override ?? benefit, organizationID: organization)
    }
}

private let liveEnabled = ProcessInfo.processInfo.environment["WID_POLAR_E2E"] == "1"
private let livePhase = ProcessInfo.processInfo.environment["WID_POLAR_PHASE"]

/// Polar rate limits the public license endpoints hard (429 with Retry-After), so live steps are paced.
private func pace() async throws { try await Task.sleep(for: .seconds(20)) }

/// Opt-in real Polar sandbox proof. Secrets are read from ~/.config/writeitdown/polar-sandbox.env only.
@MainActor
struct LivePolarAcceptanceTests {
    private static let revokeDir = URL(fileURLWithPath: "/var/tmp/wid-polar-revoke-state")

    @Test(.enabled(if: liveEnabled))
    func activationWrongProductThirdDeviceAndOfflineGrace() async throws {
        let env = try SandboxEnv()
        let key = try #require(env.values["POLAR_SANDBOX_LICENSE_KEY"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let accepted = env.state(dir: root.appendingPathComponent("accepted"))
        await accepted.activateLicense(key: key)
        try await pace()
        #expect(accepted.hasFullAccess, "Sandbox key must show License active through the real Polar client")
        #expect(accepted.licenseActivationError == nil)
        #expect(await accepted.validateLicenseIfNeeded() == true)
        try await pace()

        let rejected = env.state(dir: root.appendingPathComponent("rejected"),
                                 benefit: "00000000-0000-4000-8000-000000000000")
        await rejected.activateLicense(key: key)
        try await pace()
        #expect(!rejected.hasFullAccess)
        #expect(rejected.licenseActivationError == .wrongProduct)

        let second = try await env.client.activate(licenseKey: key, instanceName: "second device")
        try await pace()
        await #expect(throws: LicenseActivationError.activationLimitReached) {
            _ = try await env.client.activate(licenseKey: key, instanceName: "third device")
        }
        try await pace()
        try await env.client.deactivate(licenseKey: key, instanceID: second.instanceID)
        try await pace()
        try await env.client.deactivate(licenseKey: key, instanceID: try #require(accepted.settings.licenseInstanceID))

        let offlineClient = PolarLicenseClient(organizationID: env.organization, benefitID: env.benefit,
                                               baseURL: URL(string: "http://127.0.0.1:9/v1")!)
        let offline = env.state(dir: root.appendingPathComponent("accepted"), client: offlineClient)
        #expect(await offline.validateLicenseIfNeeded() == nil)
        #expect(offline.hasFullAccess, "Inside the offline grace window an unreachable server keeps the license active")
    }

    /// Phase 1: activate the second sandbox key and persist state. Then revoke it in the Polar dashboard.
    @Test(.enabled(if: liveEnabled && livePhase == "activate-revoke-key"))
    func activateKeyToBeRevoked() async throws {
        let env = try SandboxEnv()
        let key = try #require(env.values["POLAR_SANDBOX_REVOKE_LICENSE_KEY"])
        try? FileManager.default.removeItem(at: Self.revokeDir)
        let state = env.state(dir: Self.revokeDir)
        await state.activateLicense(key: key)
        #expect(state.hasFullAccess)
    }

    /// Phase 2: after revocation the same persisted install must be refused on validation.
    @Test(.enabled(if: liveEnabled && livePhase == "verify-revoked"))
    func revokedKeyIsRefused() async throws {
        let env = try SandboxEnv()
        let state = env.state(dir: Self.revokeDir)
        #expect(await state.validateLicenseIfNeeded() == false)
        #expect(!state.hasFullAccess)
    }
}
