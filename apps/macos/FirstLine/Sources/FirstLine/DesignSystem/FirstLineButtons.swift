/**
 * [INPUT]: 依赖 AppKit、DesignSystem/Colors、DesignSystem/Typography
 * [OUTPUT]: FirstLineButtons - appearance-aware AppKit 主/次/链接按钮工厂
 * [POS]: First Line AppKit surface 共用按钮规格；与 SwiftUI ButtonStyles 的 24pt 水平 padding、44pt 高度一致
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
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
        button.font = FirstLineTypography.microcopyNSFont
        button.contentTintColor = FirstLineColors.uiNSColor
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
        button.font = FirstLineTypography.buttonLabelNSFont
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }
}

private final class FirstLineButton: NSButton {
    enum Role { case primary, secondary }
    var role: Role = .secondary { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 48, height: 44)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = 8
        switch role {
        case .primary:
            layer?.borderWidth = 0
            layer?.backgroundColor = FirstLineColors.inkNSColor.cgColor
            contentTintColor = FirstLineColors.paperNSColor
        case .secondary:
            layer?.borderWidth = 1
            layer?.borderColor = FirstLineColors.uiLightNSColor.cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = FirstLineColors.inkNSColor
        }
    }
}
