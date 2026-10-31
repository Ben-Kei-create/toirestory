import Foundation

/// Shared dimensions (metres, scene units). The paper hangs in the plane z = frontZ.
enum PaperGeometry {
    static let cols = 7
    static let width: Float = 0.20
    static let pitch: Float = width / Float(cols - 1)
    static let rowSpacing: Float = 0.0125
    static let maxRows = 56
    static let segmentHeight: Float = 0.42
    static let charPitch: Float = 0.0175
    static let pixelsPerMeter: Float = 3200

    static let rollY: Float = 0.20
    static let rollRadius: Float = 0.055
    static let frontZ: Float = rollRadius + 0.002
    static let wallZ: Float = -0.04

    static let cameraZ: Float = 0.9
    static let fovDegrees: Float = 45
}
