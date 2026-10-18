import AppKit
import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct LicenseEntitlementTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    private func startFromHome(_ state: AppState) throws {
        let home = HomeViewController(appState: state)
        let button = try #require(descendants(home.view, of: NSButton.self).first { $0.tag == 60 })
        button.performClick(nil)
    }

    private func typeInRoom(_ state: AppState) throws {
        let room = SessionViewController(appState: state)
        let input = try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
        input.insertText("another draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.sessionEngine.text == "another draft")
    }

    private func writeFixture(at root: URL, fields: [String: Any]) throws -> SettingsStore {
        var fixture: [String: Any] = [
            "theme": "dark", "defaultDuration": 300, "reducedMotion": "always",
            "trialSessionsUsed": AppState.trialSessionLimit
        ]
        fixture.merge(fields) { _, new in new }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: fixture).write(to: root.appendingPathComponent("settings.json"))
        return SettingsStore(configDirectory: root)
    }

    private func makeState(at root: URL, client: MockLicenseClient = MockLicenseClient()) -> AppState {
        AppState(settingsStore: SettingsStore(configDirectory: root), licenseClient: client,
                 installIDStore: InstallIDStore(configDirectory: root), clock: { now }, productID: "prod_mock")
    }

    @Test(arguments: [false, true])
    func legacyFlagCannotUnlockExhaustedTrialAcrossRestart(unlocked: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try writeFixture(at: root, fields: ["hasUnlockedFullAccess": unlocked])
        for _ in 0..<2 {
            let mock = MockLicenseClient()
            let state = makeState(at: root, client: mock)
            #expect(state.settings.licenseStatus == .trial)
            #expect(state.settings.theme == .dark)
            #expect(state.settings.reducedMotion == .always)
            #expect(!state.hasFullAccess)
            #expect(!state.licenseValidationInFlight)
            await state.validateLicenseIfNeeded()
            #expect(await mock.lastValidatedToken == nil)
            let home = HomeViewController(appState: state)
            #expect(descendants(home.view, of: NSTextField.self).contains {
                $0.stringValue == "Mac trial: 3 of 3 sessions used."
            })
            try startFromHome(state)
            #expect(state.selectedSurface == .upgrade)
            #expect(state.sessionEngine.phase == .idle)
            #expect(state.isTrialExhausted)
            #expect(try store.load().trialSessionsUsed == AppState.trialSessionLimit)
            #expect(try store.load().licenseStatus == .trial)
        }
    }

    @Test(arguments: [nil, "", " \t\n"] as [String?])
    func activeWithoutKeyCannotUnlockEvenWithCachedMetadata(key: String?) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try writeFixture(at: root, fields: [
            "licenseStatus": "active", "licenseKey": key as Any? ?? NSNull(),
            "licenseInstanceID": "lki_existing", "licenseProductID": "prod_mock",
            "licenseLastValidatedAt": now.timeIntervalSinceReferenceDate
        ])
        let mock = MockLicenseClient()
        let state = makeState(at: root, client: mock)
        #expect(state.settings.licenseStatus == .trial)
        #expect(!state.hasFullAccess)
        #expect(!state.licenseValidationInFlight)
        await state.validateLicenseIfNeeded()
        #expect(await mock.lastValidatedToken == nil)
        try startFromHome(state)
        #expect(state.selectedSurface == .upgrade)
        #expect(try store.load().licenseStatus == .trial)
        #expect(!makeState(at: root).hasFullAccess)

        // Mutable in-memory settings must not bypass the entitlement check either.
        state.settings.licenseStatus = .active
        #expect(!state.hasFullAccess)
        await state.validateLicenseIfNeeded()
        #expect(await mock.lastValidatedToken == nil)
        state.newPiece()
        #expect(state.selectedSurface == .upgrade)
        #expect(state.sessionEngine.phase == .idle)
    }

    @Test
    func legacyFlagDoesNotHideTrialConsumption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try writeFixture(at: root, fields: ["hasUnlockedFullAccess": true, "trialSessionsUsed": 2])
        let state = makeState(at: root)
        try startFromHome(state)
        #expect(state.selectedSurface == .session)
        #expect(state.settings.trialSessionsUsed == 2)
        try typeInRoom(state)
        #expect(state.settings.trialSessionsUsed == 3)
        #expect(try store.load().trialSessionsUsed == 3)
        state.newPiece()
        #expect(state.selectedSurface == .upgrade)
        let restarted = makeState(at: root)
        try startFromHome(restarted)
        #expect(restarted.selectedSurface == .upgrade)
    }

    @Test(arguments: [false, true])
    func keyedActivationAndRestartPreserveAccess(offline: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try writeFixture(at: root, fields: ["hasUnlockedFullAccess": true])
        let state = makeState(at: root)
        try startFromHome(state)
        #expect(state.selectedSurface == .upgrade)
        await state.activateLicense(key: " TEST-KEY ")
        #expect(state.hasFullAccess)
        #expect(state.licenseActivationJustSucceeded)
        try startFromHome(state)
        #expect(state.selectedSurface == .session)
        try typeInRoom(state)
        #expect(try store.load().trialSessionsUsed == 3)
        #expect(try store.load().licenseKey == "TEST-KEY")

        let mock = MockLicenseClient(validationError: offline ? .networkFailure : nil)
        let restarted = makeState(at: root, client: mock)
        #expect(!restarted.hasFullAccess)
        #expect(restarted.licenseValidationInFlight)
        try startFromHome(restarted)
        #expect(restarted.selectedSurface == .upgrade)
        await restarted.validateLicenseIfNeeded()
        #expect(await mock.lastValidatedToken == "mock-token")
        #expect(restarted.hasFullAccess)
        try startFromHome(restarted)
        #expect(restarted.selectedSurface == .session)
        try typeInRoom(restarted)
        #expect(try store.load().trialSessionsUsed == 3)
    }
}
