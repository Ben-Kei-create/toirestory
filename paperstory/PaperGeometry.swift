import Foundation

/// Shared dimensions (metres, scene units). The paper hangs in the plane z = frontZ.
enum PaperGeometry {
    static let cols = 7
    static let width: Float = 0.20
    static let pitch: Float = width / Float(cols - 1)
    static let rowSpacing: Float = 0.0125
    /// メッシュ容量の見積り用(1枚の紙片が取りうる行数の上限)。
    static let maxRows = 200
    /// ロールから垂れ下がる紙のうち、保持する長さ。これより下(画面外)の行は捨てる。
    static let keepLength: Float = 1.0
    static let segmentHeight: Float = 0.42
    static let charPitch: Float = 0.0175
    static let fontSizeRatio: Float = 0.92
    static let minimumTextPoints: Float = 18
    static let pixelsPerMeter: Float = 3200

    static let rollY: Float = 0.20
    static let rollRadius: Float = 0.055
    static let frontZ: Float = rollRadius + 0.002
    static let wallZ: Float = -0.04

    static let initialHang: Float = 0.43
    static let cameraZ: Float = 0.70
    static let fovDegrees: Float = 45
}
