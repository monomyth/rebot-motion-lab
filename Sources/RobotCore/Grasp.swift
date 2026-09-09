import Foundation
import simd

/// Kinematic attach/release of the scene cube. No contact forces.
public enum Grasp {
    public static let closeMM = 25.0
    public static let releaseMM = 40.0
    public static let xyMargin = 0.008
    public static let zMargin = 0.005
    public static let levelLimit = cos(5 * degreesToRadians)

    public static func aabbContains(cubeCenter: SIMD3<Double>, cubeSize: SIMD3<Double>, endLink: simd_double4x4) -> Bool {
        let local = endLink.inverse * SIMD4(cubeCenter.x, cubeCenter.y, cubeCenter.z, 1)
        let half = cubeSize / 2
        return abs(local.x) <= half.x + xyMargin
            && abs(local.y) <= half.y + xyMargin
            && abs(local.z) <= half.z + zMargin
    }

    public static func aligned(_ cube: CubeState, endLink: simd_double4x4) -> CubeState {
        guard cube.present, cube.attached else { return cube }
        var next = cube
        let world = endLink * cube.attachLocal
        next.center = translation(world)
        next.rotation = quaternion(from: rotation(world))
        return next
    }

    /// Updates attach state from a gripper change, then aligns an attached cube to `endLink`.
    public static func update(previousGrip: Double, pose: Pose, cube: inout CubeState, endLink: simd_double4x4) {
        guard cube.present else { cube.attached = false; return }
        if cube.attached {
            if pose.grip >= releaseMM {
                cube = aligned(cube, endLink: endLink)
                cube.attached = false
                cube.attachLocal = matrix_identity_double4x4
                cube.restOnFloor()
            } else {
                cube = aligned(cube, endLink: endLink)
            }
            return
        }
        let closing = pose.grip < previousGrip - 1e-9
        if closing, pose.grip <= closeMM, aabbContains(cubeCenter: cube.center, cubeSize: cube.size, endLink: endLink) {
            cube.attachLocal = endLink.inverse * cube.worldMatrix
            cube.attached = true
            cube = aligned(cube, endLink: endLink)
        }
    }

    public static func cubeTopInTool(_ cube: CubeState) -> SIMD3<Double>? {
        guard cube.present, cube.attached else { return nil }
        return simd_normalize(rotation(cube.attachLocal) * SIMD3(0, 0, 1))
    }

    public static func isLevel(toolZ: SIMD3<Double>, cubeTop: SIMD3<Double>?) -> Bool {
        if let top = cubeTop { return simd_dot(simd_normalize(top), SIMD3(0, 0, 1)) >= levelLimit }
        return simd_dot(simd_normalize(toolZ), SIMD3(0, 0, -1)) >= levelLimit
    }
}
