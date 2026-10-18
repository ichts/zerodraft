/**
 * [INPUT]: 依赖 AppPaths.configDirectory 和 Codable 设置模型
 * [OUTPUT]: AppSettings、时长/静默限额及外观/专注/排印选择、SettingsStore；含许可产品身份和签名 token 缓存，忽略旧试用计数
 * [POS]: 配置层；合法时长校验、忽略旧解锁标记，无非空白 key 的 active 降为 inactive；旧 trial 状态与计数不授予访问；写作偏好和 license 数据落盘，正文绝不落盘
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

enum SilenceLimit: Int, Codable, CaseIterable {
    case strict = 5, standard = 8, relaxed = 12
    var label: String {
        switch self {
        case .strict: "Strict - 5s"
        case .standard: "Standard - 8s"
        case .relaxed: "Relaxed - 12s"
        }
    }
}

enum WritingAlignment: String, Codable, CaseIterable {
    case centered, left
    var label: String { self == .centered ? "Centered narrow" : "Left wide" }
}

enum WritingFontSize: String, Codable, CaseIterable {
    case small, medium, large
    var label: String { rawValue.capitalized }
    var points: CGFloat {
        switch self {
        case .small: 23
        case .medium: 28
        case .large: 34
        }
    }
}

struct AppSettings: Codable, Equatable {
    var theme: AppTheme
    var defaultDuration: TimeInterval
    var reducedMotion: ReducedMotionOverride
    var silenceLimit: SilenceLimit
    var focusMode: Bool
    var writingAlignment: WritingAlignment
    var writingFontSize: WritingFontSize

    /// licenseKey 保留历史字段名，当前保存 Waffo 订单号；无 token 的旧缓存不授予访问。
    var licenseKey: String?
    var licenseStatus: LicenseStatus
    var licenseActivatedAt: Date?
    var licenseLastValidatedAt: Date?
    var licenseInstanceID: String?
    var licenseProductID: String?
    var licenseToken: String?

    var hasLicenseKey: Bool {
        licenseKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    init(
        theme: AppTheme,
        defaultDuration: TimeInterval,
        reducedMotion: ReducedMotionOverride,
        silenceLimit: SilenceLimit = .standard,
        focusMode: Bool = false,
        writingAlignment: WritingAlignment = .centered,
        writingFontSize: WritingFontSize = .medium,
        licenseKey: String? = nil,
        licenseStatus: LicenseStatus = .inactive,
        licenseActivatedAt: Date? = nil,
        licenseLastValidatedAt: Date? = nil,
        licenseInstanceID: String? = nil,
        licenseProductID: String? = nil,
        licenseToken: String? = nil
    ) {
        self.theme = theme
        self.defaultDuration = SessionEngine.validDuration(defaultDuration)
        self.reducedMotion = reducedMotion
        self.silenceLimit = silenceLimit
        self.focusMode = focusMode
        self.writingAlignment = writingAlignment
        self.writingFontSize = writingFontSize
        self.licenseKey = licenseKey
        self.licenseActivatedAt = licenseActivatedAt
        self.licenseLastValidatedAt = licenseLastValidatedAt
        self.licenseInstanceID = licenseInstanceID
        self.licenseProductID = licenseProductID
        self.licenseToken = licenseToken

        self.licenseStatus = licenseStatus
        if licenseStatus == .active && !hasLicenseKey {
            self.licenseStatus = .inactive
        }
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case defaultDuration
        case reducedMotion
        case silenceLimit, focusMode, writingAlignment, writingFontSize
        case licenseKey
        case licenseStatus
        case licenseActivatedAt
        case licenseLastValidatedAt
        case licenseInstanceID
        case licenseProductID, licenseToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decode(AppTheme.self, forKey: .theme)
        defaultDuration = SessionEngine.validDuration((try? container.decode(TimeInterval.self, forKey: .defaultDuration)) ?? SessionEngine.defaultDurationSeconds)
        reducedMotion = try container.decode(ReducedMotionOverride.self, forKey: .reducedMotion)
        silenceLimit = (try? container.decode(SilenceLimit.self, forKey: .silenceLimit)) ?? .standard
        focusMode = (try? container.decode(Bool.self, forKey: .focusMode)) ?? false
        writingAlignment = (try? container.decode(WritingAlignment.self, forKey: .writingAlignment)) ?? .centered
        writingFontSize = (try? container.decode(WritingFontSize.self, forKey: .writingFontSize)) ?? .medium
        licenseKey = try container.decodeIfPresent(String.self, forKey: .licenseKey)
        licenseActivatedAt = try container.decodeIfPresent(Date.self, forKey: .licenseActivatedAt)
        licenseLastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .licenseLastValidatedAt)
        licenseInstanceID = try container.decodeIfPresent(String.self, forKey: .licenseInstanceID)
        licenseProductID = try container.decodeIfPresent(String.self, forKey: .licenseProductID)
        licenseToken = try container.decodeIfPresent(String.self, forKey: .licenseToken)

        licenseStatus = try container.decodeIfPresent(LicenseStatus.self, forKey: .licenseStatus) ?? .inactive
        if licenseStatus == .active && !hasLicenseKey {
            licenseStatus = .inactive
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(SessionEngine.validDuration(defaultDuration), forKey: .defaultDuration)
        try container.encode(reducedMotion, forKey: .reducedMotion)
        try container.encode(silenceLimit, forKey: .silenceLimit)
        try container.encode(focusMode, forKey: .focusMode)
        try container.encode(writingAlignment, forKey: .writingAlignment)
        try container.encode(writingFontSize, forKey: .writingFontSize)
        try container.encodeIfPresent(licenseKey, forKey: .licenseKey)
        try container.encode(licenseStatus, forKey: .licenseStatus)
        try container.encodeIfPresent(licenseActivatedAt, forKey: .licenseActivatedAt)
        try container.encodeIfPresent(licenseLastValidatedAt, forKey: .licenseLastValidatedAt)
        try container.encodeIfPresent(licenseInstanceID, forKey: .licenseInstanceID)
        try container.encodeIfPresent(licenseProductID, forKey: .licenseProductID)
        try container.encodeIfPresent(licenseToken, forKey: .licenseToken)
    }

    static let defaultValue = AppSettings(
        theme: .system,
        defaultDuration: SessionEngine.defaultDurationSeconds,
        reducedMotion: .system,
        licenseKey: nil,
        licenseStatus: .inactive,
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
