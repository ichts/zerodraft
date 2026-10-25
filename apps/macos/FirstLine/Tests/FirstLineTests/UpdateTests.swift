import AppKit
import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct UpdatePolicyTests {
    @Test func noUpdateUIIsEverPresentedWhileASessionRuns() {
        #expect(UpdatePolicy.mayPresentUpdateUI(sessionIsRunning: false))
        #expect(!UpdatePolicy.mayPresentUpdateUI(sessionIsRunning: true))
    }

    @Test func theMenuCommandIsOnlyAvailableOutsideTheRoom() {
        #expect(UpdatePolicy.mayRunUserInitiatedCheck(hasUpdater: true, sessionIsRunning: false))
        #expect(!UpdatePolicy.mayRunUserInitiatedCheck(hasUpdater: true, sessionIsRunning: true))
        #expect(!UpdatePolicy.mayRunUserInitiatedCheck(hasUpdater: false, sessionIsRunning: false))
    }

    @Test func deferredUpdateWaitsForTheSessionToEnd() {
        var policy = UpdateDeferralPolicy()
        #expect(!policy.hasDeferredUpdate)
        policy.deferUpdate()
        #expect(policy.hasDeferredUpdate)
        let duringSession = policy.takePresentationRequest(sessionIsRunning: true, canCheckForUpdates: true)
        #expect(!duringSession)
        #expect(policy.hasDeferredUpdate)
        let afterSession = policy.takePresentationRequest(sessionIsRunning: false, canCheckForUpdates: true)
        #expect(afterSession)
        #expect(!policy.hasDeferredUpdate)
        // Asked once only; a sitting writer is not nagged on every tick.
        let again = policy.takePresentationRequest(sessionIsRunning: false, canCheckForUpdates: true)
        #expect(!again)
    }

    @Test func deferredUpdateNeverOverridesBusySparkle() {
        var policy = UpdateDeferralPolicy()
        policy.deferUpdate()
        let requested = policy.takePresentationRequest(sessionIsRunning: false, canCheckForUpdates: false)
        #expect(!requested)
        #expect(policy.hasDeferredUpdate)
    }

    @Test func finishingTheUpdateSessionDropsTheDeferral() {
        var policy = UpdateDeferralPolicy()
        policy.deferUpdate()
        policy.clear()
        #expect(!policy.hasDeferredUpdate)
        let requested = policy.takePresentationRequest(sessionIsRunning: false, canCheckForUpdates: true)
        #expect(!requested)
    }

    /// The gate the release script enforces: no check may run unless the writer asks for it.
    @Test func infoPlistKeepsChecksOffUntilTheWriterOptsIn() throws {
        let values = try #require(NSDictionary(contentsOf: AppState.configurationURL) as? [String: Any])
        #expect(values["SUEnableAutomaticChecks"] as? Bool == false)
        #expect((values["SUScheduledCheckInterval"] as? Int ?? 0) == 86_400)
        let feed = try #require(values["SUFeedURL"] as? String)
        let url = try #require(URL(string: feed))
        #expect(url.scheme == "https")
        #expect(url.lastPathComponent == "appcast.xml")
        let key = try #require(values["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        let build = try #require(values["CFBundleVersion"] as? String)
        #expect(Int(build).map { $0 > 0 } == true)
    }
}

@MainActor
final class StubUpdateSettings: UpdateSettings {
    var automaticallyChecksForUpdates: Bool

    init(automaticallyChecksForUpdates: Bool = false) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
}

@MainActor
struct SettingsUpdateTests {
    private func checkboxes(_ view: NSView) -> [NSButton] {
        ((view as? NSButton).flatMap { $0.title.isEmpty ? nil : [$0] } ?? []) + view.subviews.flatMap(checkboxes)
    }

    private func labels(_ view: NSView) -> [String] {
        ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(labels)
    }

    /// Q-05/Q-07: the new row uses the control type style, and About reports the shipped version.
    @Test func theUpdatesRowAndAboutVersionFollowTheSurfaceStyle() throws {
        let settings = SettingsViewController(appState: licensedTestState(), updateSettings: StubUpdateSettings())
        let box = try #require(checkboxes(settings.view).first { $0.title == "Check for updates automatically" })
        #expect(box.font?.pointSize == FirstLineTypography.smallNSFont.pointSize)
        #expect(labels(settings.view).contains("Updates"))
        #expect(labels(settings.view).contains("Version \(AppState.displayVersion)"))
        #expect(AppState.displayVersion == (try #require(NSDictionary(contentsOf: AppState.configurationURL) as? [String: Any])["CFBundleShortVersionString"] as? String))
    }

    @Test func automaticChecksStartOffAndTheSwitchWritesThrough() throws {
        let stub = StubUpdateSettings()
        let settings = SettingsViewController(appState: licensedTestState(), updateSettings: stub)
        let box = try #require(checkboxes(settings.view).first { $0.title == "Check for updates automatically" })
        #expect(box.state == .off)
        box.performClick(nil)
        #expect(box.state == .on)
        #expect(stub.automaticallyChecksForUpdates)
        box.performClick(nil)
        #expect(!stub.automaticallyChecksForUpdates)
    }

    @Test func theSwitchReflectsAPreviouslyTurnedOnSetting() throws {
        let stub = StubUpdateSettings(automaticallyChecksForUpdates: true)
        let settings = SettingsViewController(appState: licensedTestState(), updateSettings: stub)
        let box = try #require(checkboxes(settings.view).first { $0.title == "Check for updates automatically" })
        #expect(box.state == .on)
    }

    @Test func noUpdateSwitchWhereThereIsNoUpdater() {
        // A bare executable (tests, swift run) has no Sparkle updater, so Settings must not offer the switch.
        let settings = SettingsViewController(appState: licensedTestState())
        #expect(!checkboxes(settings.view).contains { $0.title == "Check for updates automatically" })
    }
}

@MainActor
struct UpdateMenuTests {
    @Test func checkForUpdatesIsDisabledWithoutAnUpdater() throws {
        let state = licensedTestState()
        let delegate = FirstLineAppDelegate(appState: state)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate, showsUpdateCheck: true)
        let item = try #require(Self.updateItem(menu))
        // This process has no Sparkle updater, so the item is present but cannot act.
        #expect(!delegate.validateMenuItem(item))
    }

    @Test func updateItemIsAbsentWithoutAnUpdater() {
        let state = licensedTestState()
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate(appState: state))
        #expect(Self.updateItem(menu) == nil)
    }

    @Test func updateItemSitsUnderAboutWhenPresent() throws {
        let state = licensedTestState()
        let delegate = FirstLineAppDelegate(appState: state)
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: delegate, showsUpdateCheck: true)
        let appMenu = try #require(menu.items.first?.submenu)
        let titles = appMenu.items.map(\.title)
        let about = try #require(titles.firstIndex(of: "About Write It Down"))
        let update = try #require(titles.firstIndex(of: "Check for Updates…"))
        #expect(update == about + 1)
        #expect(appMenu.items[update].target === delegate)
    }

    private static func updateItem(_ menu: NSMenu) -> NSMenuItem? {
        menu.items.first?.submenu?.items.first { $0.action == #selector(FirstLineAppDelegate.checkForUpdates(_:)) }
    }
}
