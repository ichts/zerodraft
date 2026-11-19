import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// D-102: the window has no ground of its own and the writer's desktop shows around the paper; D-116: the lights
/// live in the paper's top gutter. Numbers decide; the real-window captures only show what the numbers describe.
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

    @Test func paperSitsTheSameGutterFromAllFourWindowEdges() throws {
        let (controller, root) = controller(surface: .session)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        let paper = try #require(descendants(content, PaperSheetView.self).first)
        let frame = paper.convert(paper.bounds, to: nil)
        // The clear title bar adds no gutter of its own: the paper is 32 pt from the top edge like the other three.
        #expect(abs(frame.minX - 32) < 0.5)
        #expect(abs((window.frame.width - frame.maxX) - 32) < 0.5)
        #expect(abs(frame.minY - 32) < 0.5)
        #expect(abs((window.frame.height - frame.maxY) - 32) < 0.5)
        #expect(window.contentMinSize == NSSize(width: 980, height: 680), "the paper's minimum stays 916 x 616")
    }

    /// The writer's view: the three lights sit in the paper's top gutter, centred in its 32 pt, the red one on
    /// the paper's left edge, instead of floating 6-8 pt from the corner over the wallpaper.
    @Test func trafficLightsSitInThePapersTopGutterAlignedToItsLeftEdge() throws {
        let (controller, root) = controller(surface: .session)
        defer { try? FileManager.default.removeItem(at: root) }
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        let paper = try #require(descendants(content, PaperSheetView.self).first)
        let paperFrame = paper.convert(paper.bounds, to: nil)
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let frames = try kinds.map { kind -> NSRect in
            let button = try #require(window.standardWindowButton(kind))
            return button.convert(button.bounds, to: nil)
        }
        for frame in frames {
            #expect(abs((window.frame.height - frame.midY) - 16) < 0.5, "centred in the 32 pt gutter above the paper")
            #expect(frame.maxY <= window.frame.height && window.frame.height - frame.minY <= 32 + 0.5, "inside the gutter")
        }
        #expect(abs(frames[0].minX - paperFrame.minX) < 0.5, "red light on the paper's left edge")
        #expect(frames[0].maxX < frames[1].minX && frames[1].maxX < frames[2].minX, "system order and spacing kept")
        // The system puts the lights back at its own spots whenever it re-lays the title bar (seen on macOS 26
        // the moment typing starts); they follow it to the gutter again without being asked.
        for kind in kinds {
            let button = try #require(window.standardWindowButton(kind))
            button.setFrameOrigin(NSPoint(x: button.frame.minX - 24, y: button.frame.minY + 4))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))  // the end of the system's pass, same turn on screen
        let red = try #require(window.standardWindowButton(.closeButton))
        let reset = try kinds.map { kind -> NSRect in
            let button = try #require(window.standardWindowButton(kind))
            return button.convert(button.bounds, to: nil)
        }
        #expect(abs(reset[0].minX - 32) < 0.5, "back in the gutter after a system reset")
        #expect(abs(reset[1].minX - frames[1].minX) < 0.5 && abs(reset[2].minX - frames[2].minX) < 0.5,
                "the three keep the system's spacing, none lands under another")
        // A resize re-lays the title bar; the lights land back in the same place.
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        let after = red.convert(red.bounds, to: nil)
        #expect(abs(after.minX - 32) < 0.5)
        #expect(abs((window.frame.height - after.midY) - 16) < 0.5)
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
        let top = NSPoint(x: 400, y: window.frame.height - 6)  // inside the 32 pt gutter the lights live in
        room.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: top, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 0, pressure: 0)!)
        #expect(lights() == [1, 1, 1], "the title strip brings them back")
        room.viewWillDisappear()
        #expect(lights() == [1, 1, 1], "leaving the room restores them")
    }
}
