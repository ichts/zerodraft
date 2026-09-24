/**
 * [INPUT]: 依赖 AppKit、App/AppState、DesignSystem tokens 与 FirstLineButtons
 * [OUTPUT]: HomeViewController - 固定 60 秒启动入口与 trial 状态
 * [POS]: writeitdown start screen and keyboard focus return target
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 */

import AppKit

@MainActor
final class HomeViewController: NSViewController {
    private let appState: AppState
    private var startButton: NSButton!

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

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(startButton)
    }

    private func buildInterface() {
        let logotypeFont = FirstLineTypography.logotypeNSFont ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        let logotype = label("WRITE_IT_DOWN", font: logotypeFont, color: FirstLineColors.inkNSColor)
        logotype.attributedStringValue = NSAttributedString(
            string: "WRITE_IT_DOWN",
            attributes: [
                .font: logotypeFont,
                .foregroundColor: FirstLineColors.inkNSColor,
                .kern: 1.82,
            ]
        )
        let identityGroup = verticalGroup(
            views: [
                logotype,
                label(
                    "We force you to write it down.",
                    font: FirstLineTypography.titleNSFont,
                    color: FirstLineColors.inkNSColor
                ),
            ],
            spacing: CGFloat(FirstLineSpacing.sm)
        )

        let ruleGroup = verticalGroup(
            views: [
                label(
                    "With a clock: stop for eight seconds and your draft is deleted.",
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

        startButton = FirstLineButtons.primary(
            title: "Give it sixty seconds.",
            target: self,
            action: #selector(startSession)
        )
        startButton.setAccessibilityRole(.button)
        startButton.setAccessibilityLabel(startButton.title)
        let primaryViews: [NSView] = [identityGroup, ruleGroup, trialStatus, startButton]

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

    @objc private func startSession() {
        appState.startSession(duration: 60)
    }
}
