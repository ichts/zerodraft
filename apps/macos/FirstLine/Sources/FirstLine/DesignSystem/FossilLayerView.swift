/**
 * [INPUT]: 依赖 AppKit、DesignSystem/Colors（inkNSColor / dangerNSColor）
 * [OUTPUT]: FossilLayerView - AppKit 版静态 hesitation fossil 纹理层（移植自 SwiftUI FossilLayer）
 * [POS]: FirstLine 重写 Phase 2b Flood soul 层；bone 地面上一次 seeded 放置的 mono 片段，
 *        只在 paper 列外的 gutter 内；danger 时纯色变红（opacity 不变）；几何显著变化时重算。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 与 SwiftUI 版的等价：seeded mulberry RNG（seed 0x1337）、同一 corpus、同一 gutter 边界
 * （halfFrag 内缩）、同一 danger 行为（只换 foreground，opacity 恒定）。
 * 实现选 draw(_:) 重画而非 CATextLayer：避开 layer-hosting 顺序 / 非 flipped 坐标 / y-flip + 旋转
 * 叠加导致的定位错乱；NSView draw 天然随 appearance 与 bounds 变化重绘，最稳。
 * 点击穿透：hitTest 返回 nil（下层窗口接收事件）。
 */

import AppKit

@MainActor
final class FossilLayerView: NSView {

    private struct Placement {
        let text: String
        let center: CGPoint
        let fontSize: CGFloat
        let baseOpacity: CGFloat
        let rotation: CGFloat
    }

    private var placements: [Placement] = []
    private var lastSize: CGSize = .zero
    private var isDanger: Bool = false
    private(set) var reducesMotion: Bool = false
    private let paperColumnWidth: CGFloat

    private static let corpus: [String] = [
        "dont delte this whatever you do",
        "the first sentence is still the only sentence",
        "brain dump number four hundered",
        "fix it LATER. later later later",
        "i had the idea and then it left",
        "reread it nine times. sent zero",
        "saved as draft. never opened again",
        "the second sentence killed it",
        "rewrite of the rewrite of the openin",
        "i paused to check my phone. that was it",
        "stopped to find the perfect word. found nothing",
        "almost. always almost",
    ]

    init(paperColumnWidth: CGFloat = 720) {
        self.paperColumnWidth = paperColumnWidth
        super.init(frame: .zero)
    }

    // 纯纹理层：点击穿透到下层。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Flipped: 坐标原点左上，y 向下。placements 的 center.y 是「从顶向下的视觉纵坐标」。
    // Flipped 视图下直接用 p.center.y，不需手动 height-y 翻转；NSAttributedString 天然正确朝向。
    override var isFlipped: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDanger(_ danger: Bool, reducesMotion: Bool) {
        self.reducesMotion = reducesMotion
        guard danger != isDanger else { return }
        isDanger = danger
        // draw 方案：danger 变色直接重画。reducedMotion 时瞬切；否则保留纯色变（opacity 不动），
        // 不做 CALayer 过渡 - 静态纹理的瞬切/淡变对静态化石观感可接受，避免引入动画复杂度。
        needsDisplay = true
    }

    // appearance 变化（明/暗）时 inkNSColor / dangerNSColor 重解析，需重画。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        regenerateIfNeeded(size: bounds.size)
    }

    private func regenerateIfNeeded(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard abs(size.width - lastSize.width) > 1 || abs(size.height - lastSize.height) > 1 else { return }
        lastSize = size
        regenerate(size: size)
        needsDisplay = true
    }

    private func regenerate(size: CGSize) {
        placements.removeAll()

        let halfPaper = paperColumnWidth / 2
        let margin = max((size.width / 2) - halfPaper, 0)
        guard margin >= 20 else { return }

        var rng = SeededRandom(seed: 0x1337)
        let count = Self.corpus.count
        let edgePadding: CGFloat = 12
        let maxFragWidth = min(margin - edgePadding * 2, 180)
        let halfFrag = maxFragWidth / 2
        let verticalSlot = size.height / CGFloat(count + 1)

        for index in 0..<count {
            let text = Self.corpus[index]
            let sideIsLeft = index % 2 == 0
            let centerMin = sideIsLeft
                ? edgePadding + halfFrag
                : (size.width - margin) + edgePadding + halfFrag
            let centerMax = sideIsLeft
                ? margin - edgePadding - halfFrag
                : size.width - edgePadding - halfFrag
            let usable = max(centerMax - centerMin, 0)
            let cx = centerMin + CGFloat(rng.nextDouble()) * usable
            // NSView draw 在非 flipped 坐标系（原点左下），draw 内统一用 height - y 翻转。
            // 这里 cy 存「从顶向下的视觉纵坐标」，draw 时翻成底层坐标。
            let cyFromTop = verticalSlot * CGFloat(index + 1)
                + (CGFloat(rng.nextDouble()) - 0.5) * verticalSlot * 0.5
            let fontSize = 11 + CGFloat(rng.nextDouble()) * 4
            let baseOpacity = 0.10 + rng.nextDouble() * 0.06
            let rotation = (rng.nextDouble() - 0.5) * 10

            placements.append(Placement(
                text: text,
                center: CGPoint(x: cx, y: cyFromTop),
                fontSize: fontSize,
                baseOpacity: baseOpacity,
                rotation: rotation
            ))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let color = isDanger ? FirstLineColors.dangerNSColor : FirstLineColors.inkNSColor

        for p in placements {
            // Flipped view: center.y directly maps to top-down visual position.
            context.saveGState()

            // opacity（color 与 opacity 分离：danger 只换 hue，opacity 不变）。
            context.setAlpha(p.baseOpacity)

            // 平移到化石中心 + 旋转（绕中心）。
            context.translateBy(x: p.center.x, y: p.center.y)
            context.rotate(by: p.rotation * .pi / 180)

            let font = NSFont.monospacedSystemFont(ofSize: p.fontSize, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let attr = NSAttributedString(string: p.text, attributes: attrs)

            // 左对齐、宽度约束 maxFragWidth，从中心左侧 maxFragWidth/2 起画。
            let halfPaper2 = paperColumnWidth / 2
            let margin = max((bounds.width / 2) - halfPaper2, 0)
            let edgePadding: CGFloat = 12
            let maxFragWidth = min(margin - edgePadding * 2, 180)
            let approxLineHeight = p.fontSize * 1.3
            let textHeight = approxLineHeight * 4
            let drawRect = CGRect(
                x: -maxFragWidth / 2,
                y: -textHeight / 2,
                width: maxFragWidth,
                height: textHeight
            )
            // 顶部对齐到中心上方一半，向下换行画。
            attr.draw(in: drawRect)

            context.restoreGState()
        }
    }
}

/// Seeded mulberry-style RNG（与 SwiftUI 版一致）。
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func nextDouble() -> Double {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= (t &* (t | 61)) ^ (t >> 7)
        t ^= t >> 14
        return Double(t >> 11) / Double(1 << 53)
    }
}
