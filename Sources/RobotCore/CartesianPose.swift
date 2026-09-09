import Foundation
import simd

/// Base/world frame is right handed, Z up. Positions are mm; quaternions are [x,y,z,w].
public struct CartesianPose: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey { case positionMM = "position_mm", quaternionXYZW = "quaternion_xyzw" }
    public var positionMM: [Double]
    public var quaternionXYZW: [Double]
    public init(positionMM: [Double], quaternionXYZW: [Double]) {
        self.positionMM = positionMM; self.quaternionXYZW = quaternionXYZW
    }
    public init(_ transform: simd_double4x4) {
        positionMM = [transform[3].x * 1000, transform[3].y * 1000, transform[3].z * 1000]
        let q = simd_quatd(transform).normalized.vector
        quaternionXYZW = [q.x, q.y, q.z, q.w]
    }
    public func validated() throws -> Self {
        guard positionMM.count == 3, quaternionXYZW.count == 4,
              (positionMM + quaternionXYZW).allSatisfy(\.isFinite),
              positionMM.allSatisfy({ abs($0) <= 2000 }),
              abs(simd_length(SIMD4(quaternionXYZW[0], quaternionXYZW[1], quaternionXYZW[2], quaternionXYZW[3])) - 1) < 0.001
        else { throw ExperimentError.invalid("Pose needs three finite mm coordinates and a unit quaternion [x,y,z,w].") }
        return self
    }
    public var transform: simd_double4x4 {
        var m = simd_double4x4(simd_quatd(vector: SIMD4(quaternionXYZW[0], quaternionXYZW[1], quaternionXYZW[2], quaternionXYZW[3])).normalized)
        m[3] = SIMD4(positionMM[0] / 1000, positionMM[1] / 1000, positionMM[2] / 1000, 1)
        return m
    }
}

public func rotationError(_ target: simd_quatd, _ current: simd_quatd) -> SIMD3<Double> {
    var q = (target * current.inverse).normalized
    if q.real < 0 { q = simd_quatd(vector: -q.vector) }
    let length = simd_length(q.imag)
    return length < 1e-12 ? .zero : q.imag / length * (2 * atan2(length, q.real))
}

extension Kinematics {
    public static let graspOffset = SIMD3<Double>(-0.020, 0, 0)
    public func toolTransform(_ joints: [Double], frame: String = "tool") -> simd_double4x4 {
        let m = transforms(joints)["end_link"]!
        guard frame == "grasp" else { return m }
        var offset = matrix_identity_double4x4; offset[3] = SIMD4(Self.graspOffset, 1)
        return m * offset
    }
    public struct PoseSolution: Sendable {
        public let joints: [Double]
        public let positionErrorMM: Double
        public let orientationErrorDeg: Double
        public var success: Bool { positionErrorMM < 2 && orientationErrorDeg < 1 }
    }
    /// Six-dimensional damped least squares. Does not mutate the rendered robot.
    public func solvePose(target: CartesianPose, initial: [Double], frame: String = "tool", iterations: Int = 500) throws -> PoseSolution {
        _ = try target.validated()
        guard ["tool", "grasp"].contains(frame), initial.count == 6, initial.allSatisfy(\.isFinite) else { throw ExperimentError.invalid("Invalid pose frame or initial joints.") }
        let desired = target.transform, orientation = simd_quatd(desired), position = SIMD3(desired[3].x, desired[3].y, desired[3].z)
        var q = clampPose(initial)
        let angularScale = 0.15
        for _ in 0..<max(0, iterations) {
            let m = toolTransform(q, frame: frame), p = SIMD3(m[3].x, m[3].y, m[3].z), r = simd_quatd(m)
            let e = position - p, a = rotationError(orientation, r)
            if simd_length(e) < 0.0005 && simd_length(a) < 0.003 { break }
            let error = [e.x, e.y, e.z, a.x * angularScale, a.y * angularScale, a.z * angularScale]
            let columns = (0..<6).map { i -> [Double] in
                let h = q[i] + 0.01 <= definition.armJoints[i].upper / degreesToRadians ? 0.01 : -0.01
                var trial = q; trial[i] += h
                let t = toolTransform(trial, frame: frame), dp = (SIMD3(t[3].x,t[3].y,t[3].z) - p) / (h * degreesToRadians)
                let dr = rotationError(simd_quatd(t), r) * angularScale / (h * degreesToRadians)
                return [dp.x, dp.y, dp.z, dr.x, dr.y, dr.z]
            }
            var system = (0..<6).map { row in (0..<6).map { col in columns.reduce(0) { $0 + $1[row] * $1[col] } + (row == col ? 0.00001 : 0) } }
            var rhs = error
            for i in 0..<6 {
                let pivot = (i..<6).max { abs(system[$0][i]) < abs(system[$1][i]) }!
                system.swapAt(i, pivot); rhs.swapAt(i, pivot)
                let divisor = system[i][i]
                for k in i..<6 { system[i][k] /= divisor }; rhs[i] /= divisor
                for j in 0..<6 where j != i {
                    let factor = system[j][i]
                    for k in i..<6 { system[j][k] -= factor * system[i][k] }; rhs[j] -= factor * rhs[i]
                }
            }
            q = clampPose((0..<6).map { i in q[i] + clamp(zip(columns[i],rhs).reduce(0) { $0 + $1.0 * $1.1 }, -0.12, 0.12) / degreesToRadians })
        }
        let m = toolTransform(q, frame: frame)
        return PoseSolution(joints: q, positionErrorMM: simd_distance(position, SIMD3(m[3].x,m[3].y,m[3].z)) * 1000,
                            orientationErrorDeg: simd_length(rotationError(orientation, simd_quatd(m))) / degreesToRadians)
    }
}
