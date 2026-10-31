import UIKit

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

/// 紙の質感・ミシン目・縦書き本文を1枚の画像に印刷する。
/// 画像の上端が紙のロール側(s最大)、下端が紙の先端(s=0)。区間0が一番下。
enum PaperPrintRenderer {
    nonisolated static func renderAtlas(segments: [[Character]]) -> CGImage? {
        let ppm = CGFloat(PaperGeometry.pixelsPerMeter)
        let w = Int(CGFloat(PaperGeometry.width) * ppm)
        let segH = CGFloat(PaperGeometry.segmentHeight) * ppm
        let count = segments.count
        let h = Int(segH * CGFloat(count))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        var rng = SplitMix(state: 0x70135702)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let full = CGRect(x: 0, y: 0, width: w, height: h)

            // 地色
            UIColor(red: 0.972, green: 0.962, blue: 0.935, alpha: 1).setFill()
            cg.fill(full)

            // 紙の質感(素材画像をタイル状に敷く)。素材が無ければ手続き的な繊維で代用。
            if let url = Bundle.main.url(forResource: "paper-basecolor", withExtension: "png"),
               let tile = UIImage(contentsOfFile: url.path) {
                let side = CGFloat(w)
                var y: CGFloat = 0
                var row = 0
                while y < CGFloat(h) {
                    tile.draw(in: CGRect(x: 0, y: y, width: side, height: side))
                    y += side
                    row += 1
                }
                // 素材はやや白いので、暖色をわずかに重ねて紙らしい色味にする
                UIColor(red: 0.96, green: 0.93, blue: 0.88, alpha: 0.18).setFill()
                cg.setBlendMode(.multiply)
                cg.fill(full)
                cg.setBlendMode(.normal)
            } else {
                cg.setLineCap(.round)
                for _ in 0..<(w * h / 90) {
                    let x = CGFloat.random(in: 0...CGFloat(w), using: &rng)
                    let y = CGFloat.random(in: 0...CGFloat(h), using: &rng)
                    let len = CGFloat.random(in: 6...26, using: &rng)
                    let a = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                    cg.setStrokeColor(UIColor(white: CGFloat.random(in: 0.55...0.9, using: &rng), alpha: 0.05).cgColor)
                    cg.setLineWidth(1)
                    cg.move(to: CGPoint(x: x, y: y))
                    cg.addLine(to: CGPoint(x: x + cos(a) * len, y: y + sin(a) * len))
                    cg.strokePath()
                }
            }

            // ミシン目(区間の境界)
            for k in 0..<(count - 1) {
                let y = CGFloat(k + 1) * segH
                cg.setStrokeColor(UIColor(red: 0.5, green: 0.48, blue: 0.45, alpha: 0.6).cgColor)
                cg.setLineWidth(3)
                cg.setLineDash(phase: 0, lengths: [16, 9])
                cg.setLineCap(.butt)
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: CGFloat(w), y: y))
                cg.strokePath()
                // 切れ目の影
                cg.setStrokeColor(UIColor(white: 1, alpha: 0.5).cgColor)
                cg.setLineWidth(1.5)
                cg.move(to: CGPoint(x: 0, y: y + 2.5))
                cg.addLine(to: CGPoint(x: CGFloat(w), y: y + 2.5))
                cg.strokePath()
            }
            cg.setLineDash(phase: 0, lengths: [])

            // 縦書き本文: 区間kは下から数えてk番目。区間内は上から下へ。
            let pitch = CGFloat(PaperGeometry.charPitch) * ppm
            let fontSize = pitch * CGFloat(PaperGeometry.fontSizeRatio)
            let font = UIFont(name: "HiraMinProN-W6", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .medium)
            let ink = UIColor(red: 0.17, green: 0.16, blue: 0.19, alpha: 0.9)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let margin = (segH - pitch * CGFloat(TextLayout.maxSegmentChars)) / 2
            let rotated: Set<Character> = ["ー", "―", "…", "「", "」", "『", "』", "（", "）", "〈", "〉", "─"]
            let punctuation: Set<Character> = ["。", "、"]

            for (k, seg) in segments.enumerated() {
                let top = CGFloat(count - 1 - k) * segH
                for (j, ch) in seg.enumerated() {
                    let cx = CGFloat(w) / 2
                    let cy = top + margin + (CGFloat(j) + 0.5) * pitch
                    let str = String(ch) as NSString
                    let size = str.size(withAttributes: attrs)
                    if rotated.contains(ch) {
                        cg.saveGState()
                        cg.translateBy(x: cx, y: cy)
                        cg.rotate(by: .pi / 2)
                        str.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attrs)
                        cg.restoreGState()
                    } else {
                        var ox = cx - size.width / 2
                        var oy = cy - size.height / 2
                        if punctuation.contains(ch) {
                            ox += fontSize * 0.5
                            oy -= fontSize * 0.5
                        }
                        str.draw(at: CGPoint(x: ox, y: oy), withAttributes: attrs)
                    }
                }
            }
        }
        return image.cgImage
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
