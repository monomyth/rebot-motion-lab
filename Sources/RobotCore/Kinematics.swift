import Foundation
import simd

public let degreesToRadians = Double.pi / 180
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
        let opening = (grip.isFinite ? clamp(grip, 0, 90) : 60) / 2000
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
    public func endLink(_ joints: [Double], grip: Double = 60) -> simd_double4x4 {
        transforms(joints, grip: grip)["end_link"]!
    }
    public func position(_ joints: [Double]) -> SIMD3<Double> {
        translation(endLink(joints))
    }
    public func toolX(_ joints: [Double]) -> SIMD3<Double> {
        let m = endLink(joints)
        return SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
    }
    public func toolY(_ joints: [Double]) -> SIMD3<Double> {
        let m = endLink(joints)
        return SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
    }
    public func toolZ(_ joints: [Double]) -> SIMD3<Double> {
        let m = endLink(joints)
        return SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
    }
    public func rpy(_ joints: [Double]) -> SIMD3<Double> { RobotCore.rpy(from: endLink(joints)) }
    public func isLevel(_ joints: [Double], cubeTop: SIMD3<Double>? = nil) -> Bool {
        Grasp.isLevel(toolZ: toolZ(joints), cubeTop: cubeTop)
    }
    public struct Solution: Sendable {
        public let joints: [Double]
        public let error: Double
        public let orientationError: Double
        public init(joints: [Double], error: Double, orientationError: Double = 0) {
            self.joints = joints; self.error = error; self.orientationError = orientationError
        }
        public var success: Bool { error < 0.002 && orientationError < 5 * degreesToRadians }
    }
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
    /// keepLevel: tool +Z up; unattached picks roll so the jaws open along world ±Y.
    /// fingersDown: tool +X along world −Z (fingertips down, wrist up). TCP is still the
    /// fingertip. Pads straddle a floor cube; a corner or edge of the solid is enough.
    public func solve(target: SIMD3<Double>, initial: [Double], keepLevel: Bool, cubeTopInTool: SIMD3<Double>?, fingersDown: Bool = false, iterations: Int = 400) -> Solution {
        if !keepLevel, !fingersDown { return solve(target: target, initial: initial, iterations: iterations) }
        let positioned = solve(target: target, initial: initial, iterations: iterations)
        var q = positioned.joints
        guard target.x.isFinite, target.y.isFinite, target.z.isFinite else {
            return Solution(joints: q, error: .infinity, orientationError: .infinity)
        }
        let oriWeight = 0.05
        for _ in 0..<max(0, iterations) {
            let residual = orientationResidual(q, target: target, cubeTopInTool: cubeTopInTool, fingersDown: fingersDown)
            let pos = SIMD3(residual[0], residual[1], residual[2])
            let ori = SIMD3(residual[3], residual[4], residual[5])
            if simd_length(pos) < 0.001, simd_length(ori) < 0.03 { break }
            var J = Array(repeating: Array(repeating: 0.0, count: 6), count: 6)
            for i in 0..<6 {
                let h = q[i] + 0.01 <= definition.armJoints[i].upper / degreesToRadians ? 0.01 : -0.01
                var trial = q; trial[i] += h
                let n = orientationResidual(trial, target: target, cubeTopInTool: cubeTopInTool, fingersDown: fingersDown)
                let scale = 1 / (h * degreesToRadians)
                for r in 0..<6 { J[r][i] = (n[r] - residual[r]) * scale }
            }
            let step = dampedStep(J, residual, oriWeight: oriWeight)
            q = clampPose(q.enumerated().map { i, v in v - clamp(step[i], -0.12, 0.12) / degreesToRadians })
        }
        let final = orientationResidual(q, target: target, cubeTopInTool: cubeTopInTool, fingersDown: fingersDown)
        return Solution(
            joints: q,
            error: simd_length(SIMD3(final[0], final[1], final[2])),
            orientationError: simd_length(SIMD3(final[3], final[4], final[5]))
        )
    }
    /// `a - b` is zero only when the unit axes match. A cross product is also
    /// zero when they are opposite, which made keep-level accept a tool pointed up.
    private func orientationResidual(_ q: [Double], target: SIMD3<Double>, cubeTopInTool: SIMD3<Double>?, fingersDown: Bool) -> [Double] {
        let T = endLink(q)
        let pos = translation(T) - target
        let ori: SIMD3<Double>
        if fingersDown {
            let xErr = simd_normalize(toolX(q)) - SIMD3(0, 0, -1)
            ori = SIMD3(xErr.x, xErr.z, simd_dot(simd_normalize(toolY(q)), SIMD3(1, 0, 0)))
        } else if let local = cubeTopInTool {
            ori = simd_normalize(rotation(T) * local) - SIMD3(0, 0, 1)
        } else {
            ori = simd_normalize(toolZ(q)) - SIMD3(0, 0, 1)
        }
        return [pos.x, pos.y, pos.z, ori.x, ori.y, ori.z]
    }
    private func dampedStep(_ J: [[Double]], _ residual: [Double], oriWeight: Double) -> [Double] {
        var A = Array(repeating: Array(repeating: 0.0, count: 6), count: 6)
        var b = Array(repeating: 0.0, count: 6)
        let w = [1.0, 1.0, 1.0, oriWeight, oriWeight, oriWeight]
        for i in 0..<6 {
            A[i][i] = 0.0004
            for k in 0..<6 {
                let wk = w[k]
                b[i] += J[k][i] * residual[k] * wk
                for j in 0..<6 { A[i][j] += J[k][i] * J[k][j] * wk }
            }
        }
        return solveLinear6(A, b)
    }
    private func solveLinear6(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        var a = matrix
        var x = vector
        for i in 0..<6 {
            var pivot = i
            for r in (i + 1)..<6 where abs(a[r][i]) > abs(a[pivot][i]) { pivot = r }
            a.swapAt(i, pivot); x.swapAt(i, pivot)
            let d = a[i][i]
            if abs(d) < 1e-12 { continue }
            for r in (i + 1)..<6 {
                let f = a[r][i] / d
                for c in i..<6 { a[r][c] -= f * a[i][c] }
                x[r] -= f * x[i]
            }
        }
        var q = Array(repeating: 0.0, count: 6)
        for i in stride(from: 5, through: 0, by: -1) {
            var s = x[i]
            for c in (i + 1)..<6 { s -= a[i][c] * q[c] }
            q[i] = abs(a[i][i]) < 1e-12 ? 0 : s / a[i][i]
        }
        return q
    }
}
