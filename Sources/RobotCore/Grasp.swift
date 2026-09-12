import Foundation
import simd

/// Kinematic attach/release of the scene cube. No contact forces.
///
/// The tool origin is the closed fingertip center. Pads extend along tool −X
/// (~65 mm) and open along ±Y. Attach is a pinch of the solid: some of the cube
/// in the jaw cavity (a corner or edge is enough) and both inner pads on it.
/// The cube center does not have to sit in the cavity. One pad is glue, not a grasp.
public enum Grasp {
    public static let jawXMin = -0.062
    public static let jawXMax = -0.008
    public static let jawPad = 0.014
    public static let levelLimit = cos(5 * degreesToRadians)
    /// Inner gripping faces only (not the whole 31 mm finger AABB, which is mostly backing).
    /// Y includes 0.5 mm of the cavity so a face-touch of the solid counts as a pinch.
    public static let leftPadMin = SIMD3(-0.065, -0.0005, -0.020)
    public static let leftPadMax = SIMD3(-0.002, 0.008, 0.020)
    public static let rightPadMin = SIMD3(-0.065, -0.008, -0.020)
    public static let rightPadMax = SIMD3(-0.002, 0.0005, 0.020)

    public static func cubeWidthMM(_ cube: CubeState) -> Double { cube.size.y * 1000 }
    /// Width of the cube along the jaw opening (tool +Y), in mm.
    public static func projectedWidthMM(_ cube: CubeState, endLink: simd_double4x4) -> Double {
        let axis = SIMD3(endLink.columns.1.x, endLink.columns.1.y, endLink.columns.1.z)
        let n = simd_length(axis)
        guard n > 1e-9 else { return cubeWidthMM(cube) }
        let u = axis / n
        return (abs(u.x) * cube.size.x + abs(u.y) * cube.size.y + abs(u.z) * cube.size.z) * 1000
    }
    public static func attachOpeningMM(_ cube: CubeState, endLink: simd_double4x4) -> Double { projectedWidthMM(cube, endLink: endLink) + 0.5 }
    public static func releaseOpeningMM(_ cube: CubeState, endLink: simd_double4x4) -> Double { projectedWidthMM(cube, endLink: endLink) + 12 }
    public static func minimumOpeningMM(_ cube: CubeState, endLink: simd_double4x4) -> Double { max(0, projectedWidthMM(cube, endLink: endLink) - 1) }

    /// TCP that puts the cube in the pad length (not at the fingertips).
    public static func padGraspTCP(_ cube: CubeState, toolX: SIMD3<Double>, toolZ: SIMD3<Double>, depth: Double = 0.035, height: Double = 0.048) -> SIMD3<Double> {
        let x = simd_normalize(toolX)
        let z = simd_normalize(toolZ)
        return cube.center + x * depth + z * (height - cube.center.z)
    }

    public static func clampedGrip(_ requested: Double, cube: CubeState, endLink: simd_double4x4) -> Double {
        let grip = clamp(requested, 0, 90)
        guard cube.present else { return grip }
        if cube.attached || inJaws(cube: cube, endLink: endLink, gripMM: grip) {
            return max(grip, minimumOpeningMM(cube, endLink: endLink))
        }
        return grip
    }

    /// Some of the solid sits in the cavity between the pads (corner/edge is enough).
    public static func inJaws(cube: CubeState, endLink: simd_double4x4, gripMM: Double) -> Bool {
        let hy = max(gripMM / 2000.0, 0.001) + 0.002
        let lo = SIMD3(jawXMin, -hy, -0.020)
        let hi = SIMD3(jawXMax, hy, 0.020)
        return boxPenetration(cube: cube, frame: endLink, lo: lo, hi: hi) > 0
    }

    /// Inner faces of both pads overlap the solid — a pinch, not one-sided glue.
    public static func pinching(cube: CubeState, leftFinger: simd_double4x4, rightFinger: simd_double4x4) -> Bool {
        boxPenetration(cube: cube, frame: leftFinger, lo: leftPadMin, hi: leftPadMax) > 0
            && boxPenetration(cube: cube, frame: rightFinger, lo: rightPadMin, hi: rightPadMax) > 0
    }

    public static func aligned(_ cube: CubeState, endLink: simd_double4x4) -> CubeState {
        guard cube.present, cube.attached else { return cube }
        var next = cube
        let world = endLink * cube.attachLocal
        next.center = translation(world)
        next.rotation = quaternion(from: rotation(world))
        return next
    }

    public static func update(
        previousGrip: Double, pose: Pose, cube: inout CubeState, endLink: simd_double4x4,
        leftFinger: simd_double4x4? = nil, rightFinger: simd_double4x4? = nil
    ) {
        guard cube.present else { cube.attached = false; return }
        if cube.attached {
            if pose.grip >= releaseOpeningMM(cube, endLink: endLink) {
                cube = aligned(cube, endLink: endLink)
                cube.attached = false
                cube.attachLocal = matrix_identity_double4x4
                cube.verticalVelocity = 0
            } else {
                cube = aligned(cube, endLink: endLink)
                cube.verticalVelocity = 0
            }
            return
        }
        let closing = pose.grip < previousGrip - 1e-9
        let inCavity = inJaws(cube: cube, endLink: endLink, gripMM: pose.grip)
        let nearWidth = pose.grip <= attachOpeningMM(cube, endLink: endLink) && pose.grip >= minimumOpeningMM(cube, endLink: endLink) - 8
        // Solid pinch: both inner pads on the cube (corner/edge is enough). Center-in-box
        // is not required. One pad is glue. Without finger frames, cavity overlap + width.
        var pinched = nearWidth && inCavity
        if let leftFinger, let rightFinger {
            pinched = pinching(cube: cube, leftFinger: leftFinger, rightFinger: rightFinger)
        }
        if closing, pinched {
            cube.attachLocal = endLink.inverse * cube.worldMatrix
            cube.attached = true
            cube.verticalVelocity = 0
            cube = aligned(cube, endLink: endLink)
        }
    }

    public static func cubeTopInTool(_ cube: CubeState) -> SIMD3<Double>? {
        guard cube.present, cube.attached else { return nil }
        return simd_normalize(rotation(cube.attachLocal) * SIMD3(0, 0, 1))
    }

    public static func isLevel(toolZ: SIMD3<Double>, cubeTop: SIMD3<Double>?) -> Bool {
        if let top = cubeTop { return simd_dot(simd_normalize(top), SIMD3(0, 0, 1)) >= levelLimit }
        return simd_dot(simd_normalize(toolZ), SIMD3(0, 0, 1)) >= levelLimit
    }

    /// How far a finger-pad box sits inside the cube. Zero if the solids only touch.
    public static func padPenetration(cube: CubeState, leftFinger: simd_double4x4, rightFinger: simd_double4x4) -> Double {
        Swift.max(
            boxPenetration(cube: cube, frame: leftFinger, lo: leftPadMin, hi: leftPadMax),
            boxPenetration(cube: cube, frame: rightFinger, lo: rightPadMin, hi: rightPadMax)
        )
    }

    /// OBB–OBB SAT. Corner sampling misses a pad box that contains the cube.
    private static func boxPenetration(cube: CubeState, frame: simd_double4x4, lo: SIMD3<Double>, hi: SIMD3<Double>) -> Double {
        let halfA = cube.size / 2
        let padCenter = (lo + hi) / 2
        let padHalf = (hi - lo) / 2
        let axisX = SIMD3(frame.columns.0.x, frame.columns.0.y, frame.columns.0.z)
        let axisY = SIMD3(frame.columns.1.x, frame.columns.1.y, frame.columns.1.z)
        let axisZ = SIMD3(frame.columns.2.x, frame.columns.2.y, frame.columns.2.z)
        let padWorld = translation(frame) + axisX * padCenter.x + axisY * padCenter.y + axisZ * padCenter.z
        let inverse = cube.rotation.inverse
        let center = inverse.act(padWorld - cube.center)
        let b0 = inverse.act(axisX), b1 = inverse.act(axisY), b2 = inverse.act(axisZ)
        let padAxes = [b0, b1, b2]
        let cubeAxes = [SIMD3<Double>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        var minOverlap = Double.infinity
        func separated(_ n: SIMD3<Double>) -> Bool {
            let length = simd_length(n)
            guard length > 1e-12 else { return false }
            let axis = n / length
            let ra = abs(axis.x) * halfA.x + abs(axis.y) * halfA.y + abs(axis.z) * halfA.z
            let rb = abs(simd_dot(axis, padAxes[0])) * padHalf.x
                + abs(simd_dot(axis, padAxes[1])) * padHalf.y
                + abs(simd_dot(axis, padAxes[2])) * padHalf.z
            let overlap = ra + rb - abs(simd_dot(center, axis))
            if overlap <= 0 { return true }
            minOverlap = Swift.min(minOverlap, overlap)
            return false
        }
        for axis in cubeAxes where separated(axis) { return 0 }
        for axis in padAxes where separated(axis) { return 0 }
        for a in cubeAxes {
            for b in padAxes where separated(simd_cross(a, b)) { return 0 }
        }
        return minOverlap.isFinite ? minOverlap : 0
    }
}
