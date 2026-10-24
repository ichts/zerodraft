/**
 * [INPUT]: AppKit, DesignSystem/Colors.
 * [OUTPUT]: Shared ink focus ring for every button, popup and segmented control.
 * [POS]: One focus treatment for all cards; the system accent ring is never used.
 * [PROTOCOL]: Change this header and the focus-ring tests when the treatment changes.
 */
import AppKit

/// Test-facing contract: a control uses the design-system ink ring and can say
/// whether that ring is currently shown.
@MainActor
protocol FirstLineInkFocusRinging: AnyObject {
    var showsInkFocusRing: Bool { get }
    var inkFocusRingColor: NSColor { get }
}

/// The ink outline drawn three points outside a pill/control, matching the live
/// web's 2px ink outline at 3px offset. The control's own focusRingType is none.
@MainActor
private final class FirstLineInkFocusOutline: CAShapeLayer {
    var inset: CGFloat = 4
    var inkCornerRadius: CGFloat?

    override init() {
        super.init()
        fillColor = nil
        lineWidth = 2
        isHidden = true
        name = "firstline-ink-focus"
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let source = layer as? FirstLineInkFocusOutline {
            inset = source.inset
            inkCornerRadius = source.inkCornerRadius
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(for control: NSControl, color: NSColor, visible: Bool) {
        let rect = control.bounds.insetBy(dx: -inset, dy: -inset)
        if frame != rect {
            frame = rect
            bounds = CGRect(origin: .zero, size: rect.size)
        }
        let radius = inkCornerRadius ?? rect.height / 2
        path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        control.effectiveAppearance.performAsCurrentDrawingAppearance {
            strokeColor = color.cgColor
        }
        isHidden = !visible
    }
}

@MainActor
private enum FirstLineInkFocusInstaller {
    static func install(on control: NSControl) -> FirstLineInkFocusOutline {
        control.focusRingType = .none
        control.wantsLayer = true
        control.layer?.masksToBounds = false
        let outline = FirstLineInkFocusOutline()
        control.layer?.addSublayer(outline)
        return outline
    }
}

@MainActor
class FirstLineInkFocusButton: NSButton, FirstLineInkFocusRinging {
    private var inkOutline: FirstLineInkFocusOutline!
    var inkFocusRingInset: CGFloat = 4 { didSet { needsDisplay = true } }
    var inkFocusRingCornerRadius: CGFloat? { didSet { needsDisplay = true } }

    var showsInkFocusRing: Bool { visibleOutline }
    var inkFocusRingColor: NSColor { FirstLineColors.inkNSColor }

    private var visibleOutline: Bool {
        window?.firstResponder === self
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inkOutline = FirstLineInkFocusInstaller.install(on: self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inkOutline = FirstLineInkFocusInstaller.install(on: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusRingType = .none
        needsDisplay = true
        updateInkOutline()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        updateInkOutline()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        updateInkOutline(visible: false)
        return accepted
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        updateInkOutline()
    }

    private func updateInkOutline(visible: Bool? = nil) {
        guard let inkOutline else { return }
        // NSButton may reset layer masking after init; the ring lives half outside
        // the control bounds and must not be clipped by the button's own layer.
        layer?.masksToBounds = false
        inkOutline.inset = inkFocusRingInset
        inkOutline.inkCornerRadius = inkFocusRingCornerRadius
        inkOutline.update(for: self, color: inkFocusRingColor, visible: visible ?? visibleOutline)
    }
}

@MainActor
class FirstLineInkPopUpButton: NSPopUpButton, FirstLineInkFocusRinging {
    private var inkOutline: FirstLineInkFocusOutline!
    var inkFocusRingInset: CGFloat = 3 { didSet { needsDisplay = true } }
    var inkFocusRingCornerRadius: CGFloat? = 6 { didSet { needsDisplay = true } }

    var showsInkFocusRing: Bool { visibleOutline }
    var inkFocusRingColor: NSColor { FirstLineColors.inkNSColor }

    private var visibleOutline: Bool {
        window?.firstResponder === self
    }

    override init(frame frameRect: NSRect, pullsDown flag: Bool) {
        super.init(frame: frameRect, pullsDown: flag)
        inkOutline = FirstLineInkFocusInstaller.install(on: self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inkOutline = FirstLineInkFocusInstaller.install(on: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusRingType = .none
        needsDisplay = true
        updateInkOutline()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        updateInkOutline()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        updateInkOutline(visible: false)
        return accepted
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        updateInkOutline()
    }

    private func updateInkOutline(visible: Bool? = nil) {
        guard let inkOutline else { return }
        // NSButton may reset layer masking after init; the ring lives half outside
        // the control bounds and must not be clipped by the button's own layer.
        layer?.masksToBounds = false
        inkOutline.inset = inkFocusRingInset
        inkOutline.inkCornerRadius = inkFocusRingCornerRadius
        inkOutline.update(for: self, color: inkFocusRingColor, visible: visible ?? visibleOutline)
    }
}
