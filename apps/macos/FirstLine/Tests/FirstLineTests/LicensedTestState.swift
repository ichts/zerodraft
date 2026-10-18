import Foundation
@testable import WriteItDown

/// Editor/navigation tests use an explicit test-only entitlement. Licensing tests use AppState directly.
@MainActor
func licensedTestState(
    sessionEngine: SessionEngine = SessionEngine(),
    settingsStore: SettingsStore? = nil,
    installIDStore: InstallIDStore? = nil,
    clock: @escaping () -> Date = Date.init
) -> AppState {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = settingsStore ?? SettingsStore(configDirectory: root)
    var saved = try! store.load()
    if saved.licenseStatus != .inactive {
        saved.licenseStatus = .inactive
        try! store.save(saved)
    }
    let state = AppState(sessionEngine: sessionEngine, settingsStore: store,
                         licenseClient: MockLicenseClient(),
                         installIDStore: installIDStore ?? InstallIDStore(configDirectory: root),
                         clock: clock, productID: "prod_mock")
    state.settings.licenseKey = "test-order"
    state.settings.licenseToken = "mock-token"
    state.settings.licenseInstanceID = "test-instance"
    state.settings.licenseProductID = "prod_mock"
    state.settings.licenseActivatedAt = clock()
    state.settings.licenseLastValidatedAt = clock()
    state.settings.licenseStatus = .active
    state.selectedSurface = .home
    return state
}
