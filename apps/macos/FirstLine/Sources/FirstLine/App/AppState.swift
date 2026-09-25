/**
 * [INPUT]: 依赖 SessionEngine、SettingsStore、LicenseClient 管理应用状态
 * [OUTPUT]: 提供 Surface 枚举与 AppState 状态容器，首输入 trial gate、配置驱动结账与产品限定的 license 持久化
 * [POS]: 导航及 trial gate；启动校验前限制缓存许可；Home/Exit 清空运行中草稿，锁定运行中的时长/静默阈值，Settings 返回原 surface
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import Foundation
import AppKit

enum Surface: String, CaseIterable, Hashable, Identifiable {
    case home = "Home"
    case session = "Session"
    case settings = "Settings"
    case upgrade = "Upgrade"

    var id: String { rawValue }

    static let navigationCases: [Surface] = [.home, .session, .settings]
}

@MainActor
@Observable
final class AppState {
    static let trialSessionLimit = 3
    static let configurationURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Info.plist")
    private static var configuration: [String: Any] {
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.infoDictionary ?? [:] }
        return (NSDictionary(contentsOf: configurationURL) as? [String: Any]) ?? [:]
    }
    static var displayPrice: String { configuration["WIDDisplayPrice"] as? String ?? "" }
    static var dodoProductID: String { configuration["WIDDodoProductID"] as? String ?? "" }
    static var checkoutURL: URL? { checkoutURL(in: configuration) }
    static func checkoutURL(in values: [String: Any]) -> URL? {
        guard let value = values["WIDCheckoutURL"] as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    /// Dodo validate 不可达时，仍把 license 视作 active 的最长宽限期。
    static let licenseOfflineGraceInterval: TimeInterval = 7 * 24 * 60 * 60

    var selectedSurface: Surface = .home
    private var surfaceBeforeSettings: Surface = .home
    var selectedDuration: TimeInterval = SessionEngine.defaultDurationSeconds
    let sessionEngine: SessionEngine
    let settingsStore: SettingsStore
    let licenseClient: LicenseClient
    let installIDStore: InstallIDStore
    let clock: () -> Date
    let productID: String
    var settings: AppSettings
    private(set) var licenseValidationInFlight = false
    private var activationRevision = 0

    var hasFullAccess: Bool {
        guard settings.licenseStatus == .active else { return false }
        if settings.licenseKey == nil { return true }
        return !licenseValidationInFlight && !productID.isEmpty && settings.licenseProductID == productID
    }

    /// UpgradeView / SettingsView 读取这些字段渲染激活状态。
    var licenseActivationInFlight = false
    var licenseActivationError: LicenseActivationError?
    var licenseActivationJustSucceeded = false

    init(
        sessionEngine: SessionEngine = SessionEngine(),
        settingsStore: SettingsStore = SettingsStore(),
        licenseClient: LicenseClient = MockLicenseClient(),
        installIDStore: InstallIDStore = InstallIDStore(),
        clock: @escaping () -> Date = Date.init,
        productID: String = AppState.dodoProductID
    ) {
        self.sessionEngine = sessionEngine
        self.settingsStore = settingsStore
        self.licenseClient = licenseClient
        self.installIDStore = installIDStore
        self.clock = clock
        self.productID = productID
        self.settings = (try? settingsStore.load()) ?? .defaultValue
        self.licenseValidationInFlight = (settings.licenseStatus == .active || settings.licenseStatus == .unknown) && settings.licenseKey != nil
        self.selectedDuration = settings.defaultDuration

        launchInitialSurface()

        // onStateChange 由 @MainActor 的 engine 方法触发，覆盖 timer 与编辑器两条状态迁移路径。
        sessionEngine.onStateChange = { [weak self] phase in
            MainActor.assumeIsolated {
                self?.handleEngineStateChange(phase)
            }
        }
    }

    func startSession(duration: TimeInterval? = nil) {
        guard sessionEngine.phase != .success && !sessionIsRunning else { return }
        guard canStartTrialSession else {
            selectedSurface = .upgrade
            return
        }

        let resolvedDuration = SessionEngine.validDuration(duration ?? selectedDuration)
        sessionEngine.start(duration: resolvedDuration, silenceLimit: settings.silenceLimit)
        selectedSurface = .session
    }

    func consumeTrialOnFirstInput() {
        guard sessionEngine.hasStarted, chargedSessionID != sessionEngine.sessionID else { return }
        chargedSessionID = sessionEngine.sessionID
        consumeTrialSessionIfNeeded()
    }

    private var chargedSessionID: UUID?

    func prepareSessionInput() -> Bool {
        sessionEngine.tick()
        if sessionEngine.phase == .failure {
            startSession(duration: sessionEngine.duration)
        }
        return selectedSurface == .session &&
            (sessionEngine.phase == .writing || sessionEngine.phase == .danger)
    }

    func goHome() {
        guard sessionEngine.phase != .success else { return }
        if sessionIsRunning {
            abandonSession()
        } else {
            selectedSurface = .home
        }
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
        guard selectedSurface != .settings else { return }
        surfaceBeforeSettings = selectedSurface
        selectedSurface = .settings
    }

    func closeSettings() {
        sessionEngine.tick()
        selectedSurface = surfaceBeforeSettings
    }

    func abandonSession() {
        sessionEngine.abandon()
        selectedSurface = .home
    }

    func handleTick() {
        // Engine phase routing runs synchronously through onStateChange.
        sessionEngine.tick()
    }

    func updateTheme(_ theme: AppTheme) {
        settings.theme = theme
        persistSettings()
    }

    var sessionIsRunning: Bool {
        sessionEngine.phase == .writing || sessionEngine.phase == .danger
    }

    func updateDefaultDuration(_ duration: TimeInterval) {
        guard !sessionIsRunning else { return }
        settings.defaultDuration = SessionEngine.validDuration(duration)
        selectedDuration = settings.defaultDuration
        persistSettings()
    }

    func updateSilenceLimit(_ limit: SilenceLimit) {
        guard !sessionIsRunning else { return }
        settings.silenceLimit = limit
        persistSettings()
    }

    func updateFocusMode(_ enabled: Bool) {
        settings.focusMode = enabled
        persistSettings()
    }

    func updateAlignment(_ alignment: WritingAlignment) {
        settings.writingAlignment = alignment
        persistSettings()
    }

    func updateFontSize(_ size: WritingFontSize) {
        settings.writingFontSize = size
        persistSettings()
    }

    func newPiece() {
        sessionEngine.abandon()
        startSession(duration: selectedDuration)
    }

    func updateReducedMotion(_ option: ReducedMotionOverride) {
        settings.reducedMotion = option
        persistSettings()
    }

    func openCheckout() {
        guard let url = Self.checkoutURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openLicenseHelp() {
        guard let url = URL(string: "https://writeitdown.app/support.html") else { return }
        NSWorkspace.shared.open(url)
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

        guard !productID.isEmpty else {
            licenseActivationError = .productNotConfigured
            return
        }
        let instanceName = installIDStore.loadOrCreate().shortName
        do {
            let activation = try await licenseClient.activate(licenseKey: trimmed, instanceName: instanceName)
            guard activation.productID == productID else {
                licenseActivationError = .wrongProduct
                return
            }
            // Snapshot the pre-activation state so a failed persist cannot leave the
            // app granting access that is not durable on disk.
            let preActivation = settings
            settings.licenseKey = trimmed
            settings.licenseStatus = .active
            settings.licenseInstanceID = activation.instanceID
            settings.licenseProductID = productID
            settings.licenseActivatedAt = clock()
            settings.licenseLastValidatedAt = clock()
            do {
                try persistSettingsThrowing()
                activationRevision += 1
                licenseValidationInFlight = false
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
        guard settings.licenseStatus == .active || settings.licenseStatus == .unknown,
              let key = settings.licenseKey else { return }
        licenseValidationInFlight = true
        let revision = activationRevision
        defer {
            if activationRevision == revision { licenseValidationInFlight = false }
        }
        guard !productID.isEmpty, settings.licenseProductID == productID else { return }

        do {
            let valid = try await licenseClient.validate(licenseKey: key)
            guard activationRevision == revision, settings.licenseKey == key,
                  settings.licenseProductID == productID else { return }
            if valid {
                settings.licenseStatus = .active
                settings.licenseLastValidatedAt = clock()
                persistSettings()
            } else {
                applyRevokedState()
            }
        } catch {
            guard activationRevision == revision, settings.licenseKey == key,
                  settings.licenseProductID == productID else { return }
            applyOfflineGraceDecision()
        }
    }

    private func applyRevokedState() {
        settings.licenseStatus = .revoked
        persistSettings()
    }

    private func applyOfflineGraceDecision() {
        let last = settings.licenseLastValidatedAt ?? settings.licenseActivatedAt
        guard let last else {
            settings.licenseStatus = .unknown
            persistSettings()
            return
        }
        if clock().timeIntervalSince(last) > Self.licenseOfflineGraceInterval {
            settings.licenseStatus = .unknown
            persistSettings()
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

    /// Central engine state observer: routes an expired empty session home.
    private func handleEngineStateChange(_ phase: SessionPhase) {
        switch phase {
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

    /// 跟踪 engine 上一次的 phase，用于在状态回调里识别 live->idle 转换并集中路由 Home。
    private var previousEnginePhase: SessionPhase = .idle

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
        guard !hasFullAccess else { return Self.trialSessionLimit }
        return max(0, Self.trialSessionLimit - settings.trialSessionsUsed)
    }

    var trialStatusText: String {
        if licenseValidationInFlight { return "Checking license..." }
        if settings.licenseStatus == .active && !hasFullAccess {
            return "License does not match the configured writeitdown product."
        }
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
        !hasFullAccess && trialSessionsRemaining == 0
    }

    private var canStartTrialSession: Bool {
        hasFullAccess || settings.trialSessionsUsed < Self.trialSessionLimit
    }

    private func consumeTrialSessionIfNeeded() {
        guard !hasFullAccess else { return }
        settings.trialSessionsUsed += 1
        persistSettings()
    }

}
