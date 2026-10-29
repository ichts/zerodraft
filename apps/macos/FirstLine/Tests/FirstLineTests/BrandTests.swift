import AppKit
import Foundation
import Testing
@testable import WriteItDown

@MainActor
struct BrandTests {
    @Test func infoPlistNamesWriteItDown() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/FirstLine/Info.plist").standardizedFileURL
        let data = try Data(contentsOf: plist)
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["CFBundleIdentifier"] as? String == "app.writeitdown.mac")
        #expect(AppPaths.applicationSupportRoot.lastPathComponent == "WriteItDown")
        #expect(info["CFBundleName"] as? String == "Write It Down")
        #expect(info["WIDDisplayPrice"] as? String == "$4.99")
        #expect(AppState.checkoutURL?.absoluteString == "https://writeitdown.app/mac.html")
        #expect(AppState.licenseProductID == "prod_VUeTDTehcGAqJK")
        #expect(info["WIDLicenseServiceURL"] as? String == "https://licenses.writeitdown.app")
        #expect(info["WIDLicensePublicKey"] as? String == "ZjyVb5Twq4UPWjattEuyWZdSr0nsAYslV41RJtFtBsw=")
        #expect(AppState.configuredLicenseClient.isConfigured)
        #expect((info["NSHumanReadableCopyright"] as? String)?.contains("Your Company") == false)
    }

    @Test func startScreenAndMenusShowWriteItDown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        let home = HomeViewController(appState: state)
        home.loadViewIfNeeded()
        let labels = allLabels(in: home.view)
        let lockups = descendants(of: BrandChipLockupView.self, in: home.view)
        #expect(lockups.count == 1)
        #expect(lockups.first?.accessibilityLabel() == "Write It Down")
        #expect(labels.contains("How long?"))
        #expect(!labels.contains("Forward only. Nothing is saved."))
        #expect(labels.contains("Minutes") || labels.contains("minutes"))
        #expect(labels.contains("Delete after silence"))
        #expect(allButtons(in: home.view).contains { $0.title == "1" })
        #expect(allButtons(in: home.view).contains { $0.title == "Begin" })
        let help = try #require(allButtons(in: home.view).first { $0.title == "?" })
        #expect(help.accessibilityLabel() == "How it works")
        let menu = MainMenuBuilder.buildMenu(appState: state, validationOwner: FirstLineAppDelegate())
        #expect(menu.items.first?.title == "Write It Down")
        #expect(menu.items.first?.submenu?.items.first?.title == "About Write It Down")
        #expect(RootWindowController(appState: state).window?.title == "Write It Down")
    }

    @Test func startScreenHasNoSiteHeadlineDeckOrSlogan() {
        let state = AppState()
        let home = HomeViewController(appState: state)
        let labels = allLabels(in: home.view).joined(separator: " ")
        #expect(!labels.contains("We force you"))
        #expect(!labels.contains("With a clock"))
        #expect(!labels.contains("Give it sixty seconds"))
    }

    @Test func upgradeShowsOneTimePrice() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root), installIDStore: InstallIDStore(configDirectory: root))
        let upgrade = UpgradeViewController(appState: state)
        upgrade.loadViewIfNeeded()
        let price = AppState.displayPrice
        #expect(allLabels(in: upgrade.view).contains { $0.contains(price) })
    }

    @Test func rulesViewReusesTheLandingExplanationAndDismisses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root),
                             installIDStore: InstallIDStore(configDirectory: root))
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = home
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.makeKeyAndOrderFront(nil)
        home.view.layoutSubtreeIfNeeded()
        let help = try #require(allButtons(in: home.view).first { $0.title == "?" })
        window.makeFirstResponder(help)
        #expect(window.firstResponder === help, "the question mark is not keyboard reachable")
        help.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let rules = try #require(home.presentedViewControllers?.first as? RulesViewController)
        rules.view.layoutSubtreeIfNeeded()
        let labels = allLabels(in: rules.view)
        let ordered = ["How it works", "Forward only. Nothing kept.", "No way back",
                       "Eight seconds of silence", "Reach zero, keep it"]
        for text in ordered {
            #expect(labels.contains(text), "missing rule text: \(text)")
        }
        let positions = ordered.compactMap { labels.firstIndex(of: $0) }
        #expect(positions == positions.sorted(), "the rules are not in the landing page's order")
        #expect(labels.contains("Open it, start typing, say the thing you have been avoiding. The only way out is through."))
        #expect(!labels.contains { $0.contains("!") })
        let done = try #require(allButtons(in: rules.view).first { $0.title == "Done" })
        #expect(done.keyEquivalent == "\r")
        let ret = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: rules.view.window!.windowNumber,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        #expect(rules.view.window?.performKeyEquivalent(with: ret) == true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        #expect(home.presentedViewControllers?.isEmpty != false, "Return did not dismiss the rules")
        window.orderOut(nil)
    }

    @Test func rulesViewCancelOperationDismisses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState(settingsStore: SettingsStore(configDirectory: root),
                             installIDStore: InstallIDStore(configDirectory: root))
        let home = HomeViewController(appState: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = home
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.makeKeyAndOrderFront(nil)
        home.view.layoutSubtreeIfNeeded()
        let help = try #require(allButtons(in: home.view).first { $0.title == "?" })
        window.makeFirstResponder(help)
        help.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let rules = try #require(home.presentedViewControllers?.first as? RulesViewController)
        rules.view.layoutSubtreeIfNeeded()
        let sheet = try #require(rules.view.window)
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        sheet.sendEvent(escape)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        #expect(home.presentedViewControllers?.isEmpty == true, "Escape did not dismiss the rules")
        window.orderOut(nil)
    }

    private func allTextFields(in view: NSView) -> [NSTextField] {
        let current = (view as? NSTextField).map { [$0] } ?? []
        return current + view.subviews.flatMap(allTextFields)
    }

    private func allButtons(in view: NSView) -> [NSButton] {
        let current = (view as? NSButton).map { [$0] } ?? []
        return current + view.subviews.flatMap(allButtons)
    }

    private func allLabels(in view: NSView) -> [String] {
        let value = (view as? NSButton)?.title ?? (view as? NSControl)?.stringValue
        return (value.map { [$0] } ?? []) + view.subviews.flatMap(allLabels)
    }

    /// The picker's front door shows the same A mark chip the web header opens with: the
    /// app icon's squircle plate around the split W, then the wordmark on the same baseline
    /// (D-075). Geometry, layer order and theme polarity are measured, not eyeballed.
    @Test func pickerLockupShowsTheChipTheWebHeaderUses() throws {
        _ = NSApplication.shared
        for (appearance, plateIsLight) in [(NSAppearance.Name.aqua, true), (.darkAqua, false)] {
            let state = AppState()
            let home = HomeViewController(appState: state)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentViewController = home
            window.setContentSize(NSSize(width: 1040, height: 720))
            home.view.layoutSubtreeIfNeeded()
            let lockup = try #require(descendants(of: BrandChipLockupView.self, in: home.view).first)
            defer { window.orderOut(nil) }

            let size = lockup.intrinsicContentSize
            #expect(abs(size.height - BrandChipLockupView.pickerTypeSize * BrandChipLockupView.emHeight) < 0.01,
                    "the lockup keeps the web header's 1.046 em height")
            #expect(abs(size.width / size.height - BrandChipLockupView.emWidth / BrandChipLockupView.emHeight) < 0.001,
                    "the lockup keeps the web header's 7.467 x 1.046 em box")
            let chip = lockup.chipFrame
            #expect(abs(chip.width - chip.height) < 0.01, "the chip is square")
            #expect(abs(chip.width - lockup.bounds.height) < 0.01, "the chip spans the lockup's full height")
            #expect(abs(chip.minX) < 0.01, "the chip opens the lockup")
            #expect(abs(lockup.wordmarkFrame.width - lockup.bounds.width) < 0.01, "the wordmark spans the box")
            #expect(abs(chip.width / lockup.bounds.width - 1.046 / 7.467) < 0.001,
                    "the chip takes the 1.046 em share of the lockup")
            #expect(abs(lockup.chipCornerRadius - chip.height * 0.2233) < 0.01,
                    "the plate is the app icon's 22.33% squircle")

            let plate = resolved(BrandChipLockupView.plateFillColor, appearance)
            let edge = resolved(BrandChipLockupView.plateEdgeColor, appearance)
            let ink = resolved(FirstLineColors.inkNSColor, appearance)
            #expect(sameColor(plate, FirstLineColors.pageNSColor, appearance: appearance))
            #expect(sameColor(edge, FirstLineColors.hairStrongNSColor, appearance: appearance))
            #expect((luminance(plate) > luminance(ink)) == plateIsLight,
                    "light appearance: paper plate under ink W; dark: ink plate under bone W")

            // The composed lockup really draws the plate under the W, and the wordmark
            // continues to its right. A wordmark-only lockup has no plate pixels.
            let rep = try bitmap(of: lockup)
            let scale = CGFloat(rep.pixelsWide) / max(lockup.bounds.width, 1)
            let chipPixels = Int((chip.width * scale).rounded())
            let counts = pixelCounts(rep, chipWidth: chipPixels, plate: plate, ink: ink)
            let chipArea = Double(chipPixels * chipPixels)
            #expect(Double(counts.plate) / chipArea > 0.5, "the plate covers the chip")
            #expect(Double(counts.ink) / chipArea > 0.03, "the W strokes sit inside the chip")
            #expect(Double(counts.ink) / chipArea < 0.4, "the plate stays visible around the W")
            #expect(counts.word > 0, "the wordmark follows the chip")

            // The mark sits on the plate, not beside it: the W's box lies inside the chip, is
            // centred on it and takes the chip's 0.798 width share (DESIGN 11.6). The old
            // wordmark-only glyph put its W off the plate's centre and failed these. Measured on
            // the glyph layer rendered at 8x so antialiasing does not move the edges.
            let box = try #require(glyphInkBox(of: lockup, chipWidth: chip.width))
            #expect(abs(box.width / chip.width - 0.798) < 0.02, "the W takes 0.798 of the plate: \(box)")
            #expect(abs(box.midX - chip.width / 2) < chip.width * 0.04, "the W is centred on the plate: \(box)")
            #expect(abs(box.midY - chip.height / 2) < chip.height * 0.04, "the W is vertically centred: \(box)")
        }
    }

    private struct PixelCounts {
        let plate: Int
        let ink: Int
        let word: Int
    }

    private func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// Counts covered pixels on the plate side and the ink side of the chip, plus ink
    /// pixels right of it. A wordmark-only lockup leaves the chip's surrounding pixels
    /// transparent and fails the plate share; a missing W fails the ink share.
    private func pixelCounts(_ rep: NSBitmapImageRep, chipWidth: Int,
                             plate: NSColor, ink: NSColor) -> PixelCounts {
        let plateLight = luminance(plate)
        let inkLight = luminance(ink)
        let midpoint = (plateLight + inkLight) / 2
        let plateIsLighter = plateLight > inkLight
        var plateCount = 0
        var inkCount = 0
        var wordCount = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.5 else { continue }
                let light = luminance(color)
                let onPlateSide = plateIsLighter ? light > midpoint : light < midpoint
                if onPlateSide {
                    if x < chipWidth { plateCount += 1 }
                } else if x < chipWidth {
                    inkCount += 1
                } else {
                    wordCount += 1
                }
            }
        }
        return PixelCounts(plate: plateCount, ink: inkCount, word: wordCount)
    }

    /// The bounding box (in lockup points) of the glyph layer's coverage inside the chip's width.
    private func glyphInkBox(of lockup: BrandChipLockupView, chipWidth: CGFloat) -> CGRect? {
        guard let image = lockup.wordmarkImage else { return nil }
        let scale: CGFloat = 8
        let size = lockup.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = { rep.size = size; return NSGraphicsContext(bitmapImageRep: rep) }() else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<Int(chipWidth * scale) {
                guard (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 else { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// The bundled glyph layer is the web header's, byte for byte, so the two chips cannot drift.
    @Test func pickerGlyphLayerIsTheWebHeadersFile() throws {
        let web = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("writeitdown/logo/write-it-down-lockup.svg")
        let bundled = try #require(BundledResources.bundle.url(forResource: "write-it-down-lockup", withExtension: "svg"))
        #expect(try Data(contentsOf: bundled) == Data(contentsOf: web))
    }

    private func resolved(_ color: NSColor, _ appearance: NSAppearance.Name) -> NSColor {
        var value = color
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            value = color.usingColorSpace(.sRGB) ?? color
        }
        return value
    }

    private func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * Double(rgb.redComponent) + 0.7152 * Double(rgb.greenComponent) + 0.0722 * Double(rgb.blueComponent)
    }

    private func sameColor(_ lhs: NSColor, _ rhs: NSColor, appearance: NSAppearance.Name) -> Bool {
        let left = resolved(lhs, appearance)
        let right = resolved(rhs, appearance)
        return abs(left.redComponent - right.redComponent) < 0.01
            && abs(left.greenComponent - right.greenComponent) < 0.01
            && abs(left.blueComponent - right.blueComponent) < 0.01
            && abs(left.alphaComponent - right.alphaComponent) < 0.01
    }

    private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        view.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: type, in: child)
        }
    }
}
