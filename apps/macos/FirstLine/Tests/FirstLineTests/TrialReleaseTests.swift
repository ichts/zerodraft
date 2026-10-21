import AppKit
import Foundation
import Testing
@testable import WriteItDown

private struct OfflineSignedClient: LicenseClient {
    let verifier: LicenseTokenVerifier
    var isConfigured: Bool { true }
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        throw LicenseActivationError.networkFailure
    }
    func validate(token: String) async throws -> String? { throw LicenseValidationError.networkFailure }
    func deactivate(token: String) async throws { throw LicenseValidationError.networkFailure }
    func permitsAccess(token: String, instanceID: String, installLabel: String, now: Date) -> Bool {
        (try? verifier.verify(token, installLabel: installLabel, now: now).activationId) == instanceID
    }
}

@MainActor
struct TrialReleaseTests {
    private func makeState(at root: URL, now: @escaping () -> TimeInterval = { 0 },
                           client: MockLicenseClient = MockLicenseClient()) -> AppState {
        AppState(sessionEngine: SessionEngine(now: now), settingsStore: SettingsStore(configDirectory: root),
                 licenseClient: client, installIDStore: InstallIDStore(configDirectory: root), productID: "prod_mock")
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    private func editor(in room: SessionViewController) throws -> AppendOnlyTextView {
        try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
    }

    private func writeSession(_ state: AppState) throws {
        state.startSession()
        let room = SessionViewController(appState: state)
        let field = try editor(in: room)
        field.insertText("first words", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.sessionEngine.text == "first words")
        state.abandonSession()
    }

    @Test func freshInstallOpensHomeWithThreeSessionsWithoutLicenseTraffic() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = MockLicenseClient()
        let state = makeState(at: root, client: client)
        #expect(state.selectedSurface == .home)
        #expect(state.canStartSession)
        #expect(!state.hasFullAccess)
        #expect(state.accessStatusText == "Free trial: 3 of 3 sessions left.")
        #expect(await state.validateLicenseIfNeeded() == nil)
        #expect(await client.lastValidatedToken == nil)
        let home = HomeViewController(appState: state)
        #expect(descendants(home.view, of: NSTextField.self).contains {
            $0.stringValue == "Free trial: 3 of 3 sessions left."
        })
        let delegate = FirstLineAppDelegate(appState: state)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate)
        let newPiece = try #require(menu.items.flatMap { $0.submenu?.items ?? [] }.first {
            $0.action == #selector(FirstLineAppDelegate.newPiece(_:))
        })
        #expect(delegate.validateMenuItem(newPiece))
        state.openSettings()
        #expect(state.selectedSurface == .settings)
        state.closeSettings()
        #expect(state.selectedSurface == .home)
    }

    @Test func firstNonemptyInputSpendsOnceIncludingComposition() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root)
        state.startSession()
        state.goHome()
        #expect(state.settings.trialSessionsUsed == 0)
        state.startSession()
        let room = SessionViewController(appState: state)
        let field = try editor(in: room)
        field.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
        field.setMarkedText("", selectedRange: NSRange(location: 0, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        field.deleteBackward(nil)
        field.paste(nil)
        #expect(state.settings.trialSessionsUsed == 0)
        field.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 1)
        #expect(try state.settingsStore.load().trialSessionsUsed == 1)
        field.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        field.insertText(" more", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 1)
        #expect(state.accessStatusText == "Free trial: 2 of 3 sessions left.")
    }

    @Test func exhaustionPersistsAndRoutesToExistingActivationScreen() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root)
        for _ in 0..<3 { try writeSession(state) }
        #expect(state.selectedSurface == .upgrade)
        let restarted = makeState(at: root)
        #expect(restarted.trialSessionsRemaining == 0)
        #expect(!restarted.canStartSession)
        #expect(!restarted.hasFullAccess)
        restarted.startSession()
        restarted.newPiece()
        restarted.openWritingMode()
        restarted.goHome()
        restarted.openSettings()
        #expect(restarted.selectedSurface == .upgrade)
        #expect(!restarted.prepareSessionInput(isActivity: true))
        #expect(restarted.sessionEngine.text.isEmpty)
        let screen = UpgradeViewController(appState: restarted)
        let fields = descendants(screen.view, of: NSTextField.self)
        #expect(fields.contains { $0.stringValue == "After 3 free sessions, a license is required to keep writing." })
        #expect(fields.contains { $0.placeholderString == "Order number or activation code" })
        let buy = try #require(descendants(screen.view, of: NSButton.self).first { $0.title.hasPrefix("Buy a license") })
        #expect(!buy.isEnabled)
    }

    @Test func wipedSessionRestartSpendsAnotherButLastWipeDoesNotSellImmediately() throws {
        var now = 0.0
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root, now: { now })
        state.startSession()
        let room = SessionViewController(appState: state)
        let field = try editor(in: room)
        for used in 1...3 {
            field.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(state.settings.trialSessionsUsed == used)
            now += 9
            room.tick()
            #expect(state.sessionEngine.phase == .failure)
            #expect(state.selectedSurface == .session)
            #expect(field.string.isEmpty)
            field.setMarkedText("", selectedRange: NSRange(location: 0, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
            field.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(state.sessionEngine.phase == .failure)
            #expect(state.selectedSurface == .session)
            #expect(state.settings.trialSessionsUsed == used)
            let expected = used == 3 ? "DRAFT DELETED AT 0:08. ACTIVATE TO KEEP WRITING."
                                     : "DRAFT DELETED AT 0:08. TYPE TO START AGAIN."
            #expect(descendants(room.view, of: NSTextField.self).contains { $0.stringValue == expected && !$0.isHidden })
        }
        field.insertText("fourth", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(field.string.isEmpty)
        #expect(state.selectedSurface == .upgrade)
        #expect(state.settings.trialSessionsUsed == 3)
    }

    @Test func lastSessionCanRecoverCompleteAndOfferCopyBeforeNextGate() throws {
        var now = 0.0
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root, now: { now })
        state.settings.trialSessionsUsed = 2
        state.startSession()
        let room = SessionViewController(appState: state)
        let field = try editor(in: room)
        field.insertText("one", replacementRange: NSRange(location: NSNotFound, length: 0))
        now = 5.5
        room.tick()
        #expect(state.sessionEngine.phase == .danger)
        field.insertText(" two", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.sessionEngine.phase == .writing)
        for second in stride(from: 10.0, through: 55.0, by: 5) {
            now = second
            field.insertText(" word", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        now = 60
        room.tick()
        #expect(state.sessionEngine.phase == .success)
        #expect(state.selectedSurface == .session)
        #expect(!state.sessionEngine.text.isEmpty)
        let copy = NSMenuItem(title: "Copy", action: #selector(FirstLineAppDelegate.copyKept(_:)), keyEquivalent: "")
        #expect(FirstLineAppDelegate(appState: state).validateMenuItem(copy))
        #expect(state.settings.trialSessionsUsed == 3)
        state.newPiece()
        #expect(state.selectedSurface == .upgrade)
    }

    @Test(arguments: [false, true])
    func lastTrialSettingsRoundTripPreservesWipeOrKept(complete: Bool) throws {
        var now = 0.0
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root, now: { now })
        state.settings.trialSessionsUsed = 2
        state.startSession()
        let room = SessionViewController(appState: state)
        let field = try editor(in: room)
        field.insertText("one", replacementRange: NSRange(location: NSNotFound, length: 0))
        if complete {
            for second in stride(from: 5.0, through: 55.0, by: 5) {
                now = second
                field.insertText(" word", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        state.openSettings()
        #expect(state.selectedSurface == .settings)
        now = complete ? 60 : 9
        state.closeSettings()
        #expect(state.sessionEngine.phase == (complete ? .success : .failure))
        #expect(state.selectedSurface == .session)
        state.newPiece()
        #expect(state.selectedSurface == .upgrade)
    }

    @Test(arguments: [false, true])
    func persistenceFailureRejectsInputBeforeAcceptingText(marked: Bool) throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root)
        state.startSession()
        let room = SessionViewController(appState: state)
        let field = try editor(in: room)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("settings.json"), withIntermediateDirectories: true)
        if marked {
            field.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            field.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        #expect(field.string.isEmpty)
        #expect(state.sessionEngine.text.isEmpty)
        #expect(!state.sessionEngine.hasStarted)
        #expect(state.settings.trialSessionsUsed == 0)
        #expect(state.selectedSurface == .upgrade)
        #expect(state.accessStatusText.contains("Could not save trial usage"))
        let screen = UpgradeViewController(appState: state)
        #expect(descendants(screen.view, of: NSTextField.self).contains {
            !$0.isHidden && $0.stringValue.contains("Could not save trial usage")
        })
        #expect(!state.canStartSession)
    }

    @Test func unreadableSettingsDoNotResetTrialBudget() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appendingPathComponent("settings.json"))
        let state = makeState(at: root)
        #expect(state.selectedSurface == .upgrade)
        #expect(state.trialSessionsRemaining == 0)
        #expect(state.accessStatusText.contains("Could not read trial usage"))
    }

    @Test func corruptTrialCountPreservesOfflineSignedLicense() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = SignedLicenseFixture()
        let store = SettingsStore(configDirectory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(InstallID(uuid: UUID(uuidString: fixture.install)!, createdAt: fixture.now))
            .write(to: root.appendingPathComponent("install-id.json"))
        try store.save(AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                   licenseKey: "order", licenseStatus: .active, licenseActivatedAt: fixture.now,
                                   licenseLastValidatedAt: fixture.now, licenseInstanceID: "activation-test",
                                   licenseProductID: fixture.product, licenseToken: fixture.token()))
        let file = root.appendingPathComponent("settings.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["trialSessionsUsed"] = "bad"
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let state = AppState(settingsStore: store, licenseClient: OfflineSignedClient(verifier: try fixture.verifier()),
                             installIDStore: InstallIDStore(configDirectory: root), clock: { fixture.now },
                             productID: fixture.product)
        #expect(state.settings.trialSessionsUsed == 3)
        #expect(state.trialSessionsRemaining == 0)
        #expect(!state.hasFullAccess)
        #expect(state.selectedSurface == .upgrade)
        #expect(await state.validateLicenseIfNeeded() == nil)
        #expect(state.hasFullAccess)
        state.startSession()
        let room = SessionViewController(appState: state)
        let field = try editor(in: room)
        field.insertText("offline draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.sessionEngine.text == "offline draft")
    }

    @Test func activationUnlocksExhaustedTrialWithoutChangingCounterAndRefundNeverRestoresIt() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = MockLicenseClient(validationResult: false)
        let state = makeState(at: root, client: client)
        for _ in 0..<3 { try writeSession(state) }
        await state.activateLicense(key: "test-order")
        #expect(state.hasFullAccess)
        state.goHome()
        for _ in 0..<4 { try writeSession(state) }
        #expect(state.settings.trialSessionsUsed == 3)
        #expect(await state.validateLicenseIfNeeded() == false)
        #expect(!state.hasFullAccess)
        #expect(!state.canStartSession)
        state.startSession()
        #expect(state.selectedSurface == .upgrade)
        #expect(makeState(at: root).selectedSurface == .upgrade)
    }

    @Test func partialLicenseMetadataDoesNotCreateAFreshTrial() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try SettingsStore(configDirectory: root).save(AppSettings(
            theme: .system, defaultDuration: 60, reducedMotion: .system,
            licenseActivatedAt: Date(), licenseProductID: "old-product"))
        let state = makeState(at: root)
        #expect(!state.canStartSession)
        #expect(state.selectedSurface == .upgrade)
    }

    @Test(arguments: [LicenseStatus.inactive, .active, .unknown, .revoked, .invalid])
    func cachedLicenseNeverFallsBackToUnusedTrial(status: LicenseStatus) throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        try store.save(AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                   licenseKey: "old-order", licenseStatus: status,
                                   licenseInstanceID: "instance", licenseProductID: "prod_mock", licenseToken: "bad-token"))
        let state = makeState(at: root)
        #expect(state.settings.trialSessionsUsed == 0)
        #expect(state.trialSessionsRemaining == 0)
        #expect(!state.canStartSession)
        #expect(state.selectedSurface == .upgrade)
    }
}
