/**
 * [INPUT]: AppKit, DesignSystem/Colors, DesignSystem/Typography, DesignSystem/Spacing.
 * [OUTPUT]: FirstLineButtons primary (48 ink pill), secondary (44 outline pill) and quiet link factories.
 * [POS]: Shared native button specs for every surface; system sans labels and native focus rings.
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 */

import AppKit

@MainActor
enum FirstLineButtons {
    static func primary(title: String, target: AnyObject?, action: Selector) -> NSButton {
        styled(title: title, target: target, action: action, role: .primary)
    }

    static func secondary(title: String, target: AnyObject?, action: Selector) -> NSButton {
        styled(title: title, target: target, action: action, role: .secondary)
    }

    static func link(title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = FirstLineColors.chromeNSColor
        button.focusRingType = .default
        button.setAccessibilityRole(.button)
        return button
    }

    private static func styled(
        title: String,
        target: AnyObject?,
        action: Selector,
        role: FirstLineButton.Role
    ) -> NSButton {
        let button = FirstLineButton(title: title, target: target, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.role = role
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = FirstLineTypography.uiSemiboldNSFont
        button.focusRingType = .default
        button.wantsLayer = true
        button.layer?.cornerRadius = role.height / 2
        button.heightAnchor.constraint(equalToConstant: role.height).isActive = true
        return button
    }
}

private final class FirstLineButton: NSButton {
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
            refreshAppearance()
        }
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
                layer?.borderWidth = 0
                layer?.borderColor = nil
                layer?.backgroundColor = FirstLineColors.inkNSColor.withAlphaComponent(0.06).cgColor
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

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}
