import Foundation
import CoreGraphics
import CoreText
import ImageIO

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Paper texture and vertically arranged text, rendered without a UI framework on a background task.
enum PaperPrintRenderer {
    nonisolated static func renderAtlas(segments: [[Character]]) -> CGImage? {
        guard !segments.isEmpty else { return nil }
        let ppm = CGFloat(PaperGeometry.pixelsPerMeter)
        let w = Int(CGFloat(PaperGeometry.width) * ppm)
        let segH = CGFloat(PaperGeometry.segmentHeight) * ppm
        let h = Int(segH * CGFloat(segments.count))
        guard let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Keep the image's upper-left coordinate system used by mesh UVs and wet marks.
        cg.translateBy(x: 0, y: CGFloat(h))
        cg.scaleBy(x: 1, y: -1)
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        cg.setFillColor(CGColor(red: 0.972, green: 0.962, blue: 0.935, alpha: 1))
        cg.fill(full)
        var rng = SplitMix(state: 0x70135702)

        if let url = Bundle.main.url(forResource: "paper-basecolor", withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let tile = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let side = CGFloat(w)
            var y: CGFloat = 0
            while y < CGFloat(h) {
                cg.draw(tile, in: CGRect(x: 0, y: y, width: side, height: side))
                y += side
            }
            cg.setBlendMode(.multiply)
            cg.setFillColor(CGColor(red: 0.96, green: 0.93, blue: 0.88, alpha: 0.18))
            cg.fill(full)
            cg.setBlendMode(.normal)
        } else {
            cg.setLineCap(.round)
            for _ in 0..<(w * h / 90) {
                let x = CGFloat.random(in: 0...CGFloat(w), using: &rng)
                let y = CGFloat.random(in: 0...CGFloat(h), using: &rng)
                let length = CGFloat.random(in: 6...26, using: &rng)
                let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                cg.setStrokeColor(CGColor(gray: CGFloat.random(in: 0.55...0.9, using: &rng), alpha: 0.05))
                cg.setLineWidth(1)
                cg.move(to: CGPoint(x: x, y: y))
                cg.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                cg.strokePath()
            }
        }

        for k in 1..<segments.count {
            let y = CGFloat(k) * segH
            cg.setLineDash(phase: 0, lengths: [16, 9])
            cg.setLineCap(.butt)
            cg.setLineWidth(3)
            cg.setStrokeColor(CGColor(red: 0.5, green: 0.48, blue: 0.45, alpha: 0.6))
            cg.move(to: CGPoint(x: 0, y: y))
            cg.addLine(to: CGPoint(x: CGFloat(w), y: y))
            cg.strokePath()
            cg.setLineWidth(1.5)
            cg.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
            cg.move(to: CGPoint(x: 0, y: y + 2.5))
            cg.addLine(to: CGPoint(x: CGFloat(w), y: y + 2.5))
            cg.strokePath()
        }
        cg.setLineDash(phase: 0, lengths: [])

        let pitch = CGFloat(PaperGeometry.charPitch) * ppm
        let fontSize = pitch * CGFloat(PaperGeometry.fontSizeRatio)
        let font = CTFontCreateWithName("HiraMinProN-W6" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.17, green: 0.16, blue: 0.19, alpha: 0.9)
        ]
        let margin = (segH - pitch * CGFloat(TextLayout.maxSegmentChars)) / 2
        let rotated: Set<Character> = ["ー", "―", "…", "「", "」", "『", "』", "（", "）", "〈", "〉", "─"]
        let punctuation: Set<Character> = ["。", "、"]
        for (k, segment) in segments.enumerated() {
            let top = CGFloat(segments.count - 1 - k) * segH
            for (j, character) in segment.enumerated() {
                var cx = CGFloat(w) / 2
                var cy = top + margin + (CGFloat(j) + 0.5) * pitch
                if punctuation.contains(character) {
                    cx += fontSize * 0.5
                    cy -= fontSize * 0.5
                }
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attrs))
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                cg.saveGState()
                cg.translateBy(x: cx, y: cy)
                if rotated.contains(character) { cg.rotate(by: .pi / 2) }
                // Core Text glyphs use an upward Y axis, unlike the atlas layout above.
                cg.scaleBy(x: 1, y: -1)
                cg.textMatrix = .identity
                cg.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
                CTLineDraw(line, cg)
                cg.restoreGState()
            }
        }
        return cg.makeImage()
    }
}

/// 濡れた手で触れた跡。印刷済みの紙画像の上に、湿って暗く透けたような染みを足していく。
final class WetPaintLayer {
    private let context: CGContext
    private let width: Int
    private let height: Int
    private var rng = SplitMix(state: 0xA17E)

    init?(base: CGImage) {
        width = base.width
        height = base.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        context = ctx
    }

    /// (px, py) は画像左上基準。radius は px。
    func addBlob(px: CGFloat, py: CGFloat, radius: CGFloat) {
        let cg = context
        let cy = CGFloat(height) - py
        let space = CGColorSpaceCreateDeviceRGB()
        cg.saveGState()
        cg.setBlendMode(.multiply)
        // 指の腹+周囲の小さな水滴を、少しずつずらした柔らかい円で重ねる
        var lobes: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 1)]
        for _ in 0..<5 {
            lobes.append((CGFloat.random(in: -0.55...0.55, using: &rng) * radius,
                          CGFloat.random(in: -0.55...0.55, using: &rng) * radius,
                          CGFloat.random(in: 0.35...0.7, using: &rng)))
        }
        for _ in 0..<3 {
            lobes.append((CGFloat.random(in: -1.3...1.3, using: &rng) * radius,
                          CGFloat.random(in: -1.3...1.3, using: &rng) * radius,
                          CGFloat.random(in: 0.08...0.18, using: &rng)))
        }
        for (dx, dy, k) in lobes {
            let r = radius * k
            let colors = [CGColor(red: 0.72, green: 0.70, blue: 0.69, alpha: 0.14),
                          CGColor(red: 0.82, green: 0.81, blue: 0.80, alpha: 0.1),
                          CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.0)] as CFArray
            guard let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.65, 1]) else { continue }
            let c = CGPoint(x: px + dx, y: cy + dy)
            cg.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
        // 水が染みた縁はわずかに濃い
        cg.setStrokeColor(CGColor(red: 0.7, green: 0.68, blue: 0.67, alpha: 0.12))
        cg.setLineWidth(max(2, radius * 0.05))
        cg.strokeEllipse(in: CGRect(x: px - radius * 0.62, y: cy - radius * 0.62, width: radius * 1.24, height: radius * 1.24))
        cg.restoreGState()
    }

    func snapshot() -> CGImage? { context.makeImage() }
}
