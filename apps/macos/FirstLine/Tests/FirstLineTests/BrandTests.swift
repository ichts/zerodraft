import AppKit
import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct BrandTests {
    @Test func infoPlistNamesWriteItDown() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/FirstLine/Info.plist").standardizedFileURL
        let data = try Data(contentsOf: plist)
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "app.writeitdown.mac")
        #expect(AppPaths.applicationSupportRoot.lastPathComponent == "WriteItDown")
        #expect(info["CFBundleName"] as? String == "Write It Down")
        #expect((info["NSHumanReadableCopyright"] as? String)?.contains("Your Company") == false)
    }

    @Test func startScreenAndMenusShowWriteItDown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        let home = HomeViewController(appState: state)
        home.loadViewIfNeeded()
        let labels = allLabels(in: home.view)
        #expect(labels.contains("WRITE_IT_DOWN"))
        #expect(labels.contains("MINUTES"))
        #expect(labels.contains("DELETE AFTER SILENCE"))
        #expect(allButtons(in: home.view).contains { $0.title == "1" })
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate())
        #expect(menu.items.first?.title == "Write It Down")
        #expect(menu.items.first?.submenu?.items.first?.title == "About Write It Down")
        #expect(RootWindowController(appState: state).window?.title == "Write It Down")
    }

    @Test func startScreenHasNoSiteHeadlineDeckOrSlogan() {
        let state = AppState()
        let home = HomeViewController(appState: state)
        let labels = allLabels(in: home.view).joined(separator: " ")
        #expect(!labels.contains("We force you"))
        #expect(!labels.contains("With a clock"))
        #expect(!labels.contains("Give it sixty seconds"))
    }

    @Test func upgradeShowsOneTimePrice() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        let upgrade = UpgradeViewController(appState: state)
        upgrade.loadViewIfNeeded()
        #expect(allLabels(in: upgrade.view).contains("One-time $4.99. 2 Macs. No subscription. 14-day refund."))
    }

    private func allTextFields(in view: NSView) -> [NSTextField] {
        let current = (view as? NSTextField).map { [$0] } ?? []
        return current + view.subviews.flatMap(allTextFields)
    }

    private func allButtons(in view: NSView) -> [NSButton] {
        let current = (view as? NSButton).map { [$0] } ?? []
        return current + view.subviews.flatMap(allButtons)
    }

    private func allLabels(in view: NSView) -> [String] {
        let value = (view as? NSButton)?.title ?? (view as? NSControl)?.stringValue
        return (value.map { [$0] } ?? []) + view.subviews.flatMap(allLabels)
    }
}
