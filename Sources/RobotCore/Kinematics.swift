import Foundation
import simd

public let degreesToRadians = Double.pi / 180
public let maximumGripperOpeningMM = 90.0
public let homePose: [Double] = [0, -95, -95, 10, 0, 0]
// The source URDF's zero pose folds the upper arm and forearm back alongside one another.
public let foldedPose: [Double] = [0, 0, 0, 0, 0, 0]
public let robotPresets: [(name: String, joints: [Double], grip: Double?)] = [
    ("Folded", foldedPose, 0), ("Ready", homePose, nil),
    ("Reach", [0, -140, -155, 20, 0, 0], nil), ("Upright", [0, -90, -179.8, 0, 0, 0], nil)
]
public func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double { min(upper, max(lower, value)) }
public func vector(_ a: [Double]) -> SIMD3<Double> { SIMD3(a[0], a[1], a[2]) }
public func originTransform(xyz: [Double], rpy: [Double]) -> simd_double4x4 {
    let rotation = simd_quatd(angle: rpy[2], axis: [0, 0, 1]) *
        simd_quatd(angle: rpy[1], axis: [0, 1, 0]) * simd_quatd(angle: rpy[0], axis: [1, 0, 0])
    var result = simd_double4x4(rotation)
    result.columns.3 = SIMD4(xyz[0], xyz[1], xyz[2], 1)
    return result
}

public struct Kinematics: Sendable {
    public let definition: RobotDefinition
    private let origins: [simd_double4x4]
    public init(_ definition: RobotDefinition) {
        self.definition = definition
        origins = definition.joints.map { originTransform(xyz: $0.xyz, rpy: $0.rpy) }
    }
    public func clampPose(_ joints: [Double]) -> [Double] {
        definition.armJoints.enumerated().map { i, j in
            let v = joints.indices.contains(i) && joints[i].isFinite ? joints[i] : homePose[i]
            return clamp(v, j.lower / degreesToRadians, j.upper / degreesToRadians)
        }
    }
    public func transforms(_ joints: [Double], grip: Double = 60) -> [String: simd_double4x4] {
        let q = clampPose(joints)
        let opening = (grip.isFinite ? clamp(grip, 0, maximumGripperOpeningMM) : 60) / 2000
        var links = ["base_link": matrix_identity_double4x4]
        var armIndex = 0
        for (i, joint) in definition.joints.enumerated() {
            var motion = matrix_identity_double4x4
            if joint.type == "revolute" {
                motion = simd_double4x4(simd_quatd(angle: q[armIndex] * degreesToRadians, axis: vector(joint.axis)))
                armIndex += 1
            } else if joint.type == "prismatic" {
                // Source URDF: right finger mimics left with multiplier -1.
                let displacement = vector(joint.axis) * (joint.name == "finger_left" ? opening : -opening)
                motion.columns.3 = SIMD4(displacement.x, displacement.y, displacement.z, 1)
            }
            links[joint.child] = links[joint.parent]! * origins[i] * motion
        }
        return links
    }
    public func position(_ joints: [Double]) -> SIMD3<Double> {
        let p = transforms(joints)["end_link"]!.columns.3
        return SIMD3(p.x, p.y, p.z)
    }
    public struct Solution: Sendable { public let joints: [Double]; public let error: Double; public var success: Bool { error < 0.002 } }
    /// Position-only DLS. The returned candidate never mutates the input pose.
    public func solve(target: SIMD3<Double>, initial: [Double], iterations: Int = 300) -> Solution {
        var q = clampPose(initial)
        guard target.x.isFinite, target.y.isFinite, target.z.isFinite else { return Solution(joints: q, error: .infinity) }
        for _ in 0..<max(0, iterations) {
            let p = position(q), error = target - p
            if simd_length(error) < 0.001 { break }
            let jacobian = (0..<6).map { i -> SIMD3<Double> in
                let h = q[i] + 0.01 <= definition.armJoints[i].upper / degreesToRadians ? 0.01 : -0.01
                var trial = q; trial[i] += h
                return (position(trial) - p) / (h * degreesToRadians)
            }
            var a = matrix_identity_double3x3 * 0.0004
            for c in jacobian { a += simd_double3x3(columns: (c * c.x, c * c.y, c * c.z)) }
            let step = a.inverse * error
            q = clampPose(q.enumerated().map { i, v in v + clamp(simd_dot(jacobian[i], step), -0.12, 0.12) / degreesToRadians })
        }
        return Solution(joints: q, error: simd_distance(position(q), target))
    }
}
