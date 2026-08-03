/**
 * [INPUT]: 依赖 AppKit、DesignSystem/Colors
 * [OUTPUT]: FossilLayerView - AppKit 版静态 hesitation fossil 纹理层（移植自 SwiftUI FossilLayer）
 * [POS]: FirstLine 重写 Phase 2b Flood soul 层；bone 地面上一次 seeded 放置的 mono 片段，
 *        只在 paper 列外的 gutter 内；danger 时纯色变红（opacity 不变）；几何显著变化时重算。
 * [PROTOCOL]: 变更时更新此头部，然后检查 FirstLine/CLAUDE.md
 *
 * 与 SwiftUI 版的等价：seeded mulberry RNG（seed 0x1337）、同一 corpus、同一 gutter 边界
 * （halfFragWidth 内缩）、同一 danger 行为（只换 foreground，opacity 恒定）。
 * 不实现 ambient 动画；danger 的色变过渡由 setDanger 的 CATransition 承担（reduce-motion 时瞬切）。
 */

import AppKit

@MainActor
final class FossilLayerView: NSView {

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
        wantsLayer = true
        layer = CALayer()
    }

    // 纯纹理层：点击穿透到下层。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDanger(_ danger: Bool, reducesMotion: Bool) {
        self.reducesMotion = reducesMotion
        guard danger != isDanger else { return }
        isDanger = danger
        applyDangerColor()
    }

    private func applyDangerColor() {
        let color = isDanger ? FirstLineColors.dangerNSColor : FirstLineColors.inkNSColor
        if reducesMotion {
            for p in placements { p.layer?.foregroundColor = color.cgColor }
            return
        }
        // 0.3s 色变过渡（opacity 不动）。
        let anim = CABasicAnimation(keyPath: "foregroundColor")
        anim.duration = 0.3
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for p in placements {
            p.layer?.add(anim, forKey: "foregroundColor")
            p.layer?.foregroundColor = color.cgColor
        }
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
    }

    private func regenerate(size: CGSize) {
        // 清旧
        placements.forEach { $0.layer?.removeFromSuperlayer() }
        placements.removeAll()
        guard let host = layer else { return }

        let halfPaper = paperColumnWidth / 2
        let margin = max((size.width / 2) - halfPaper, 0)
        guard margin >= 56 else { return }

        var rng = SeededRandom(seed: 0x1337)
        let count = Self.corpus.count
        let edgePadding: CGFloat = 12
        let maxFragWidth = min(margin - edgePadding * 2, 180)
        let halfFrag = maxFragWidth / 2
        let verticalSlot = size.height / CGFloat(count + 1)
        let color = isDanger ? FirstLineColors.dangerNSColor : FirstLineColors.inkNSColor

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
            let cy = verticalSlot * CGFloat(index + 1)
                + (CGFloat(rng.nextDouble()) - 0.5) * verticalSlot * 0.5
            let fontSize = 11 + CGFloat(rng.nextDouble()) * 4
            let baseOpacity = 0.10 + rng.nextDouble() * 0.06
            let rotation = (rng.nextDouble() - 0.5) * 10

            let textLayer = CATextLayer()
            textLayer.string = text
            textLayer.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textLayer.fontSize = fontSize
            textLayer.foregroundColor = color.cgColor
            textLayer.opacity = Float(baseOpacity)
            textLayer.alignmentMode = .left
            textLayer.truncationMode = .end
            textLayer.isWrapped = true
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            // 宽度约束（包裹）：设置 frame width = maxFragWidth
            let approxLineHeight = fontSize * 1.3
            let approxHeight = approxLineHeight * 4
            textLayer.frame = CGRect(x: cx - halfFrag, y: size.height - cy - approxHeight / 2,
                                     width: maxFragWidth, height: approxHeight)
            // 旋转（绕中心）
            textLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            textLayer.position = CGPoint(x: cx, y: size.height - cy)
            textLayer.transform = CATransform3DMakeRotation(rotation * .pi / 180, 0, 0, 1)
            host.addSublayer(textLayer)
            placements.append(Placement(layer: textLayer))
        }
    }

    private struct Placement {
        let layer: CATextLayer?
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
