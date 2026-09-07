import Foundation

public struct Pose: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var joints: [Double]
    public var grip: Double
    public init(name: String, joints: [Double], grip: Double, id: UUID = UUID()) {
        self.id = id; self.name = name; self.joints = joints; self.grip = grip
    }
    public static var startup: Pose { Pose(name: "Folded", joints: foldedPose, grip: 0) }
    public static var example: [Pose] { [
        Pose(name: "Ready", joints: homePose, grip: 60),
        Pose(name: "Reach left", joints: [-35,-125,-115,30,0,0], grip: 60),
        Pose(name: "Close gripper", joints: [-35,-125,-115,30,0,0], grip: 0),
        Pose(name: "Lift & turn", joints: [35,-90,-105,15,0,0], grip: 0),
        Pose(name: "Release", joints: [35,-90,-105,15,0,0], grip: 60)
    ] }
}
public enum Motion {
    public static func smooth(_ value: Double) -> Double {
        let t = clamp(value, 0, 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
    public static func duration(from: Pose, to: Pose) -> Double {
        let angle = zip(from.joints, to.joints).map { abs($0 - $1) }.max() ?? 0
        return max(0.6, 1.875 * angle / 60, 1.875 * abs(to.grip - from.grip) / 60)
    }
    public static func interpolate(from: Pose, to: Pose, fraction: Double) -> Pose {
        let s = smooth(fraction)
        return Pose(name: to.name, joints: zip(from.joints, to.joints).map { $0 + ($1 - $0) * s }, grip: from.grip + (to.grip - from.grip) * s, id: to.id)
    }
}
public struct TrajectoryFile: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public var name: String
        public var joints: [Double]
        public var gripper_opening: Double
    }
    public var format = "rebot-motion-lab-v1"
    public var robot = "B601-DM"
    public var simulation = "kinematic"
    public var angle_unit = "degrees"
    public var gripper_unit = "mm"
    public var speed_percent: Double
    public var interpolation = "quintic smoothstep"
    public var joint_order = (1...6).map { "joint\($0)" }
    public var poses: [Entry]
    public init(poses: [Pose], speed: Double) {
        self.poses = poses.map { Entry(name: $0.name, joints: $0.joints, gripper_opening: $0.grip) }
        speed_percent = speed
    }
    public func validated(using robotModel: Kinematics) throws -> [Pose] {
        guard format == "rebot-motion-lab-v1", robot == "B601-DM", simulation == "kinematic",
              angle_unit == "degrees", gripper_unit == "mm", interpolation == "quintic smoothstep",
              joint_order == (1...6).map({ "joint\($0)" }), speed_percent.isFinite,
              (10...100).contains(speed_percent), !poses.isEmpty, poses.count <= 1000 else { throw TrajectoryError.invalid }
        return try poses.map { entry in
            guard entry.joints.count == 6, entry.joints.allSatisfy(\.isFinite),
                  entry.joints == robotModel.clampPose(entry.joints), entry.gripper_opening.isFinite,
                  (0...90).contains(entry.gripper_opening), !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TrajectoryError.invalid }
            return Pose(name: entry.name, joints: entry.joints, grip: entry.gripper_opening)
        }
    }
}
public enum TrajectoryError: LocalizedError {
    case invalid
    public var errorDescription: String? { "Use a B601-DM trajectory with six bounded joint angles in degrees, 0–90 mm gripper opening, and speed from 10–100%." }
}
