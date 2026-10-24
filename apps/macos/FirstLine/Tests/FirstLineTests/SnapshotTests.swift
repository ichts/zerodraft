import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// Deterministic snapshots of real AppKit surfaces at the app window's content size.
/// Set WID_SNAPSHOT_DIR to write PNG evidence; the colour assertions run either way.
@MainActor
struct SnapshotTests {
    private let size = NSSize(width: 1040, height: 720)

    @Test func everySurfaceRendersInLightAndDark() throws {
        _ = NSApplication.shared
        let output = ProcessInfo.processInfo.environment["WID_SNAPSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"

            let picker = try trialState(used: 2)
            try snapshot(HomeViewController(appState: picker), name: "picker-\(suffix)", appearance: appearance,
                         output: output, sheetPoint: NSPoint(x: 250, y: 360))

            let exhausted = try trialState(used: 3)
            try snapshot(UpgradeViewController(appState: exhausted), name: "activation-\(suffix)", appearance: appearance,
                         output: output, sheetPoint: NSPoint(x: 250, y: 360))

            let licensed = licensedTestState()
            try snapshot(UpgradeViewController(appState: licensed), name: "activation-active-\(suffix)", appearance: appearance,
                         output: output, sheetPoint: NSPoint(x: 250, y: 360))

            try snapshot(SettingsViewController(appState: licensedTestState()), name: "settings-\(suffix)",
                         appearance: appearance, output: output, sheetPoint: NSPoint(x: 200, y: 360))
            let exhaustedSettings = try trialState(used: 3)
            try snapshot(SettingsViewController(appState: exhaustedSettings), name: "settings-entry-\(suffix)",
                         appearance: appearance, output: output, sheetPoint: NSPoint(x: 200, y: 360))
            try snapshot(HomeViewController(appState: try trialState(used: 2)), name: "picker-focus-\(suffix)",
                         appearance: appearance, output: output, sheetPoint: NSPoint(x: 250, y: 360), focus: true)
            try snapshot(UpgradeViewController(appState: try trialState(used: 3)), name: "activation-focus-\(suffix)",
                         appearance: appearance, output: output, sheetPoint: NSPoint(x: 250, y: 360), focus: true)
            try snapshot(UpgradeViewController(appState: checkingState()), name: "activation-checking-\(suffix)",
                         appearance: appearance, output: output, sheetPoint: NSPoint(x: 250, y: 360))
            try snapshot(UpgradeViewController(appState: activatingState()), name: "activation-activating-\(suffix)",
                         appearance: appearance, output: output, sheetPoint: NSPoint(x: 250, y: 360))
            try snapshot(UpgradeViewController(appState: try trialState(used: 3, checkoutConfigured: false)),
                         name: "activation-unavailable-\(suffix)",
                         appearance: appearance, output: output, sheetPoint: NSPoint(x: 250, y: 360))

            let rest = roomState(appearance: appearance)
            try snapshot(rest.room, name: "room-rest-\(suffix)", appearance: appearance,
                         output: output, sheetPoint: NSPoint(x: 170, y: 360))

            let typed = roomState(appearance: appearance)
            typeDraft(typed)
            try snapshot(typed.room, name: "room-typing-\(suffix)", appearance: appearance,
                         output: output, sheetPoint: NSPoint(x: 170, y: 360))

            let exitHint = roomState(appearance: appearance)
            typeDraft(exitHint)
            exitHint.room.exitConfirmation = ExitConfirmation(window: 60)
            exitHint.room.requestExit()
            try snapshot(exitHint.room, name: "room-exit-hint-\(suffix)", appearance: appearance,
                         output: output, sheetPoint: NSPoint(x: 170, y: 360))
        }

        try snapshot(activationError(), name: "activation-error-light", appearance: .aqua,
                     output: output, sheetPoint: NSPoint(x: 250, y: 360))
        try snapshot(warningState(reducesMotion: false).room, name: "room-warning-light", appearance: .aqua, output: output)
        try snapshot(warningState(reducesMotion: true).room, name: "room-warning-reduced-light", appearance: .aqua, output: output)
        try snapshot(warningState(reducesMotion: false, appearance: .darkAqua).room, name: "room-warning-dark",
                     appearance: .darkAqua, output: output)
        let deletedLight = deletedState(appearance: .aqua)
        try snapshot(deletedLight, name: "room-deleted-light", appearance: .aqua,
                     output: output, sheetPoint: NSPoint(x: 170, y: 360))
        let deletedDark = deletedState(appearance: .darkAqua)
        try snapshot(deletedDark, name: "room-deleted-dark", appearance: .darkAqua,
                     output: output, sheetPoint: NSPoint(x: 170, y: 360))
        let keptLight = keptState(appearance: .aqua, copy: false)
        try snapshot(keptLight, name: "room-kept-light", appearance: .aqua,
                     output: output, sheetPoint: NSPoint(x: 170, y: 360))
        let copiedLight = keptState(appearance: .aqua, copy: true)
        try snapshot(copiedLight, name: "room-copied-light", appearance: .aqua,
                     output: output, sheetPoint: NSPoint(x: 170, y: 360))
        let copiedDark = keptState(appearance: .darkAqua, copy: true)
        try snapshot(copiedDark, name: "room-copied-dark", appearance: .darkAqua,
                     output: output, sheetPoint: NSPoint(x: 170, y: 360))
        let keptDark = keptState(appearance: .darkAqua, copy: false)
        try snapshot(keptDark, name: "room-kept-dark", appearance: .darkAqua,
                     output: output, sheetPoint: NSPoint(x: 170, y: 360))
    }

    @Test func keptCopyFocusRendersInLightAndDark() throws {
        let output = ProcessInfo.processInfo.environment["WID_SNAPSHOT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for copied in [false, true] {
                let room = keptState(appearance: appearance, copy: copied)
                let label = copied ? "copied" : "copy"
                try snapshot(room, name: "room-\(label)-focus-\(suffix)", appearance: appearance,
                             output: output, sheetPoint: NSPoint(x: 170, y: 360), focus: true)
            }
        }
    }

    // MARK: - States

    private func trialState(used: Int, checkoutConfigured: Bool = true) throws -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = used
        let store = SettingsStore(configDirectory: root)
        try store.save(settings)
        let checkout: CheckoutClient = checkoutConfigured
            ? MockCheckoutClient()
            : HostedCheckoutClient(baseURL: nil)
        return AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                        checkoutClient: checkout, installIDStore: InstallIDStore(configDirectory: root),
                        productID: "prod_mock")
    }

    private func checkingState() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = 3
        settings.licenseKey = "KEY"
        settings.licenseStatus = .active
        settings.licenseActivatedAt = now
        settings.licenseLastValidatedAt = now
        settings.licenseInstanceID = "lki_existing"
        settings.licenseProductID = "prod_mock"
        settings.licenseToken = "mock-token"
        let store = SettingsStore(configDirectory: root)
        try? store.save(settings)
        return AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                        checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                        clock: { now }, productID: "prod_mock")
    }

    private func activatingState() -> AppState {
        let state = try! trialState(used: 3)
        state.licenseActivationInFlight = true
        return state
    }

    private func activationError() -> UpgradeViewController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = 3
        let store = SettingsStore(configDirectory: root)
        try? store.save(settings)
        let state = AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                             checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        state.licenseActivationError = .cleanupFailure
        return UpgradeViewController(appState: state)
    }

    private struct RoomFixture {
        let room: SessionViewController
        let clock: MutableClock
        let engine: SessionEngine
    }

    private func roomState(appearance: NSAppearance.Name) -> RoomFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = MutableClock(0)
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        if appearance == .darkAqua { state.updateTheme(.dark) }
        state.startSession(duration: 60)
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        let room = SessionViewController(appState: state, pasteboard: board)
        _ = room.view
        return RoomFixture(room: room, clock: clock, engine: engine)
    }

    private func typeDraft(_ fixture: RoomFixture) {
        let editor = allTextViews(in: fixture.room.view).compactMap { $0 as? AppendOnlyTextView }.first!
        editor.insertText("cant say this out loud but\ni dont want the promotion\npromotion. i want time",
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 0.4
        fixture.engine.registerMarkedTextActivity()
        fixture.room.tick()
    }

    private func warningState(reducesMotion: Bool, appearance: NSAppearance.Name = .aqua) -> RoomFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = MutableClock(0)
        let engine = SessionEngine(now: { clock.now })
        let state = licensedTestState(sessionEngine: engine,
                                      settingsStore: SettingsStore(configDirectory: root),
                                      installIDStore: InstallIDStore(configDirectory: root))
        if appearance == .darkAqua { state.updateTheme(.dark) }
        if reducesMotion { state.updateReducedMotion(.always) }
        state.startSession(duration: 60)
        let room = SessionViewController(appState: state)
        _ = room.view
        let editor = allTextViews(in: room.view).compactMap { $0 as? AppendOnlyTextView }.first!
        editor.insertText("cant say this out loud but\ni dont want the promotion\npromotion. i want time",
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        clock.now = 5.6
        engine.tick()
        room.tick()
        return RoomFixture(room: room, clock: clock, engine: engine)
    }

    private func deletedState(appearance: NSAppearance.Name) -> SessionViewController {
        let fixture = roomState(appearance: appearance)
        fixture.room.cutFlashDuration = 0
        let editor = allTextViews(in: fixture.room.view).compactMap { $0 as? AppendOnlyTextView }.first!
        editor.insertText("one sentence", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 8.1
        fixture.room.tick()
        return fixture.room
    }

    private func keptState(appearance: NSAppearance.Name, copy: Bool) -> SessionViewController {
        let fixture = roomState(appearance: appearance)
        let editor = allTextViews(in: fixture.room.view).compactMap { $0 as? AppendOnlyTextView }.first!
        editor.insertText("cant say this out loud but\ni dont want the promotion\npromotion. i want time",
                          replacementRange: NSRange(location: NSNotFound, length: 0))
        let engine = fixture.engine
        for second in stride(from: 4.0, to: 60.0, by: 4.0) {
            fixture.clock.now = second
            engine.registerMarkedTextActivity()
        }
        fixture.clock.now = 60
        engine.tick()
        fixture.room.tick()
        if copy { fixture.room.copyKeptText() }
        return fixture.room
    }

    // MARK: - Rendering

    private func snapshot(_ controller: NSViewController, name: String, appearance: NSAppearance.Name,
                          output: URL?, sheetPoint: NSPoint? = nil, focus: Bool = false) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentViewController = controller
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        if focus {
            window.makeKeyAndOrderFront(nil)
            controller.viewDidAppear()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            controller.view.layoutSubtreeIfNeeded()
        }
        controller.view.displayIfNeeded()
        let rep = try #require(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
        if focus, controller is SessionViewController {
            let button = try #require(window.firstResponder as? NSButton)
            #expect(["COPY TEXT", "COPIED"].contains(button.title))
            #expect(button.focusRingType == .none)
            let ringing = try #require(button as? FirstLineInkFocusRinging)
            #expect(ringing.showsInkFocusRing)
        }
        if let output {
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("\(name).png"))
        }
        try assertPixel(rep, at: NSPoint(x: 4, y: 4), equals: FirstLineColors.pageNSColor, in: appearance, name: name)
        // The right edge can carry a vertical scroller in a tall settings card;
        // sample the other left-page corner instead of the scroller track.
        try assertPixel(rep, at: NSPoint(x: 4, y: rep.pixelsHigh - 5),
                        equals: FirstLineColors.pageNSColor, in: appearance, name: name)
        if let sheetPoint {
            let scale = CGFloat(rep.pixelsWide) / size.width
            try assertPixel(rep, at: NSPoint(x: sheetPoint.x * scale, y: sheetPoint.y * scale),
                            equals: FirstLineColors.sheetNSColor, in: appearance, name: name)
        }
        if focus { window.orderOut(nil) }
        SnapshotWindowKeeper.windows.append(window)
    }

    private func assertPixel(_ rep: NSBitmapImageRep, at point: NSPoint, equals token: NSColor,
                             in appearance: NSAppearance.Name, name: String) throws {
        let resolved = try #require(appearanceColor(token, appearance))
        let color = try #require(rep.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB))
        let expected = try #require(resolved.usingColorSpace(.sRGB))
        let delta = abs(color.redComponent - expected.redComponent)
            + abs(color.greenComponent - expected.greenComponent)
            + abs(color.blueComponent - expected.blueComponent)
        if delta >= 0.16 { print("PIXFAIL \(name) point=\(Int(point.x)),\(Int(point.y)) got=\(color) expected=\(expected) size=\(rep.pixelsWide)x\(rep.pixelsHigh)") }
        #expect(delta < 0.16, "\(name): pixel \(Int(point.x)),\(Int(point.y)) differs from the token")
    }

    private func appearanceColor(_ color: NSColor, _ appearance: NSAppearance.Name) -> NSColor? {
        var resolved: NSColor?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return resolved
    }

    private func allTextViews(in view: NSView) -> [NSTextView] {
        ((view as? NSTextView).map { [$0] } ?? []) + view.subviews.flatMap(allTextViews)
    }
}

@MainActor
private enum SnapshotWindowKeeper {
    static var windows: [NSWindow] = []
}

private final class MutableClock {
    var now: TimeInterval
    init(_ now: TimeInterval) { self.now = now }
}
