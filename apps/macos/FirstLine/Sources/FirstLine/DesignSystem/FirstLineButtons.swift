/**
 * [INPUT]: AppKit, DesignSystem/Colors, DesignSystem/Typography, DesignSystem/Spacing, InkFocus.
 * [OUTPUT]: FirstLineButtons primary (48 ink pill), room primary, secondary (44 outline pill) and quiet link factories; every control uses the ink focus ring.
 * [POS]: Shared native button specs; room primary opts into live hover/press motion, all controls use the design-system ink focus.
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 */

import AppKit

@MainActor
enum FirstLineButtons {
    static func primary(title: String, target: AnyObject?, action: Selector) -> NSButton {
        styled(title: title, target: target, action: action, role: .primary)
    }

    static func roomPrimary(title: String, target: AnyObject?, action: Selector,
                            reducesMotion: @escaping () -> Bool) -> NSButton {
        styled(title: title, target: target, action: action, role: .primary, roomMotion: reducesMotion)
    }

    /// `height` lets a secondary outline button sit in a row with a 48 pt primary
    /// without a 4 pt height mismatch; the pill radius follows the actual height.
    static func secondary(title: String, target: AnyObject?, action: Selector,
                          height: CGFloat? = nil) -> NSButton {
        styled(title: title, target: target, action: action, role: .secondary, height: height)
    }

    static func link(title: String, target: AnyObject?, action: Selector) -> NSButton {
        FirstLineLinkButton(title: title, target: target, action: action)
    }

    private static func styled(
        title: String,
        target: AnyObject?,
        action: Selector,
        role: FirstLineButton.Role,
        roomMotion: (() -> Bool)? = nil,
        height: CGFloat? = nil
    ) -> NSButton {
        let button = FirstLineButton(title: title, target: target, action: action)
        button.inkFocusRingInset = 3
        button.translatesAutoresizingMaskIntoConstraints = false
        button.role = role
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = FirstLineTypography.uiSemiboldNSFont
        button.roomMotion = roomMotion
        button.wantsLayer = true
        let resolvedHeight = height ?? role.height
        button.layer?.cornerRadius = resolvedHeight / 2
        button.heightAnchor.constraint(equalToConstant: resolvedHeight).isActive = true
        return button
    }
}

private final class FirstLineLinkButton: FirstLineInkFocusButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        style()
    }

    private func style() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .inline
        font = .systemFont(ofSize: 13, weight: .medium)
        contentTintColor = FirstLineColors.chromeNSColor
        inkFocusRingInset = 3
        inkFocusRingCornerRadius = 4
        setAccessibilityRole(.button)
    }
}

private final class FirstLineButton: FirstLineInkFocusButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inkFocusRingInset = 3
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        inkFocusRingInset = 3
    }

    enum Role {
        case primary, secondary

        var height: CGFloat {
            switch self {
            case .primary: 48
            case .secondary: 44
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .primary: 24
            case .secondary: 20
            }
        }
    }

    // contentTintColor 是 content 属性，设它会触发 setNeedsLayout。绝不能在 updateLayer()（layout/display
    // pass 内）设它，否则触发 _NSViewLayoutFeedbackLoop 无限回环卡死。这里在 role 变更时设一次；
    // ink/sheet 是 dynamic NSColor，自动随明暗适配，无需在 updateLayer 里重设。
    var role: Role = .secondary {
        didSet {
            // An ink-filled pill cannot carry an ink ring outside itself, and a ring
            // three points inside leaves a dark margin that also reads as a doubled
            // outline. Draw the single light ring on the pill edge instead.
            inkFocusRingInset = role == .primary ? 0 : 3
            refreshAppearance()
        }
    }

    override var inkFocusRingColor: NSColor {
        role == .primary ? FirstLineColors.onInkNSColor : FirstLineColors.inkNSColor
    }

    var roomMotion: (() -> Bool)?
    private var hover = false
    private var pressing = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard roomMotion != nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard roomMotion != nil else { super.mouseEntered(with: event); return }
        hover = true
        updateRoomTransform()
    }

    override func mouseExited(with event: NSEvent) {
        guard roomMotion != nil else { super.mouseExited(with: event); return }
        hover = false
        updateRoomTransform()
    }

    override func mouseDown(with event: NSEvent) {
        pressing = true
        updateRoomTransform()
        defer {
            pressing = false
            updateRoomTransform()
        }
        super.mouseDown(with: event)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateRoomTransform()
    }

    private func updateRoomTransform() {
        guard let roomMotion, let layer else { return }
        let transform = (pressing || isHighlighted) ? CGAffineTransform(scaleX: 0.97, y: 0.97)
            : CGAffineTransform(translationX: 0, y: hover ? 1 : 0)
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(transform)
        CATransaction.commit()
        layer.removeAnimation(forKey: "transform")
        guard !roomMotion() else { return }
        let motion = CABasicAnimation(keyPath: "transform")
        motion.fromValue = NSValue(caTransform3D: previous)
        motion.toValue = NSValue(caTransform3D: layer.transform)
        motion.duration = 0.16
        motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        layer.add(motion, forKey: "transform")
    }

    override var isEnabled: Bool {
        didSet { refreshAppearance() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentTintColor = isEnabled
                ? (role == .primary ? FirstLineColors.onInkNSColor : FirstLineColors.inkNSColor)
                : FirstLineColors.muteNSColor
        }
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + role.horizontalPadding * 2, height: role.height)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = bounds.height > 0 ? bounds.height / 2 : role.height / 2
        effectiveAppearance.performAsCurrentDrawingAppearance {
            guard isEnabled else {
                // A disabled control keeps its own shape: the outline pill stays an
                // outline with a hairline edge and mute label, so an unavailable action
                // is never a heavier object than the available one beside it.
                switch role {
                case .primary:
                    layer?.borderWidth = 0
                    layer?.borderColor = nil
                    layer?.backgroundColor = FirstLineColors.inkNSColor.withAlphaComponent(0.06).cgColor
                case .secondary:
                    layer?.borderWidth = 1
                    layer?.borderColor = FirstLineColors.hairNSColor.cgColor
                    layer?.backgroundColor = FirstLineColors.sheetNSColor.cgColor
                }
                return
            }
            switch role {
            case .primary:
                layer?.borderWidth = 0
                layer?.borderColor = nil
                layer?.backgroundColor = FirstLineColors.inkNSColor.cgColor
            case .secondary:
                layer?.borderWidth = 1
                layer?.borderColor = FirstLineColors.hairStrongNSColor.cgColor
                layer?.backgroundColor = FirstLineColors.sheetNSColor.cgColor
            }
        }
    }
}
