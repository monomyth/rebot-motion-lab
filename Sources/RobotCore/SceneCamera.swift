import Foundation
import simd

public enum SceneCamera: String, CaseIterable, Sendable {
    case orbit = "Orbit"
    case front = "Front"
    case top = "Top"
    case gripper = "Gripper"

    public static let names = allCases.map(\.rawValue)
}

public struct GeminiOptics: Equatable, Sendable {
    public var verticalFOVDegrees: Float
    public var nearMeters: Float
    public var farMeters: Float
    /// Orbbec Gemini 305 RGB: H94°×V68°, range 4–100 cm+.
    public static let gemini305 = GeminiOptics(verticalFOVDegrees: 68, nearMeters: 0.04, farMeters: 1.0)
    /// Orbbec Gemini 336L RGB: H94°×V68°, range 0.17–20 m+.
    public static let gemini336L = GeminiOptics(verticalFOVDegrees: 68, nearMeters: 0.17, farMeters: 20)
}

/// Cube-first from +X, 45° down, Gemini 336L.
public enum FrontCameraPreset {
    public static let azimuth: Float = 0
    public static let elevation: Float = .pi / 4
    public static let distance: Float = 1.08
    public static let target = SIMD3<Float>(0.26, 0, 0.10)
    public static let optics = GeminiOptics.gemini336L
}

/// Gemini 305 on the gripper plate. Optical center (−78, 0, 65) mm from TCP.
/// +15° Y matches the LEFT CAD mount: 15° down from tool +X.
public enum GripperCameraPreset {
    public static let pitchRadians: Float = 15 * .pi / 180
    public static let fromTCP = SIMD3<Float>(-0.078, 0, 0.065)
    public static let optics = GeminiOptics.gemini305
    public static var lookDirection: SIMD3<Float> {
        SIMD3(cos(pitchRadians), 0, -sin(pitchRadians))
    }
    public static var lookAt: SIMD3<Float> {
        fromTCP + lookDirection * 0.12
    }
}

public enum CameraFrustum {
    /// Vertical pinhole test in one world frame (position and axes both world).
    public static func contains(
        worldPoint: SIMD3<Float>,
        cameraPos: SIMD3<Float>,
        forward: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>,
        fovYDegrees: Float,
        aspect: Float,
        slack: Float = 1.15,
        minDepth: Float = 0.01
    ) -> Bool {
        let offset = worldPoint - cameraPos
        let depth = simd_dot(offset, forward)
        guard depth > minDepth else { return false }
        let fov = fovYDegrees * .pi / 180
        let x = simd_dot(offset, right) / depth
        let y = simd_dot(offset, up) / depth
        let halfY = tan(fov / 2)
        let halfX = halfY * aspect
        return abs(x) <= halfX * slack && abs(y) <= halfY * slack
    }
}
