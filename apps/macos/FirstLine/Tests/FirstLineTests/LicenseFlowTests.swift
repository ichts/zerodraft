import Foundation
import Testing
@testable import FirstLine

@MainActor
struct LicenseFlowTests {
    private func makeAppState(
        activationBehavior: MockLicenseClient.ActivationBehavior = .success,
        validationResult: Bool = true,
        validationError: LicenseValidationError? = nil,
        initialSettings: AppSettings? = nil,
        clockNow: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> (AppState, MockLicenseClient, SettingsStore, FileManager, URL) {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        if let initialSettings {
            try store.save(initialSettings)
        }
        let mock = MockLicenseClient(
            activationBehavior: activationBehavior,
            validationResult: validationResult,
            validationError: validationError
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
            clock: { clockNow }
        )
        return (appState, mock, store, fm, tempRoot)
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
    func activeLicenseBypassesTrialLimit() throws {
        let exhausted = AppSettings(
            theme: .system,
            defaultDuration: 300,
            immersiveSessionMode: true,
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
            immersiveSessionMode: true,
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
            immersiveSessionMode: true,
            reducedMotion: .system,
            licenseKey: "PRO-VALID",
            licenseStatus: .active,
            licenseActivatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            licenseLastValidatedAt: Date(timeIntervalSince1970: 1_699_000_000)
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
        #expect(try store.load().licenseLastValidatedAt == later)
    }

    @Test
    func validateLicenseRevokesWhenDodoReturnsInvalid() async throws {
        let active = AppSettings(
            theme: .system,
            defaultDuration: 300,
            immersiveSessionMode: true,
            reducedMotion: .system,
            licenseKey: "PRO-REFUNDED",
            licenseStatus: .active,
            licenseActivatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            licenseLastValidatedAt: Date(timeIntervalSince1970: 1_699_000_000)
        )
        let (appState, _, _, fm, tempRoot) = try makeAppState(
            validationResult: false,
            initialSettings: active
        )
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.validateLicenseIfNeeded()

        #expect(appState.settings.licenseStatus == .revoked)
        #expect(appState.settings.hasUnlockedFullAccess == false)
    }

    @Test
    func validateLicenseNetworkFailureWithinGraceKeepsActive() async throws {
        let recentlyValidated = Date(timeIntervalSince1970: 1_700_000_000)
        let oneDayLater = Date(timeIntervalSince1970: 1_700_000_000 + 86_400)
        let active = AppSettings(
            theme: .system,
            defaultDuration: 300,
            immersiveSessionMode: true,
            reducedMotion: .system,
            licenseKey: "PRO-OFFLINE",
            licenseStatus: .active,
            licenseActivatedAt: recentlyValidated,
            licenseLastValidatedAt: recentlyValidated
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
            immersiveSessionMode: true,
            reducedMotion: .system,
            licenseKey: "PRO-EXPIRED",
            licenseStatus: .active,
            licenseActivatedAt: lastValidated,
            licenseLastValidatedAt: lastValidated
        )
        let (appState, _, _, fm, tempRoot) = try makeAppState(
            validationError: .networkFailure,
            initialSettings: active,
            clockNow: eightDaysLater
        )
        defer { try? fm.removeItem(at: tempRoot) }

        await appState.validateLicenseIfNeeded()

        #expect(appState.settings.licenseStatus == .unknown)
        #expect(appState.settings.hasUnlockedFullAccess == false)
    }
}
