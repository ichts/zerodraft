import Foundation
import AppKit
import Testing
@testable import WriteItDown

@MainActor
struct ActivationLinkTests {
    private func makeState(licensed: Bool = false) -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if licensed { return licensedTestState() }
        return AppState(settingsStore: SettingsStore(configDirectory: root), licenseClient: MockLicenseClient(),
                        checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                        productID: "prod_mock")
    }

    @Test(arguments: [
        ("writeitdown://activate#key=cs_test_a1B2", "cs_test_a1B2"),
        ("writeitdown://activate#key=cs_live_a1B2", "cs_live_a1B2"),
        ("writeitdown://activate/#key=cs_live_a1B2", "cs_live_a1B2"),
        ("WriteItDown://Activate#key=cs_live_a1B2", "cs_live_a1B2"),
    ])
    func acceptsOnlyTheExactShape(_ link: String, _ key: String) throws {
        #expect(ActivationLink.key(from: try #require(URL(string: link))) == key)
    }

    @Test(arguments: [
        "writeitdown://activate", "writeitdown://activate#key=", "writeitdown://activate#key=cs_test_",
        "writeitdown://activate?key=cs_test_a1", "writeitdown://activate?x=1#key=cs_test_a1", "writeitdown://other#key=cs_test_a1", "writeitdown://activate#key=cs_test_a1=",
        "writeitdown://activate#key=cs_test_a1&x=1",
        "writeitdown://activate#key=cs_test_a1&key=cs_test_b2", "writeitdown://activate#key=cs_test_a%20b",
        "writeitdown://activate#key=pi_test_a1", "writeitdown://activate#key=cs_test_a1%0Ab",
        "writeitdown://activate/x#key=cs_test_a1", "writeitdown://u@activate#key=cs_test_a1",
        "writeitdown://settings#key=cs_test_a1", "https://activate#key=cs_test_a1",
        "writeitdown://activate#key=cs_test_\u{e9}",
    ])
    func rejectsEverythingElse(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(ActivationLink.key(from: url) == nil)
    }

    @Test func rejectsOverlongKey() throws {
        let url = try #require(URL(string: "writeitdown://activate#key=cs_test_" + String(repeating: "a", count: 100)))
        #expect(ActivationLink.key(from: url) == nil)
    }

    @Test func linkPrefillsTheActivationCardWithoutActivating() throws {
        let state = makeState()
        state.receiveActivationLink(try #require(URL(string: "writeitdown://activate#key=cs_test_a1")))
        #expect(state.selectedSurface == .upgrade)
        let card = UpgradeViewController(appState: state)
        func fields(_ view: NSView) -> [NSTextField] { ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(fields) }
        #expect(fields(card.view).contains { $0.stringValue == "cs_test_a1" && $0.isEditable })
        #expect(state.pendingActivationKey == nil)
        #expect(state.settings.licenseStatus == .inactive)
        #expect(!state.licenseActivationInFlight)
    }

    @Test func linkDoesNotInterruptALiveSessionAndWaits() throws {
        let state = makeState()
        state.startSession()
        state.sessionEngine.registerCommittedText("x")
        #expect(state.isWritingSessionActive)
        let surface = state.selectedSurface
        state.receiveActivationLink(try #require(URL(string: "writeitdown://activate#key=cs_test_a1")))
        #expect(state.selectedSurface == surface)
        #expect(state.pendingActivationKey == "cs_test_a1")
    }

    @Test func licensedMacIgnoresTheLink() throws {
        let state = makeState(licensed: true)
        state.receiveActivationLink(try #require(URL(string: "writeitdown://activate#key=cs_test_a1")))
        #expect(state.pendingActivationKey == nil)
        #expect(state.selectedSurface == .home)
    }

    @Test func invalidLinkChangesNothing() throws {
        let state = makeState()
        let surface = state.selectedSurface
        state.receiveActivationLink(try #require(URL(string: "writeitdown://activate#key=nope")))
        #expect(state.selectedSurface == surface)
        #expect(state.pendingActivationKey == nil)
    }

    @Test func infoPlistRegistersOnlyTheActivationScheme() throws {
        let config = try #require(NSDictionary(contentsOf: AppState.configurationURL) as? [String: Any])
        let types = try #require(config["CFBundleURLTypes"] as? [[String: Any]])
        #expect(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } == ["writeitdown"])
    }
}
