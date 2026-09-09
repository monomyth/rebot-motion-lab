import Foundation
import simd

/// Geometry shared by numeric, mouse and MCP placement. The existing floor is 4 m square.
public enum CubePlacement {
    public static let minimumSideMM = 10.0
    public static let maximumSideMM = maximumGripperOpeningMM
    public static let floorHalfExtentMM = 2000.0
    public static let sideRangeMM = minimumSideMM...maximumSideMM

    public static func validate(xyMM: [Double], sideMM: Double, yawDeg: Double, jitterMM: Double = 0) throws {
        guard sideMM.isFinite, sideRangeMM.contains(sideMM) else {
            throw ExperimentError.invalid("Cube side must be 10–90 mm (1–9 cm), no larger than the fully open gripper.")
        }
        guard xyMM.count == 2, xyMM.allSatisfy(\.isFinite), yawDeg.isFinite,
              (-180...180).contains(yawDeg), jitterMM.isFinite, jitterMM >= 0 else {
            throw ExperimentError.invalid("Cube placement needs finite X/Y coordinates and a yaw between −180° and 180°.")
        }
        let yaw = yawDeg * degreesToRadians
        let footprintHalf = sideMM / 2 * (abs(cos(yaw)) + abs(sin(yaw)))
        guard xyMM.allSatisfy({ abs($0) + footprintHalf + jitterMM <= floorHalfExtentMM + 1e-8 }) else {
            throw ExperimentError.invalid("The entire cube, including its rotated footprint and placement jitter, must fit on the 4 m × 4 m floor.")
        }
    }

    public static func floorPoint(origin: SIMD3<Double>, direction: SIMD3<Double>) -> SIMD3<Double>? {
        guard [origin.x, origin.y, origin.z, direction.x, direction.y, direction.z].allSatisfy(\.isFinite), abs(direction.z) > 1e-8 else { return nil }
        let distance = (FloorConstraint.height - origin.z) / direction.z
        guard distance >= 0 else { return nil }
        let point = origin + direction * distance
        return [point.x, point.y, FloorConstraint.height]
    }
}
