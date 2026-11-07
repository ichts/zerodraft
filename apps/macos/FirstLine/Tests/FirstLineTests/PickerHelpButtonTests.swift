import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// D-091: the picker's help button is a quiet 32 pt circle on the logo row's centre line, flush with the card's
/// inner padding. Numbers decide; the real-window captures only show what the numbers describe.
@MainActor
struct PickerHelpButtonTests {
    @MainActor private struct Rig {
        let window: NSWindow
        let card: FirstLineCardView
        let lockup: BrandChipLockupView
        let help: NSButton
        var content: NSView { card.contentView }
        func frame(_ view: NSView) -> NSRect { view.convert(view.bounds, to: content) }
    }

    private func rig(dark: Bool = false) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = 1
        let store = SettingsStore(configDirectory: root)
        try store.save(settings)
        let state = AppState(settingsStore: store, licenseClient: MockLicenseClient(),
                             checkoutClient: MockCheckoutClient(), installIDStore: InstallIDStore(configDirectory: root),
                             productID: "prod_mock")
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentViewController = home
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.makeKeyAndOrderFront(nil)
        home.view.layoutSubtreeIfNeeded()
        home.viewDidAppear()
        home.view.layoutSubtreeIfNeeded()
        let card = try #require(descendants(home.view, FirstLineCardView.self).first)
        let lockup = try #require(descendants(home.view, BrandChipLockupView.self).first)
        let help = try #require(descendants(home.view, NSButton.self).first {
            $0.accessibilityLabel() == "How it works"
        })
        return Rig(window: window, card: card, lockup: lockup, help: help)
    }

    private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        view.subviews.flatMap { ((($0 as? T).map { [$0] }) ?? []) + descendants($0, type) }
    }

    private func resolved(_ colour: NSColor?, _ appearance: NSAppearance) -> [CGFloat] {
        var out: [CGFloat] = []
        appearance.performAsCurrentDrawingAppearance {
            if let c = colour?.usingColorSpace(.sRGB) { out = [c.redComponent, c.greenComponent, c.blueComponent] }
        }
        return out
    }

    /// WCAG relative-luminance contrast of two opaque sRGB colours.
    private func contrast(_ a: NSColor, _ b: NSColor, in appearance: NSAppearance) -> Double {
        func luminance(_ colour: NSColor) -> Double {
            var out = 0.0
            appearance.performAsCurrentDrawingAppearance {
                let c = colour.usingColorSpace(.sRGB)!
                func lin(_ v: CGFloat) -> Double { v <= 0.03928 ? Double(v) / 12.92 : pow((Double(v) + 0.055) / 1.055, 2.4) }
                out = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
            }
            return out
        }
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test func helpIsAQuietCircleOnTheLogoCentreLineFlushWithTheCardPadding() throws {
        let r = try rig()
        defer { r.window.orderOut(nil) }
        let frame = r.frame(r.help)
        #expect(abs(frame.width - 32) < 0.5 && abs(frame.height - 32) < 0.5)
        #expect(abs(frame.midY - r.frame(r.lockup).midY) <= 0.5)
        #expect(abs(frame.maxX - r.content.bounds.maxX) <= 0.5)
        r.help.displayIfNeeded()
        r.help.updateLayer()
        #expect(r.help.layer?.cornerRadius == 16)
        #expect((r.help.layer?.borderWidth ?? 0) == 1)
        let centre = r.help.convert(NSPoint(x: r.help.bounds.midX, y: r.help.bounds.midY), to: r.content.superview)
        #expect(r.content.hitTest(centre) === r.help)
        // The "?" is text on the sheet: 7:1 floor, in ink (the quiet chrome role was 5.8:1 in dark).
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            #expect(contrast(FirstLineColors.inkNSColor, FirstLineColors.sheetNSColor, in: appearance) >= 7)
        }
        #expect(resolved(r.help.contentTintColor, r.window.effectiveAppearance)
            == resolved(FirstLineColors.inkNSColor, r.window.effectiveAppearance))
        let dark = try rig(dark: true)
        defer { dark.window.orderOut(nil) }
        #expect(resolved(dark.help.contentTintColor, dark.window.effectiveAppearance)
            == resolved(FirstLineColors.inkNSColor, dark.window.effectiveAppearance))
        // Keyboard: the ink focus ring is the circle itself, 3 pt outside.
        r.window.makeFirstResponder(r.help)
        #expect((r.help as? FirstLineInkFocusRinging)?.showsInkFocusRing == true)
    }
}
