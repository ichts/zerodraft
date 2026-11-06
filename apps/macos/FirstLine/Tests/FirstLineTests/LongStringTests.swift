import AppKit
import Foundation
import Testing
@testable import WriteItDown

/// Mac design audit A5: the app ships one locale today, but no control may clip its own label when a
/// string runs long. Two synthetic passes at the minimum window (980x680): a German-like pass (every
/// word grows by about half, unbreakable) and a CJK pass (full-width glyphs, no spaces). A text that
/// does not fit its frame fails here before a translation ever does.
@MainActor
struct LongStringTests {
    private static let minimum = NSSize(width: 980, height: 680)

    enum Pass: String, CaseIterable {
        case german, cjk

        func stretch(_ text: String) -> String {
            switch self {
            case .german:
                return text.split(separator: " ", omittingEmptySubsequences: false).map { word in
                    word.count < 3 ? String(word) : word + String(repeating: "ung", count: max(1, word.count / 3))
                }.joined(separator: " ")
            case .cjk:
                return String(repeating: "写", count: max(2, text.filter { !$0.isWhitespace }.count))
            }
        }
    }

    // MARK: - Surfaces

    @Test(arguments: Pass.allCases) func pickerKeepsEverySegmentWhole(pass: Pass) throws {
        let home = HomeViewController(appState: try trialState(used: 1))
        let window = host(home)
        stress(home.view, pass)
        try assertNothingClips(in: home.view, surface: "picker/\(pass)")
        window.orderOut(nil)
    }

    @Test(arguments: Pass.allCases) func activationKeepsEveryPillWhole(pass: Pass) throws {
        let upgrade = UpgradeViewController(appState: try trialState(used: 3))
        let window = host(upgrade)
        stress(upgrade.view, pass)
        try assertNothingClips(in: upgrade.view, surface: "activation/\(pass)")
        window.orderOut(nil)
    }

    @Test(arguments: Pass.allCases) func rulesRowsGrowWithTheirText(pass: Pass) throws {
        let rules = RulesViewController()
        let window = host(rules)
        stress(rules.view, pass)
        try assertNothingClips(in: rules.view, surface: "rules/\(pass)")
        window.orderOut(nil)
    }

    @Test(arguments: Pass.allCases) func settingsKeepsEveryControlWhole(pass: Pass) throws {
        let settings = SettingsViewController(appState: try trialState(used: 3), updateSettings: StubUpdateSettings())
        let window = host(settings)
        stress(settings.view, pass)
        try assertNothingClips(in: settings.view, surface: "settings/\(pass)")
        window.orderOut(nil)
    }

    // MARK: - Mechanics

    /// Rewrites every visible label and button title in place, keeping each one's own font and paragraph style.
    private func stress(_ root: NSView, _ pass: Pass) {
        for field in descendants(of: root, as: NSTextField.self) where !field.isEditable && !field.isHiddenOrHasHiddenAncestor {
            let current = field.attributedStringValue
            guard current.length > 0 else { continue }
            let next = NSMutableAttributedString(attributedString: current)
            next.replaceCharacters(in: NSRange(location: 0, length: next.length), with: pass.stretch(current.string))
            field.attributedStringValue = next
        }
        for button in descendants(of: root, as: NSButton.self) where !button.isHiddenOrHasHiddenAncestor && !button.title.isEmpty {
            guard button.title != "?" else { continue }
            button.title = pass.stretch(button.title)
            button.invalidateIntrinsicContentSize()
        }
        root.window?.contentView?.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
    }

    /// With `WID_SNAPSHOT_DIR` set, the stressed surface is also written out as a PNG (a content snapshot).
    private func record(_ root: NSView, surface: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["WID_SNAPSHOT_DIR"] else { return }
        root.displayIfNeeded()
        let rep = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try data.write(to: url.appendingPathComponent("stress-" + surface.replacingOccurrences(of: "/", with: "-") + ".png"))
    }

    private func assertNothingClips(in root: NSView, surface: String) throws {
        try record(root, surface: surface)
        let clip = (root.window?.contentView ?? root).bounds
        for field in descendants(of: root, as: NSTextField.self) where !field.isHiddenOrHasHiddenAncestor {
            let text = field.attributedStringValue
            guard text.length > 0, field.frame.width > 0 else { continue }
            if field.maximumNumberOfLines == 1 {
                #expect(text.size().width <= field.frame.width + 1,
                        "\(surface): '\(text.string.prefix(24))' is \(text.size().width) wide in \(field.frame.width)")
            } else {
                let needed = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.frame.width,
                                                                    height: .greatestFiniteMagnitude)).height ?? 0
                #expect(field.frame.height + 1 >= needed,
                        "\(surface): '\(text.string.prefix(24))' needs \(needed) tall, has \(field.frame.height)")
            }
        }
        for button in descendants(of: root, as: NSButton.self) where !button.isHiddenOrHasHiddenAncestor && !button.title.isEmpty {
            let font = button.font ?? .systemFont(ofSize: 13)
            let width = NSAttributedString(string: button.title, attributes: [.font: font]).size().width
            #expect(button.frame.width + 0.5 >= button.intrinsicContentSize.width,
                    "\(surface): '\(button.title.prefix(24))' is squeezed to \(button.frame.width), its own size is \(button.intrinsicContentSize.width)")
            #expect(width <= button.frame.width + 1,
                    "\(surface): '\(button.title.prefix(24))' is \(width) wide in a \(button.frame.width) pill")
            let frame = root.convert(button.bounds, from: button)
            #expect(clip.insetBy(dx: -1, dy: -1).contains(frame) || button.enclosingScrollView != nil,
                    "\(surface): '\(button.title.prefix(24))' leaves the window: \(frame)")
        }
    }

    private func host(_ controller: NSViewController) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.minimum), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentViewController = controller
        window.setContentSize(Self.minimum)
        window.contentView?.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        return window
    }

    private func trialState(used: Int) throws -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = AppSettings.defaultValue
        settings.trialSessionsUsed = used
        let store = SettingsStore(configDirectory: root)
        try store.save(settings)
        return AppState(settingsStore: store, licenseClient: MockLicenseClient(), checkoutClient: MockCheckoutClient(),
                        installIDStore: InstallIDStore(configDirectory: root), productID: "prod_mock")
    }

    private func descendants<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        view.subviews.flatMap { ((($0 as? T).map { [$0] }) ?? []) + descendants(of: $0, as: type) }
    }
}
