/**
 * [INPUT]: 依赖 AppKit、App/AppState、DesignSystem（Colors/Typography/FirstLineButtons/FloodCanvasView）
 * [OUTPUT]: FailureViewController - 失败界面（Draft deleted. + Try Again / Back to Home + joined fossil）
 * [POS]: FirstLine 重写 Phase 3 的 failure surface；退役 SwiftUI FailureView，不保存失败文本
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 复刻 SwiftUI FailureView：顶部 2pt danger 红条；左对齐标题/正文；Try Again（主钮，startSession）+
 * Back to Home（次钮，goHome）；右下角 joined fossil（wipedText 前 64 字，mono 11，ink 0.14，旋转 3 度）。
 */

import AppKit

@MainActor
final class FailureViewController: NSViewController {
    private let appState: AppState
    private var fossilLabel: NSTextField?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = FloodCanvasView(fillColor: FirstLineColors.canvasNSColor)
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root
        buildInterface()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateFossil()
        // focus the primary action for keyboard users
        if let win = view.window, let btn = tryAgainButton {
            win.makeFirstResponder(btn)
        }
    }

    private var tryAgainButton: NSButton?

    private func buildInterface() {
        // 顶部 2pt danger 红条
        let bar = FloodCanvasView(fillColor: FirstLineColors.dangerNSColor)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        // 标题
        let title = NSTextField(labelWithString: "Draft deleted.")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = FirstLineTypography.titleNSFont
        title.textColor = FirstLineColors.inkNSColor

        // 正文
        let body = NSTextField(labelWithString: "You stopped for eight seconds. It joined the pile.")
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = FirstLineTypography.bodyNSFont
        body.textColor = FirstLineColors.uiNSColor
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 0
        body.cell?.truncatesLastVisibleLine = false

        // 按钮
        let tryAgain = FirstLineButtons.primary(title: "Try Again", target: self, action: #selector(tryAgainTapped))
        tryAgainButton = tryAgain
        let backHome = FirstLineButtons.secondary(title: "Back to Home", target: self, action: #selector(backHomeTapped))

        let buttonRow = NSStackView(views: [tryAgain, backHome])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = FirstLineSpacing.md
        buttonRow.alignment = .centerY

        // 左对齐竖排内容
        let content = NSStackView(views: [title, body, buttonRow])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.spacing = FirstLineSpacing.sm
        content.alignment = .leading
        content.setCustomSpacing(FirstLineSpacing.xs, after: body)
        view.addSubview(content)

        // joined fossil（右下）
        let fossil = NSTextField(labelWithString: "")
        fossil.translatesAutoresizingMaskIntoConstraints = false
        fossil.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        fossil.textColor = FirstLineColors.inkNSColor.withAlphaComponent(0.14)
        fossil.lineBreakMode = .byTruncatingTail
        fossil.maximumNumberOfLines = 1
        fossil.isSelectable = false
        fossil.setAccessibilityElement(false)
        // 旋转 3 度
        fossil.wantsLayer = true
        fossil.layer?.setAffineTransform(CGAffineTransform(rotationAngle: 3 * .pi / 180))
        view.addSubview(fossil)
        fossilLabel = fossil

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 2),

            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            content.topAnchor.constraint(greaterThanOrEqualTo: bar.bottomAnchor, constant: FirstLineSpacing.lg),
            content.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            fossil.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            fossil.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -64),
            fossil.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
        ])
    }

    private func updateFossil() {
        let raw = appState.sessionEngine.wipedText
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        let prefix = String(collapsed.prefix(64))
        fossilLabel?.stringValue = prefix
        fossilLabel?.isHidden = prefix.isEmpty
    }

    @objc private func tryAgainTapped() {
        appState.startSession()
    }

    @objc private func backHomeTapped() {
        appState.goHome()
    }
}
