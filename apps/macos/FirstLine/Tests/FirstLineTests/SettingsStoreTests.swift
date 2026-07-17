import Foundation
import Testing
@testable import FirstLine

struct SettingsStoreTests {
    @Test
    func settingsRoundTrip() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        let settings = AppSettings(theme: .dark, defaultDuration: 600, immersiveSessionMode: true, reducedMotion: .always)

        try store.save(settings)
        let loaded = try store.load()

        #expect(loaded == settings)
    }

    @Test
    func settingsDefaultWhenFileMissing() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        let loaded = try store.load()

        #expect(loaded == .defaultValue)
    }

    @Test
    func settingsIgnoreRemovedIntroductionFlag() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let settingsFile = configDirectory.appendingPathComponent("settings.json")
        let legacySettings = """
        {
          "defaultDuration" : 600,
          "hasCompletedIntroduction" : true,
          "immersiveSessionMode" : false,
          "reducedMotion" : "always",
          "theme" : "dark"
        }
        """
        let data = try #require(legacySettings.data(using: .utf8))
        try data.write(to: settingsFile, options: .atomic)

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        let loaded = try store.load()

        #expect(loaded == AppSettings(theme: .dark, defaultDuration: 600, immersiveSessionMode: false, reducedMotion: .always))
    }

    @Test
    func settingsDecodeMissingTrialFieldsWithDefaults() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDirectory = tempRoot.appendingPathComponent("Config", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let settingsFile = configDirectory.appendingPathComponent("settings.json")
        let settingsWithoutTrial = """
        {
          "defaultDuration" : 600,
          "immersiveSessionMode" : false,
          "reducedMotion" : "always",
          "theme" : "dark"
        }
        """
        let data = try #require(settingsWithoutTrial.data(using: .utf8))
        try data.write(to: settingsFile, options: .atomic)

        let store = SettingsStore(fileManager: fm, configDirectory: configDirectory)
        let loaded = try store.load()

        #expect(loaded.trialSessionsUsed == 0)
        #expect(loaded.hasUnlockedFullAccess == false)
    }
}
