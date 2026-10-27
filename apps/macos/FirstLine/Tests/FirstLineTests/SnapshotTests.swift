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
            try snapshot(SettingsViewController(appState: licensedTestState(), updateSettings: StubUpdateSettings()),
                         name: "settings-updates-\(suffix)",
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
                         output: output, paperPoint: NSPoint(x: 520, y: 660))

            let typed = roomState(appearance: appearance)
            typeDraft(typed)
            try snapshot(typed.room, name: "room-typing-\(suffix)", appearance: appearance,
                         output: output, paperPoint: NSPoint(x: 520, y: 660))

            let exitHint = roomState(appearance: appearance)
            typeDraft(exitHint)
            exitHint.room.exitConfirmation = ExitConfirmation(window: 60)
            exitHint.room.requestExit()
            try snapshot(exitHint.room, name: "room-exit-hint-\(suffix)", appearance: appearance,
                         output: output, paperPoint: NSPoint(x: 520, y: 660))
        }

        try snapshot(activationError(), name: "activation-error-light", appearance: .aqua,
                     output: output, sheetPoint: NSPoint(x: 250, y: 360))
        // The warn state is the one room state whose sheet is not the plain tone: it is measured against the
        // wash tint at the fraction the tick produced (idle 5.6 s of the 8 s standard limit = 0.2).
        try snapshot(warningState(reducesMotion: false).room, name: "room-warning-light", appearance: .aqua,
                     output: output, washPoint: (NSPoint(x: 520, y: 120), 0.2))
        try snapshot(warningState(reducesMotion: true).room, name: "room-warning-reduced-light", appearance: .aqua,
                     output: output, washPoint: (NSPoint(x: 520, y: 120), 1))
        try snapshot(warningState(reducesMotion: false, appearance: .darkAqua).room, name: "room-warning-dark",
                     appearance: .darkAqua, output: output)
        let deletedLight = deletedState(appearance: .aqua)
        try snapshot(deletedLight, name: "room-deleted-light", appearance: .aqua,
                     output: output, paperPoint: NSPoint(x: 520, y: 660))
        let deletedDark = deletedState(appearance: .darkAqua)
        try snapshot(deletedDark, name: "room-deleted-dark", appearance: .darkAqua,
                     output: output, paperPoint: NSPoint(x: 520, y: 660))
        let keptLight = keptState(appearance: .aqua, copy: false)
        try snapshot(keptLight, name: "room-kept-light", appearance: .aqua,
                     output: output, paperPoint: NSPoint(x: 520, y: 660))
        let copiedLight = keptState(appearance: .aqua, copy: true)
        try snapshot(copiedLight, name: "room-copied-light", appearance: .aqua,
                     output: output, paperPoint: NSPoint(x: 520, y: 660))
        let copiedDark = keptState(appearance: .darkAqua, copy: true)
        try snapshot(copiedDark, name: "room-copied-dark", appearance: .darkAqua,
                     output: output, paperPoint: NSPoint(x: 520, y: 660))
        let keptDark = keptState(appearance: .darkAqua, copy: false)
        try snapshot(keptDark, name: "room-kept-dark", appearance: .darkAqua,
                     output: output, paperPoint: NSPoint(x: 520, y: 660))
    }

    /// The grain is texture on the sheet, not an image that reacts to the writer: typing changes the words
    /// and nothing about the paper. The region is sampled from real window frames, before and after input.
    /// Typing never regenerates the field. The clock stays inside the reading window here on purpose: past five
    /// seconds of silence the wash is a *state* on the sheet, and that change is measured by
    /// `ReviewRoundTests.warningWashTintsTheRenderedPaper`, not conflated with the grain's stillness (D-072).
    @Test func paperStaysStillWhileTyping() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let name = appearance == .aqua ? "light" : "dark"
            let fixture = roomState(appearance: appearance)
            let before = try paperPixels(fixture.room, appearance: appearance)
            typeDraft(fixture)
            fixture.clock.now = 3
            fixture.room.tick()
            let after = try paperPixels(fixture.room, appearance: appearance)
            #expect(before == after, "\(name): the paper changed under the writer's keys")
        }
    }

    /// A text-free band of the sheet, at the window's real size, as raw sRGB bytes.
    private func paperPixels(_ controller: NSViewController, appearance: NSAppearance.Name) throws -> Data {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentViewController = controller
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        controller.view.displayIfNeeded()
        let rep = try #require(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
        SnapshotWindowKeeper.windows.append(window)
        let scale = CGFloat(rep.pixelsWide) / size.width
        let origin = NSPoint(x: 120 * scale, y: 280 * scale)
        let side = Int(200 * scale)
        var bytes = Data()
        for y in Int(origin.y)..<(Int(origin.y) + side) {
            for x in Int(origin.x)..<(Int(origin.x) + side) {
                let colour = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                bytes.append(UInt8((colour.redComponent * 255).rounded()))
                bytes.append(UInt8((colour.greenComponent * 255).rounded()))
                bytes.append(UInt8((colour.blueComponent * 255).rounded()))
            }
        }
        return bytes
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
                             output: output, paperPoint: NSPoint(x: 520, y: 660), focus: true)
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
        settleBar(fixture)
    }

    /// Static PNGs show the bar's model; the live room runs a CA animation. The bar is off the
    /// sheet on the stopped screen, so only the drained model is left to settle (D-070).
    private func settleBar(_ fixture: RoomFixture) {
        let fraction: CGFloat = fixture.engine.phase == .failure || fixture.engine.phase == .success ? 0
            : (fixture.engine.hasStarted ? CGFloat(fixture.engine.remaining / max(fixture.engine.duration, 1)) : 1)
        for bar in allViews(in: fixture.room.view, of: FirstLineFillBar.self) {
            bar.settleForRendering(fraction)
        }
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
        let fixture = RoomFixture(room: room, clock: clock, engine: engine)
        settleBar(fixture)
        return fixture
    }

    private func deletedState(appearance: NSAppearance.Name) -> SessionViewController {
        let fixture = roomState(appearance: appearance)
        fixture.room.cutFlashDuration = 0
        let editor = allTextViews(in: fixture.room.view).compactMap { $0 as? AppendOnlyTextView }.first!
        editor.insertText("one sentence", replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.clock.now = 8.1
        fixture.room.tick()
        settleBar(fixture)
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
        settleBar(fixture)
        if copy { fixture.room.copyKeptText() }
        return fixture.room
    }

    // MARK: - Rendering

    private func snapshot(_ controller: NSViewController, name: String, appearance: NSAppearance.Name,
                          output: URL?, sheetPoint: NSPoint? = nil, paperPoint: NSPoint? = nil,
                          washPoint: (point: NSPoint, fraction: CGFloat)? = nil,
                          focus: Bool = false) throws {
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
        if let paperPoint {
            let scale = CGFloat(rep.pixelsWide) / size.width
            try assertPaper(rep, around: NSPoint(x: paperPoint.x * scale, y: paperPoint.y * scale),
                            in: appearance, name: name)
        }
        if let washPoint {
            let scale = CGFloat(rep.pixelsWide) / size.width
            try assertWash(rep, around: NSPoint(x: washPoint.point.x * scale, y: washPoint.point.y * scale),
                           fraction: washPoint.fraction, in: appearance, name: name)
        }
        if focus { window.orderOut(nil) }
        SnapshotWindowKeeper.windows.append(window)
    }

    /// The paper is measured, not eyeballed: a text-free region must average the locked tone and must
    /// carry grain (a real spread), on every room state the wash does not cover, in both appearances (D-056).
    private func assertPaper(_ rep: NSBitmapImageRep, around point: NSPoint,
                             in appearance: NSAppearance.Name, name: String) throws {
        let resolved = try #require(appearanceColor(FirstLineColors.paperNSColor, appearance))
        let expected = try #require(resolved.usingColorSpace(.sRGB))
        let side = 24
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var samples: [(Double, Double, Double)] = []
        for y in Int(point.y)..<Int(point.y) + side {
            for x in Int(point.x)..<Int(point.x) + side {
                guard let colour = pixel(rep, x: x, y: y) else { continue }
                let sample = (Double(colour.redComponent), Double(colour.greenComponent), Double(colour.blueComponent))
                samples.append(sample)
                sum.r += sample.0
                sum.g += sample.1
                sum.b += sample.2
            }
        }
        let count = Double(samples.count)
        try #require(count > 0)
        let mean = (sum.r / count, sum.g / count, sum.b / count)
        // The exact two-level tone assertion runs on the field the view draws, in
        // `PaperContrastTests.theRenderedFieldStaysOnTheLockedTone`, where the pixels are the ones the sheet is
        // made of. This window bitmap is a 24 px patch of a mottled sheet, so it guards gross drift (a lamp light used to lift the dark sheet 25 levels) while the field
        // assertion guards the value itself (D-072).
        let lift = [mean.0 - Double(expected.redComponent),
                    mean.1 - Double(expected.greenComponent),
                    mean.2 - Double(expected.blueComponent)]
        let variance = samples.reduce(0.0) { $0 + pow($1.0 - mean.0, 2) } / count
        let spread = variance.squareRoot()
        let outOfBand = lift.contains { abs($0) > 0.06 }
        #expect(!outOfBand, "\(name): the paper's tone left the locked band, mean=\(mean) lift=\(lift)")
        #expect(spread > 0.002, "\(name): the paper carries no grain, spread=\(spread)")
    }

    /// The warning sheet is measured too: the rendered patch must be the paper tone mixed toward the locked
    /// wash colour by the state's own fraction, warmed against the plain sheet and painted with grain. The plain
    /// tone band cannot hold here, because the alarm is a state on the sheet rather than a second paper (D-072).
    private func assertWash(_ rep: NSBitmapImageRep, around point: NSPoint, fraction: CGFloat,
                            in appearance: NSAppearance.Name, name: String) throws {
        let base = try #require(appearanceColor(FirstLineColors.paperNSColor, appearance)?.usingColorSpace(.sRGB))
        let target = try #require(appearanceColor(FirstLineColors.paperWashNSColor, appearance)?.usingColorSpace(.sRGB))
        let expected = (r: base.redComponent + (target.redComponent - base.redComponent) * fraction,
                        g: base.greenComponent + (target.greenComponent - base.greenComponent) * fraction,
                        b: base.blueComponent + (target.blueComponent - base.blueComponent) * fraction)
        let side = 24
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var count = 0.0
        for y in Int(point.y)..<Int(point.y) + side {
            for x in Int(point.x)..<Int(point.x) + side {
                guard let colour = pixel(rep, x: x, y: y) else { continue }
                sum.r += Double(colour.redComponent)
                sum.g += Double(colour.greenComponent)
                sum.b += Double(colour.blueComponent)
                count += 1
            }
        }
        try #require(count > 0)
        let mean = (r: sum.r / count, g: sum.g / count, b: sum.b / count)
        let lift = (mean.r - Double(expected.r), mean.g - Double(expected.g), mean.b - Double(expected.b))
        // Same tolerance as the plain-tone patch: this bitmap round-trips through the window's colour space,
        // while the exact wash value is asserted on the paper wash view and in `PaperContrastTests`.
        #expect(abs(lift.0) < 0.06 && abs(lift.1) < 0.06 && abs(lift.2) < 0.06,
                "\(name): the washed sheet is not the locked wash tint, lift=\(lift)")
        #expect(Double(base.redComponent - base.greenComponent) < mean.0 - mean.1,
                "\(name): the wash does not warm the sheet")
    }

    private func assertPixel(_ rep: NSBitmapImageRep, at point: NSPoint, equals token: NSColor,
                             in appearance: NSAppearance.Name, name: String) throws {
        let resolved = try #require(appearanceColor(token, appearance))
        let color = try #require(pixel(rep, x: Int(point.x), y: Int(point.y)))
        let expected = try #require(resolved.usingColorSpace(.sRGB))
        let delta = abs(color.redComponent - expected.redComponent)
            + abs(color.greenComponent - expected.greenComponent)
            + abs(color.blueComponent - expected.blueComponent)
        if delta >= 0.16 { print("PIXFAIL \(name) point=\(Int(point.x)),\(Int(point.y)) got=\(color) expected=\(expected) size=\(rep.pixelsWide)x\(rep.pixelsHigh)") }
        #expect(delta < 0.16, "\(name): pixel \(Int(point.x)),\(Int(point.y)) differs from the token")
    }

    /// A bitmap pixel read in the bitmap's own colour space. `colorAt` tags the bytes as calibrated RGB, so
    /// converting that to sRGB lifts dark tones by about 15 levels that are not on the screen.
    private func pixel(_ rep: NSBitmapImageRep, x: Int, y: Int) -> NSColor? {
        var raw = [Int](repeating: 0, count: rep.samplesPerPixel)
        rep.getPixel(&raw, atX: x, y: y)
        let maximum = CGFloat((1 << rep.bitsPerSample) - 1)
        var components = raw.map { CGFloat($0) / maximum }
        if components.count == 3 { components.append(1) }
        return NSColor(colorSpace: rep.colorSpace, components: &components, count: components.count)
            .usingColorSpace(.sRGB)
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

    private func allViews<T: NSView>(in view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { allViews(in: $0, of: type) }
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
