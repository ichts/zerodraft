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
        #expect(!state.canUseApp)
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
        #expect(fields.contains { $0.stringValue == "Order number or activation code" })
        #expect(fields.contains { $0.placeholderString == "WID-XXXX-XXXX" })
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
            $0.placeholderString == "WID-XXXX-XXXX"
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
        // A restart trusts the stored token immediately, so the picker is the first surface
        // whether or not the background revalidation can reach the service.
        let restarted = makeState(at: root, client: MockLicenseClient(validationError: offline ? .networkFailure : nil))
        #expect(restarted.selectedSurface == .home)
        #expect(restarted.hasFullAccess)
        await restarted.validateLicenseIfNeeded()
        #expect(restarted.hasFullAccess)
        #expect(restarted.selectedSurface == .home)
        restarted.startSession()
        #expect(restarted.selectedSurface == .session)
    }

    /// Launch is the first thing a licensed writer sees. A Mac holding a signed, unexpired token
    /// must present the picker without ever showing the activation card; the online check runs in
    /// the background and only a definitive revocation may surface the license card again.
    /// This bound the reported launch: the license card flashed, then the app said it was active.
    @Test func launchWithAStoredSignedLicensePresentsThePickerFirst() async throws {
        let fixture = SignedLicenseFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // The install id the token is signed for, exactly as the app stores it.
        try """
        {"uuid": "\(fixture.install)", "createdAt": \(fixture.now.timeIntervalSinceReferenceDate)}
        """.write(to: root.appendingPathComponent("install-id.json"), atomically: true, encoding: .utf8)
        var saved = AppSettings.defaultValue
        saved.trialSessionsUsed = AppState.trialSessionLimit
        saved.licenseKey = "test-order-123"
        saved.licenseStatus = .active
        saved.licenseInstanceID = "activation-test"
        saved.licenseProductID = fixture.product
        saved.licenseToken = try fixture.token()
        saved.licenseActivatedAt = fixture.now
        saved.licenseLastValidatedAt = fixture.now
        let store = SettingsStore(configDirectory: root)
        try store.save(saved)

        let state = AppState(settingsStore: store, licenseClient: fixture.client(),
                             installIDStore: InstallIDStore(configDirectory: root),
                             clock: { fixture.now }, productID: fixture.product)
        // The window is built while the launch revalidation is still running.
        #expect(state.licenseValidationInFlight)
        #expect(state.hasFullAccess)
        #expect(state.selectedSurface == .home)

        let container = RootContainerViewController(appState: state)
        _ = container.view
        container.show(state.selectedSurface)
        #expect(container.children.count == 1)
        #expect(container.children.contains { $0 is HomeViewController })
        #expect(container.children.contains { $0 is UpgradeViewController } == false)
        if let directory = ProcessInfo.processInfo.environment["WID_SNAPSHOT_DIR"] {
            let size = NSSize(width: 1040, height: 720)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentViewController = container
            window.setContentSize(size)
            container.view.layoutSubtreeIfNeeded()
            container.view.displayIfNeeded()
            let bitmap = try #require(container.view.bitmapImageRepForCachingDisplay(in: container.view.bounds))
            container.view.cacheDisplay(in: container.view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try png.write(to: output.appendingPathComponent("licensed-launch-content.png"))
        }
    }
}
