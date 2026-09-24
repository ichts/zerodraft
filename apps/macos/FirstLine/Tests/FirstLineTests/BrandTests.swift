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
        #expect(labels.contains("We force you to write it down."))
        #expect(labels.contains("Give it sixty seconds."))
        let headline = try #require(allTextFields(in: home.view).first { $0.stringValue == "We force you to write it down." })
        let logotype = try #require(allTextFields(in: home.view).first { $0.stringValue == "WRITE_IT_DOWN" })
        let deck = try #require(allTextFields(in: home.view).first { $0.stringValue.hasPrefix("With a clock:") })
        let button = try #require(allButtons(in: home.view).first { $0.title == "Give it sixty seconds." })
        #expect(headline.font!.pointSize > max(logotype.font!.pointSize, deck.font!.pointSize, button.font!.pointSize))
        #expect(logotype.font!.familyName == "IBM Plex Mono")
        #expect(logotype.attributedStringValue.attribute(.kern, at: 0, effectiveRange: nil) as? Double == 1.82)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate())
        #expect(menu.items.first?.title == "Write It Down")
        #expect(menu.items.first?.submenu?.items.first?.title == "About Write It Down")
        #expect(RootWindowController(appState: state).window?.title == "Write It Down")
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
