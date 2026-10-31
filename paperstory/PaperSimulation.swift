import Foundation
import simd

/// 格子状の点(幅 cols × 長さ rows)で表した紙片。s は紙の先端(s=0)から測った素材上の位置で、
/// 行0がロール側(大きい s)。位置と本文・ミシン目は同じ s で結びついている。
final class PaperStrip {
    var s: [Float]
    var pos: [SIMD3<Float>]
    var prev: [SIMD3<Float>]
    let isPinned: Bool
    var weld: Weld?

    var rowCount: Int { s.count }

    init(s: [Float], pos: [SIMD3<Float>], prev: [SIMD3<Float>], isPinned: Bool) {
        self.s = s
        self.pos = pos
        self.prev = prev
        self.isPinned = isPinned
    }
}

/// 切断中の紙片どうしを繋ぐ「まだ裂けていない列」。左右どちらかから順に外れる。
final class Weld {
    let upper: PaperStrip
    let fromLeft: Bool
    var broken = [Bool](repeating: false, count: PaperGeometry.cols)
    var time: Float = 0
    static let duration: Float = 0.30
    /// 各列が外れる時刻(秒)
    let delays: [Float]

    init(upper: PaperStrip, fromLeft: Bool, delays: [Float]? = nil) {
        self.upper = upper
        self.fromLeft = fromLeft
        let cols = PaperGeometry.cols
        self.delays = delays ?? (0..<cols).map { c in
            Weld.duration * Float(fromLeft ? c : cols - 1 - c) / Float(cols)
        }
    }
}

final class PaperWorld {
    private typealias G = PaperGeometry
    private static let cols = PaperGeometry.cols

    let segmentCount: Int
    let totalLength: Float
    private(set) var main: PaperStrip
    private(set) var pieces: [PaperStrip] = []
    private(set) var sExit: Float
    private(set) var rollAngle: Float = 0
    var feedVelocity: Float = 0
    private var time: Float = 0

    var onTear: (() -> Void)?

    /// 紙を最後まで引き出した(読了)
    var isExhausted: Bool { sExit >= totalLength - 0.001 }

    var strips: [PaperStrip] { [main] + pieces }
    var isTearing: Bool { pieces.contains { $0.weld != nil } }

    init(segmentCount: Int, initialHang: Float = PaperGeometry.initialHang) {
        self.segmentCount = segmentCount
        totalLength = Float(segmentCount) * G.segmentHeight
        sExit = initialHang
        main = PaperWorld.makeHangingStrip(topS: initialHang, bottomS: 0)
    }

    private static func makeHangingStrip(topS: Float, bottomS: Float) -> PaperStrip {
        var rows: [Float] = []
        var v = topS
        while v > bottomS + 0.002 {
            rows.append(v)
            v -= G.rowSpacing
        }
        rows.append(bottomS)
        var pos: [SIMD3<Float>] = []
        for (r, s) in rows.enumerated() {
            for c in 0..<cols {
                let x = -G.width / 2 + Float(c) * G.pitch
                pos.append([x, G.rollY - (topS - s), G.frontZ + 0.003 * sin(Float(r) * 0.35 + Float(c) * 0.6)])
            }
        }
        return PaperStrip(s: rows, pos: pos, prev: pos, isPinned: true)
    }

    // MARK: - 操作

    /// 紙を `amount` だけ引き出す。ロールは引いた長さぶん回る。
    func feed(_ amount: Float) {
        let d = min(amount, totalLength - sExit)
        guard d > 0 else { feedVelocity = 0; return }
        let cols = Self.cols
        sExit += d
        rollAngle += d / G.rollRadius
        let m = main
        m.s[0] = sExit
        for i in cols..<m.pos.count {
            m.pos[i].y -= d
            m.prev[i].y -= d
            // 勢いよく引くと紙が手前に膨らむ
            let r = i / cols
            m.prev[i].z -= d * 0.015 * Float(min(r, 12)) / 12
        }
        while m.rowCount > 1, m.s[0] - m.s[1] >= G.rowSpacing {
            let gap = m.s[0] - m.s[1]
            let f = (gap - G.rowSpacing) / gap
            var np: [SIMD3<Float>] = []
            var nq: [SIMD3<Float>] = []
            for c in 0..<cols {
                np.append(m.pos[c] + (m.pos[cols + c] - m.pos[c]) * f)
                nq.append(m.prev[c] + (m.prev[cols + c] - m.prev[c]) * f)
            }
            m.s.insert(m.s[1] + G.rowSpacing, at: 1)
            m.pos.insert(contentsOf: np, at: cols)
            m.prev.insert(contentsOf: nq, at: cols)
        }
    }

    /// 巻き戻そうとしたとき。紙は軽くたわむだけで、本文は戻らない。
    func nudgeBack(_ amount: Float) {
        let cols = Self.cols
        let m = main
        for i in cols..<m.pos.count {
            let r = Float(i / cols)
            m.prev[i].z += min(amount, 0.02) * 0.2 * min(r, 14) / 14
        }
    }

    /// 完全に出ているミシン目(切れる候補)。
    var perforations: [Float] {
        guard let last = main.s.last else { return [] }
        return (1..<max(segmentCount, 1)).map { Float($0) * G.segmentHeight }
            .filter { $0 > last + 0.001 && $0 < main.s[0] - 0.02 }
    }

    /// 「ここで切る」の対象: ロール近くを避けた、いちばん上のミシン目。
    func defaultCutTarget() -> Float? {
        perforations.filter { worldPoints(atS: $0).map { $0[Self.cols / 2].y < G.rollY - 0.06 } ?? false }.max()
    }

    /// 素材上の位置 s に対応する、現在の紙の幅方向の点列。
    func worldPoints(atS s: Float) -> [SIMD3<Float>]? {
        let m = main
        guard m.rowCount > 1, s <= m.s[0], s >= m.s[m.rowCount - 1] else { return nil }
        var i = 0
        while i + 1 < m.rowCount - 1, m.s[i + 1] >= s { i += 1 }
        let cols = Self.cols
        let span = m.s[i] - m.s[i + 1]
        let t = span > 1e-6 ? (m.s[i] - s) / span : 0
        return (0..<cols).map { m.pos[i * cols + $0] + (m.pos[(i + 1) * cols + $0] - m.pos[i * cols + $0]) * t }
    }

    /// ミシン目 sp に沿って切る。裂けは左右どちらかから走り、下の紙片が落ちる。
    @discardableResult
    func cut(atS sp: Float, fromLeft: Bool, ragged startColumn: Int? = nil) -> Bool {
        let m = main
        let cols = Self.cols
        guard !isTearing, m.rowCount > 1, sp < m.s[0], sp > m.s[m.rowCount - 1] else { return false }
        var i = 0
        while i + 1 < m.rowCount, m.s[i + 1] >= sp { i += 1 }
        guard i + 1 < m.rowCount else { return false }
        let gap = m.s[i] - m.s[i + 1]
        var cutPos: [SIMD3<Float>] = []
        var cutPrev: [SIMD3<Float>] = []
        for c in 0..<cols {
            let a = i * cols + c, b = (i + 1) * cols + c
            // 濡れて切れた場合は、列ごとに切れ目の位置がずれてギザギザになる
            let jitter: Float = startColumn == nil ? 0 : Float.random(in: -0.011...0.011)
            let t = max(0, min(1, (m.s[i] - (sp + jitter)) / gap))
            cutPos.append(m.pos[a] + (m.pos[b] - m.pos[a]) * t)
            cutPrev.append(m.prev[a] + (m.prev[b] - m.prev[a]) * t)
        }
        let lower = PaperStrip(s: [sp] + Array(m.s[(i + 1)...]),
                               pos: cutPos + Array(m.pos[((i + 1) * cols)...]),
                               prev: cutPrev + Array(m.prev[((i + 1) * cols)...]),
                               isPinned: false)
        m.s = Array(m.s[0...i]) + [sp]
        m.pos = Array(m.pos[0..<((i + 1) * cols)]) + cutPos
        m.prev = Array(m.prev[0..<((i + 1) * cols)]) + cutPrev
        if let start = startColumn {
            let delays = (0..<cols).map { c in
                Weld.duration * Float(abs(c - start)) / Float(cols) + Float.random(in: 0...0.1)
            }
            lower.weld = Weld(upper: m, fromLeft: fromLeft, delays: delays)
        } else {
            lower.weld = Weld(upper: m, fromLeft: fromLeft)
        }
        pieces.append(lower)
        if pieces.count > 3 { pieces.removeFirst() }
        feedVelocity = 0
        onTear?()
        return true
    }

    // MARK: - 物理

    private var accumulator: Float = 0
    private static let fixedStep: Float = 1.0 / 120.0

    /// フレームレートに依存しないよう、物理は固定時間刻みで進める。
    func step(_ frameDt: Float) {
        let dt = min(frameDt, 0.1)
        if abs(feedVelocity) > 0.003 {
            feed(feedVelocity * dt)
            feedVelocity *= exp(-dt * 4)
        } else {
            feedVelocity = 0
        }
        accumulator += dt
        while accumulator >= Self.fixedStep {
            accumulator -= Self.fixedStep
            substep(Self.fixedStep)
        }
    }

    private func substep(_ h: Float) {
        time += h
        for st in strips { integrate(st, h: h) }
        for it in 0..<14 {
            for st in strips { solve(st, reverse: it % 2 == 1) }
            solveWelds()
            for st in strips { collide(st) }
        }
        updateWelds(h)
        pieces.removeAll { piece in
            piece.weld == nil && (piece.pos.map(\.y).max() ?? 0) < -0.7
        }
    }

    private func integrate(_ st: PaperStrip, h: Float) {
        let cols = Self.cols
        let rows = st.rowCount
        let start = st.isPinned ? cols : 0
        // 紙は軽く、空気をはらんでふわっと動く: 弱い重力・強い面直角方向の空気抵抗・大きな減衰
        let gravity: Float = st.isPinned ? -3.2 : -2.2
        let flutter: Float = st.isPinned ? 0.05 : 0.35
        let damping: Float = st.isPinned ? 0.975 : 0.992
        let normalDrag: Float = st.isPinned ? 0.30 : 0.18
        for i in start..<st.pos.count {
            let r = i / cols, c = i % cols
            var vel = (st.pos[i] - st.prev[i]) * damping
            let left = st.pos[r * cols + max(c - 1, 0)]
            let right = st.pos[r * cols + min(c + 1, cols - 1)]
            let up = st.pos[max(r - 1, 0) * cols + c]
            let down = st.pos[min(r + 1, rows - 1) * cols + c]
            var n = simd_cross(right - left, up - down)
            let len = simd_length(n)
            if len > 1e-9 {
                n /= len
                vel -= n * (simd_dot(vel, n) * normalDrag)
            }
            var acc = SIMD3<Float>(0, gravity, 0)
            acc.z += sin(time * 1.3 + Float(r) * 0.22 + Float(c) * 0.4) * flutter
            acc.x += sin(time * 0.9 + Float(r) * 0.15) * flutter * 0.4
            if st.isPinned { acc.z -= (st.pos[i].z - G.frontZ) * 1.5 }
            st.prev[i] = st.pos[i]
            st.pos[i] += vel + acc * h * h
        }
        if st.isPinned {
            for c in 0..<cols {
                let p = SIMD3<Float>(-G.width / 2 + Float(c) * G.pitch, G.rollY, G.frontZ)
                st.pos[c] = p
                st.prev[c] = p
            }
        }
    }

    private func solve(_ st: PaperStrip, reverse: Bool) {
        let cols = Self.cols
        let rows = st.rowCount
        let pinnedCount = st.isPinned ? cols : 0

        func link(_ a: Int, _ b: Int, _ rest: Float, _ k: Float) {
            let wa: Float = a < pinnedCount ? 0 : 1
            let wb: Float = b < pinnedCount ? 0 : 1
            let wsum = wa + wb
            guard wsum > 0 else { return }
            let d = st.pos[b] - st.pos[a]
            let len = simd_length(d)
            guard len > 1e-7 else { return }
            let corr = d * ((len - rest) / len * k / wsum)
            st.pos[a] += corr * wa
            st.pos[b] -= corr * wb
        }

        for r in 0..<rows {
            for c in 0..<(cols - 1) { link(r * cols + c, r * cols + c + 1, G.pitch, 1) }
            for c in 0..<(cols - 2) { link(r * cols + c, r * cols + c + 2, 2 * G.pitch, 0.12) }
        }
        for rr in 0..<(rows - 1) {
            let r = reverse ? rows - 2 - rr : rr
            let dv = st.s[r] - st.s[r + 1]
            let diag = (G.pitch * G.pitch + dv * dv).squareRoot()
            for c in 0..<cols {
                link(r * cols + c, (r + 1) * cols + c, dv, 1)
                if c < cols - 1 {
                    link(r * cols + c, (r + 1) * cols + c + 1, diag, 0.6)
                    link(r * cols + c + 1, (r + 1) * cols + c, diag, 0.6)
                }
            }
        }
        if rows > 2 {
            for r in 0..<(rows - 2) {
                let dv = st.s[r] - st.s[r + 2]
                for c in 0..<cols { link(r * cols + c, (r + 2) * cols + c, dv, 0.12) }
            }
        }
    }

    private func solveWelds() {
        let cols = Self.cols
        for piece in pieces {
            guard let w = piece.weld else { continue }
            let up = w.upper
            let base = (up.rowCount - 1) * cols
            for c in 0..<cols where !w.broken[c] {
                let mid = (piece.pos[c] + up.pos[base + c]) * 0.5
                piece.pos[c] = mid
                up.pos[base + c] = mid
            }
        }
    }

    private func updateWelds(_ dt: Float) {
        let cols = Self.cols
        for piece in pieces {
            guard let w = piece.weld else { continue }
            w.time += dt
            for c in 0..<cols where !w.broken[c] {
                if w.time > w.delays[c] {
                    w.broken[c] = true
                    piece.prev[c].y += 0.002   // 裂けた瞬間に下へ引かれる
                }
            }
            if !w.broken.contains(false) { piece.weld = nil }
        }
    }

    private func collide(_ st: PaperStrip) {
        let start = st.isPinned ? Self.cols : 0
        let minZ = G.wallZ + 0.004
        let rr = G.rollRadius + 0.001
        for i in start..<st.pos.count {
            var p = st.pos[i]
            if p.z < minZ { p.z = minZ }
            let dy = p.y - G.rollY
            let dist = (dy * dy + p.z * p.z).squareRoot()
            if dist < rr, abs(p.x) < G.width / 2 + 0.005, dist > 1e-6 {
                p.y = G.rollY + dy / dist * rr
                p.z = p.z / dist * rr
            }
            st.pos[i] = p
        }
    }
}
