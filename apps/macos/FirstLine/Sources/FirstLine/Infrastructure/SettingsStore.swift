/**
 * [INPUT]: 依赖 AppPaths.configDirectory 和 Codable 设置模型
 * [OUTPUT]: 提供 AppSettings、AppTheme、ReducedMotionOverride、SettingsStore，包含原生 trial 计数
 * [POS]: Infrastructure 设置层，负责默认值与 settings.json 持久化
 * [PROTOCOL]: 变更时更新此头部，然后检查 AGENTS.md
 */

import Foundation

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ReducedMotionOverride: String, Codable, CaseIterable, Identifiable {
    case system
    case always
    case never

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System Default"
        case .always: "Always Reduce"
        case .never: "Never Reduce"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var theme: AppTheme
    var defaultDuration: TimeInterval
    var reducedMotion: ReducedMotionOverride
    var trialSessionsUsed: Int

    /// v0.2 新增：结构化 license 状态。来自 Dodo activate / validate 调用。
    var licenseKey: String?
    var licenseStatus: LicenseStatus
    var licenseActivatedAt: Date?
    var licenseLastValidatedAt: Date?
    var licenseInstanceID: String?

    init(
        theme: AppTheme,
        defaultDuration: TimeInterval,
        reducedMotion: ReducedMotionOverride,
        trialSessionsUsed: Int = 0,
        hasUnlockedFullAccess: Bool = false,
        licenseKey: String? = nil,
        licenseStatus: LicenseStatus = .trial,
        licenseActivatedAt: Date? = nil,
        licenseLastValidatedAt: Date? = nil,
        licenseInstanceID: String? = nil
    ) {
        self.theme = theme
        self.defaultDuration = defaultDuration
        self.reducedMotion = reducedMotion
        self.trialSessionsUsed = trialSessionsUsed
        self.licenseKey = licenseKey
        self.licenseActivatedAt = licenseActivatedAt
        self.licenseLastValidatedAt = licenseLastValidatedAt
        self.licenseInstanceID = licenseInstanceID

        // 向后兼容：v0.1 的 hasUnlockedFullAccess=true 映射到 v0.2 的 licenseStatus=.active。
        // 显式传入 licenseStatus 时尊重调用方意图。
        if hasUnlockedFullAccess && licenseStatus == .trial {
            self.licenseStatus = .active
        } else {
            self.licenseStatus = licenseStatus
        }
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case defaultDuration
        case reducedMotion
        case trialSessionsUsed
        case hasUnlockedFullAccess
        case licenseKey
        case licenseStatus
        case licenseActivatedAt
        case licenseLastValidatedAt
        case licenseInstanceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decode(AppTheme.self, forKey: .theme)
        defaultDuration = try container.decode(TimeInterval.self, forKey: .defaultDuration)
        reducedMotion = try container.decode(ReducedMotionOverride.self, forKey: .reducedMotion)
        trialSessionsUsed = try container.decodeIfPresent(Int.self, forKey: .trialSessionsUsed) ?? 0
        let legacyUnlocked = try container.decodeIfPresent(Bool.self, forKey: .hasUnlockedFullAccess) ?? false
        licenseKey = try container.decodeIfPresent(String.self, forKey: .licenseKey)
        licenseActivatedAt = try container.decodeIfPresent(Date.self, forKey: .licenseActivatedAt)
        licenseLastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .licenseLastValidatedAt)
        licenseInstanceID = try container.decodeIfPresent(String.self, forKey: .licenseInstanceID)

        let decodedStatus = try container.decodeIfPresent(LicenseStatus.self, forKey: .licenseStatus) ?? .trial
        if legacyUnlocked && decodedStatus == .trial {
            licenseStatus = .active
        } else {
            licenseStatus = decodedStatus
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(defaultDuration, forKey: .defaultDuration)
        try container.encode(reducedMotion, forKey: .reducedMotion)
        try container.encode(trialSessionsUsed, forKey: .trialSessionsUsed)
        try container.encodeIfPresent(licenseKey, forKey: .licenseKey)
        try container.encode(licenseStatus, forKey: .licenseStatus)
        try container.encodeIfPresent(licenseActivatedAt, forKey: .licenseActivatedAt)
        try container.encodeIfPresent(licenseLastValidatedAt, forKey: .licenseLastValidatedAt)
        try container.encodeIfPresent(licenseInstanceID, forKey: .licenseInstanceID)
    }

    static let defaultValue = AppSettings(
        theme: .system,
        defaultDuration: SessionEngine.defaultDurationSeconds,
        reducedMotion: .system,
        trialSessionsUsed: 0,
        licenseKey: nil,
        licenseStatus: .trial,
        licenseActivatedAt: nil,
        licenseLastValidatedAt: nil,
        licenseInstanceID: nil
    )
}

struct SettingsStore {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let configDirectory: URL

    init(fileManager: FileManager = .default, configDirectory: URL = AppPaths.configDirectory) {
        self.fileManager = fileManager
        self.configDirectory = configDirectory
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    private var settingsFileURL: URL {
        configDirectory.appendingPathComponent("settings.json")
    }

    func load() throws -> AppSettings {
        guard fileManager.fileExists(atPath: settingsFileURL.path) else {
            return .defaultValue
        }

        let data = try Data(contentsOf: settingsFileURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    func save(_ settings: AppSettings) throws {
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: settingsFileURL, options: .atomic)
    }
}
