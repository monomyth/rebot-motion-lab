import Foundation
import simd

/// Kinematic attach/release of the scene cube. No contact forces.
///
/// The tool origin is the closed fingertip center. Pads extend along tool −X
/// (~65 mm) and open along ±Y. A pinch needs the cube in that jaw volume and
/// the opening near the cube width — not slammed to 20 mm through a 40 mm cube.
public enum Grasp {
    public static let jawXMin = -0.062
    public static let jawXMax = -0.008
    public static let jawPad = 0.014
    public static let levelLimit = cos(5 * degreesToRadians)
    public static let leftPadMin = SIMD3(-0.065, 0.0005, -0.020)
    public static let leftPadMax = SIMD3(-0.002, 0.031, 0.020)
    public static let rightPadMin = SIMD3(-0.065, -0.031, -0.020)
    public static let rightPadMax = SIMD3(-0.002, -0.0005, 0.020)

    public static func cubeWidthMM(_ cube: CubeState) -> Double { cube.size.y * 1000 }
    /// Width of the cube along the jaw opening (tool +Y), in mm.
    public static func projectedWidthMM(_ cube: CubeState, endLink: simd_double4x4) -> Double {
        let axis = SIMD3(endLink.columns.1.x, endLink.columns.1.y, endLink.columns.1.z)
        let n = simd_length(axis)
        guard n > 1e-9 else { return cubeWidthMM(cube) }
        let u = axis / n
        return (abs(u.x) * cube.size.x + abs(u.y) * cube.size.y + abs(u.z) * cube.size.z) * 1000
    }
    public static func attachOpeningMM(_ cube: CubeState, endLink: simd_double4x4) -> Double { projectedWidthMM(cube, endLink: endLink) + 2 }
    public static func releaseOpeningMM(_ cube: CubeState, endLink: simd_double4x4) -> Double { projectedWidthMM(cube, endLink: endLink) + 12 }
    public static func minimumOpeningMM(_ cube: CubeState, endLink: simd_double4x4) -> Double { max(0, projectedWidthMM(cube, endLink: endLink) - 2) }

    public static func clampedGrip(_ requested: Double, cube: CubeState, endLink: simd_double4x4) -> Double {
        let grip = clamp(requested, 0, 90)
        guard cube.present else { return grip }
        if cube.attached || inJaws(cube: cube, endLink: endLink) {
            return max(grip, minimumOpeningMM(cube, endLink: endLink))
        }
        return grip
    }

    /// Cube center is either at the fingertip TCP (level pinch) or along the hanging pads.
    public static func inJaws(cube: CubeState, endLink: simd_double4x4) -> Bool {
        let local = endLink.inverse * SIMD4(cube.center.x, cube.center.y, cube.center.z, 1)
        let half = cube.size / 2
        let radial = abs(local.y) <= half.y + jawPad && abs(local.z) <= half.z + jawPad
        guard radial else { return false }
        let nearTCP = abs(local.x) <= half.x + jawPad
        let hanging = local.x >= jawXMin && local.x <= jawXMax
        return nearTCP || hanging
    }

    public static func aligned(_ cube: CubeState, endLink: simd_double4x4) -> CubeState {
        guard cube.present, cube.attached else { return cube }
        var next = cube
        let world = endLink * cube.attachLocal
        next.center = translation(world)
        next.rotation = quaternion(from: rotation(world))
        return next
    }

    public static func update(previousGrip: Double, pose: Pose, cube: inout CubeState, endLink: simd_double4x4) {
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
        if closing, pose.grip <= attachOpeningMM(cube, endLink: endLink), pose.grip >= minimumOpeningMM(cube, endLink: endLink) - 8, inJaws(cube: cube, endLink: endLink) {
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

    /// How far a finger-pad box sits inside the cube. Zero if the inner faces only touch.
    public static func padPenetration(cube: CubeState, leftFinger: simd_double4x4, rightFinger: simd_double4x4) -> Double {
        Swift.max(
            boxPenetration(cube: cube, frame: leftFinger, lo: leftPadMin, hi: leftPadMax),
            boxPenetration(cube: cube, frame: rightFinger, lo: rightPadMin, hi: rightPadMax)
        )
    }

    private static func boxPenetration(cube: CubeState, frame: simd_double4x4, lo: SIMD3<Double>, hi: SIMD3<Double>) -> Double {
        let inverse = cube.rotation.inverse
        let half = cube.size / 2
        var depth = 0.0
        for x in [lo.x, hi.x] {
            for y in [lo.y, hi.y] {
                for z in [lo.z, hi.z] {
                    let p = frame * SIMD4(x, y, z, 1)
                    let local = inverse.act(SIMD3(p.x, p.y, p.z) - cube.center)
                    let dx = abs(local.x) - half.x, dy = abs(local.y) - half.y, dz = abs(local.z) - half.z
                    if dx <= 0, dy <= 0, dz <= 0 {
                        depth = Swift.max(depth, Swift.min(-dx, Swift.min(-dy, -dz)))
                    }
                }
            }
        }
        return depth
    }
}
