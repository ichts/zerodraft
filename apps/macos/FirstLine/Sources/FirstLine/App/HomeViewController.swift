/**
 * [INPUT]: 依赖 AppKit、App/AppState、DesignSystem tokens 与 FirstLineButtons
 * [OUTPUT]: HomeViewController - 固定 60 秒启动入口、trial 状态与 durable wipe aftermath
 * [POS]: First Line AppKit Home surface；复刻退役 SwiftUI HomeView 的极简 Flood 启动界面
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit

@MainActor
final class HomeViewController: NSViewController {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let canvas = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        self.view = canvas
        buildInterface()
    }

    private func buildInterface() {
        let identityGroup = verticalGroup(
            views: [
                label("First Line", font: FirstLineTypography.titleNSFont, color: FirstLineColors.inkNSColor),
                label(
                    "The first draft only moves forward.",
                    font: FirstLineTypography.taglineNSFont,
                    color: FirstLineColors.uiNSColor
                ),
            ],
            spacing: CGFloat(FirstLineSpacing.sm)
        )

        let ruleGroup = verticalGroup(
            views: [
                label(
                    "Stop for 8 seconds and the page clears.",
                    font: FirstLineTypography.bodyNSFont,
                    color: FirstLineColors.inkNSColor
                ),
                label(
                    "No delete. No paste. No undo.",
                    font: FirstLineTypography.microcopyNSFont,
                    color: FirstLineColors.uiNSColor
                ),
            ],
            spacing: CGFloat(FirstLineSpacing.xs)
        )

        let trialStatus = label(
            appState.trialStatusText,
            font: FirstLineTypography.microcopyNSFont,
            color: appState.isTrialExhausted ? FirstLineColors.inkNSColor : FirstLineColors.uiNSColor
        )

        var primaryViews: [NSView] = [identityGroup, ruleGroup, trialStatus]
        if appState.lastWipeFossil != nil {
            primaryViews.append(label(
                "Draft deleted. it joined the pile.",
                font: FirstLineTypography.sessionStatusNSFont,
                color: FirstLineColors.dangerNSColor
            ))
        }

        let startButton = FirstLineButtons.primary(
            title: "Give it sixty seconds.",
            target: self,
            action: #selector(startSession)
        )
        primaryViews.append(startButton)

        let content = verticalGroup(
            views: primaryViews,
            spacing: CGFloat(FirstLineSpacing.md)
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: CGFloat(FirstLineSpacing.xl)),
            content.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -CGFloat(FirstLineSpacing.xl)),
        ])

        if let fossil = appState.lastWipeFossil {
            addAftermathFossil(fossil)
        }
    }

    private func label(_ text: String, font: NSFont?, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        return field
    }

    private func verticalGroup(views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .gravityAreas
        stack.spacing = spacing
        return stack
    }

    private func addAftermathFossil(_ text: String) {
        let fossil = HomeAftermathFossilView(text: text)
        fossil.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fossil)

        NSLayoutConstraint.activate([
            fossil.widthAnchor.constraint(equalToConstant: 200),
            fossil.heightAnchor.constraint(equalToConstant: 72),
            fossil.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            fossil.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
        ])
    }

    @objc private func startSession() {
        appState.startSession(duration: 60)
    }
}

/// Dead margin fragment from the most recent wipe. It draws directly with a dynamic NSColor so
/// appearance changes remain correct and the fixed rotation cannot be lost during Auto Layout.
private final class HomeAftermathFossilView: NSView {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()

        let rotation = NSAffineTransform()
        rotation.translateX(by: bounds.midX, yBy: bounds.midY)
        rotation.rotate(byDegrees: -3)
        rotation.translateX(by: -bounds.midX, yBy: -bounds.midY)
        rotation.concat()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: FirstLineColors.inkNSColor.withAlphaComponent(0.12),
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(with: bounds.insetBy(dx: 4, dy: 4), options: [.usesLineFragmentOrigin, .usesFontLeading])

        context.restoreGraphicsState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
