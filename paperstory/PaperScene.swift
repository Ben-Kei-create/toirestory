import SwiftUI
import RealityKit
import UIKit

struct PaperVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
}

/// RealityKit のシーン(ロール・壁・照明・紙メッシュ)と PaperWorld をつなぐ。
@MainActor
final class PaperSceneController {
    private typealias G = PaperGeometry

    let segments: [[Character]]
    let world: PaperWorld
    private var mesh: LowLevelMesh?
    private let rollPivot = Entity()
    private var subscription: EventSubscription?
    private var paperTexture: TextureResource?
    private var wetLayer: WetPaintLayer?
    private var textureUpdateRunning = false
    private var textureDirty = false
    /// 濡れた箇所と、そこを触った回数(1〜6で段階的に濃くなり、7回目で破れる)
    private var wetSpots: [(s: Float, u: Float, count: Int)] = []
    static let maxWetLevel = 6
    private let cameraEntity = PerspectiveCamera()
    /// 視点(紙の中心まわりを回る)。0,0 が初期位置。
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0
    private var isResettingView = false
    private let impact = UIImpactFeedbackGenerator(style: .rigid)

    /// ミシン目の強調表示(SwiftUI 側のオーバーレイが読む)
    var highlightS: Float?
    var isReady = false

    private static let maxStrips = 4
    private static let vertexCapacity = maxStrips * (G.maxRows + 2) * G.cols
    private static let indexCapacity = maxStrips * (G.maxRows + 1) * (G.cols - 1) * 6

    init() {
        segments = Array(TextLayout.segments(from: Story.opening).prefix(5))
        world = PaperWorld(segmentCount: segments.count)
        world.onTear = { [weak self] in self?.impact.impactOccurred() }
    }

    func setup(_ content: RealityViewCameraContent) async {
        cameraEntity.camera.fieldOfViewInDegrees = G.fovDegrees
        content.add(cameraEntity)
        updateCamera()

        let key = DirectionalLight()
        key.light.intensity = 1400
        key.look(at: .zero, from: [0.9, 0.5, 0.7], relativeTo: nil)
        content.add(key)
        let fill = DirectionalLight()
        fill.light.intensity = 350
        fill.look(at: .zero, from: [-0.6, -0.2, 0.8], relativeTo: nil)
        content.add(fill)

        // 壁
        var wallMat = PhysicallyBasedMaterial()
        wallMat.baseColor = .init(tint: UIColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1))
        wallMat.roughness = .init(floatLiteral: 1)
        wallMat.metallic = .init(floatLiteral: 0)
        let wall = ModelEntity(mesh: .generatePlane(width: 8, height: 8), materials: [wallMat])
        wall.position = [0, 0, G.wallZ - 0.002]
        content.add(wall)

        buildRollAndHolder(content)

        // 紙: 質感と本文を印刷した画像を用意し、変形メッシュに貼る
        let atlas = await Task.detached(priority: .userInitiated) {
            PaperPrintRenderer.renderAtlas(segments: self.segments)
        }.value
        guard let atlas else { return }
        do {
            let texture = try await TextureResource(image: atlas, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
            paperTexture = texture
            wetLayer = WetPaintLayer(base: atlas)
            var paper = PhysicallyBasedMaterial()
            paper.baseColor = .init(tint: .white, texture: .init(texture))
            paper.emissiveColor = .init(color: .white, texture: .init(texture))
            paper.emissiveIntensity = 0.1
            paper.roughness = .init(floatLiteral: 0.92)
            paper.metallic = .init(floatLiteral: 0)
            paper.faceCulling = .none

            let llm = try Self.makeMesh()
            mesh = llm
            let resource = try await MeshResource(from: llm)
            let entity = ModelEntity(mesh: resource, materials: [paper])
            content.add(entity)
            updateMesh()
            isReady = true
        } catch {
            print("paper setup failed:", error)
        }

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(Float(event.deltaTime))
        }
    }

    private func buildRollAndHolder(_ content: RealityViewCameraContent) {
        var white = PhysicallyBasedMaterial()
        white.baseColor = .init(tint: UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        white.roughness = .init(floatLiteral: 0.95)
        var line = PhysicallyBasedMaterial()
        line.baseColor = .init(tint: UIColor(red: 0.62, green: 0.6, blue: 0.56, alpha: 1))
        line.roughness = .init(floatLiteral: 1)
        var cardboard = PhysicallyBasedMaterial()
        cardboard.baseColor = .init(tint: UIColor(red: 0.72, green: 0.58, blue: 0.4, alpha: 1))
        cardboard.roughness = .init(floatLiteral: 1)
        var metal = PhysicallyBasedMaterial()
        metal.baseColor = .init(tint: UIColor(white: 0.78, alpha: 1))
        metal.roughness = .init(floatLiteral: 0.4)
        metal.metallic = .init(floatLiteral: 0.6)

        rollPivot.position = [0, G.rollY, 0]
        let axisTurn = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])

        let roll = ModelEntity(mesh: .generateCylinder(height: G.width, radius: G.rollRadius), materials: [white])
        roll.orientation = axisTurn
        rollPivot.addChild(roll)
        let core = ModelEntity(mesh: .generateCylinder(height: G.width + 0.006, radius: 0.019), materials: [cardboard])
        core.orientation = axisTurn
        rollPivot.addChild(core)

        // 回転が見えるよう、巻きの継ぎ目の線を円周上に数本置く
        for k in 0..<4 {
            let angle = Float(k) * .pi / 2 + 0.4
            let mark = ModelEntity(mesh: .generateBox(size: [G.width * 0.98, 0.002, 0.016]), materials: [line])
            mark.position = [0, G.rollRadius * sin(angle) * 1.002, G.rollRadius * cos(angle) * 1.002]
            mark.orientation = simd_quatf(angle: -angle + .pi / 2, axis: [1, 0, 0])
            rollPivot.addChild(mark)
        }
        content.add(rollPivot)

        let plate = ModelEntity(mesh: .generateBox(size: [0.27, 0.12, 0.012]), materials: [metal])
        plate.position = [0, G.rollY, G.wallZ + 0.008]
        content.add(plate)
        for sign in [Float(-1), 1] {
            let arm = ModelEntity(mesh: .generateBox(size: [0.006, 0.012, 0.05]), materials: [metal])
            arm.position = [sign * (G.width / 2 + 0.008), G.rollY, G.wallZ + 0.03]
            content.add(arm)
        }
    }

    // MARK: - 毎フレーム

    private func tick(_ dt: Float) {
        world.step(dt)
        if isResettingView {
            let k = 1 - exp(-dt * 4)
            yaw -= yaw * k
            pitch -= pitch * k
            if abs(yaw) < 0.002, abs(pitch) < 0.002 { yaw = 0; pitch = 0; isResettingView = false }
            updateCamera()
        }
        rollPivot.orientation = simd_quatf(angle: world.rollAngle, axis: [1, 0, 0])
        updateMesh()
    }

    private static func makeMesh() throws -> LowLevelMesh {
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<PaperVertex>.offset(of: \.position)!),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<PaperVertex>.offset(of: \.normal)!),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<PaperVertex>.offset(of: \.uv)!)
        ]
        desc.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<PaperVertex>.stride)]
        desc.vertexCapacity = vertexCapacity
        desc.indexCapacity = indexCapacity
        return try LowLevelMesh(descriptor: desc)
    }

    private func updateMesh() {
        guard let mesh else { return }
        let cols = G.cols
        let total = world.totalLength
        var vCount = 0
        var iCount = 0
        let strips = Array(world.strips.prefix(Self.maxStrips))

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let verts = raw.bindMemory(to: PaperVertex.self)
            mesh.withUnsafeMutableIndices { rawIdx in
                let idx = rawIdx.bindMemory(to: UInt32.self)
                for st in strips {
                    let rows = st.rowCount
                    guard rows > 1, vCount + rows * cols <= verts.count,
                          iCount + (rows - 1) * (cols - 1) * 6 <= idx.count else { continue }
                    let base = vCount
                    for r in 0..<rows {
                        let v = 1 - (total - st.s[r]) / total
                        for c in 0..<cols {
                            let i = r * cols + c
                            let left = st.pos[r * cols + max(c - 1, 0)]
                            let right = st.pos[r * cols + min(c + 1, cols - 1)]
                            let up = st.pos[max(r - 1, 0) * cols + c]
                            let down = st.pos[min(r + 1, rows - 1) * cols + c]
                            var n = simd_cross(right - left, up - down)
                            let len = simd_length(n)
                            n = len > 1e-9 ? n / len : [0, 0, 1]
                            verts[base + i] = PaperVertex(position: st.pos[i], normal: n,
                                                          uv: [Float(c) / Float(cols - 1), v])
                        }
                    }
                    vCount += rows * cols
                    for r in 0..<(rows - 1) {
                        for c in 0..<(cols - 1) {
                            let a = UInt32(base + r * cols + c)
                            let b = a + 1
                            let d = a + UInt32(cols)
                            let e = d + 1
                            idx[iCount] = a; idx[iCount + 1] = d; idx[iCount + 2] = e
                            idx[iCount + 3] = a; idx[iCount + 4] = e; idx[iCount + 5] = b
                            iCount += 6
                        }
                    }
                }
            }
        }
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: iCount, topology: .triangle,
                              bounds: BoundingBox(min: [-0.6, -2, -0.6], max: [0.6, 0.6, 0.6]))
        ])
    }

    // MARK: - 濡れた手

    /// 画面上の点にある紙の位置(素材上の s と、幅方向 0...1)。
    private func paperCoordinate(at pt: CGPoint, in size: CGSize) -> (s: Float, u: Float)? {
        let cols = G.cols
        for st in world.strips where st.rowCount > 1 {
            for r in 0..<(st.rowCount - 1) {
                for c in 0..<(cols - 1) {
                    let idx = [r * cols + c, r * cols + c + 1, (r + 1) * cols + c + 1, (r + 1) * cols + c]
                    let q = idx.map { project(st.pos[$0], in: size) }
                    guard Self.contains(q, pt) else { continue }
                    // 四角形内の位置を、辺の中点どうしを結ぶ軸から近似して求める
                    let tu = Self.param(pt, q[0], q[1], q[3], q[2])
                    let s = st.s[r] + (st.s[r + 1] - st.s[r]) * Float(tu.v)
                    let u = (Float(c) + Float(tu.u)) / Float(cols - 1)
                    return (s, u)
                }
            }
        }
        return nil
    }

    /// 四角形 (a,b,d,e)=(左上,右上,左下,右下) 内の点 p の (u,v) を、2回の補正で近似する。
    private static func param(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ d: CGPoint, _ e: CGPoint) -> (u: CGFloat, v: CGFloat) {
        var u: CGFloat = 0.5, v: CGFloat = 0.5
        for _ in 0..<6 {
            let top = CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            let bot = CGPoint(x: d.x + (e.x - d.x) * u, y: d.y + (e.y - d.y) * u)
            let cur = CGPoint(x: top.x + (bot.x - top.x) * v, y: top.y + (bot.y - top.y) * v)
            let ex = p.x - cur.x, ey = p.y - cur.y
            let du = CGVector(dx: (b.x - a.x) * (1 - v) + (e.x - d.x) * v, dy: (b.y - a.y) * (1 - v) + (e.y - d.y) * v)
            let dv = CGVector(dx: bot.x - top.x, dy: bot.y - top.y)
            let det = du.dx * dv.dy - du.dy * dv.dx
            guard abs(det) > 1e-6 else { break }
            u += (ex * dv.dy - ey * dv.dx) / det
            v += (du.dx * ey - du.dy * ex) / det
            u = max(0, min(1, u)); v = max(0, min(1, v))
        }
        return (u, v)
    }

    /// 紙をタップしたときの、濡れた指の跡。
    func touchPaper(at pt: CGPoint, in size: CGSize) {
        guard let wet = wetLayer, let hit = paperCoordinate(at: pt, in: size) else { return }
        // 近くに濡れた跡があれば同じ箇所として数える
        let near = wetSpots.firstIndex { abs($0.s - hit.s) < 0.03 && abs($0.u - hit.u) * G.width < 0.03 }
        let count = (near.map { wetSpots[$0].count } ?? 0) + 1
        if count > Self.maxWetLevel {
            // 7回目: 濡れた紙がその場で破れる
            if let near { wetSpots.remove(at: near) }
            let col = Int((hit.u * Float(G.cols - 1)).rounded())
            world.cut(atS: hit.s, fromLeft: hit.u < 0.5, ragged: col)
            return
        }
        if let near { wetSpots[near].count = count } else { wetSpots.append((hit.s, hit.u, 1)) }
        let ppm = CGFloat(G.pixelsPerMeter)
        let px = CGFloat(hit.u) * CGFloat(G.width) * ppm
        let py = CGFloat(world.totalLength - hit.s) * ppm
        wet.addBlob(px: px, py: py, radius: CGFloat.random(in: 0.011...0.016) * ppm)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        textureDirty = true
        guard !textureUpdateRunning else { return }
        textureUpdateRunning = true
        Task { @MainActor in
            while self.textureDirty, let tex = self.paperTexture, let img = wet.snapshot() {
                self.textureDirty = false
                try? await tex.replace(withImage: img, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
            }
            self.textureUpdateRunning = false
        }
    }

    // MARK: - 視点

    private var cameraPosition: SIMD3<Float> {
        let r = G.cameraZ
        return [r * sin(yaw) * cos(pitch), r * sin(pitch), r * cos(yaw) * cos(pitch)]
    }

    private func updateCamera() {
        cameraEntity.look(at: .zero, from: cameraPosition, relativeTo: nil)
    }

    /// 紙以外を触れたまま動かして視点を回す。
    func orbit(dx: CGFloat, dy: CGFloat) {
        isResettingView = false
        yaw = max(-1.2, min(1.2, yaw - Float(dx) * 0.007))
        pitch = max(-0.45, min(0.9, pitch + Float(dy) * 0.007))
        updateCamera()
    }

    func resetView() { isResettingView = true }

    // MARK: - 画面座標との対応

    func project(_ p: SIMD3<Float>, in size: CGSize) -> CGPoint {
        let pos = cameraPosition
        let fwd = simd_normalize(-pos)
        let right = simd_normalize(simd_cross(fwd, [0, 1, 0]))
        let up = simd_cross(right, fwd)
        let rel = p - pos
        let z = max(simd_dot(rel, fwd), 0.01)
        let t = tan(G.fovDegrees * .pi / 360)
        let aspect = Float(size.width / size.height)
        let nx = simd_dot(rel, right) / (z * t * aspect)
        let ny = simd_dot(rel, up) / (z * t)
        return CGPoint(x: (CGFloat(nx) + 1) / 2 * size.width, y: (1 - CGFloat(ny)) / 2 * size.height)
    }

    /// 紙を「引く」向き(画面上の単位ベクトル)と、画面上で1mが何ptか。
    func pullAxis(in size: CGSize) -> (dir: CGVector, pointsPerMeter: CGFloat) {
        let a = project([0, 0, G.frontZ], in: size)
        let b = project([0, -0.1, G.frontZ], in: size)
        let v = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let len = max(hypot(v.dx, v.dy), 1)
        return (CGVector(dx: v.dx / len, dy: v.dy / len), len / 0.1)
    }

    /// 触れた位置が紙の上か(縁は少し広めに判定)。
    func isOnPaper(_ pt: CGPoint, in size: CGSize) -> Bool {
        let cols = G.cols
        var polys: [[CGPoint]] = []
        for st in world.strips where st.rowCount > 1 {
            var poly: [CGPoint] = []
            for r in 0..<st.rowCount { poly.append(project(st.pos[r * cols], in: size)) }
            for r in stride(from: st.rowCount - 1, through: 0, by: -1) { poly.append(project(st.pos[r * cols + cols - 1], in: size)) }
            polys.append(poly)
        }
        let pad: CGFloat = 16
        for off in [(0, 0), (pad, 0), (-pad, 0), (0, pad), (0, -pad)] {
            let q = CGPoint(x: pt.x + off.0, y: pt.y + off.1)
            for poly in polys where Self.contains(poly, q) { return true }
        }
        return false
    }

    static func contains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// 触れた位置の近く(±radius pt)にあるミシン目。
    func perforation(near pt: CGPoint, in size: CGSize, radius: CGFloat = 48) -> Float? {
        var best: (Float, CGFloat)?
        for s in world.perforations {
            guard let pts = world.worldPoints(atS: s) else { continue }
            let line = pts.map { project($0, in: size) }
            var dist = CGFloat.infinity
            for i in 0..<(line.count - 1) { dist = min(dist, Self.distance(pt, line[i], line[i + 1])) }
            if dist < radius, dist < (best?.1 ?? .infinity) { best = (s, dist) }
        }
        return best?.0
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let l2 = ab.dx * ab.dx + ab.dy * ab.dy
        let t = l2 > 0 ? max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / l2)) : 0
        return hypot(p.x - (a.x + ab.dx * t), p.y - (a.y + ab.dy * t))
    }

    func highlightPoints(in size: CGSize) -> [CGPoint]? {
        guard let s = highlightS, let pts = world.worldPoints(atS: s) else { return nil }
        return pts.map { project($0, in: size) }
    }

    /// 「ここで切る」: 対象のミシン目を示してから切る。
    func cutHere() {
        guard !world.isTearing, let target = world.defaultCutTarget() else { return }
        highlightS = target
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            self.world.cut(atS: target, fromLeft: true)
            self.highlightS = nil
        }
    }
}
