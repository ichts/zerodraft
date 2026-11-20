/**
 * [INPUT]: a seed, base frequency, octave count and optional stitch tile, as an SVG `<feTurbulence>` takes them.
 * [OUTPUT]: Turbulence - the SVG 1.1 / Filter Effects reference turbulence generator (fractalNoise), per channel.
 * [POS]: The noise under the paper's grain and cloud (PaperField); the web draws the same SVGs (tokens.css v3).
 * [PROTOCOL]: Change this header, then check FirstLine/AGENTS.md.
 *
 * Ported from the specification's reference code, so a pixel sampled at the same user-space point carries the value
 * the browser computes (measured against Chromium: correlation 0.9999, at most 1 level apart in 255).
 */

import Foundation

/// The SVG feTurbulence reference generator (SVG 1.1 / Filter Effects 1), one colour channel.
struct Turbulence: Sendable {
    private static let bSize = 0x100
    private static let bm = 0xff
    private static let perlinN = 0x1000
    private var lattice = [Int](repeating: 0, count: 0x100 + 0x100 + 2)
    private var gradient = [[Double]](repeating: [Double](repeating: 0, count: (0x100 + 0x100 + 2) * 2), count: 4)

    init(seed: Int) {
        let m = 2_147_483_647, a = 16807, q = 127_773, r = 2836
        var s = seed
        if s <= 0 { s = -(s % (m - 1)) + 1 }
        if s > m - 1 { s = m - 1 }
        func next() -> Int {
            var result = a * (s % q) - r * (s / q)
            if result <= 0 { result += m }
            s = result
            return result
        }
        let b = Self.bSize
        for k in 0..<4 {
            for i in 0..<b {
                lattice[i] = i
                for j in 0..<2 { gradient[k][i * 2 + j] = Double((next() % (b + b)) - b) / Double(b) }
                let len = (gradient[k][i * 2] * gradient[k][i * 2] + gradient[k][i * 2 + 1] * gradient[k][i * 2 + 1]).squareRoot()
                gradient[k][i * 2] /= len
                gradient[k][i * 2 + 1] /= len
            }
        }
        var i = b
        while true {
            i -= 1
            if i == 0 { break }
            let k = lattice[i]
            let j = next() % b
            lattice[i] = lattice[j]
            lattice[j] = k
        }
        for i in 0..<(b + 2) {
            lattice[b + i] = lattice[i]
            for k in 0..<4 { for j in 0..<2 { gradient[k][(b + i) * 2 + j] = gradient[k][i * 2 + j] } }
        }
    }

    struct Stitch { var width: Int; var height: Int; var wrapX: Int; var wrapY: Int }

    @inline(__always)
    private func noise2(_ channel: Int, _ x: Double, _ y: Double, _ stitch: Stitch?) -> Double {
        let bm = Self.bm
        var t = x + Double(Self.perlinN)
        var bx0 = Int(t) & bm
        var bx1 = (bx0 + 1) & bm
        let rx0 = t - Double(Int(t))
        let rx1 = rx0 - 1
        t = y + Double(Self.perlinN)
        var by0 = Int(t) & bm
        var by1 = (by0 + 1) & bm
        let ry0 = t - Double(Int(t))
        let ry1 = ry0 - 1
        if let stitch {
            if bx0 >= stitch.wrapX { bx0 -= stitch.width }
            if bx1 >= stitch.wrapX { bx1 -= stitch.width }
            if by0 >= stitch.wrapY { by0 -= stitch.height }
            if by1 >= stitch.wrapY { by1 -= stitch.height }
        }
        bx0 &= bm; bx1 &= bm; by0 &= bm; by1 &= bm
        let i = lattice[bx0], j = lattice[bx1]
        let b00 = lattice[i + by0], b10 = lattice[j + by0], b01 = lattice[i + by1], b11 = lattice[j + by1]
        let sx = rx0 * rx0 * (3 - 2 * rx0)
        let sy = ry0 * ry0 * (3 - 2 * ry0)
        let g = gradient[channel]
        var u = rx0 * g[b00 * 2] + ry0 * g[b00 * 2 + 1]
        var v = rx1 * g[b10 * 2] + ry0 * g[b10 * 2 + 1]
        let a = u + sx * (v - u)
        u = rx0 * g[b01 * 2] + ry1 * g[b01 * 2 + 1]
        v = rx1 * g[b11 * 2] + ry1 * g[b11 * 2 + 1]
        let b = u + sx * (v - u)
        return a + sy * (b - a)
    }

    /// fractalNoise, `(sum + 1) / 2`, unclamped.
    func fractal(_ channel: Int, x: Double, y: Double, baseX: Double, baseY: Double, octaves: Int,
                 tile: (x: Double, y: Double, width: Double, height: Double)?) -> Double {
        var fx = baseX, fy = baseY
        var stitch: Stitch?
        if let tile {
            if fx != 0 {
                let lo = (tile.width * fx).rounded(.down) / tile.width, hi = (tile.width * fx).rounded(.up) / tile.width
                fx = fx / lo < hi / fx ? lo : hi
            }
            if fy != 0 {
                let lo = (tile.height * fy).rounded(.down) / tile.height, hi = (tile.height * fy).rounded(.up) / tile.height
                fy = fy / lo < hi / fy ? lo : hi
            }
            let w = Int(tile.width * fx + 0.5), h = Int(tile.height * fy + 0.5)
            stitch = Stitch(width: w, height: h, wrapX: Int(tile.x * fx + Double(Self.perlinN)) + w,
                            wrapY: Int(tile.y * fy + Double(Self.perlinN)) + h)
        }
        var sum = 0.0, vx = x * fx, vy = y * fy, ratio = 1.0
        for _ in 0..<octaves {
            sum += noise2(channel, vx, vy, stitch) / ratio
            vx *= 2; vy *= 2; ratio *= 2
            if var s = stitch {
                s.width += s.width
                s.wrapX = 2 * s.wrapX - Self.perlinN
                s.height += s.height
                s.wrapY = 2 * s.wrapY - Self.perlinN
                stitch = s
            }
        }
        return (sum + 1) / 2
    }
}
