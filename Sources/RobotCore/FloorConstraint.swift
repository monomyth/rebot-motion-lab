import Foundation
import simd

/// Plane contact from convex-hull support vertices of every moving STL, including both fingers.
/// Hull support is exact for a plane; no mesh loading or geometry allocation occurs while dragging.
public struct FloorConstraint: Sendable {
    public static let height = -0.001 // Matches the top of the rendered base plane, in meters.
    private static let margin = 0.000001 // One micrometer keeps Float rendering above the plane.
    private struct Document: Decodable { let links: [Hull] }
    private struct Hull: Decodable, Sendable { let name: String; let vertices: [[Double]] }
    private struct Support: Sendable { let name: String; let points: [SIMD3<Double>] }
    private let robot: Kinematics
    private let supports: [Support]
    private let descendants: [Set<String>]
    private let radiusBound: Double
    public init(_ robot: Kinematics) throws {
        self.robot = robot
        let document = try Assets.decode("model/floor-hulls.json", as: Document.self)
        supports = document.links.map { Support(name: $0.name, points: $0.vertices.map(vector)) }
        descendants = robot.definition.armJoints.map { joint in
            var names: Set<String> = [joint.child]
            for child in robot.definition.joints where names.contains(child.parent) { names.insert(child.child) }
            return names
        }
        radiusBound = robot.definition.joints.reduce(0) { $0 + simd_length(vector($1.xyz)) }
            + (supports.flatMap(\.points).map(simd_length).max() ?? 0) + 0.09
    }
    public func lowestSupport(_ pose: Pose) -> (name: String, height: Double) {
        let transforms = robot.transforms(pose.joints, grip: pose.grip)
        var name = ""
        var height = Double.infinity
        for hull in supports {
            let m = transforms[hull.name]!
            for p in hull.points {
                let z = m[0].z * p.x + m[1].z * p.y + m[2].z * p.z + m[3].z
                if z < height { height = z; name = hull.name }
            }
        }
        return (name, height)
    }
    public func minimumHeight(_ pose: Pose, cube: CubeState? = nil) -> Double {
        let transforms = robot.transforms(pose.joints, grip: pose.grip)
        var height = Double.infinity
        for hull in supports {
            let m = transforms[hull.name]!
            for p in hull.points { height = min(height, m[0].z * p.x + m[1].z * p.y + m[2].z * p.z + m[3].z) }
        }
        if let cube, cube.present, cube.attached {
            height = min(height, Grasp.aligned(cube, endLink: transforms["end_link"]!).minimumHeight)
        }
        return height
    }
    public func isAllowed(_ pose: Pose, cube: CubeState? = nil) -> Bool {
        guard minimumHeight(pose, cube: cube) >= Self.height else { return false }
        if cubePenetration(pose, cube: cube) > 0.0005 { return false }
        if padOverlap(pose, cube: cube) > 0.0005 { return false }
        return true
    }

    /// Positive when a non-finger hull point or a finger pad sits inside an unattached cube.
    public func cubePenetration(_ pose: Pose, cube: CubeState?) -> Double {
        guard let cube, cube.present, !cube.attached else { return 0 }
        let transforms = robot.transforms(pose.joints, grip: pose.grip)
        let inverse = cube.rotation.inverse
        let half = cube.size / 2
        var depth = 0.0
        for hull in supports where !hull.name.hasPrefix("finger_") {
            let m = transforms[hull.name]!
            for p in hull.points {
                let world = SIMD3(
                    m[0].x * p.x + m[1].x * p.y + m[2].x * p.z + m[3].x,
                    m[0].y * p.x + m[1].y * p.y + m[2].y * p.z + m[3].y,
                    m[0].z * p.x + m[1].z * p.y + m[2].z * p.z + m[3].z
                )
                let local = inverse.act(world - cube.center)
                let dx = abs(local.x) - half.x, dy = abs(local.y) - half.y, dz = abs(local.z) - half.z
                if dx <= 0, dy <= 0, dz <= 0 {
                    depth = max(depth, min(-dx, min(-dy, -dz)))
                }
            }
        }
        return max(depth, Grasp.padPenetration(cube: cube, leftFinger: transforms["finger_left_link"]!, rightFinger: transforms["finger_right_link"]!))
    }

    /// Returns the first contact along the requested motion, even when its endpoint is clear.
    public func limited(from: Pose, to: Pose, cube: CubeState? = nil) -> Pose {
        let candidate = limitedByFloor(from: from, to: to, cube: cube)
        let stopped = stopAtUnattachedCube(from: from, candidate: candidate, cube: cube)
        return clampGripAroundCube(from: from, candidate: stopped, cube: cube)
    }
    private func cubeAt(_ cube: CubeState, pose: Pose) -> CubeState {
        guard cube.attached else { return cube }
        return Grasp.aligned(cube, endLink: robot.endLink(pose.joints, grip: pose.grip))
    }

    private func padOverlap(_ pose: Pose, cube: CubeState?) -> Double {
        guard let cube, cube.present else { return 0 }
        let world = cubeAt(cube, pose: pose)
        let t = robot.transforms(pose.joints, grip: pose.grip)
        return Grasp.padPenetration(cube: world, leftFinger: t["finger_left_link"]!, rightFinger: t["finger_right_link"]!)
    }

    private func clampGripAroundCube(from: Pose, candidate: Pose, cube: CubeState?) -> Pose {
        guard let cube, cube.present else { return candidate }
        if padOverlap(candidate, cube: cube) <= 0.0005 { return candidate }
        if candidate.grip >= from.grip { return candidate }
        if padOverlap(from, cube: cube) > 0.0005 {
            var pose = candidate
            pose.grip = from.grip
            return pose
        }
        var closed = candidate.grip, open = from.grip
        for _ in 0..<32 {
            let mid = (closed + open) / 2
            var pose = candidate
            pose.grip = mid
            if padOverlap(pose, cube: cube) <= 0.0005 { open = mid } else { closed = mid }
        }
        var pose = candidate
        pose.grip = open
        return pose
    }
    private func stopAtUnattachedCube(from: Pose, candidate: Pose, cube: CubeState?) -> Pose {
        guard let cube, cube.present, !cube.attached else { return candidate }
        let penTo = cubePenetration(candidate, cube: cube)
        if penTo <= 0.0005 { return candidate }
        let penFrom = cubePenetration(from, cube: cube)
        if penFrom > 0.0005 {
            // Sticky contact: do not go deeper, but always allow retract.
            return penTo <= penFrom + 1e-9 ? candidate : from
        }
        var low = 0.0, high = 1.0
        for _ in 0..<32 {
            let middle = (low + high) / 2
            if cubePenetration(blend(from, candidate, middle), cube: cube) <= 0.0005 { low = middle } else { high = middle }
        }
        return blend(from, candidate, low)
    }
    private func limitedByFloor(from: Pose, to: Pose, cube: CubeState?) -> Pose {
        let changed = (0..<6).filter { from.joints[$0] != to.joints[$0] }
        if changed.isEmpty {
            // Finger travel is linear, so endpoint heights bound the complete swept motion.
            let end = minimumHeight(to, cube: cube)
            if end >= Self.height + Self.margin { return to }
            let start = minimumHeight(from, cube: cube)
            var low = 0.0, high = 1.0
            guard start >= Self.height else { return from }
            for _ in 0..<32 {
                let middle = (low + high) / 2
                if minimumHeight(blend(from, to, middle), cube: cube) >= Self.height + Self.margin { low = middle } else { high = middle }
            }
            return blend(from, to, low)
        }
        if changed.count == 1, from.grip == to.grip, cube?.attached != true {
            return limitJoint(from: from, to: to, index: changed[0])
        }
        // For coordinated moves, bound the curvature of every vertex's height. This
        // certifies intervals instead of merely testing samples that could tunnel through.
        let angle = zip(from.joints, to.joints).reduce(0) { $0 + abs($1.1 - $1.0) * degreesToRadians }
        let held = cube?.attached == true ? simd_length(cube!.size) / 2 : 0
        let curvature = (radiusBound + held) * angle * angle + 2 * angle * abs(to.grip - from.grip) / 2000
        var evaluations = 0
        func walk(_ a: Double, _ b: Double, _ ha: Double, _ hb: Double, _ depth: Int) -> Double {
            if min(ha, hb) >= Self.margin, min(ha, hb) >= curvature * (b - a) * (b - a) / 8 { return b }
            // Fail closed if unusually complex motion exhausts the bounded search.
            if depth == 24 || evaluations >= 4096 { return a }
            let m = (a + b) / 2
            let hm = minimumHeight(blend(from, to, m), cube: cube) - Self.height
            evaluations += 1
            let first = walk(a, m, ha, hm, depth + 1)
            if first < m { return first }
            return walk(m, b, hm, hb, depth + 1)
        }
        // A pose already in plane contact (held cube on the floor, fingertip stop)
        // must still be allowed to leave. Treat a legal start as just above the margin
        // so the certifier does not fail-close at t=0.
        var startClearance = minimumHeight(from, cube: cube) - Self.height
        let endClearance = minimumHeight(to, cube: cube) - Self.height
        if startClearance < -1e-8 {
            return endClearance + 1e-9 >= startClearance ? to : from
        }
        if startClearance >= -1e-8 { startClearance = max(startClearance, Self.margin) }
        let fraction = walk(0, 1, startClearance, endClearance, 0)
        return fraction == 1 ? to : blend(from, to, fraction)
    }
    private func limitJoint(from: Pose, to: Pose, index: Int) -> Pose {
        let transforms = robot.transforms(from.joints, grip: from.grip)
        let joint = robot.definition.armJoints[index]
        let origin = transforms[joint.parent]! * originTransform(xyz: joint.xyz, rpy: joint.rpy)
        let pivot = SIMD3(origin[3].x, origin[3].y, origin[3].z)
        let transformedAxis = origin * SIMD4(vector(joint.axis), 0)
        let axis = simd_normalize(SIMD3(transformedAxis.x, transformedAxis.y, transformedAxis.z))
        let delta = (to.joints[index] - from.joints[index]) * degreesToRadians
        let direction = delta < 0 ? -1.0 : 1.0
        var travel = abs(delta)
        for hull in supports where descendants[index].contains(hull.name) {
            let transform = transforms[hull.name]!
            for point in hull.points {
                let p = transform * SIMD4(point, 1)
                let offset = SIMD3(p.x, p.y, p.z) - pivot
                let parallel = simd_dot(axis, offset)
                let a = offset.z - axis.z * parallel
                let b = simd_cross(axis, offset).z * direction
                let c = pivot.z + axis.z * parallel - Self.height - Self.margin
                let radius = hypot(a, b)
                if radius < 1e-14 || c >= radius { continue }
                // Already in the plane: only block motion that goes deeper.
                if a + c < -Self.margin {
                    if minimumHeight(to, cube: nil) + 1e-9 >= minimumHeight(from, cube: nil) { continue }
                    return from
                }
                let ratio = clamp(-c / radius, -1, 1)
                let phase = atan2(b, a), root = acos(ratio)
                // Only descending roots enter the floor. Ascending roots permit reversal.
                for candidate in [phase - root, phase + root] {
                    var s = candidate.truncatingRemainder(dividingBy: 2 * .pi)
                    if s < -1e-10 { s += 2 * .pi }
                    s = max(0, s)
                    if s <= travel, -a * sin(s) + b * cos(s) < -1e-12 { travel = s }
                }
            }
        }
        if travel >= abs(delta) { return to }
        return blend(from, to, max(0, travel - 1e-10) / abs(delta))
    }
    private func blend(_ from: Pose, _ to: Pose, _ t: Double) -> Pose {
        var pose = to
        pose.joints = zip(from.joints, to.joints).map { $0 + ($1 - $0) * t }
        pose.grip = from.grip + (to.grip - from.grip) * t
        return pose
    }
}
