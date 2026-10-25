import AppKit
import Foundation
import Sparkle
import Testing
@testable import WriteItDown

@MainActor
struct UpdatePolicyTests {
    @Test func noUpdateUIIsEverPresentedOnTheSessionSurface() {
        #expect(UpdatePolicy.mayPresentUpdateUI(roomIsShown: false))
        #expect(!UpdatePolicy.mayPresentUpdateUI(roomIsShown: true))
    }

    @Test func theMenuCommandIsOnlyAvailableOutsideTheRoom() {
        #expect(UpdatePolicy.mayRunUserInitiatedCheck(hasUpdater: true, roomIsShown: false))
        #expect(!UpdatePolicy.mayRunUserInitiatedCheck(hasUpdater: true, roomIsShown: true))
        #expect(!UpdatePolicy.mayRunUserInitiatedCheck(hasUpdater: false, roomIsShown: false))
    }

    @Test func deferredUpdateWaitsForTheRoomToClose() {
        var policy = UpdateDeferralPolicy()
        #expect(!policy.hasDeferredUpdate)
        policy.deferUpdate()
        #expect(policy.hasDeferredUpdate)
        let duringRoom = policy.takePresentationRequest(roomIsShown: true, canCheckForUpdates: true)
        #expect(!duringRoom)
        #expect(policy.hasDeferredUpdate)
        let afterRoom = policy.takePresentationRequest(roomIsShown: false, canCheckForUpdates: true)
        #expect(afterRoom)
        #expect(!policy.hasDeferredUpdate)
        // Asked once only; a sitting writer is not nagged on every tick.
        let again = policy.takePresentationRequest(roomIsShown: false, canCheckForUpdates: true)
        #expect(!again)
    }

    @Test func deferredUpdateNeverOverridesBusySparkle() {
        var policy = UpdateDeferralPolicy()
        policy.deferUpdate()
        let requested = policy.takePresentationRequest(roomIsShown: false, canCheckForUpdates: false)
        #expect(!requested)
        #expect(policy.hasDeferredUpdate)
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
        // Both keys together: Sparkle refuses a signed-feed updater that skips pre-extraction checks.
        #expect(values["SURequireSignedFeed"] as? Bool == true)
        #expect(values["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        // Sparkle's 20-day default would accept an unverified feed after that long.
        #expect(values["SUSignedFeedFailureExpirationInterval"] as? Int == 0)
        let build = try #require(values["CFBundleVersion"] as? String)
        #expect(Int(build).map { $0 > 0 } == true)
    }
}

@MainActor
struct UpdateRoomSurfaceTests {
    @Test func theSessionSurfaceIsTheRoomGate() {
        let state = licensedTestState()
        #expect(!state.isShowingWritingRoom)
        state.selectedSurface = .session
        #expect(state.isShowingWritingRoom)
        state.selectedSurface = .home
        #expect(!state.isShowingWritingRoom)
    }

    @Test func settingsAndHomeLeaveTheRoom() {
        let state = licensedTestState()
        state.selectedSurface = .session
        state.openSettings()
        #expect(state.selectedSurface == .settings)
        #expect(!state.isShowingWritingRoom)
        state.closeSettings()
        #expect(state.selectedSurface == .session)
        #expect(state.isShowingWritingRoom)
        state.goHome()
        #expect(!state.isShowingWritingRoom)
    }
}

@MainActor
final class UpdatePresentationGateTests {
    private var retainedDelegates: [UpdateUserDriver] = []

    private func roomDriver(
        roomIsShown: @escaping () -> Bool = { true },
        onDeferred: @escaping () -> Void
    ) -> RoomAwareStandardUserDriver {
        let delegate = UpdateUserDriver(roomIsShown: roomIsShown)
        retainedDelegates.append(delegate)
        return RoomAwareStandardUserDriver(
            hostBundle: .main,
            delegate: delegate,
            roomIsShown: roomIsShown,
            onDeferred: onDeferred
        )
    }

    @Test func theRoomCancelsACheckBeforeItsWindowAppears() {
        var deferred = 0
        var cancelled = false
        let driver = roomDriver(onDeferred: { deferred += 1 })
        let sparkleDriver: any SPUUserDriver = driver
        sparkleDriver.showUserInitiatedUpdateCheck(cancellation: { cancelled = true })
        #expect(cancelled)
        #expect(deferred == 1)
    }

    @Test func theRoomCancelsADownloadBeforeItsStatusWindowAppears() {
        var deferred = 0
        var cancelled = false
        let driver = roomDriver(onDeferred: { deferred += 1 })
        let sparkleDriver: any SPUUserDriver = driver
        sparkleDriver.showDownloadInitiated(cancellation: { cancelled = true })
        #expect(cancelled)
        #expect(deferred == 1)
    }

    @Test func theRoomAcknowledgesResultsWithoutAnAlert() {
        var deferred = 0
        var acknowledged = false
        let driver = roomDriver(onDeferred: { deferred += 1 })
        let sparkleDriver: any SPUUserDriver = driver
        sparkleDriver.showUpdateNotFoundWithError(NSError(domain: "test", code: 1), acknowledgement: { acknowledged = true })
        #expect(acknowledged)
        #expect(deferred == 0)
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
