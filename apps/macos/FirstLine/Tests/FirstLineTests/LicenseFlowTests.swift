import Foundation
import AppKit
import Testing
@testable import WriteItDown

private actor SuspendedValidationClient: LicenseClient {
    private var validation: CheckedContinuation<Bool, Error>?
    private var waiter: CheckedContinuation<Void, Never>?

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        LicenseActivation(instanceID: UUID().uuidString, licenseKeyID: "lic_test", name: instanceName,
                          businessID: "biz_test", createdAt: "2024-01-01T00:00:00Z", productID: "prod_mock")
    }

    func validate(licenseKey: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            validation = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitForValidation() async {
        if validation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func completeValidation(_ result: Result<Bool, LicenseValidationError>) {
        validation?.resume(with: result.mapError { $0 as Error })
        validation = nil
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {}
}

@MainActor
struct LicenseFlowTests {
    private func makeAppState(
        activationBehavior: MockLicenseClient.ActivationBehavior = .success,
        validationResult: Bool = true,
        validationError: LicenseValidationError? = nil,
        initialSettings: AppSettings? = nil,
        clockNow: Date = Date(timeIntervalSince1970: 1_700_000_000),
        responseProductID: String? = "prod_mock",
        deactivateFails: Bool = false
    ) throws -> (AppState, MockLicenseClient, SettingsStore, FileManager, URL) {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        if let initialSettings {
            try store.save(initialSettings)
        }
        let mock = MockLicenseClient(
            activationBehavior: activationBehavior,
            validationResult: validationResult,
            validationError: validationError,
            productID: responseProductID,
            deactivateFails: deactivateFails
        )
        let installStore = InstallIDStore(
            fileManager: fm,
            configDirectory: configDirectory,
            now: { clockNow }
        )
        let appState = AppState(
            settingsStore: store,
            licenseClient: mock,
            installIDStore: installStore,
            clock: { clockNow },
            productID: "prod_mock"
        )
        return (appState, mock, store, fm, tempRoot)
    }

    private func editor(in view: NSView) -> AppendOnlyTextView? {
        if let input = view as? AppendOnlyTextView { return input }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }

    @Test func trialIsConsumedOnFirstKeystrokeNotOnEntry() throws {
        let (state, _, store, fm, root) = try makeAppState()
        defer { try? fm.removeItem(at: root) }
        state.startSession()
        let input = try #require(editor(in: SessionViewController(appState: state).view))
        #expect(state.settings.trialSessionsUsed == 0)
        input.insertText("first", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 1)
        input.insertText(" second", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 1)
        #expect(try store.load().trialSessionsUsed == 1)
    }

    @Test func markedTextConsumesTrialOnlyOnce() throws {
        let (state, _, _, fm, root) = try makeAppState()
        defer { try? fm.removeItem(at: root) }
        state.startSession()
        let input = try #require(editor(in: SessionViewController(appState: state).view))
        input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 1)
        input.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 1)
    }

    @Test func untouchedRoomDoesNotConsumeTrial() throws {
        let (state, _, store, fm, root) = try makeAppState()
        defer { try? fm.removeItem(at: root) }
        state.startSession()
        state.abandonSession()
        #expect(state.settings.trialSessionsUsed == 0)
        #expect(try store.load().trialSessionsUsed == 0)
    }

    @Test func exhaustedTrialRoutesToUpgrade() throws {
        let (state, _, _, fm, root) = try makeAppState()
        defer { try? fm.removeItem(at: root) }
        state.settings.trialSessionsUsed = 2
        state.startSession()
        let input = try #require(editor(in: SessionViewController(appState: state).view))
        input.insertText("third", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.settings.trialSessionsUsed == 3)
        state.newPiece()
        #expect(state.selectedSurface == .upgrade)
        #expect(state.sessionEngine.phase == .idle)
    }

    @Test func checkoutURLComesFromInfoPlist() throws {
        let config = try #require(NSDictionary(contentsOf: AppState.configurationURL) as? [String: Any])
        let expected = config["WIDCheckoutURL"] as? String
        #expect(AppState.checkoutURL == expected.flatMap(URL.init(string:)))
        let (state, _, _, fm, root) = try makeAppState()
        defer { try? fm.removeItem(at: root) }
        let upgrade = UpgradeViewController(appState: state)
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        let all = views(upgrade.view)
        let buy = try #require(all.compactMap { $0 as? NSButton }.first { $0.title.contains("Buy a license") })
        #expect(buy.isEnabled == (AppState.checkoutURL != nil))
        if AppState.checkoutURL == nil {
            #expect(all.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Checkout is not available yet." && !$0.isHidden })
        }
        let configured = URL(string: "https://checkout.dodopayments.com/example")!
        #expect(AppState.checkoutURL(in: ["WIDCheckoutURL": configured.absoluteString]) == configured)
        #expect(AppState.checkoutURL(in: ["WIDCheckoutURL": "http://example.com"]) == nil)
    }

    @Test func displayPriceComesFromInfoPlist() throws {
        let config = try #require(NSDictionary(contentsOf: AppState.configurationURL) as? [String: Any])
        let price = try #require(config["WIDDisplayPrice"] as? String)
        let (state, _, _, fm, root) = try makeAppState()
        defer { try? fm.removeItem(at: root) }
        let upgrade = UpgradeViewController(appState: state)
        func labels(_ view: NSView) -> [String] {
            let fields = (view as? NSTextField).map { [$0.stringValue] } ?? []
            let buttons = (view as? NSButton).map { [$0.title] } ?? []
            return fields + buttons + view.subviews.flatMap(labels)
        }
        #expect(labels(upgrade.view).contains { $0.contains(price) })
    }

    @Test
    func activateLicenseSuccessSetsActiveStatusAndPersists() async throws {
        let (appState, _, store, fm, tempRoot) = try makeAppState()
        defer { try? fm.removeItem(at: tempRoot) }

        #expect(appState.settings.licenseStatus == .trial)

        await appState.activateLicense(key: "PRO-AAAA-BBBB-CCCC-DDDD")

        #expect(appState.settings.licenseStatus == .active)
        #expect(appState.settings.licenseKey == "PRO-AAAA-BBBB-CCCC-DDDD")
        #expect(appState.settings.licenseInstanceID?.hasPrefix("lki_mock_") == true)
        #expect(appState.settings.licenseActivatedAt != nil)
        #expect(appState.settings.licenseLastValidatedAt != nil)
        #expect(appState.licenseActivationJustSucceeded)
        #expect(appState.licenseActivationError == nil)

        let reloaded = try store.load()
        #expect(reloaded.licenseStatus == .active)
        #expect(reloaded.licenseKey == "PRO-AAAA-BBBB-CCCC-DDDD")
        #expect(reloaded.licenseProductID == "prod_mock")
    }

    @Test
    func activateLicenseWithWhitespaceTrimsKey() async throws {
        let (appState, mock, _, fm, tempRoot) = try makeAppState()
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.activateLicense(key: "  PRO-TRIM-ME  \n")

        let args = await mock.lastActivateArguments
        #expect(args?.licenseKey == "PRO-TRIM-ME")
        #expect(appState.settings.licenseKey == "PRO-TRIM-ME")
    }

    @Test
    func activateLicenseInvalidKeyKeepsTrialState() async throws {
        let (appState, _, store, fm, tempRoot) = try makeAppState(activationBehavior: .invalidKey)
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.activateLicense(key: "PRO-BAD-KEY")

        #expect(appState.settings.licenseStatus == .trial)
        #expect(appState.settings.licenseKey == nil)
        #expect(appState.licenseActivationError == .invalidKey)
        #expect(appState.licenseActivationJustSucceeded == false)
        #expect(try store.load().licenseStatus == .trial)
    }

    @Test
    func activateLicenseLimitReachedReportsError() async throws {
        let (appState, _, _, fm, tempRoot) = try makeAppState(activationBehavior: .activationLimitReached)
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.activateLicense(key: "PRO-LIMIT")

        #expect(appState.settings.licenseStatus == .trial)
        #expect(appState.licenseActivationError == .activationLimitReached)
    }

    @Test
    func activateLicenseNetworkFailureReportsError() async throws {
        let (appState, _, _, fm, tempRoot) = try makeAppState(activationBehavior: .networkFailure)
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.activateLicense(key: "PRO-NET")

        #expect(appState.settings.licenseStatus == .trial)
        #expect(appState.licenseActivationError == .networkFailure)
    }

    @Test
    func activateLicenseEmptyTriggersEmptyKeyErrorWithoutCallingClient() async throws {
        let (appState, mock, _, fm, tempRoot) = try makeAppState()
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.activateLicense(key: "   ")

        #expect(appState.licenseActivationError == .emptyKey)
        let args = await mock.lastActivateArguments
        #expect(args == nil)
    }

    @Test
    func emptyProductConfigurationRejectsActivation() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let mock = MockLicenseClient()
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), licenseClient: mock,
                             installIDStore: InstallIDStore(configDirectory: root), productID: "")
        await state.activateLicense(key: "KEY")
        #expect(state.licenseActivationError == .productNotConfigured)
        #expect(await mock.lastActivateArguments == nil)
    }

    @Test
    func cachedKeyIsBlockedUntilValidationAndRequiresMatchingProduct() async throws {
        let active = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                 trialSessionsUsed: AppState.trialSessionLimit, licenseKey: "KEY",
                                 licenseStatus: .active, licenseActivatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 licenseProductID: "prod_mock")
        let (state, mock, _, fm, root) = try makeAppState(initialSettings: active)
        defer { try? fm.removeItem(at: root) }
        state.startSession()
        #expect(state.sessionEngine.phase == .idle)
        await state.validateLicenseIfNeeded()
        #expect(await mock.lastValidatedKey == "KEY")
        state.startSession()
        #expect(state.sessionEngine.phase == .writing)

        let wrongRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: wrongRoot) }
        let wrongStore = SettingsStore(configDirectory: wrongRoot)
        try wrongStore.save(active)
        let wrong = AppState(settingsStore: wrongStore, licenseClient: MockLicenseClient(),
                             installIDStore: InstallIDStore(configDirectory: wrongRoot), productID: "other")
        await wrong.validateLicenseIfNeeded()
        wrong.startSession()
        #expect(wrong.selectedSurface == .upgrade)
        #expect(wrong.trialStatusText.contains("does not match"))
        func fields(_ view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields)
        }
        #expect(fields(SettingsViewController(appState: wrong).view).contains { $0.placeholderString == "Paste license key" })
    }

    @Test
    func pendingLicenseCheckAllowsRemainingTrialAndChargesFirstInput() throws {
        let active = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                 trialSessionsUsed: 1, licenseKey: "KEY", licenseStatus: .active,
                                 licenseProductID: "prod_mock")
        let (state, _, store, fm, root) = try makeAppState(initialSettings: active)
        defer { try? fm.removeItem(at: root) }
        #expect(state.licenseValidationInFlight)
        state.startSession()
        #expect(state.selectedSurface == .session)
        #expect(state.prepareSessionInput())
        state.sessionEngine.registerCommittedText("trial")
        state.consumeTrialOnFirstInput()
        #expect(state.settings.trialSessionsUsed == 2)
        #expect(try store.load().trialSessionsUsed == 2)
    }

    @Test
    func expiredOfflineLicenseRecoversAfterOnlineValidation() async throws {
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        let now = then.addingTimeInterval(8 * 86_400)
        let active = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                 trialSessionsUsed: AppState.trialSessionLimit, licenseKey: "KEY",
                                 licenseStatus: .active, licenseActivatedAt: then,
                                 licenseLastValidatedAt: then, licenseProductID: "prod_mock")
        let (offline, _, store, fm, root) = try makeAppState(validationError: .networkFailure,
                                                               initialSettings: active, clockNow: now)
        defer { try? fm.removeItem(at: root) }
        await offline.validateLicenseIfNeeded()
        #expect(offline.settings.licenseStatus == .unknown)
        offline.startSession()
        #expect(offline.selectedSurface == .upgrade)

        let wrongClient = MockLicenseClient()
        let wrongProduct = AppState(settingsStore: store, licenseClient: wrongClient,
                                    installIDStore: InstallIDStore(configDirectory: root.appendingPathComponent("Config")),
                                    productID: "other")
        await wrongProduct.validateLicenseIfNeeded()
        #expect(await wrongClient.lastValidatedKey == nil)
        wrongProduct.startSession()
        #expect(wrongProduct.selectedSurface == .upgrade)

        let recovered = AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                                 installIDStore: InstallIDStore(configDirectory: root.appendingPathComponent("Config")),
                                 clock: { now }, productID: "prod_mock")
        #expect(recovered.licenseValidationInFlight)
        recovered.startSession()
        #expect(recovered.selectedSurface == .upgrade)
        await recovered.validateLicenseIfNeeded()
        #expect(recovered.settings.licenseStatus == .active)
        #expect(try store.load().licenseStatus == .active)
        recovered.startSession()
        #expect(recovered.selectedSurface == .session)
    }

    @Test(arguments: [0, 1, 2])
    func staleValidationCannotOverwriteSameKeyReactivation(outcome: Int) async throws {
        let active = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                 trialSessionsUsed: AppState.trialSessionLimit, licenseKey: "KEY",
                                 licenseStatus: .active, licenseProductID: "prod_mock")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        try store.save(active)
        let client = SuspendedValidationClient()
        let state = AppState(settingsStore: store, licenseClient: client,
                             installIDStore: InstallIDStore(configDirectory: root), productID: "prod_mock")
        let check = Task { await state.validateLicenseIfNeeded() }
        await client.waitForValidation()
        await state.activateLicense(key: "KEY")
        #expect(state.licenseActivationJustSucceeded)
        switch outcome {
        case 0: await client.completeValidation(.success(true))
        case 1: await client.completeValidation(.success(false))
        default: await client.completeValidation(.failure(.networkFailure))
        }
        await check.value
        #expect(state.settings.licenseStatus == .active)
        let savedInstanceID = try store.load().licenseInstanceID
        #expect(state.settings.licenseInstanceID == savedInstanceID)
        #expect(!state.licenseValidationInFlight)
        state.startSession()
        #expect(state.selectedSurface == .session)
    }

    @Test(arguments: [false, true])
    func rejectedProductCleansOnlyNewInstanceAndReportsFailure(cleanupFails: Bool) async throws {
        let old = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                              licenseKey: "OLD", licenseStatus: .active,
                              licenseActivatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                              licenseInstanceID: "lki_existing", licenseProductID: "prod_mock")
        let (state, mock, store, fm, root) = try makeAppState(initialSettings: old,
            responseProductID: "other", deactivateFails: cleanupFails)
        defer { try? fm.removeItem(at: root) }
        await state.activateLicense(key: "NEW")
        let cleanup = await mock.lastDeactivateArguments
        #expect(cleanup?.licenseKey == "NEW")
        #expect(cleanup?.instanceID != "lki_existing")
        #expect(cleanup?.instanceID.hasPrefix("lki_mock_") == true)
        #expect(state.licenseActivationError == (cleanupFails ? .cleanupFailure : .wrongProduct))
        #expect(state.settings.licenseInstanceID == "lki_existing")
        #expect(try store.load().licenseKey == "OLD")
    }

    @Test
    func rejectedActivationNeverDeactivatesPreviouslyAcceptedInstance() async throws {
        let old = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                              licenseKey: "KEY", licenseStatus: .active,
                              licenseInstanceID: "lki_existing", licenseProductID: "prod_mock")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        try store.save(old)
        let mock = MockLicenseClient(productID: "other", activationInstanceID: "lki_existing")
        let state = AppState(settingsStore: store, licenseClient: mock,
                             installIDStore: InstallIDStore(configDirectory: root), productID: "prod_mock")
        await state.activateLicense(key: "KEY")
        #expect(state.licenseActivationError == .wrongProduct)
        #expect(await mock.lastDeactivateArguments == nil)
        #expect(try store.load().licenseInstanceID == "lki_existing")
    }

    @Test
    func cleanupFailureOnUnsavedActivationLeavesTrialGateClosed() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let blocked = root.appendingPathComponent("blocked")
        try "file".write(to: blocked, atomically: true, encoding: .utf8)
        let mock = MockLicenseClient(deactivateFails: true)
        let state = AppState(settingsStore: SettingsStore(configDirectory: blocked.appendingPathComponent("Config")),
                             licenseClient: mock, installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        state.settings.trialSessionsUsed = AppState.trialSessionLimit
        await state.activateLicense(key: "KEY")
        #expect(state.licenseActivationError == .cleanupFailure)
        #expect((state.licenseActivationError?.errorDescription ?? "").contains("Contact support"))
        #expect(await mock.lastDeactivateArguments?.licenseKey == "KEY")
        state.startSession()
        #expect(state.selectedSurface == .upgrade)
    }

    @Test
    func offlineGraceExpiresWhileAppRemainsOpenAndOnlineValidationRestoresAccess() async throws {
        let last = Date(timeIntervalSince1970: 1_700_000_000)
        var now = last.addingTimeInterval(86_400)
        let active = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                 trialSessionsUsed: AppState.trialSessionLimit, licenseKey: "KEY",
                                 licenseStatus: .active, licenseActivatedAt: last,
                                 licenseLastValidatedAt: last, licenseProductID: "prod_mock")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let store = SettingsStore(configDirectory: root)
        try store.save(active)
        let state = AppState(settingsStore: store, licenseClient: MockLicenseClient(validationError: .networkFailure),
                             installIDStore: InstallIDStore(configDirectory: root), clock: { now }, productID: "prod_mock")
        await state.validateLicenseIfNeeded()
        #expect(state.hasFullAccess)
        now = last.addingTimeInterval(AppState.licenseOfflineGraceInterval + 1)
        #expect(!state.hasFullAccess)
        state.startSession()
        #expect(state.selectedSurface == .upgrade)
        #expect(state.trialStatusText.contains("online validation"))

        let online = AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                              installIDStore: InstallIDStore(configDirectory: root), clock: { now }, productID: "prod_mock")
        await online.validateLicenseIfNeeded()
        #expect(online.hasFullAccess)
        online.startSession()
        #expect(online.selectedSurface == .session)
    }

    @Test
    func legacyUnlockIsNotBoundToOfflineGrace() throws {
        let old = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                              trialSessionsUsed: AppState.trialSessionLimit, licenseStatus: .active)
        let (state, _, _, fm, root) = try makeAppState(initialSettings: old,
            clockNow: Date(timeIntervalSince1970: 2_000_000_000))
        defer { try? fm.removeItem(at: root) }
        #expect(state.hasFullAccess)
        state.startSession()
        #expect(state.selectedSurface == .session)
    }

    @Test(arguments: [true, false])
    func visibleLicenseSurfacesRefreshAfterValidation(valid: Bool) async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cached = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                 trialSessionsUsed: AppState.trialSessionLimit, licenseKey: "KEY",
                                 licenseStatus: .active, licenseActivatedAt: now,
                                 licenseLastValidatedAt: now, licenseProductID: "prod_mock")
        let (state, _, _, fm, root) = try makeAppState(validationResult: valid, initialSettings: cached)
        defer { try? fm.removeItem(at: root) }
        let settings = SettingsViewController(appState: state)
        let upgrade = UpgradeViewController(appState: state)
        func fields(_ view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields)
        }
        func buttons(_ view: NSView) -> [NSButton] {
            ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap(buttons)
        }
        let settingsView = settings.view
        let upgradeView = upgrade.view
        let settingsKey = try #require(fields(settingsView).first { $0.placeholderString == "Paste license key" })
        let upgradeKey = try #require(fields(upgradeView).first { $0.placeholderString == "Paste license key from Dodo email" })
        settingsKey.stringValue = "unfinished key"
        upgradeKey.stringValue = "unfinished key"
        #expect(fields(settingsView).contains { $0.stringValue == "Checking license..." })
        #expect(fields(upgradeView).contains { $0.stringValue == "Checking license..." })

        await state.validateLicenseIfNeeded()
        let status = valid ? "License active." : "License revoked. Reactivate in Settings."
        for _ in 0..<50 {
            if fields(settingsView).contains(where: { $0.stringValue == status }) &&
                fields(upgradeView).contains(where: { $0.stringValue == (valid ? "License active on this Mac." : status) }) { break }
            await Task.yield()
        }
        #expect(fields(settingsView).contains { $0.stringValue == status })
        #expect(fields(upgradeView).contains { $0.stringValue == (valid ? "License active on this Mac." : status) })
        #expect(settingsKey.stringValue == "unfinished key")
        #expect(upgradeKey.stringValue == "unfinished key")
        #expect(buttons(upgradeView).contains { $0.title == (valid ? "Start writing" : "Activate") })
        #expect(settingsKey.isHidden == valid || settingsKey.superview?.isHidden == valid)
    }

    @Test
    func validationRefreshDoesNotInterruptWriting() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cached = AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                 licenseKey: "KEY", licenseStatus: .active,
                                 licenseActivatedAt: now, licenseLastValidatedAt: now,
                                 licenseProductID: "prod_mock")
        let (state, _, _, fm, root) = try makeAppState(initialSettings: cached)
        defer { try? fm.removeItem(at: root) }
        state.startSession()
        state.openSettings()
        let settings = SettingsViewController(appState: state)
        _ = settings.view
        await state.validateLicenseIfNeeded()
        #expect(state.sessionEngine.phase == .writing)
        #expect(state.selectedSurface == .settings)
    }

    @Test
    func activeLicenseBypassesTrialLimit() throws {
        let exhausted = AppSettings(
            theme: .system,
            defaultDuration: 300,
            reducedMotion: .system,
            trialSessionsUsed: AppState.trialSessionLimit,
            licenseStatus: .active
        )
        let (appState, _, _, fm, tempRoot) = try makeAppState(initialSettings: exhausted)
        defer { try? fm.removeItem(at: tempRoot) }

        appState.startSession()

        #expect(appState.sessionEngine.phase == .writing)
        #expect(appState.selectedSurface == .session)
        #expect(appState.settings.trialSessionsUsed == AppState.trialSessionLimit)
    }

    @Test
    func revokedLicenseDoesNotBypassTrialLimit() throws {
        let revoked = AppSettings(
            theme: .system,
            defaultDuration: 300,
            reducedMotion: .system,
            trialSessionsUsed: AppState.trialSessionLimit,
            licenseStatus: .revoked
        )
        let (appState, _, _, fm, tempRoot) = try makeAppState(initialSettings: revoked)
        defer { try? fm.removeItem(at: tempRoot) }

        appState.startSession()

        #expect(appState.sessionEngine.phase == .idle)
        #expect(appState.selectedSurface == .upgrade)
    }

    @Test
    func validateLicenseRefreshesLastValidatedAtWhenValid() async throws {
        let active = AppSettings(
            theme: .system,
            defaultDuration: 300,
            reducedMotion: .system,
            licenseKey: "PRO-VALID",
            licenseStatus: .active,
            licenseActivatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            licenseLastValidatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            licenseProductID: "prod_mock"
        )
        let later = Date(timeIntervalSince1970: 1_700_000_000)
        let (appState, _, store, fm, tempRoot) = try makeAppState(
            validationResult: true,
            initialSettings: active,
            clockNow: later
        )
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.validateLicenseIfNeeded()

        #expect(appState.settings.licenseStatus == .active)
        #expect(appState.settings.licenseLastValidatedAt == later)
        #expect(!appState.licenseValidationInFlight)
        #expect(try store.load().licenseLastValidatedAt == later)
    }

    @Test
    func validateLicenseRevokesWhenDodoReturnsInvalid() async throws {
        let active = AppSettings(
            theme: .system,
            defaultDuration: 300,
            reducedMotion: .system,
            licenseKey: "PRO-REFUNDED",
            licenseStatus: .active,
            licenseActivatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            licenseLastValidatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            licenseProductID: "prod_mock"
        )
        let (appState, _, _, fm, tempRoot) = try makeAppState(
            validationResult: false,
            initialSettings: active
        )
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.validateLicenseIfNeeded()

        #expect(appState.settings.licenseStatus == .revoked)
    }

    @Test
    func validateLicenseNetworkFailureWithinGraceKeepsActive() async throws {
        let recentlyValidated = Date(timeIntervalSince1970: 1_700_000_000)
        let oneDayLater = Date(timeIntervalSince1970: 1_700_000_000 + 86_400)
        let active = AppSettings(
            theme: .system,
            defaultDuration: 300,
            reducedMotion: .system,
            licenseKey: "PRO-OFFLINE",
            licenseStatus: .active,
            licenseActivatedAt: recentlyValidated,
            licenseLastValidatedAt: recentlyValidated,
            licenseProductID: "prod_mock"
        )
        let (appState, _, _, fm, tempRoot) = try makeAppState(
            validationError: .networkFailure,
            initialSettings: active,
            clockNow: oneDayLater
        )
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.validateLicenseIfNeeded()

        #expect(appState.settings.licenseStatus == .active)
    }

    @Test
    func validateLicenseNetworkFailurePastGraceDemotesToUnknown() async throws {
        let lastValidated = Date(timeIntervalSince1970: 1_700_000_000)
        let eightDaysLater = Date(timeIntervalSince1970: 1_700_000_000 + 8 * 86_400)
        let active = AppSettings(
            theme: .system,
            defaultDuration: 300,
            reducedMotion: .system,
            licenseKey: "PRO-EXPIRED",
            licenseStatus: .active,
            licenseActivatedAt: lastValidated,
            licenseLastValidatedAt: lastValidated,
            licenseProductID: "prod_mock"
        )
        let (appState, _, _, fm, tempRoot) = try makeAppState(
            validationError: .networkFailure,
            initialSettings: active,
            clockNow: eightDaysLater
        )
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.validateLicenseIfNeeded()

        #expect(appState.settings.licenseStatus == .unknown)
    }

    @Test
    func activationWithFailingPersistenceReportsStorageError() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        // Make configDirectory uncreatable: its parent is a regular file.
        let blockingFile = tempRoot.appendingPathComponent("blocked", isDirectory: false)
        try "file".write(to: blockingFile, atomically: true, encoding: .utf8)
        let badConfig = blockingFile.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let store = SettingsStore(fileManager: fm, configDirectory: badConfig)
        let mock = MockLicenseClient(activationBehavior: .success)
        let installStore = InstallIDStore(
            fileManager: fm,
            configDirectory: tempRoot.appendingPathComponent("Install", isDirectory: true),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let appState = AppState(
            settingsStore: store,
            licenseClient: mock,
            installIDStore: installStore,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            productID: "prod_mock"
        )

        await appState.activateLicense(key: "PRO-GOOD-KEY")

        #expect(appState.licenseActivationJustSucceeded == false)
        #expect(appState.licenseActivationError == .storageFailure)
        // A failed persist must not leave the app granting access for this run.
        #expect(appState.settings.licenseStatus != .active)
        let cleanup = await mock.lastDeactivateArguments
        #expect(cleanup?.licenseKey == "PRO-GOOD-KEY")
        #expect(cleanup?.instanceID.hasPrefix("lki_mock_") == true)
    }
}
