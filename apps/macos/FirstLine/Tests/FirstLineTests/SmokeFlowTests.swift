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
        let failureSaved = try appState.persistenceService.loadLibrary()
        #expect(failureSaved.isEmpty)
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

    @Test
    func emptySessionAtCompletionRoutesHomeAndPersistsNothing() throws {
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
        #expect(appState.selectedSurface == .session)
        // The user never types anything; the deadline arrives.
        uptime = 5.0
        appState.handleTick()

        #expect(engine.phase == .idle)
        #expect(appState.selectedSurface == .home)
        let emptySaved = try appState.persistenceService.loadLibrary()
        #expect(emptySaved.isEmpty)
    }

    // MARK: - Late empty-input routing via state callback (Fix M-B2)

    @Test
    func lateCommittedTextAfterDeadlineRoutesHomeViaStateCallback() throws {
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
        #expect(appState.selectedSurface == .session)
        // No text is ever typed; the completion deadline has already passed.
        uptime = 6.0
        // A late first committed text arrives after the deadline. The engine
        // adjudicates the empty draft to idle; the state callback routes Home.
        engine.registerCommittedText("late text")

        #expect(engine.phase == .idle)
        #expect(appState.selectedSurface == .home)
        let saved = try appState.persistenceService.loadLibrary()
        #expect(saved.isEmpty)
    }

    @Test
    func lateMarkedTextActivityAfterDeadlineRoutesHome() throws {
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
        #expect(appState.selectedSurface == .session)
        uptime = 6.0
        // A late IME marked-text event arrives after the completion deadline.
        engine.registerMarkedTextActivity()

        #expect(engine.phase == .idle)
        #expect(appState.selectedSurface == .home)
    }

    // MARK: - 空草稿 finish 永不 success（R4-M1）

    @Test
    func emptyFinishRoutesHomeAndPersistsNothing() throws {
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
        #expect(appState.selectedSurface == .session)
        // 用户从未输入任何文字，直接 Cmd+Enter。
        engine.finish()

        #expect(engine.phase == .idle)
        #expect(appState.selectedSurface == .home)
        let saved = try appState.persistenceService.loadLibrary()
        #expect(saved.isEmpty)
    }

    // MARK: - Durable wipe aftermath (Fix 6)

    @Test
    func failureCapturesAftermathVisibleAfterGoingHome() throws {
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
        engine.registerCommittedText("the lost paragraph text here")
        uptime = 8.0
        appState.handleTick()

        #expect(engine.phase == .failure)
        #expect(appState.lastWipeFossil == "the lost paragraph text here")

        appState.goHome()
        // The aftermath persists on Home after leaving the failure surface.
        #expect(appState.lastWipeFossil != nil)
        #expect(appState.selectedSurface == .home)
    }

    @Test
    func startingASessionClearsTheWipeAftermath() throws {
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
        engine.registerCommittedText("doomed draft")
        uptime = 8.0
        appState.handleTick()
        #expect(appState.lastWipeFossil != nil)

        appState.startSession()
        #expect(appState.lastWipeFossil == nil)
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
            settingsStore: SettingsStore(fileManager: fm, configDirectory: tempRoot.appendingPathComponent("Config", isDirectory: true)),
            saveRetryDelayNanoseconds: 20_000_000
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

        let saved = try await waitForSavedCount(1, in: appState.persistenceService, timeoutSeconds: 5)
        #expect(saved.count == 1)
        #expect(saved.first?.body.contains("session A words") == true)
        #expect(saved.first?.body.contains("session B words") == false)
    }

    @MainActor
    @Test
    func concurrentFailingSavesEachGetTheirOwnRetry() async throws {
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
            settingsStore: SettingsStore(fileManager: fm, configDirectory: tempRoot.appendingPathComponent("Config", isDirectory: true)),
            saveRetryDelayNanoseconds: 20_000_000
        )

        // Session A fails to persist; its retry is scheduled (keyed by A's sessionID).
        appState.startSession()
        engine.registerCommittedText("session A words")
        engine.finish()

        appState.abandonSession()
        // Session B also fails to persist; with the old single-task bug its retry would cancel A's.
        appState.startSession()
        engine.registerCommittedText("session B words")
        engine.finish()

        #expect((try? appState.persistenceService.loadLibrary().isEmpty) != false)

        // Unblock and let both per-session retries persist their own snapshot.
        try fm.removeItem(at: blockingFile)
        try fm.createDirectory(at: badLibrary, withIntermediateDirectories: true)

        let saved = try await waitForSavedCount(2, in: appState.persistenceService, timeoutSeconds: 5)
        #expect(saved.count == 2)
        let bodies = saved.map(\.body)
        #expect(bodies.contains(where: { $0.contains("session A words") }))
        #expect(bodies.contains(where: { $0.contains("session B words") }))
    }

    /// Polls the library until it reaches `count` entries or `timeoutSeconds` elapses,
    /// removing the wall-clock fragility of fixed sleeps for the retry path.
    private func waitForSavedCount(
        _ count: Int,
        in service: PersistenceService,
        timeoutSeconds: TimeInterval
    ) async throws -> [LibrarySession] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var saved: [LibrarySession] = []
        while Date() < deadline {
            saved = (try? service.loadLibrary()) ?? []
            if saved.count >= count { return saved }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        return saved
    }

}
