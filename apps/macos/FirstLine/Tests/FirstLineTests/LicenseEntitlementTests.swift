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

    private func makeState(at root: URL, client: MockLicenseClient = MockLicenseClient(),
                           openURL: @escaping (URL) -> Void = { _ in }) -> AppState {
        let store = SettingsStore(configDirectory: root)
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("settings.json").path) {
            var exhausted = AppSettings.defaultValue
            exhausted.trialSessionsUsed = AppState.trialSessionLimit
            try! store.save(exhausted)
        }
        return AppState(settingsStore: store, licenseClient: client,
                 installIDStore: InstallIDStore(configDirectory: root), clock: { now }, productID: "prod_mock",
                 openExternalURL: openURL)
    }

    private func assertLocked(_ state: AppState) {
        #expect(!state.hasFullAccess)
        #expect(state.selectedSurface == .upgrade)
        state.startSession()
        state.openWritingMode()
        state.newPiece()
        state.goHome()
        state.openSettings()
        state.closeSettings()
        #expect(!state.prepareSessionInput())
        #expect(state.selectedSurface == .upgrade)
        #expect(state.sessionEngine.phase == .idle)
        #expect(state.sessionEngine.text.isEmpty)
    }

    @Test func exhaustedTrialOnlyOffersActivationAndFullWebTrial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var opened: URL?
        let state = makeState(at: root, openURL: { opened = $0 })
        assertLocked(state)
        let screen = UpgradeViewController(appState: state)
        let fields = descendants(screen.view, of: NSTextField.self)
        #expect(fields.contains { $0.stringValue == "Activate Write It Down" })
        #expect(fields.contains { $0.placeholderString == "Order number or activation code" })
        let buttons = descendants(screen.view, of: NSButton.self)
        #expect(!buttons.contains { $0.title == "Back to Home" || $0.title == "Start writing" })
        let trial = try #require(buttons.first { $0.title == "Try the full web app at writeitdown.app" })
        trial.performClick(nil)
        #expect(opened?.absoluteString == "https://writeitdown.app/")
        assertLocked(state)

        let delegate = FirstLineAppDelegate(appState: state)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate)
        for action in [#selector(FirstLineAppDelegate.newPiece(_:)), #selector(FirstLineAppDelegate.goHome(_:)),
                       #selector(FirstLineAppDelegate.openWriting(_:)), #selector(FirstLineAppDelegate.openSettings(_:))] {
            let item = try #require(menu.items.flatMap { $0.submenu?.items ?? [] }.first { $0.action == action })
            #expect(!delegate.validateMenuItem(item))
            _ = NSApplication.shared.sendAction(action, to: delegate, from: item)
            assertLocked(state)
        }
    }

    @Test func activationFieldFocusChangesDoNotSubmitEmptyCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root)
        let controller = RootWindowController(appState: state)
        controller.showWindow(nil)
        defer { controller.close() }
        let window = try #require(controller.window)
        let view = try #require(window.contentView)
        let field = try #require(descendants(view, of: NSTextField.self).first {
            $0.placeholderString == "Order number or activation code"
        })
        window.makeFirstResponder(field)
        window.makeFirstResponder(nil)
        window.makeFirstResponder(field)
        await Task.yield()
        #expect(!descendants(view, of: NSTextField.self).contains {
            !$0.isHidden && $0.stringValue == "Enter your order number or activation code first."
        })
    }

    @Test(arguments: [false, true])
    func exhaustedStaleEditorRejectsCommittedAndMarkedInput(marked: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root)
        state.sessionEngine.start(duration: 60)
        state.selectedSurface = .session
        let room = SessionViewController(appState: state)
        let editor = try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
        if marked {
            editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            editor.insertText("draft", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        #expect(editor.string.isEmpty)
        assertLocked(state)
    }

    @Test(arguments: [-1, 0, 1, 2, 3, 99])
    func legacyTrialBudgetIsRetainedButUnlockFlagCannotGrantALicense(used: Int) throws {
        let limit = AppState.trialSessionLimit
        let expectedUsed = (0...limit).contains(used) ? used : limit
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture: [String: Any] = ["theme": "dark", "defaultDuration": 300, "reducedMotion": "always",
                                      "trialSessionsUsed": used, "hasUnlockedFullAccess": true, "licenseStatus": "trial"]
        try JSONSerialization.data(withJSONObject: fixture).write(to: root.appendingPathComponent("settings.json"))
        for _ in 0..<2 {
            let state = makeState(at: root)
            #expect(state.settings.theme == .dark)
            #expect(state.settings.defaultDuration == 300)
            #expect(state.settings.reducedMotion == .always)
            #expect(state.settings.licenseStatus == .inactive)
            #expect(!state.hasFullAccess)
            #expect(state.trialSessionsRemaining == limit - expectedUsed)
            if expectedUsed == limit { assertLocked(state) }
            try state.settingsStore.save(state.settings)
        }
        let persisted = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("settings.json"))) as? [String: Any]
        #expect(persisted?["trialSessionsUsed"] as? Int == expectedUsed)
        #expect(persisted?["hasUnlockedFullAccess"] == nil)
    }

    @Test(arguments: [nil, "", " \t\n"] as [String?])
    func activeWithoutCredentialRemainsLockedAcrossRestart(key: String?) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        try store.save(AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                   licenseKey: key, licenseStatus: .active, licenseLastValidatedAt: now,
                                   licenseInstanceID: "instance", licenseProductID: "prod_mock", licenseToken: "mock-token"))
        let client = MockLicenseClient()
        let state = makeState(at: root, client: client)
        await state.validateLicenseIfNeeded()
        #expect(await client.lastValidatedToken == nil)
        assertLocked(state)
        state.settings.licenseStatus = .active
        assertLocked(state)
        assertLocked(makeState(at: root))
    }

    @Test(arguments: [false, true])
    func activatedLicenseUnlocksHomeAndRestartsWithoutTrialBudget(offline: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = makeState(at: root)
        assertLocked(state)
        await state.activateLicense(key: " TEST-ORDER ")
        #expect(state.hasFullAccess)
        state.goHome()
        #expect(state.selectedSurface == .home)
        for _ in 0..<4 {
            state.startSession()
            #expect(state.selectedSurface == .session)
            let room = SessionViewController(appState: state)
            let editor = try #require(descendants(room.view, of: AppendOnlyTextView.self).first)
            editor.insertText("paid draft", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(state.sessionEngine.text == "paid draft")
            state.abandonSession()
        }
        let restarted = makeState(at: root, client: MockLicenseClient(validationError: offline ? .networkFailure : nil))
        #expect(restarted.selectedSurface == .upgrade)
        #expect(!restarted.hasFullAccess)
        await restarted.validateLicenseIfNeeded()
        #expect(restarted.hasFullAccess)
        #expect(restarted.selectedSurface == .home)
        restarted.startSession()
        #expect(restarted.selectedSurface == .session)
    }
}
