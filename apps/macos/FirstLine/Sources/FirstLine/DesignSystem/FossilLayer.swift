/**
 * [INPUT]: isDanger flag, the protected paper-column width, and a reduce-motion hint
 * [OUTPUT]: FossilLayer - a static, aria-hidden texture of hesitation fossils placed in the margins
 * [POS]: FirstLine Flood soul layer for the session; bone ground is populated once per run
 *        with seeded-random mono fragments outside the clean paper column. They never move
 *        under danger (only foreground color turns red; opacity stays constant); placements
 *        regenerate on significant geometry change to stay inside the gutters.
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */

import SwiftUI

struct FossilLayer: View {
    let isDanger: Bool
    let paperColumnWidth: CGFloat
    let reducesMotion: Bool

    @State private var placements: [Placement] = []
    @State private var lastSize: CGSize = .zero

    // Hesitation fossils only: abandoned, interrupted, never finished. No slogans, advice,
    // or comfort. Typos welcome. Mirrors index.html's FLOOD_CORPUS register.
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(placements) { placement in
                    Text(placement.text)
                        .font(.system(size: placement.fontSize, design: .monospaced))
                        .foregroundStyle(isDanger ? FirstLineColors.danger : FirstLineColors.ink)
                        .opacity(placement.baseOpacity)
                        .rotationEffect(.degrees(placement.rotation))
                        .frame(width: placement.maxWidth, alignment: .leading)
                        .position(x: placement.x, y: placement.y)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear { generatePlacements(size: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in generatePlacements(size: newSize) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(reducesMotion ? nil : .easeInOut(duration: 0.3), value: isDanger)
    }

    private func generatePlacements(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        // 仅在几何显著变化时重算（窗口缩放后 fossil 必须留在新 gutter 内）。
        guard abs(size.width - lastSize.width) > 1 || abs(size.height - lastSize.height) > 1 else { return }
        lastSize = size

        // Fragments live only in the gutters outside the clean paper column.
        let halfPaper = paperColumnWidth / 2
        let margin = max((size.width / 2) - halfPaper, 0)
        guard margin >= 56 else {
            placements = []
            return
        }

        var rng = SeededRandom(seed: 0x1337)
        let count = Self.corpus.count
        var generated: [Placement] = []

        // 每个 fossil 的完整文本框（.position 居中的 frame）必须落在 gutter 内：
        // 采样中心时减去 halfFragWidth，确保左右缘不侵入 paper 列。
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
            let cy = verticalSlot * CGFloat(index + 1)
                + (CGFloat(rng.nextDouble()) - 0.5) * verticalSlot * 0.5
            generated.append(
                Placement(
                    text: text,
                    fontSize: 11 + CGFloat(rng.nextDouble()) * 4,
                    baseOpacity: 0.10 + rng.nextDouble() * 0.06,
                    rotation: (rng.nextDouble() - 0.5) * 10,
                    x: cx,
                    y: cy,
                    maxWidth: maxFragWidth
                )
            )
        }
        placements = generated
    }

    private struct Placement: Identifiable {
        let id = UUID()
        let text: String
        let fontSize: CGFloat
        let baseOpacity: Double
        let rotation: Double
        let x: CGFloat
        let y: CGFloat
        let maxWidth: CGFloat
    }
}

/// Seeded mulberry-style RNG so fossil placement is stable for a given run.
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
