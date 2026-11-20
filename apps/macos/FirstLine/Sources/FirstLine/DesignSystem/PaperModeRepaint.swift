/**
 * [INPUT]: AppKit window and view tree, FirstLineColors.paperMode, PaperMode.
 * [OUTPUT]: PaperModeRepaint.apply(_:to:) - the one place the app switches paper mode on a window.
 * [POS]: Design-system bridge between the stored mode and AppKit's appearance machinery (D-120).
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 *
 * Paper is the aqua appearance; Lamp and Slate are both darkAqua. AppKit announces light<->dark itself, but not
 * Lamp<->Slate, so after storing the mode this walks the window's views and sends each the same
 * `viewDidChangeEffectiveAppearance` AppKit would have sent. Every view that bakes a colour into a layer or a text
 * attribute already re-resolves there, so one repaint path serves both kinds of switch. A switch repaints colour
 * only: no layout constant, focus, text or timer is touched.
 */

import AppKit

@MainActor
enum PaperModeRepaint {
    static func appearanceName(for mode: PaperMode) -> NSAppearance.Name {
        mode == .paper ? .aqua : .darkAqua
    }

    static func apply(_ mode: PaperMode, to window: NSWindow?) {
        let previous = FirstLineColors.paperMode
        FirstLineColors.paperMode = mode
        guard let window else { return }
        let name = appearanceName(for: mode)
        if window.appearance?.name != name { window.appearance = NSAppearance(named: name) }
        guard previous != mode, let root = window.contentView?.superview ?? window.contentView else { return }
        repaint(root)
    }

    /// Re-resolves every colour under `view`, as an appearance change would.
    static func repaint(_ view: NSView) {
        view.viewDidChangeEffectiveAppearance()
        view.needsDisplay = true
        view.subviews.forEach(repaint)
    }
}
