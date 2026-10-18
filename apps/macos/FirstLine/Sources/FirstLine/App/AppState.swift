/**
 * [INPUT]: 依赖 SessionEngine、SettingsStore、LicenseClient 管理应用状态
 * [OUTPUT]: 提供 Surface 枚举与 AppState 状态容器，activation-first 入口、配置驱动结账与 Waffo 签名 token 持久化
 * [POS]: 导航及付费许可门槛；active 必须有订单号及合法签名 token，满足产品/设备/实例/时限门槛；Home/Exit 清空运行中草稿，锁定运行中的时长/静默阈值，Settings 返回原 surface
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
    static let configurationURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Info.plist")
    private static var configuration: [String: Any] {
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.infoDictionary ?? [:] }
        return (NSDictionary(contentsOf: configurationURL) as? [String: Any]) ?? [:]
    }
    static var displayPrice: String { configuration["WIDDisplayPrice"] as? String ?? "" }
    static var licenseProductID: String { configuration["WIDLicenseProductID"] as? String ?? "" }
    static var configuredLicenseClient: WaffoLicenseClient {
        WaffoLicenseClient(baseURL: (configuration["WIDLicenseServiceURL"] as? String).flatMap(URL.init(string:)),
                           productID: licenseProductID,
                           publicKey: Data(base64Encoded: configuration["WIDLicensePublicKey"] as? String ?? "") ?? Data())
    }
    static let webTrialURL = URL(string: "https://writeitdown.app/")!
    static var checkoutURL: URL? { checkoutURL(in: configuration) }
    static func checkoutURL(in values: [String: Any]) -> URL? {
        guard let value = values["WIDCheckoutURL"] as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    /// 网络故障不延长签名 token 的七天有效期。
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
    let installLabel: String
    private let openExternalURL: (URL) -> Void
    var settings: AppSettings
    private(set) var licenseValidationInFlight = false
    private var activationRevision = 0
    private var validationRevision = 0

    var hasFullAccess: Bool {
        guard settings.licenseStatus == .active, settings.hasLicenseKey else { return false }
        return settings.licenseInstanceID != nil && !licenseValidationInFlight && !productID.isEmpty &&
            licenseClient.isConfigured && settings.licenseProductID == productID && licenseWithinGrace
    }

    /// UpgradeView / SettingsView 读取这些字段渲染激活状态。
    var licenseActivationInFlight = false
    var licenseActivationError: LicenseActivationError?
    var licenseActivationJustSucceeded = false

    init(
        sessionEngine: SessionEngine = SessionEngine(),
        settingsStore: SettingsStore = SettingsStore(),
        licenseClient: LicenseClient = AppState.configuredLicenseClient,
        installIDStore: InstallIDStore = InstallIDStore(),
        clock: @escaping () -> Date = Date.init,
        productID: String = AppState.licenseProductID,
        openExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.sessionEngine = sessionEngine
        self.settingsStore = settingsStore
        self.licenseClient = licenseClient
        self.installIDStore = installIDStore
        self.clock = clock
        self.productID = productID
        self.openExternalURL = openExternalURL
        self.installLabel = installIDStore.loadOrCreate().uuid.uuidString
        self.settings = (try? settingsStore.load()) ?? .defaultValue
        self.licenseValidationInFlight = (settings.licenseStatus == .active || settings.licenseStatus == .unknown) &&
            settings.hasLicenseKey && settings.licenseInstanceID != nil
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
        guard hasFullAccess else {
            selectedSurface = .upgrade
            return
        }

        let resolvedDuration = SessionEngine.validDuration(duration ?? selectedDuration)
        sessionEngine.start(duration: resolvedDuration, silenceLimit: settings.silenceLimit)
        selectedSurface = .session
    }

    func prepareSessionInput() -> Bool {
        sessionEngine.tick()
        if !sessionEngine.hasStarted && !hasFullAccess {
            sessionEngine.abandon()
            selectedSurface = .upgrade
            return false
        }
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
            selectedSurface = hasFullAccess ? .home : .upgrade
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
        guard hasFullAccess else {
            if !sessionEngine.hasStarted { selectedSurface = .upgrade }
            return
        }
        guard selectedSurface != .settings else { return }
        surfaceBeforeSettings = selectedSurface
        selectedSurface = .settings
    }

    func closeSettings() {
        sessionEngine.tick()
        selectedSurface = hasFullAccess ? surfaceBeforeSettings : .upgrade
    }

    func abandonSession() {
        sessionEngine.abandon()
        selectedSurface = hasFullAccess ? .home : .upgrade
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
        openExternalURL(url)
    }

    func openWebTrial() {
        openExternalURL(Self.webTrialURL)
    }

    func openLicenseHelp() {
        guard let url = URL(string: "https://writeitdown.app/support.html") else { return }
        openExternalURL(url)
    }

    func activateLicense(key: String) async {
        guard !licenseActivationInFlight else { return }
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            licenseActivationError = .emptyKey
            return
        }
        licenseActivationInFlight = true
        licenseActivationError = nil
        licenseActivationJustSucceeded = false
        defer { licenseActivationInFlight = false }

        guard !productID.isEmpty, licenseClient.isConfigured else {
            licenseActivationError = .productNotConfigured
            return
        }
        if settings.licenseKey?.utf8.elementsEqual(key.utf8) == true, settings.licenseInstanceID != nil,
           settings.licenseToken != nil, settings.licenseProductID == productID {
            switch await validateLicenseIfNeeded(allowInactive: true) {
            case true: return
            case nil:
                licenseActivationError = .networkFailure
                return
            case false:
                settings.licenseInstanceID = nil
                persistSettings()
            }
        }
        do {
            let activation = try await licenseClient.activate(licenseKey: key, instanceName: installLabel)
            guard activation.productID == productID else {
                await rejectActivation(activation, reason: .wrongProduct)
                return
            }
            guard licenseClient.permitsAccess(token: activation.token, instanceID: activation.instanceID,
                                               installLabel: installLabel, now: clock()) else {
                licenseActivationError = .invalidToken
                return
            }
            // Snapshot the pre-activation state so a failed persist cannot leave the
            // app granting access that is not durable on disk.
            let preActivation = settings
            settings.licenseKey = key
            settings.licenseStatus = .active
            settings.licenseInstanceID = activation.instanceID
            settings.licenseProductID = productID
            settings.licenseToken = activation.token
            settings.licenseActivatedAt = clock()
            settings.licenseLastValidatedAt = clock()
            do {
                try persistSettingsThrowing()
                activationRevision += 1
                licenseValidationInFlight = false
                licenseActivationJustSucceeded = true
            } catch {
                settings = preActivation
                await rejectActivation(activation, reason: .storageFailure)
            }
        } catch let activationError as LicenseActivationError {
            licenseActivationError = activationError
        } catch {
            licenseActivationError = .unexpected(statusCode: -1)
        }
    }

    private func rejectActivation(_ activation: LicenseActivation, reason: LicenseActivationError) async {
        guard activation.instanceID != settings.licenseInstanceID else {
            licenseActivationError = reason
            return
        }
        do {
            try await licenseClient.deactivate(token: activation.token)
            licenseActivationError = reason
        } catch {
            licenseActivationError = .cleanupFailure
        }
    }

    func clearLicenseActivationError() {
        licenseActivationError = nil
    }

    func dismissLicenseSuccessFeedback() {
        licenseActivationJustSucceeded = false
    }

    @discardableResult
    func validateLicenseIfNeeded(allowInactive: Bool = false) async -> Bool? {
        guard settings.licenseStatus == .active || settings.licenseStatus == .unknown ||
              (allowInactive && (settings.licenseStatus == .revoked || settings.licenseStatus == .invalid)),
              settings.hasLicenseKey,
              let key = settings.licenseKey, let instanceID = settings.licenseInstanceID else { return nil }
        licenseValidationInFlight = true
        validationRevision += 1
        let requestRevision = validationRevision
        let revision = activationRevision
        defer {
            if activationRevision == revision && validationRevision == requestRevision {
                licenseValidationInFlight = false
                if !licenseActivationInFlight {
                    if hasFullAccess && selectedSurface == .upgrade {
                        selectedSurface = .home
                    } else if !hasFullAccess && !sessionEngine.hasStarted {
                        sessionEngine.abandon()
                        selectedSurface = .upgrade
                    }
                }
            }
        }
        guard !productID.isEmpty, licenseClient.isConfigured,
              settings.licenseProductID == productID, let token = settings.licenseToken else { return nil }

        do {
            let renewedToken = try await licenseClient.validate(token: token)
            guard activationRevision == revision, validationRevision == requestRevision,
                  settings.licenseKey == key, settings.licenseInstanceID == instanceID,
                  settings.licenseProductID == productID else { return nil }
            guard let renewedToken else {
                applyRevokedState()
                return false
            }
            guard licenseClient.permitsAccess(token: renewedToken, instanceID: instanceID,
                                               installLabel: installLabel, now: clock()) else {
                settings.licenseStatus = .invalid
                persistSettings()
                return false
            }
            let previous = settings
            settings.licenseStatus = .active
            settings.licenseToken = renewedToken
            settings.licenseLastValidatedAt = clock()
            do { try persistSettingsThrowing() }
            catch {
                settings = previous
                licenseActivationError = .storageFailure
                return nil
            }
            return true
        } catch {
            guard activationRevision == revision, validationRevision == requestRevision,
                  settings.licenseKey == key, settings.licenseInstanceID == instanceID,
                  settings.licenseProductID == productID else { return nil }
            if (error as? LicenseValidationError) == .networkFailure {
                applyOfflineGraceDecision()
            } else {
                settings.licenseStatus = .invalid
                persistSettings()
            }
            return nil
        }
    }

    private func applyRevokedState() {
        settings.licenseStatus = .revoked
        persistSettings()
    }

    private var licenseWithinGrace: Bool {
        guard let token = settings.licenseToken, let instanceID = settings.licenseInstanceID,
              let last = settings.licenseLastValidatedAt ?? settings.licenseActivatedAt else { return false }
        let age = clock().timeIntervalSince(last)
        return age >= -60 && age < Self.licenseOfflineGraceInterval &&
            licenseClient.permitsAccess(token: token, instanceID: instanceID, installLabel: installLabel, now: clock())
    }

    private func applyOfflineGraceDecision() {
        if !licenseWithinGrace {
            settings.licenseStatus = .unknown
            persistSettings()
        }
    }

    private func persistSettings() {
        try? settingsStore.save(settings)
    }

    /// Activation and renewal must not claim durable success after a failed write.
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
        selectedSurface = hasFullAccess ? .home : .upgrade
    }

    var canNavigateToSupportSurface: Bool {
        guard hasFullAccess else { return false }
        switch sessionEngine.phase {
        case .idle, .failure:
            return true
        case .writing, .danger, .success:
            return false
        }
    }

    var licenseStatusText: String {
        if licenseValidationInFlight { return "Checking license..." }
        if settings.licenseKey != nil && settings.licenseInstanceID == nil {
            return "License not activated on this Mac. Enter your order number or activation code."
        }
        if settings.licenseStatus == .active && !hasFullAccess {
            if settings.licenseKey != nil && !productID.isEmpty &&
                settings.licenseProductID == productID && !licenseWithinGrace {
                return "License needs online validation. Reopen the app when connected."
            }
            return "License does not match the configured writeitdown product."
        }
        switch settings.licenseStatus {
        case .active:
            return "License active."
        case .revoked:
            return "License revoked. Enter a valid order number or activation code."
        case .invalid:
            return "License invalid. Activate this Mac again."
        case .unknown:
            return "License status unknown. Reconnect to validate."
        case .inactive:
            return "Activate this Mac to start writing."
        }
    }

}
