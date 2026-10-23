/**
 * [INPUT]: 依赖 SessionEngine、SettingsStore、LicenseClient、CheckoutClient 管理应用状态
 * [OUTPUT]: 提供 Surface 与 AppState，三次会话试用、耗尽后的激活入口、配置驱动结账与 Waffo 签名 token 持久化
 * [POS]: 试用首个非空输入前持久扣次，失败后仅非空输入重启，空组字清理不重启；耗尽后拒绝启动先清空会话再进激活页且 canUseApp 为 false；已有许可记录不可回退试用；完整访问仍须订单号与合法签名 token；Home/Exit 清空草稿，锁定会话选择，Settings 返回原 surface
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
    static let trialSessionLimit = AppSettings.trialSessionLimit
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
    /// Public Mac page used when the hosted checkout request fails. This is the error fallback,
    /// never the in-app Buy action itself.
    static var checkoutURL: URL? { checkoutURL(in: configuration) }
    static func checkoutURL(in values: [String: Any]) -> URL? {
        guard let value = values["WIDCheckoutURL"] as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    static var configuredCheckoutClient: HostedCheckoutClient {
        HostedCheckoutClient(baseURL: (configuration["WIDLicenseServiceURL"] as? String).flatMap(URL.init(string:)))
    }
    /// 网络故障不延长签名 token 的七天有效期。
    static let licenseOfflineGraceInterval: TimeInterval = 7 * 24 * 60 * 60

    var selectedSurface: Surface = .home
    private var surfaceBeforeSettings: Surface = .home
    var selectedDuration: TimeInterval = SessionEngine.defaultDurationSeconds
    let sessionEngine: SessionEngine
    let settingsStore: SettingsStore
    let licenseClient: LicenseClient
    let checkoutClient: CheckoutClient
    let installIDStore: InstallIDStore
    let clock: () -> Date
    let productID: String
    let installLabel: String
    private let openExternalURL: (URL) -> Void
    var settings: AppSettings
    private(set) var licenseValidationInFlight = false
    private var activationRevision = 0
    private var validationRevision = 0
    private var chargedTrialSessionID: UUID?
    private(set) var trialAccessError: String?

    /// A local trial budget is not a license. Cached or revoked licenses never fall back to it.
    var trialSessionsRemaining: Int {
        guard trialAccessError == nil, licenseActivationError != .cleanupFailure,
              settings.licenseStatus == .inactive,
              !settings.hasLicenseKey, settings.licenseToken == nil,
              settings.licenseInstanceID == nil, settings.licenseProductID == nil,
              settings.licenseActivatedAt == nil, settings.licenseLastValidatedAt == nil else { return 0 }
        return max(0, Self.trialSessionLimit - settings.trialSessionsUsed)
    }

    var canStartSession: Bool { hasFullAccess || trialSessionsRemaining > 0 }
    var canUseApp: Bool {
        canStartSession || (chargedTrialSessionID == sessionEngine.sessionID && sessionEngine.hasStarted)
    }

    var accessStatusText: String {
        if hasFullAccess { return licenseStatusText }
        if let trialAccessError { return trialAccessError }
        if trialSessionsRemaining > 0 {
            return "Free trial: \(trialSessionsRemaining) of \(Self.trialSessionLimit) sessions left."
        }
        return licenseStatusText
    }

    var hasFullAccess: Bool {
        guard settings.licenseStatus == .active, settings.hasLicenseKey else { return false }
        return settings.licenseInstanceID != nil && !licenseValidationInFlight && !productID.isEmpty &&
            licenseClient.isConfigured && settings.licenseProductID == productID && licenseWithinGrace
    }

    /// UpgradeView / SettingsView 读取这些字段渲染激活状态。
    var licenseActivationInFlight = false
    var licenseActivationError: LicenseActivationError?
    var licenseActivationJustSucceeded = false
    private(set) var checkoutInFlight = false

    init(
        sessionEngine: SessionEngine = SessionEngine(),
        settingsStore: SettingsStore = SettingsStore(),
        licenseClient: LicenseClient = AppState.configuredLicenseClient,
        checkoutClient: CheckoutClient = AppState.configuredCheckoutClient,
        installIDStore: InstallIDStore = InstallIDStore(),
        clock: @escaping () -> Date = Date.init,
        productID: String = AppState.licenseProductID,
        openExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.sessionEngine = sessionEngine
        self.settingsStore = settingsStore
        self.licenseClient = licenseClient
        self.checkoutClient = checkoutClient
        self.installIDStore = installIDStore
        self.clock = clock
        self.productID = productID
        self.openExternalURL = openExternalURL
        self.installLabel = installIDStore.loadOrCreate().uuid.uuidString
        do {
            self.settings = try settingsStore.load()
        } catch {
            self.settings = .defaultValue
            self.settings.trialSessionsUsed = Self.trialSessionLimit
            self.trialAccessError = "Could not read trial usage. Check access to the app's settings and reopen the app."
        }
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
        guard canStartSession else {
            sessionEngine.abandon()
            selectedSurface = .upgrade
            return
        }

        let resolvedDuration = SessionEngine.validDuration(duration ?? selectedDuration)
        sessionEngine.start(duration: resolvedDuration, silenceLimit: settings.silenceLimit)
        selectedSurface = .session
    }

    func prepareSessionInput(isActivity: Bool = false) -> Bool {
        sessionEngine.tick()
        if sessionEngine.phase == .failure && isActivity {
            startSession(duration: sessionEngine.duration)
        }
        if sessionEngine.phase == .failure && !isActivity { return selectedSurface == .session }
        guard selectedSurface == .session, sessionIsRunning else { return false }
        if !sessionEngine.hasStarted && !hasFullAccess {
            guard canStartSession else {
                sessionEngine.abandon()
                selectedSurface = .upgrade
                return false
            }
            if isActivity && !chargeTrialSession() { return false }
        }
        return true
    }

    /// Reserve once before TextKit accepts the first committed or marked text.
    private func chargeTrialSession() -> Bool {
        guard chargedTrialSessionID != sessionEngine.sessionID else { return true }
        let previous = settings
        settings.trialSessionsUsed += 1
        do {
            try persistSettingsThrowing()
            chargedTrialSessionID = sessionEngine.sessionID
            return true
        } catch {
            settings = previous
            trialAccessError = "Could not save trial usage. Check access to the app's settings and reopen the app."
            sessionEngine.abandon()
            selectedSurface = .upgrade
            return false
        }
    }

    func goHome() {
        guard sessionEngine.phase != .success else { return }
        if sessionIsRunning || sessionEngine.phase == .failure {
            abandonSession()
        } else {
            selectedSurface = canUseApp ? .home : .upgrade
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
        guard canUseApp else {
            if !sessionEngine.hasStarted { selectedSurface = .upgrade }
            return
        }
        guard selectedSurface != .settings else { return }
        surfaceBeforeSettings = selectedSurface
        selectedSurface = .settings
    }

    func closeSettings() {
        sessionEngine.tick()
        selectedSurface = canUseApp ? surfaceBeforeSettings : .upgrade
    }

    func abandonSession() {
        sessionEngine.abandon()
        selectedSurface = canUseApp ? .home : .upgrade
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

    var checkoutAvailable: Bool { checkoutClient.isConfigured && Self.checkoutURL != nil }

    /// The host checkout is the purchase path; the public Mac page is the error fallback.
    /// Neither the hosted URL nor any buyer credential is logged.
    func openCheckout() async {
        guard !checkoutInFlight else { return }
        checkoutInFlight = true
        defer { checkoutInFlight = false }
        do {
            openExternalURL(try await checkoutClient.createCheckoutSession())
        } catch {
            if let fallback = Self.checkoutURL { openExternalURL(fallback) }
        }
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
        // Surrounding whitespace is paste noise, never part of the credential. Trim once at the
        // entry point so the empty check, cache comparison, request body and stored key agree.
        let licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
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
        if settings.licenseKey?.utf8.elementsEqual(licenseKey.utf8) == true, settings.licenseInstanceID != nil,
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
            let activation = try await licenseClient.activate(licenseKey: licenseKey, instanceName: installLabel)
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
            settings.licenseKey = licenseKey
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
        selectedSurface = canUseApp ? .home : .upgrade
    }

    var canNavigateToSupportSurface: Bool {
        guard canUseApp else { return false }
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
