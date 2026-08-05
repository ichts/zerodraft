/**
 * [INPUT]: 依赖 SessionEngine、PersistenceService、SettingsStore 管理应用状态
 * [OUTPUT]: 提供 Surface 枚举与 AppState 状态容器，包含原生 3-session trial gate、durable wipe aftermath、按 sessionID 分开的保存重试与可验证的 license 持久化
 * [POS]: FirstLine 顶层导航真相源，负责从 Home 启动 session、消耗 trial 与支持面跳转
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import Foundation
import AppKit

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

    /// Durable aftermath of the most recent wipe: the first ~64 chars (whitespace
    /// collapsed) of the lost draft, shown on Home until the next session starts.
    var lastWipeFossil: String?

    /// 已写盘的 sessionID，确保每场成功 session 只调用一次 saveSuccessfulSession，防止 ticking 重复触发。
    private var lastPersistedSessionID: UUID?
    /// Per-attempt delay for save retries. Defaults to 1s; tests inject a small
    /// value so retry behaviour is verifiable without wall-clock waits.
    private let saveRetryDelayNanoseconds: UInt64

    init(
        sessionEngine: SessionEngine = SessionEngine(),
        persistenceService: PersistenceService = PersistenceService(),
        settingsStore: SettingsStore = SettingsStore(),
        licenseClient: LicenseClient = MockLicenseClient(),
        installIDStore: InstallIDStore = InstallIDStore(),
        clock: @escaping () -> Date = Date.init,
        saveRetryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.sessionEngine = sessionEngine
        self.persistenceService = persistenceService
        self.settingsStore = settingsStore
        self.licenseClient = licenseClient
        self.installIDStore = installIDStore
        self.clock = clock
        self.saveRetryDelayNanoseconds = saveRetryDelayNanoseconds
        self.settings = (try? settingsStore.load()) ?? .defaultValue
        // Fixed 60s contract: legacy persisted durations are superseded by the engine constant.
        self.selectedDuration = SessionEngine.defaultDurationSeconds
        if settings.defaultDuration != SessionEngine.defaultDurationSeconds {
            settings.defaultDuration = SessionEngine.defaultDurationSeconds
        }

        refreshLibrary()
        launchInitialSurface()

        // onStateChange 由 @MainActor 的 engine 方法触发，始终运行在主线程；用它观察 success/failure 迁移可同时覆盖 timer 与编辑器两条触发路径。
        sessionEngine.onStateChange = { [weak self] phase in
            MainActor.assumeIsolated {
                self?.handleEngineStateChange(phase)
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
        // Starting fresh clears the durable wipe aftermath from Home.
        lastWipeFossil = nil
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
        // Central routing and persistence live in handleEngineStateChange (the
        // engine's onStateChange callback), which fires synchronously inside tick()
        // on every phase transition. This keeps tick() a pure passthrough.
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
            // Snapshot the pre-activation state so a failed persist cannot leave the
            // app granting access that is not durable on disk.
            let preActivation = settings
            settings.licenseKey = trimmed
            settings.licenseStatus = .active
            settings.licenseInstanceID = activation.instanceID
            settings.licenseActivatedAt = clock()
            settings.licenseLastValidatedAt = clock()
            settings.hasUnlockedFullAccess = true
            do {
                try persistSettingsThrowing()
                licenseActivationJustSucceeded = true
            } catch {
                settings = preActivation
                licenseActivationError = .storageFailure
            }
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

    /// License activation is the one path that must not silently claim success
    /// when the on-disk write failed.
    private func persistSettingsThrowing() throws {
        try settingsStore.save(settings)
    }

    /// Central engine state observer: persists on success, captures the durable
    /// wipe aftermath on failure.
    private func handleEngineStateChange(_ phase: SessionPhase) {
        switch phase {
        case .success:
            persistSuccessfulSessionOnSuccess(phase)
        case .failure:
            captureWipeAftermath()
        case .idle:
            // engine 的 live->idle 转换（空草稿触达完成截止 / 迟到首输入在截止后被裁决为
            // idle）必须在状态回调里集中路由 Home，否则用户会卡在死掉的 Session 界面。
            if previousEnginePhase == .writing || previousEnginePhase == .danger {
                goHome()
            }
        default:
            break
        }
        previousEnginePhase = phase
    }

    private func captureWipeAftermath() {
        let collapsed = sessionEngine.wipedText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        lastWipeFossil = collapsed.isEmpty ? nil : String(collapsed.prefix(64))
    }

    /// 跟踪 engine 上一次的 phase，用于在状态回调里识别 live->idle 转换并集中路由 Home。
    private var previousEnginePhase: SessionPhase = .idle

    /// 会话进入 success 时把草稿写盘一次；按 sessionID 去重，ticking 的重复状态回调不会二次写入。
    private var saveRetryTasks: [UUID: Task<Void, Never>] = [:]

    // Retries persist an immutable snapshot of the succeeded session, so a user
    // who abandons or starts a new session before the retry can never have the
    // wrong text saved or the new session's own save suppressed. Retry tasks are
    // keyed per sessionID so concurrent sessions' retries never cancel each other.
    // Three attempts each, no rescheduling from inside the loop.
    private func scheduleSaveRetry(for id: UUID, snapshot: (text: String, elapsed: TimeInterval, duration: TimeInterval, wordCount: Int)) {
        saveRetryTasks[id]?.cancel()
        saveRetryTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: self.saveRetryDelayNanoseconds)
                if Task.isCancelled { return }
                if lastPersistedSessionID == id {
                    saveRetryTasks[id] = nil
                    return
                }
                do {
                    _ = try persistenceService.saveSuccessfulSession(
                        text: snapshot.text,
                        elapsed: snapshot.elapsed,
                        duration: snapshot.duration,
                        wordCount: snapshot.wordCount,
                        sessionID: id
                    )
                    lastPersistedSessionID = id
                    saveRetryTasks[id] = nil
                    return
                } catch {
                    continue
                }
            }
            saveRetryTasks[id] = nil
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
            // 直接成功取代了任何已在排队的重试 task；取消并清理，否则完成的 task 会残留在字典里
            //（它在 lastPersistedSessionID == id 检查处 return 但不清理自己的条目）。
            saveRetryTasks[id]?.cancel()
            saveRetryTasks[id] = nil
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
