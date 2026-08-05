/**
 * [INPUT]: 依赖 AppKit、DesignSystem/Colors（NSColor 动态 provider）
 * [OUTPUT]: FloodCanvasView - 可复用的 appearance-aware 纯色背景 NSView
 * [POS]: FirstLine 重写 Phase 2a 视觉底座；为白纸 / bone 地面 / 任何纯色填充提供
 *        appearance 变化时自动重解析 CGColor 的正确模式，取代 Phase 1 stub 的
 *        静态 `layer.backgroundColor = nsColor.cgColor` 暗色 bug。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/AGENTS.md
 *
 * 为什么存在：`NSColor.cgColor` 在创建瞬间按当前 effective appearance 解析一次，写入
 * layer 后不再随系统/窗口外观变化更新（Phase 1 stub 因此在 dark 系统下显示暗底）。
 * 正确模式是 wantsUpdateLayer=true + updateLayer() 重解析 + viewDidChangeEffectiveAppearance
 * 标脏重画。文本/描边用 NSColor 本身即可（自动适配），只有 layer 的背景 cgColor 需此处理。
 */

import AppKit

@MainActor
final class FloodCanvasView: NSView {

    /// 填充色，默认 bone canvas。设为 paperNSColor 即可作为白纸背景。
    var fillColor: NSColor {
        didSet { needsDisplay = true }
    }

    /// 可选描边色（appearance-aware；updateLayer 重解析，切换明暗时跟随）。
    var borderColor: NSColor? {
        didSet { needsDisplay = true }
    }
    /// 描边宽度（pt）。borderColor 非空时生效。
    var borderWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init(fillColor: NSColor = FirstLineColors.canvasNSColor) {
        self.fillColor = fillColor
        super.init(frame: .zero)
        commonInit()
    }

    convenience init(fillColor: NSColor, borderColor: NSColor?, borderWidth: CGFloat) {
        self.init(fillColor: fillColor)
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func commonInit() {
        wantsLayer = true
        // 首次挂载后强制更新一次 layer 背景，避免初始黑底（layer 默认 backgroundColor nil）。
        needsDisplay = true
    }

    // 走 updateLayer 而非 drawRect，让 layer 自己重解析 cgColor。
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = fillColor.cgColor
        if let borderColor {
            layer?.borderWidth = borderWidth
            layer?.borderColor = borderColor.cgColor
        } else {
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // 外观变化时 NSColor dynamic provider 会返回新色，强制重画让 updateLayer 重新解析。
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 挂载到窗口后强制更新一次背景（layer 默认 backgroundColor nil，避免初始黑底）。
        needsDisplay = true
    }
}
