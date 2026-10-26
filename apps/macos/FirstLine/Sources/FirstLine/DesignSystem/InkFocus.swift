/**
 * [INPUT]: AppKit, DesignSystem/Colors.
 * [OUTPUT]: Shared ink focus ring for every button, popup, switch and segmented control.
 * [POS]: One ink focus treatment for card controls; text fields keep the standard system focus ring.
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
/// The geometry lives in plain stored properties so CALayer's nonisolated copy
/// initializer can read them; only drawing is main-actor work.
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

    @MainActor
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

/// One ring per control: installs the outline layer and keeps its geometry and
/// visibility current. The button, popup and switch controls share it so the ink
/// focus treatment has one implementation.
@MainActor
final class InkFocusRing {
    private let outline: FirstLineInkFocusOutline

    init(on control: NSControl) {
        control.focusRingType = .none
        control.wantsLayer = true
        control.layer?.masksToBounds = false
        outline = FirstLineInkFocusOutline()
        control.layer?.addSublayer(outline)
    }

    func update(on control: NSControl, visible: Bool, inset: CGFloat, cornerRadius: CGFloat?) {
        // NSControl subclasses may reset layer masking after init; the ring lives
        // half outside the control bounds and must not be clipped by its own layer.
        control.layer?.masksToBounds = false
        outline.inset = inset
        outline.inkCornerRadius = cornerRadius
        outline.update(for: control, color: FirstLineColors.inkNSColor, visible: visible)
    }

    func beginShowing(on control: NSControl, inset: CGFloat, cornerRadius: CGFloat?) {
        update(on: control, visible: control.window?.firstResponder === control,
               inset: inset, cornerRadius: cornerRadius)
    }
}

@MainActor
class FirstLineInkFocusButton: NSButton, FirstLineInkFocusRinging {
    private var inkRing: InkFocusRing!
    var inkFocusRingInset: CGFloat = 4 { didSet { needsDisplay = true } }
    var inkFocusRingCornerRadius: CGFloat? { didSet { needsDisplay = true } }

    var showsInkFocusRing: Bool { visibleOutline }
    var inkFocusRingColor: NSColor { FirstLineColors.inkNSColor }

    private var visibleOutline: Bool {
        window?.firstResponder === self
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inkRing = InkFocusRing(on: self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inkRing = InkFocusRing(on: self)
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
        guard let inkRing else { return }
        inkRing.update(on: self, visible: visible ?? visibleOutline,
                       inset: inkFocusRingInset, cornerRadius: inkFocusRingCornerRadius)
    }
}

@MainActor
class FirstLineInkPopUpButton: NSPopUpButton, FirstLineInkFocusRinging {
    private var inkRing: InkFocusRing!
    var inkFocusRingInset: CGFloat = 3 { didSet { needsDisplay = true } }
    var inkFocusRingCornerRadius: CGFloat? = 6 { didSet { needsDisplay = true } }

    var showsInkFocusRing: Bool { visibleOutline }
    var inkFocusRingColor: NSColor { FirstLineColors.inkNSColor }

    private var visibleOutline: Bool {
        window?.firstResponder === self
    }

    override init(frame frameRect: NSRect, pullsDown flag: Bool) {
        super.init(frame: frameRect, pullsDown: flag)
        inkRing = InkFocusRing(on: self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inkRing = InkFocusRing(on: self)
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
        guard let inkRing else { return }
        inkRing.update(on: self, visible: visible ?? visibleOutline,
                       inset: inkFocusRingInset, cornerRadius: inkFocusRingCornerRadius)
    }
}

/// A settings boolean: the row's label leads, the switch trails. The switch
/// carries no title of its own, so every control is named exactly once.
@MainActor
final class FirstLineInkSwitch: NSSwitch, FirstLineInkFocusRinging {
    private var inkRing: InkFocusRing!
    var inkFocusRingInset: CGFloat = 3 { didSet { needsDisplay = true } }

    var showsInkFocusRing: Bool { visibleOutline }
    var inkFocusRingColor: NSColor { FirstLineColors.inkNSColor }

    private var visibleOutline: Bool {
        window?.firstResponder === self
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inkRing = InkFocusRing(on: self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inkRing = InkFocusRing(on: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
        guard let inkRing else { return }
        inkRing.update(on: self, visible: visible ?? visibleOutline,
                       inset: inkFocusRingInset, cornerRadius: bounds.height / 2)
    }
}
