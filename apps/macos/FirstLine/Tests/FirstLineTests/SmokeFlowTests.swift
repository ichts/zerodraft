import AppKit
import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct SmokeFlowTests {
    private func makeState(now: @escaping () -> TimeInterval = { 0 }) -> (AppState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("Config", isDirectory: true)
        let state = AppState(
            sessionEngine: SessionEngine(now: now),
            settingsStore: SettingsStore(configDirectory: config),
            installIDStore: InstallIDStore(configDirectory: config)
        )
        return (state, root)
    }

    private func fileMetadata(at root: URL) -> [String: Date] {
        let fm = FileManager.default
        guard let paths = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [:] }
        var result: [String: Date] = [:]
        for case let file as URL in paths {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate {
                result[file.path] = modified
            }
        }
        return result
    }

    private func assertNoDraftWritten(_ draft: String, root: URL, realRootBefore: [String: Date]) throws {
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("Library").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("Recovery").path))
        if let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                let data = try Data(contentsOf: file)
                #expect(!data.contains(Data(draft.utf8)), "Writing escaped into \(file.lastPathComponent)")
            }
        }
        #expect(fileMetadata(at: AppPaths.applicationSupportRoot) == realRootBefore)
    }

    @Test
    func keptSessionWritesNoFiles() throws {
        var now = 0.0
        let realRootBefore = fileMetadata(at: AppPaths.applicationSupportRoot)
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession(duration: 60)
        state.sessionEngine.registerCommittedText("private kept draft")
        for second in stride(from: 6.0, through: 54.0, by: 6.0) {
            now = second
            state.sessionEngine.registerMarkedTextActivity()
        }
        now = 60
        state.handleTick()
        #expect(state.sessionEngine.phase == .success)
        #expect(state.sessionEngine.text == "private kept draft")
        try assertNoDraftWritten("private kept draft", root: root, realRootBefore: realRootBefore)
    }

    @Test
    func wipedSessionWritesNoFiles() throws {
        var now = 0.0
        let realRootBefore = fileMetadata(at: AppPaths.applicationSupportRoot)
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        state.sessionEngine.registerCommittedText("private wiped draft")
        now = 8
        state.handleTick()
        #expect(state.sessionEngine.phase == .failure)
        #expect(state.sessionEngine.text.isEmpty)
        try assertNoDraftWritten("private wiped draft", root: root, realRootBefore: realRootBefore)
    }

    @Test
    func libraryIsNotANavigationTarget() {
        let (state, root) = makeState()
        defer { try? FileManager.default.removeItem(at: root) }
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate())
        let navigationTitles = menu.items.flatMap { $0.submenu?.items.map(\.title) ?? [] }
        #expect(!navigationTitles.contains("Library"))
        #expect(!Surface.navigationCases.contains { $0.rawValue == "Library" })
        state.openWritingMode()
        #expect(state.selectedSurface == .session)
        state.goHome()
        #expect(state.selectedSurface == .home)
    }

    @Test
    func startingMacTrialSessionConsumesOneUse() throws {
        let (state, root) = makeState()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        #expect(state.settings.trialSessionsUsed == 1)
        #expect(state.trialSessionsRemaining == 2)
        #expect(state.selectedSurface == .session)
        #expect(try state.settingsStore.load().trialSessionsUsed == 1)
    }

    @Test
    func exhaustedMacTrialShowsUpgradeInsteadOfStartingSession() throws {
        let (state, root) = makeState()
        defer { try? FileManager.default.removeItem(at: root) }
        state.settings.trialSessionsUsed = AppState.trialSessionLimit
        state.startSession()
        #expect(state.sessionEngine.phase == .idle)
        #expect(state.selectedSurface == .upgrade)
    }

    @Test
    func legacyUnlockedMacAppBypassesTrialLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("Config", isDirectory: true)
        let store = SettingsStore(configDirectory: config)
        try store.save(AppSettings(theme: .system, defaultDuration: 60, reducedMotion: .system,
                                   trialSessionsUsed: AppState.trialSessionLimit, hasUnlockedFullAccess: true))
        let state = AppState(settingsStore: store, installIDStore: InstallIDStore(configDirectory: config))
        state.startSession()
        #expect(state.sessionEngine.phase == .writing)
        #expect(state.settings.licenseStatus == .active)
    }

    @Test
    func navigationHelpersAreGuardedDuringSuccess() {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession(duration: 60)
        state.sessionEngine.registerCommittedText("hello world")
        for second in stride(from: 6.0, through: 54.0, by: 6.0) {
            now = second
            state.sessionEngine.registerMarkedTextActivity()
        }
        now = 60
        state.handleTick()
        #expect(state.sessionEngine.phase == .success)
        state.openSettings()
        #expect(state.selectedSurface == .settings)
        state.openWritingMode()
        state.goHome()
        state.startSession()
        #expect(state.selectedSurface == .settings)
    }

    @Test
    func validPersistedDurationIsRemembered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("Config", isDirectory: true)
        let store = SettingsStore(configDirectory: config)
        var settings = AppSettings.defaultValue
        settings.defaultDuration = 300
        try store.save(settings)
        let state = AppState(settingsStore: store, installIDStore: InstallIDStore(configDirectory: config))
        #expect(state.settings.defaultDuration == 300)
        state.startSession()
        #expect(state.sessionEngine.duration == 300)
    }

    @Test
    func launchAlwaysShowsHome() throws {
        let (firstRun, root) = makeState()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(firstRun.selectedSurface == .home)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = 1
        try firstRun.settingsStore.save(settings)
        let returning = AppState(settingsStore: firstRun.settingsStore,
                                 installIDStore: InstallIDStore(configDirectory: root.appendingPathComponent("Config")))
        #expect(returning.selectedSurface == .home)
        #expect(returning.sessionEngine.phase == .idle)
    }

    @Test
    func supportSurfacesAreGuardedDuringActiveSession() {
        let (state, root) = makeState()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        #expect(!state.canNavigateToSupportSurface)
        state.openSettings()
        #expect(state.selectedSurface == .settings)
    }

    @Test
    func supportSurfacesAreAvailableOnlyWhenSessionIsInactive() {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(state.canNavigateToSupportSurface)
        state.startSession(duration: 60)
        #expect(!state.canNavigateToSupportSurface)
        state.sessionEngine.registerCommittedText("hello")
        for second in stride(from: 6.0, through: 54.0, by: 6.0) {
            now = second
            state.sessionEngine.registerMarkedTextActivity()
        }
        now = 60
        state.handleTick()
        #expect(state.sessionEngine.phase == .success)
        #expect(!state.canNavigateToSupportSurface)
        state.abandonSession()
        #expect(state.canNavigateToSupportSurface)
    }

    @Test
    func abandonDuringWritingClearsTextAndReturnsHome() {
        let (state, root) = makeState()
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        state.sessionEngine.registerCommittedText("draft")
        state.abandonSession()
        #expect(state.sessionEngine.phase == .idle)
        #expect(state.sessionEngine.text.isEmpty)
        #expect(state.selectedSurface == .home)
    }

    @Test
    func abandonDuringDangerClearsTextAndReturnsHome() {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        state.sessionEngine.registerCommittedText("draft")
        now = 5
        state.handleTick()
        #expect(state.sessionEngine.phase == .danger)
        state.abandonSession()
        #expect(state.sessionEngine.phase == .idle)
        #expect(state.sessionEngine.text.isEmpty)
        #expect(state.selectedSurface == .home)
    }

    @Test
    func untouchedRoomHasNoDeadline() {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession(duration: 60)
        now = 65
        state.handleTick()
        #expect(state.sessionEngine.phase == .writing)
        #expect(state.selectedSurface == .session)
    }

    @Test
    func lateCommittedTextAfterDeadlineRoutesHomeViaStateCallback() {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession(duration: 60)
        now = 65
        state.sessionEngine.registerCommittedText("first text")
        #expect(state.sessionEngine.phase == .writing)
        #expect(state.selectedSurface == .session)
    }

    @Test
    func lateMarkedTextActivityAfterDeadlineRoutesHome() {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession(duration: 60)
        now = 65
        state.sessionEngine.registerMarkedTextActivity()
        #expect(state.sessionEngine.phase == .writing)
        #expect(state.selectedSurface == .session)
    }

    private func editor(in view: NSView) -> AppendOnlyTextView? {
        if let editor = view as? AppendOnlyTextView { return editor }
        for child in view.subviews {
            if let found = editor(in: child) { return found }
        }
        return nil
    }

    @Test
    func exhaustedTrialBlocksBothLateKeystrokeAndIMEAfterWipe() throws {
        for marked in [false, true] {
            var now = 0.0
            let (state, root) = makeState(now: { now })
            defer { try? FileManager.default.removeItem(at: root) }
            state.settings.trialSessionsUsed = AppState.trialSessionLimit - 1
            state.startSession()
            state.sessionEngine.registerCommittedText("old draft")
            let controller = SessionViewController(appState: state)
            let input = try #require(editor(in: controller.view))
            input.loadRestoredText("old draft")
            now = 9
            if marked {
                input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            } else {
                input.insertText("new", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            #expect(state.selectedSurface == .upgrade)
            #expect(state.sessionEngine.phase == .failure)
            #expect(state.settings.trialSessionsUsed == AppState.trialSessionLimit)
            #expect(input.string.isEmpty)
        }
    }

    @Test
    func licensedRestartKeepsOnlyNewInputIncludingIMECommit() throws {
        for marked in [false, true] {
            var now = 0.0
            let (state, root) = makeState(now: { now })
            defer { try? FileManager.default.removeItem(at: root) }
            state.settings.licenseStatus = .active
            state.startSession()
            state.sessionEngine.registerCommittedText("old draft")
            let oldID = state.sessionEngine.sessionID
            let controller = SessionViewController(appState: state)
            let input = try #require(editor(in: controller.view))
            input.loadRestoredText("old draft")
            if marked {
                input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            now = 9
            if marked {
                let oldEnd = NSRange(location: (input.string as NSString).length, length: 0)
                input.insertText("你", replacementRange: oldEnd)
            } else {
                input.insertText("new", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            let expected = marked ? "你" : "new"
            #expect(state.selectedSurface == .session)
            #expect(state.sessionEngine.sessionID != oldID)
            #expect(state.sessionEngine.text == expected)
            #expect(input.string == expected)
            #expect(state.settings.trialSessionsUsed == 0)
        }
    }

    @Test
    func uncommittedCompositionWarnsAndClearsTheEditor() async throws {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.startSession()
        let controller = SessionViewController(appState: state)
        let input = try #require(editor(in: controller.view))
        input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(input.hasMarkedText())
        #expect(state.sessionEngine.text.isEmpty)
        controller.viewDidAppear()
        defer { controller.viewWillDisappear() }
        now = 5
        state.handleTick()
        #expect(state.sessionEngine.phase == .danger)
        now = 8
        state.handleTick()
        #expect(state.sessionEngine.phase == .failure)
        controller.tick()
        #expect(input.string.isEmpty)
        #expect(!input.hasMarkedText())
    }

    @Test
    func wipeDuringCompositionClearsOldDraftBeforeNextCandidate() throws {
        var now = 0.0
        let (state, root) = makeState(now: { now })
        defer { try? FileManager.default.removeItem(at: root) }
        state.settings.licenseStatus = .active
        state.startSession()
        state.sessionEngine.registerCommittedText("old draft")
        let controller = SessionViewController(appState: state)
        let input = try #require(editor(in: controller.view))
        input.loadRestoredText("old draft")
        input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(input.hasMarkedText())
        now = 8
        state.handleTick()
        #expect(state.sessionEngine.phase == .failure)
        input.insertText("好", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(state.sessionEngine.text == "好")
        #expect(input.string == "好")
    }

}
