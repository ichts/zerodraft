/**
 * [INPUT]: 依赖 SessionEngine、PersistenceService、SettingsStore 管理应用状态
 * [OUTPUT]: 提供 Surface 枚举与 AppState 状态容器，包含原生 3-session trial gate
 * [POS]: FirstLine 顶层导航真相源，负责从 Home 启动 session、消耗 trial 与支持面跳转
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
import AppKit
import SwiftUI

enum Surface: String, CaseIterable, Hashable, Identifiable {
    case home = "Home"
    case session = "Session"
    case failure = "Failure"
    case success = "Success"
    case library = "Library"
    case settings = "Settings"
    case upgrade = "Upgrade"

    var id: String { rawValue }

    static let navigationCases: [Surface] = [.home, .session, .failure, .success, .library, .settings]
}

@MainActor
@Observable
final class AppState {
    static let trialSessionLimit = 3
    /// Dodo validate 不可达时，仍把 license 视作 active 的最长宽限期。
    static let licenseOfflineGraceInterval: TimeInterval = 7 * 24 * 60 * 60

    var selectedSurface: Surface = .home
    var selectedDuration: TimeInterval = SessionEngine.defaultDurationSeconds
    let sessionEngine: SessionEngine
    let persistenceService: PersistenceService
    let settingsStore: SettingsStore
    let licenseClient: LicenseClient
    let installIDStore: InstallIDStore
    let clock: () -> Date
    var settings: AppSettings
    var librarySessions: [LibrarySession] = []
    var selectedLibrarySession: LibrarySession?
    var deleteTarget: LibrarySession?
    var deletePromptVisible = false

    /// UpgradeView / SettingsView 读取这些字段渲染激活状态。
    var licenseActivationInFlight = false
    var licenseActivationError: LicenseActivationError?
    var licenseActivationJustSucceeded = false

    /// 已写盘的 sessionID，确保每场成功 session 只调用一次 saveSuccessfulSession，防止 ticking 重复触发。
    private var lastPersistedSessionID: UUID?

    init(
        sessionEngine: SessionEngine = SessionEngine(),
        persistenceService: PersistenceService = PersistenceService(),
        settingsStore: SettingsStore = SettingsStore(),
        licenseClient: LicenseClient = MockLicenseClient(),
        installIDStore: InstallIDStore = InstallIDStore(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.sessionEngine = sessionEngine
        self.persistenceService = persistenceService
        self.settingsStore = settingsStore
        self.licenseClient = licenseClient
        self.installIDStore = installIDStore
        self.clock = clock
        self.settings = (try? settingsStore.load()) ?? .defaultValue
        // Fixed 60s contract: legacy persisted durations are superseded by the engine constant.
        self.selectedDuration = SessionEngine.defaultDurationSeconds
        if settings.defaultDuration != SessionEngine.defaultDurationSeconds {
            settings.defaultDuration = SessionEngine.defaultDurationSeconds
        }

        refreshLibrary()
        launchInitialSurface()

        // onStateChange 由 @MainActor 的 engine 方法触发，始终运行在主线程；用它观察 success 迁移可同时覆盖 timer 与编辑器两条触发路径。
        sessionEngine.onStateChange = { [weak self] phase in
            MainActor.assumeIsolated {
                self?.persistSuccessfulSessionOnSuccess(phase)
            }
        }
    }

    func startSession(duration: TimeInterval? = nil) {
        guard sessionEngine.phase != .success else { return }
        guard canStartTrialSession else {
            selectedSurface = .upgrade
            return
        }

        consumeTrialSessionIfNeeded()
        let resolvedDuration = duration ?? SessionEngine.defaultDurationSeconds
        sessionEngine.start(duration: resolvedDuration)
        selectedSurface = .session
    }

    func goHome() {
        guard sessionEngine.phase != .success else { return }
        selectedSurface = .home
    }

    func openLibrary() {
        guard canNavigateToSupportSurface else { return }
        refreshLibrary()
        selectedSurface = .library
    }

    func openWritingMode() {
        guard sessionEngine.phase != .success else { return }
        if sessionEngine.phase == .writing || sessionEngine.phase == .danger {
            selectedSurface = .session
        } else {
            startSession()
        }
    }

    func openSettings() {
        guard canNavigateToSupportSurface else { return }
        selectedSurface = .settings
    }

    func selectLibrarySession(_ session: LibrarySession) {
        selectedLibrarySession = session
    }

    func requestDelete(_ session: LibrarySession) {
        deleteTarget = session
        deletePromptVisible = true
    }

    func confirmDelete() {
        guard let session = deleteTarget else { return }
        try? persistenceService.deleteSession(at: session.fileURL)
        deleteTarget = nil
        deletePromptVisible = false
        refreshLibrary()
        if selectedLibrarySession?.id == session.id {
            selectedLibrarySession = librarySessions.first
        }
    }

    func cancelDelete() {
        deleteTarget = nil
        deletePromptVisible = false
    }

    func copyLibrarySessionText(_ session: LibrarySession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.body, forType: .string)
    }

    func openLibrarySessionInDefaultEditor(_ session: LibrarySession) {
        NSWorkspace.shared.open(session.fileURL)
    }

    func revealLibrarySessionInFinder(_ session: LibrarySession) {
        NSWorkspace.shared.activateFileViewerSelecting([session.fileURL])
    }

    func abandonSession() {
        sessionEngine.abandon()
        selectedSurface = .home
    }

    func copySuccessText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sessionEngine.text, forType: .string)
    }

    func handleTick() {
        sessionEngine.tick()
        if sessionEngine.phase == .success, lastPersistedSessionID != sessionEngine.sessionID {
            persistSuccessfulSessionOnSuccess(sessionEngine.phase)
        }
    }

    func updateTheme(_ theme: AppTheme) {
        settings.theme = theme
        persistSettings()
    }

    func updateDefaultDuration(_ duration: TimeInterval) {
        settings.defaultDuration = duration
        selectedDuration = duration
        persistSettings()
    }

    func updateImmersiveMode(_ enabled: Bool) {
        settings.immersiveSessionMode = enabled
        persistSettings()
    }

    func updateReducedMotion(_ option: ReducedMotionOverride) {
        settings.reducedMotion = option
        persistSettings()
    }

    func openLaunchWebsite() {
        guard let url = URL(string: "https://zerodraft.ai-builders.space/") else { return }
        NSWorkspace.shared.open(url)
    }

    func openLicenseHelp() {
        openLaunchWebsite()
    }

    func activateLicense(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            licenseActivationError = .emptyKey
            return
        }
        licenseActivationInFlight = true
        licenseActivationError = nil
        licenseActivationJustSucceeded = false
        defer { licenseActivationInFlight = false }

        let instanceName = installIDStore.loadOrCreate().shortName
        do {
            let activation = try await licenseClient.activate(licenseKey: trimmed, instanceName: instanceName)
            settings.licenseKey = trimmed
            settings.licenseStatus = .active
            settings.licenseInstanceID = activation.instanceID
            settings.licenseActivatedAt = clock()
            settings.licenseLastValidatedAt = clock()
            settings.hasUnlockedFullAccess = true
            persistSettings()
            licenseActivationJustSucceeded = true
        } catch let activationError as LicenseActivationError {
            licenseActivationError = activationError
        } catch {
            licenseActivationError = .unexpected(statusCode: -1)
        }
    }

    func clearLicenseActivationError() {
        licenseActivationError = nil
    }

    func dismissLicenseSuccessFeedback() {
        licenseActivationJustSucceeded = false
    }

    func validateLicenseIfNeeded() async {
        guard settings.licenseStatus == .active,
              let key = settings.licenseKey else { return }

        do {
            let valid = try await licenseClient.validate(licenseKey: key)
            if valid {
                settings.licenseLastValidatedAt = clock()
                persistSettings()
            } else {
                applyRevokedState()
            }
        } catch {
            applyOfflineGraceDecision()
        }
    }

    private func applyRevokedState() {
        settings.licenseStatus = .revoked
        settings.hasUnlockedFullAccess = false
        persistSettings()
    }

    private func applyOfflineGraceDecision() {
        let last = settings.licenseLastValidatedAt ?? settings.licenseActivatedAt
        guard let last else {
            settings.licenseStatus = .unknown
            settings.hasUnlockedFullAccess = false
            persistSettings()
            return
        }
        if clock().timeIntervalSince(last) > Self.licenseOfflineGraceInterval {
            settings.licenseStatus = .unknown
            settings.hasUnlockedFullAccess = false
            persistSettings()
        }
    }

    func revealLibraryFolder() {
        try? FileManager.default.createDirectory(at: AppPaths.libraryDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.libraryDirectory])
    }

    private func refreshLibrary() {
        librarySessions = (try? persistenceService.loadLibrary()) ?? []
        if selectedLibrarySession == nil {
            selectedLibrarySession = librarySessions.first
        }
        if let selected = selectedLibrarySession,
           let refreshed = librarySessions.first(where: { $0.id == selected.id }) {
            selectedLibrarySession = refreshed
        }
    }

    private func persistSettings() {
        try? settingsStore.save(settings)
    }

    /// 会话进入 success 时把草稿写盘一次；按 sessionID 去重，ticking 的重复状态回调不会二次写入。
    private var saveRetryTask: Task<Void, Never>?

    // Retries persist an immutable snapshot of the succeeded session, so a user
    // who abandons or starts a new session before the retry can never have the
    // wrong text saved or the new session's own save suppressed. One task, three
    // attempts, no rescheduling from inside the loop.
    private func scheduleSaveRetry(for id: UUID, snapshot: (text: String, elapsed: TimeInterval, duration: TimeInterval, wordCount: Int)) {
        saveRetryTask?.cancel()
        saveRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                if lastPersistedSessionID == id { return }
                do {
                    _ = try persistenceService.saveSuccessfulSession(
                        text: snapshot.text,
                        elapsed: snapshot.elapsed,
                        duration: snapshot.duration,
                        wordCount: snapshot.wordCount,
                        sessionID: id
                    )
                    lastPersistedSessionID = id
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private func persistSuccessfulSessionOnSuccess(_ phase: SessionPhase) {
        guard phase == .success else { return }
        let id = sessionEngine.sessionID
        guard lastPersistedSessionID != id else { return }
        let snapshot = (text: sessionEngine.text, elapsed: sessionEngine.elapsed, duration: sessionEngine.duration, wordCount: sessionEngine.wordCount)
        do {
            _ = try persistenceService.saveSuccessfulSession(
                text: snapshot.text,
                elapsed: snapshot.elapsed,
                duration: snapshot.duration,
                wordCount: snapshot.wordCount,
                sessionID: id
            )
            lastPersistedSessionID = id
        } catch {
            scheduleSaveRetry(for: id, snapshot: snapshot)
        }
    }

    private func launchInitialSurface() {
        selectedSurface = .home
    }

    var canNavigateToSupportSurface: Bool {
        switch sessionEngine.phase {
        case .idle, .failure:
            true
        case .writing, .danger, .success:
            false
        }
    }

    var trialSessionsRemaining: Int {
        guard settings.licenseStatus != .active else { return Self.trialSessionLimit }
        return max(0, Self.trialSessionLimit - settings.trialSessionsUsed)
    }

    var trialStatusText: String {
        switch settings.licenseStatus {
        case .active:
            return "License active."
        case .revoked:
            return "License revoked. Reactivate in Settings."
        case .invalid:
            return "License invalid. Reactivate in Settings."
        case .unknown:
            return "License status unknown. Reconnect to validate."
        case .trial:
            let used = min(Self.trialSessionLimit, settings.trialSessionsUsed)
            return "Mac trial: \(used) of \(Self.trialSessionLimit) sessions used."
        }
    }

    var isTrialExhausted: Bool {
        settings.licenseStatus != .active && trialSessionsRemaining == 0
    }

    private var canStartTrialSession: Bool {
        settings.licenseStatus == .active || settings.trialSessionsUsed < Self.trialSessionLimit
    }

    private func consumeTrialSessionIfNeeded() {
        guard settings.licenseStatus != .active else { return }
        settings.trialSessionsUsed += 1
        persistSettings()
    }

}
