import Foundation
import Testing
@testable import FirstLine

@MainActor
struct SmokeFlowTests {
    @Test
    func happyPathAutoSavesOnSuccess() throws {
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

        appState.startSession(duration: 5)
        engine.registerCommittedText("hello world")
        uptime = 5
        appState.handleTick()

        #expect(engine.phase == .success)
        let saved = try appState.persistenceService.loadLibrary()
        #expect(saved.count == 1)
        #expect(saved.first?.body.contains("hello world") == true)
        #expect(fm.fileExists(atPath: libraryDirectory.path))
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

        let returningSettings = AppSettings(theme: .system, defaultDuration: 60, immersiveSessionMode: true, reducedMotion: .system)
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
            defaultDuration: 60,
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
            defaultDuration: 60,
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

        appState.startSession(duration: 5)
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
    @Test
    func legacyPersistedDurationIsSupersededByFixedSixtySeconds() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        var legacy = AppSettings.defaultValue
        legacy.defaultDuration = 300
        try store.save(legacy)

        let engine = SessionEngine(now: { 0 })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: store
        )

        #expect(appState.settings.defaultDuration == SessionEngine.defaultDurationSeconds)
        appState.startSession()
        #expect(engine.duration == SessionEngine.defaultDurationSeconds)
    }

    @Test
    func manualFinishAutoSavesExactlyOnce() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryDirectory = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let engine = SessionEngine(now: { 0 })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: libraryDirectory),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: tempRoot.appendingPathComponent("Config", isDirectory: true))
        )

        appState.startSession()
        engine.registerCommittedText("finished early")
        engine.finish()
        engine.finish()
        #expect(try appState.persistenceService.loadLibrary().count == 1)
    }

    @Test
    func wipedDraftIsExposedForTheJoinedFossil() {
        var uptime = 100.0
        let engine = SessionEngine(now: { uptime })
        engine.start(duration: SessionEngine.defaultDurationSeconds)
        engine.registerCommittedText("this paragraph will be wiped")
        uptime = 108.0
        engine.tick()
        #expect(engine.phase == .failure)
        #expect(engine.wipedText == "this paragraph will be wiped")
        #expect(engine.text.isEmpty)
    }

    @MainActor
    @Test
    func failedSaveRetriesWithSnapshotEvenAfterNewSessionStarts() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let blockingFile = tempRoot.appendingPathComponent("blocked", isDirectory: false)
        try "file".write(to: blockingFile, atomically: true, encoding: .utf8)
        let badLibrary = blockingFile.appendingPathComponent("Library", isDirectory: true)

        let engine = SessionEngine(now: { 0 })
        let appState = AppState(
            sessionEngine: engine,
            persistenceService: PersistenceService(fileManager: fm, libraryDirectory: badLibrary),
            settingsStore: SettingsStore(fileManager: fm, configDirectory: tempRoot.appendingPathComponent("Config", isDirectory: true))
        )

        appState.startSession()
        engine.registerCommittedText("session A words")
        engine.finish()
        #expect((try? appState.persistenceService.loadLibrary().isEmpty) != false)

        appState.abandonSession()
        appState.startSession()
        engine.registerCommittedText("session B words")
        #expect(engine.phase == .writing)

        try fm.removeItem(at: blockingFile)
        try fm.createDirectory(at: badLibrary, withIntermediateDirectories: true)
        try await Task.sleep(nanoseconds: 2_600_000_000)

        let saved = try appState.persistenceService.loadLibrary()
        #expect(saved.count == 1)
        #expect(saved.first?.body.contains("session A words") == true)
        #expect(saved.first?.body.contains("session B words") == false)
    }

}
