import Foundation
import Testing
@testable import FirstLine

@MainActor
struct SmokeFlowTests {
    @Test
    func happyPathShowsSuccessButDoesNotAutoSave() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        appState.selectedDuration = 5
        appState.startSession()
        engine.registerCommittedText("hello world")
        uptime = 5
        appState.handleTick()

        #expect(engine.phase == .success)
        #expect(appState.librarySessions.isEmpty)
        #expect(fm.fileExists(atPath: libraryDirectory.path) == false)
        #expect(try appState.persistenceService.loadLibrary().isEmpty)
    }

    @Test
    func failurePathDoesNotSave() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        var uptime = 100.0
        let engine = SessionEngine(now: { uptime })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        appState.startSession()
        engine.registerCommittedText("a")
        uptime = 108.0
        appState.handleTick()

        #expect(engine.phase == .failure)
        #expect(appState.librarySessions.isEmpty)
    }

    @Test
    func launchAlwaysShowsHome() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let firstRun = AppState(
            sessionEngine: SessionEngine(),
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        #expect(firstRun.selectedSurface == .home)

        let returningSettings = AppSettings(theme: .system, defaultDuration: 300, immersiveSessionMode: true, reducedMotion: .system)
        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        try store.save(returningSettings)

        let uptime = 10.0
        let returningEngine = SessionEngine(now: { uptime })
        let returningRun = AppState(
            sessionEngine: returningEngine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        #expect(returningRun.selectedSurface == .home)
        #expect(returningEngine.phase == .idle)
    }

    @Test
    func keyboardNavigationHelpersSwitchSurfaces() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let appState = AppState(
            sessionEngine: SessionEngine(),
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        appState.openLibrary()
        #expect(appState.selectedSurface == .library)

        appState.openWritingMode()
        #expect(appState.selectedSurface == .session)

        appState.goHome()
        #expect(appState.selectedSurface == .home)
    }

    @Test
    func startingMacTrialSessionConsumesOneUse() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        let appState = AppState(
            sessionEngine: SessionEngine(),
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: store
        )

        appState.startSession()

        #expect(appState.settings.trialSessionsUsed == 1)
        #expect(appState.trialSessionsRemaining == 2)
        #expect(appState.selectedSurface == .session)
        #expect(try store.load().trialSessionsUsed == 1)
    }

    @Test
    func exhaustedMacTrialShowsUpgradeInsteadOfStartingSession() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        try store.save(AppSettings(
            theme: .system,
            defaultDuration: 300,
            immersiveSessionMode: true,
            reducedMotion: .system,
            trialSessionsUsed: AppState.trialSessionLimit
        ))
        let engine = SessionEngine()
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: store
        )

        appState.startSession()

        #expect(engine.phase == .idle)
        #expect(appState.selectedSurface == .upgrade)
        #expect(appState.isTrialExhausted)
        #expect(try store.load().trialSessionsUsed == AppState.trialSessionLimit)
    }

    @Test
    func unlockedMacAppBypassesTrialLimit() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        try store.save(AppSettings(
            theme: .system,
            defaultDuration: 300,
            immersiveSessionMode: true,
            reducedMotion: .system,
            trialSessionsUsed: AppState.trialSessionLimit,
            hasUnlockedFullAccess: true
        ))
        let engine = SessionEngine()
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: store
        )

        appState.startSession()

        #expect(engine.phase == .writing)
        #expect(appState.selectedSurface == .session)
        #expect(appState.settings.trialSessionsUsed == AppState.trialSessionLimit)
    }

    @Test
    func navigationHelpersAreGuardedDuringSuccess() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        appState.selectedDuration = 5
        appState.startSession()
        engine.registerCommittedText("hello world")
        uptime = 5
        appState.handleTick()

        #expect(engine.phase == .success)
        #expect(appState.selectedSurface == .session)

        appState.openLibrary()
        #expect(appState.selectedSurface == .session)

        appState.openSettings()
        #expect(appState.selectedSurface == .session)

        appState.openWritingMode()
        #expect(appState.selectedSurface == .session)

        appState.goHome()
        #expect(appState.selectedSurface == .session)

        appState.startSession()
        #expect(appState.selectedSurface == .session)
    }

    @Test
    func supportSurfacesAreGuardedDuringActiveSession() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let appState = AppState(
            sessionEngine: SessionEngine(),
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        appState.startSession()
        #expect(appState.selectedSurface == .session)
        #expect(appState.canNavigateToSupportSurface == false)

        appState.openLibrary()
        #expect(appState.selectedSurface == .session)

        appState.openSettings()
        #expect(appState.selectedSurface == .session)
    }

    @Test
    func supportSurfacesAreAvailableOnlyWhenSessionIsInactive() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        #expect(appState.canNavigateToSupportSurface)

        appState.startSession(duration: 5)
        #expect(appState.canNavigateToSupportSurface == false)

        engine.registerCommittedText("hello")
        uptime = 5
        appState.handleTick()
        #expect(engine.phase == .success)
        #expect(appState.canNavigateToSupportSurface == false)

        appState.abandonSession()
        #expect(appState.canNavigateToSupportSurface)
    }

    @Test
    func abandonDuringWritingClearsTextAndReturnsHome() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let engine = SessionEngine()
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        appState.startSession()
        engine.registerCommittedText("draft")
        appState.abandonSession()

        #expect(engine.phase == .idle)
        #expect(engine.text.isEmpty)
        #expect(appState.selectedSurface == .home)
    }

    @Test
    func abandonDuringDangerClearsTextAndReturnsHome() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        var uptime = 0.0
        let engine = SessionEngine(now: { uptime })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: configDirectory)
        )

        appState.startSession()
        engine.registerCommittedText("draft")
        uptime = 5
        appState.handleTick()
        #expect(engine.phase == .danger)

        appState.abandonSession()
        #expect(engine.phase == .idle)
        #expect(engine.text.isEmpty)
        #expect(appState.selectedSurface == .home)
    }
}
