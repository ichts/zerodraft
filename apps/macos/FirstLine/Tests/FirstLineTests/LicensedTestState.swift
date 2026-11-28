import AppKit
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

/// The two papers (D-124) and the system appearance that shows each.
enum TestPaper: String, CaseIterable, Sendable {
    case white, black

    var appearance: NSAppearance.Name { self == .white ? .aqua : .darkAqua }
    var palette: FirstLineColors.Palette { self == .white ? .white : .black }
}

/// A bitmap pixel read in the bitmap's own colour space, then converted to sRGB. `colorAt` tags the bytes as
/// calibrated RGB, which lifts dark tones by several levels that are not on the screen.
func renderedPixel(_ rep: NSBitmapImageRep, x: Int, y: Int) -> NSColor? {
    var raw = [Int](repeating: 0, count: rep.samplesPerPixel)
    rep.getPixel(&raw, atX: x, y: y)
    let maximum = CGFloat((1 << rep.bitsPerSample) - 1)
    var components = raw.map { CGFloat($0) / maximum }
    if components.count == 3 { components.append(1) }
    return NSColor(colorSpace: rep.colorSpace, components: &components, count: components.count).usingColorSpace(.sRGB)
}
