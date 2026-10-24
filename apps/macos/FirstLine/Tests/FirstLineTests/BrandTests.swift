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
        #expect(info["WIDDisplayPrice"] as? String == "$4.99")
        #expect(AppState.checkoutURL?.absoluteString == "https://writeitdown.app/mac.html")
        #expect(AppState.licenseProductID == "prod_VUeTDTehcGAqJK")
        #expect(info["WIDLicenseServiceURL"] as? String == "https://licenses.writeitdown.app")
        #expect(info["WIDLicensePublicKey"] as? String == "ZjyVb5Twq4UPWjattEuyWZdSr0nsAYslV41RJtFtBsw=")
        #expect(AppState.configuredLicenseClient.isConfigured)
        #expect((info["NSHumanReadableCopyright"] as? String)?.contains("Your Company") == false)
    }

    @Test func startScreenAndMenusShowWriteItDown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        let home = HomeViewController(appState: state)
        home.loadViewIfNeeded()
        let labels = allLabels(in: home.view)
        let images = allImages(in: home.view)
        #expect(images.filter { $0.accessibilityLabel() == "Write It Down" && $0.image != nil }.count == 1)
        #expect(labels.contains("How long?"))
        #expect(!labels.contains("Forward only. Nothing is saved."))
        #expect(labels.contains("Minutes") || labels.contains("minutes"))
        #expect(labels.contains("Delete after silence"))
        #expect(allButtons(in: home.view).contains { $0.title == "1" })
        #expect(allButtons(in: home.view).contains { $0.title == "Begin" })
        let help = try #require(allButtons(in: home.view).first { $0.title == "?" })
        #expect(help.accessibilityLabel() == "How it works")
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
        let price = AppState.displayPrice
        #expect(allLabels(in: upgrade.view).contains { $0.contains(price) })
    }

    @Test func rulesViewReusesTheLandingExplanationAndDismisses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root),
                             installIDStore: InstallIDStore(configDirectory: root))
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = home
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.makeKeyAndOrderFront(nil)
        home.view.layoutSubtreeIfNeeded()
        let help = try #require(allButtons(in: home.view).first { $0.title == "?" })
        window.makeFirstResponder(help)
        #expect(window.firstResponder === help, "the question mark is not keyboard reachable")
        help.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let rules = try #require(home.presentedViewControllers?.first as? RulesViewController)
        rules.view.layoutSubtreeIfNeeded()
        let labels = allLabels(in: rules.view)
        let ordered = ["How it works", "Forward only. Nothing kept.", "No way back",
                       "Eight seconds of silence", "Reach zero, keep it"]
        for text in ordered {
            #expect(labels.contains(text), "missing rule text: \(text)")
        }
        let positions = ordered.compactMap { labels.firstIndex(of: $0) }
        #expect(positions == positions.sorted(), "the rules are not in the landing page's order")
        #expect(labels.contains("Open it, start typing, say the thing you have been avoiding. The only way out is through."))
        #expect(!labels.contains { $0.contains("!") })
        let done = try #require(allButtons(in: rules.view).first { $0.title == "Done" })
        #expect(done.keyEquivalent == "\r")
        let ret = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: rules.view.window!.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        #expect(rules.view.window?.performKeyEquivalent(with: ret) == true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        #expect(home.presentedViewControllers?.isEmpty != false, "Return did not dismiss the rules")
        window.orderOut(nil)
    }

    @Test func rulesViewCancelOperationDismisses() throws {
        let rules = RulesViewController()
        rules.loadViewIfNeeded()
        rules.cancelOperation(nil)
        #expect(rules.presentedViewControllers?.isEmpty != false)
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

    private func allImages(in view: NSView) -> [NSImageView] {
        let current = (view as? NSImageView).map { [$0] } ?? []
        return current + view.subviews.flatMap(allImages)
    }
}
