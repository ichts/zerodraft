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
    var selectedDuration: TimeInterval = 300
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
        self.selectedDuration = self.settings.defaultDuration

        refreshLibrary()
        launchInitialSurface()
    }

    func startSession(duration: TimeInterval? = nil) {
        guard sessionEngine.phase != .success else { return }
        guard canStartTrialSession else {
            selectedSurface = .upgrade
            return
        }

        consumeTrialSessionIfNeeded()
        let resolvedDuration = duration ?? selectedDuration
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
            startSession(duration: selectedDuration)
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
