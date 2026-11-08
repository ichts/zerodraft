import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// D-102: the window has no ground of its own; the paper keeps today's size and place and the writer's desktop
/// shows around it. Numbers decide; the real-window captures only show what the numbers describe.
@MainActor
struct WallpaperWindowTests {
    private func controller(surface: Surface) -> (RootWindowController, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = 1
        let store = SettingsStore(configDirectory: root)
        try? store.save(settings)
        let state = AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                             checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        if surface == .session { state.startSession() }
        let controller = RootWindowController(appState: state)
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1040, height: 720), display: false)
        controller.window?.orderFront(nil)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return (controller, root)
    }

    private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        view.subviews.flatMap { ((($0 as? T).map { [$0] }) ?? []) + descendants($0, type) }
    }

    private func rgb(_ colour: NSColor) -> [CGFloat] {
        var out: [CGFloat] = []
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            if let c = colour.usingColorSpace(.sRGB) { out = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent] }
        }
        return out
    }

    private func alpha(_ colour: NSColor?) -> CGFloat { colour?.usingColorSpace(.sRGB)?.alphaComponent ?? -1 }

    @Test func windowIsClearWithClearTitleBarAndNoShadowOfItsOwn() throws {
        let (controller, root) = controller(surface: .home)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = try #require(controller.window)
        #expect(!window.isOpaque)
        #expect(!window.hasShadow)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titlebarSeparatorStyle == .none, "macOS 26 draws a 1 px rule under a clear title bar otherwise")
        #expect(window.titleVisibility == .hidden)
        #expect(window.title == "Write It Down")
        #expect(window.styleMask.contains(.fullSizeContentView))
        // Alpha 0 would let clicks fall through the margin; one step above keeps it a window.
        let a = alpha(window.backgroundColor)
        #expect(a > 0 && a < 0.01)
        #expect(window.isMovableByWindowBackground)
    }

    @Test func theSystemsLitTopEdgeStaysHiddenThroughResizeAndFocusChanges() throws {
        let (controller, root) = controller(surface: .home)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = try #require(controller.window)
        func decorations(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { (String(describing: type(of: $0)).contains("TitlebarDecoration") ? [$0] : []) + decorations($0) }
        }
        let frame = try #require(window.contentView?.superview)
        #expect(!decorations(frame).isEmpty, "the title bar decoration view exists on this macOS; otherwise this test proves nothing")
        #expect(decorations(frame).allSatisfy { $0.isHidden }, "a lit 1 px edge over a clear ground reads as a stray hairline")
        for view in decorations(frame) { view.isHidden = false }
        window.setFrame(NSRect(x: 0, y: 0, width: 1100, height: 760), display: false)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(decorations(frame).allSatisfy { $0.isHidden }, "AppKit re-shows it on resize and focus changes; the room hides it again")
    }

    @Test func paperKeepsTodaysSizeAndPlaceUnderTheClearTitleBar() throws {
        let (controller, root) = controller(surface: .session)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        let paper = try #require(descendants(content, PaperSheetView.self).first)
        let frame = paper.convert(paper.bounds, to: nil)
        let titleBar = window.frame.height - window.contentLayoutRect.height
        // Today: a 28 pt title bar above, then the 32 pt page gutter on every side of the paper.
        #expect(abs(frame.minX - 32) < 0.5)
        #expect(abs((window.frame.width - frame.maxX) - 32) < 0.5)
        #expect(abs(frame.minY - 32) < 0.5)
        #expect(abs((window.frame.height - frame.maxY) - (titleBar + 32)) < 0.5)
        #expect(window.contentMinSize.height - 680 == titleBar)
    }

    @Test func everySurfaceGroundIsClearInAWindowAndPageColourInFullScreen() throws {
        for surface in [Surface.home, .session, .settings, .upgrade] {
            let (controller, root) = controller(surface: .home)
            defer { try? FileManager.default.removeItem(at: root) }
            let window = try #require(controller.window)
            controller.appState.selectedSurface = surface
            controller.container.show(surface)
            let ground = try #require(window.contentViewController?.view as? FloodCanvasView)
            let surfaceView = try #require(ground.subviews.last as? FloodCanvasView)
            #expect(alpha(ground.fillColor) == 0, "\(surface) root ground")
            #expect(alpha(surfaceView.fillColor) == 0, "\(surface) surface ground")
            controller.container.setFullScreenGround(true)
            #expect(rgb(ground.fillColor) == rgb(FirstLineColors.pageNSColor))
            controller.container.setFullScreenGround(false)
            #expect(alpha(ground.fillColor) == 0)
        }
    }

    @Test func theSheetShadowFitsTheGutterSoTheWindowEdgeNeverCutsIt() throws {
        for dark in [false, true] {
            let (controller, root) = controller(surface: .session)
            defer { try? FileManager.default.removeItem(at: root) }
            let window = try #require(controller.window)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let content = try #require(window.contentView)
            let shadow = try #require(descendants(content, FirstLineShadowView.self).first)
            #expect(shadow.effectiveReach <= SessionViewController.sheetMargin + 0.01, "dark=\(dark)")
            #expect(shadow.effectiveReach > 12, "the shadow stays a soft shadow, dark=\(dark)")
        }
    }

    @Test func trafficLightsStepOutWhileTheRoomIsLiveAndComeBackOnHoverOrStop() throws {
        let (controller, root) = controller(surface: .session)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = try #require(controller.window)
        let engine = controller.appState.sessionEngine
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let lights = { kinds.map { window.standardWindowButton($0)?.alphaValue ?? -1 } }
        let room = try #require(controller.container.children.compactMap { $0 as? SessionViewController }.first)
        #expect(lights() == [1, 1, 1], "the empty room keeps them")
        engine.registerCommittedText("I")
        room.refreshRoom()
        #expect(lights() == [0, 0, 0], "typing hides them")
        let top = NSPoint(x: 400, y: window.frame.height - 6)
        room.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: top, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 0, pressure: 0)!)
        #expect(lights() == [1, 1, 1], "the title strip brings them back")
        room.viewWillDisappear()
        #expect(lights() == [1, 1, 1], "leaving the room restores them")
    }
}
