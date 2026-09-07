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
    public func minimumHeight(_ pose: Pose) -> Double {
        let transforms = robot.transforms(pose.joints, grip: pose.grip)
        var height = Double.infinity
        for hull in supports {
            let m = transforms[hull.name]!
            for p in hull.points { height = min(height, m[0].z * p.x + m[1].z * p.y + m[2].z * p.z + m[3].z) }
        }
        return height
    }
    public func isAllowed(_ pose: Pose) -> Bool { minimumHeight(pose) >= Self.height }

    /// Returns the first contact along the requested motion, even when its endpoint is clear.
    public func limited(from: Pose, to: Pose) -> Pose {
        let changed = (0..<6).filter { from.joints[$0] != to.joints[$0] }
        if changed.isEmpty {
            // Finger travel is linear, so endpoint heights bound the complete swept motion.
            let end = minimumHeight(to)
            if end >= Self.height + Self.margin { return to }
            let start = minimumHeight(from)
            var low = 0.0, high = 1.0
            guard start >= Self.height else { return from }
            for _ in 0..<32 {
                let middle = (low + high) / 2
                if minimumHeight(blend(from, to, middle)) >= Self.height + Self.margin { low = middle } else { high = middle }
            }
            return blend(from, to, low)
        }
        if changed.count == 1, from.grip == to.grip {
            return limitJoint(from: from, to: to, index: changed[0])
        }
        // For coordinated moves, bound the curvature of every vertex's height. This
        // certifies intervals instead of merely testing samples that could tunnel through.
        let angle = zip(from.joints, to.joints).reduce(0) { $0 + abs($1.1 - $1.0) * degreesToRadians }
        let curvature = radiusBound * angle * angle + 2 * angle * abs(to.grip - from.grip) / 2000
        var evaluations = 0
        func walk(_ a: Double, _ b: Double, _ ha: Double, _ hb: Double, _ depth: Int) -> Double {
            if min(ha, hb) >= Self.margin, min(ha, hb) >= curvature * (b - a) * (b - a) / 8 { return b }
            // Fail closed if unusually complex motion exhausts the bounded search.
            if depth == 24 || evaluations >= 4096 { return a }
            let m = (a + b) / 2
            let hm = minimumHeight(blend(from, to, m)) - Self.height
            evaluations += 1
            let first = walk(a, m, ha, hm, depth + 1)
            if first < m { return first }
            return walk(m, b, hm, hb, depth + 1)
        }
        let fraction = walk(0, 1, minimumHeight(from) - Self.height, minimumHeight(to) - Self.height, 0)
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
                // An initially invalid pose must never advance further into the floor.
                if a + c < -Self.margin { return from }
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
