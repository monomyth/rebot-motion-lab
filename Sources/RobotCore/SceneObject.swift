import Foundation
import simd

/// One kinematic scene cube. Bottom face rests on the solid base plane when unattached.
public struct CubeState: Equatable, Sendable {
    public var present: Bool
    public var attached: Bool
    public var size: SIMD3<Double>
    public var center: SIMD3<Double>
    public var rotation: simd_quatd
    public var attachLocal: simd_double4x4
    public var spawnCenter: SIMD3<Double>
    public var spawnSize: SIMD3<Double>
    public var spawnRotation: simd_quatd

    public static let defaultSize = SIMD3<Double>(repeating: 0.04)
    public static var defaultCenter: SIMD3<Double> {
        SIMD3(0.28, 0, FloorConstraint.height + defaultSize.z / 2)
    }

    public static var spawn: CubeState {
        let center = defaultCenter
        return CubeState(
            present: true, attached: false, size: defaultSize, center: center,
            rotation: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), attachLocal: matrix_identity_double4x4,
            spawnCenter: center, spawnSize: defaultSize, spawnRotation: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        )
    }

    public var yaw: Double {
        let v = rotation.act(SIMD3<Double>(1, 0, 0))
        return atan2(v.y, v.x)
    }

    public var topNormal: SIMD3<Double> { simd_normalize(rotation.act(SIMD3(0, 0, 1))) }

    public var worldMatrix: simd_double4x4 {
        var m = simd_double4x4(rotation)
        m.columns.3 = SIMD4(center.x, center.y, center.z, 1)
        return m
    }

    public var corners: [SIMD3<Double>] {
        let h = size / 2
        var points: [SIMD3<Double>] = []
        for dx in [-h.x, h.x] {
            for dy in [-h.y, h.y] {
                for dz in [-h.z, h.z] {
                    points.append(center + rotation.act(SIMD3(dx, dy, dz)))
                }
            }
        }
        return points
    }

    public var minimumHeight: Double { corners.map(\.z).min() ?? center.z - size.z / 2 }

    public mutating func restOnFloor() {
        let lift = FloorConstraint.height - minimumHeight
        if lift > 0 { center.z += lift }
    }

    public mutating func restoreSpawn() {
        present = true
        attached = false
        size = spawnSize
        center = spawnCenter
        rotation = spawnRotation
        attachLocal = matrix_identity_double4x4
        restOnFloor()
    }

    public func placing(center: SIMD3<Double>? = nil, size: SIMD3<Double>? = nil, yaw: Double? = nil) throws -> CubeState {
        var next = self
        if let size {
            guard size.x.isFinite, size.y.isFinite, size.z.isFinite, size.x > 0.005, size.y > 0.005, size.z > 0.005,
                  size.x <= 0.12, size.y <= 0.12, size.z <= 0.12 else {
                throw CubeError.invalid("Cube size must be finite and between 5 mm and 120 mm on each side.")
            }
            next.size = size
        }
        if let center {
            guard center.x.isFinite, center.y.isFinite, center.z.isFinite else { throw CubeError.invalid("Cube center must be finite.") }
            next.center = center
        }
        if let yaw {
            guard yaw.isFinite else { throw CubeError.invalid("Cube yaw must be finite.") }
            next.rotation = simd_quatd(angle: yaw, axis: SIMD3(0, 0, 1))
        }
        next.attached = false
        next.attachLocal = matrix_identity_double4x4
        if next.minimumHeight < FloorConstraint.height - 1e-9 {
            throw CubeError.invalid("Cube would intersect the solid base plane. No change was applied.")
        }
        next.spawnCenter = next.center
        next.spawnSize = next.size
        next.spawnRotation = next.rotation
        return next
    }
}

public enum CubeError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public func rpy(from matrix: simd_double4x4) -> SIMD3<Double> {
    let r20 = matrix.columns.0.z
    let pitch = asin(clamp(-r20, -1, 1))
    let roll = atan2(matrix.columns.1.z, matrix.columns.2.z)
    let yaw = atan2(matrix.columns.0.y, matrix.columns.0.x)
    return SIMD3(roll, pitch, yaw)
}

public func rotation(_ matrix: simd_double4x4) -> simd_double3x3 {
    simd_double3x3(
        SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
        SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
        SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
    )
}

public func quaternion(from matrix: simd_double3x3) -> simd_quatd {
    let m00 = matrix.columns.0.x, m11 = matrix.columns.1.y, m22 = matrix.columns.2.z
    let trace = m00 + m11 + m22
    if trace > 0 {
        let s = 0.5 / sqrt(trace + 1)
        return simd_quatd(
            ix: (matrix.columns.1.z - matrix.columns.2.y) * s,
            iy: (matrix.columns.2.x - matrix.columns.0.z) * s,
            iz: (matrix.columns.0.y - matrix.columns.1.x) * s,
            r: 0.25 / s
        )
    }
    if m00 > m11 && m00 > m22 {
        let s = 2 * sqrt(1 + m00 - m11 - m22)
        return simd_quatd(
            ix: 0.25 * s,
            iy: (matrix.columns.1.x + matrix.columns.0.y) / s,
            iz: (matrix.columns.2.x + matrix.columns.0.z) / s,
            r: (matrix.columns.1.z - matrix.columns.2.y) / s
        )
    }
    if m11 > m22 {
        let s = 2 * sqrt(1 + m11 - m00 - m22)
        return simd_quatd(
            ix: (matrix.columns.1.x + matrix.columns.0.y) / s,
            iy: 0.25 * s,
            iz: (matrix.columns.2.y + matrix.columns.1.z) / s,
            r: (matrix.columns.2.x - matrix.columns.0.z) / s
        )
    }
    let s = 2 * sqrt(1 + m22 - m00 - m11)
    return simd_quatd(
        ix: (matrix.columns.2.x + matrix.columns.0.z) / s,
        iy: (matrix.columns.2.y + matrix.columns.1.z) / s,
        iz: 0.25 * s,
        r: (matrix.columns.0.y - matrix.columns.1.x) / s
    )
}

public func translation(_ matrix: simd_double4x4) -> SIMD3<Double> {
    SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
}
