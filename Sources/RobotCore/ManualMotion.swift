import Foundation

/// Two cascaded low-pass filters give manual input a critically damped response.
/// The exact time-domain solution preserves velocity when retargeting and keeps
/// both stages within the bounds of the supplied poses, even after a reversal.
public struct ManualMotion: Sendable {
    public private(set) var current: Pose
    public private(set) var target: Pose
    private var leading: Pose
    // About 100 ms to cover 90% of a step; continuous dragging trails by ~50 ms.
    private static let rate = 40.0
    private static let tolerance = 0.001
    public var isMoving: Bool {
        current.joints != target.joints || current.grip != target.grip ||
        leading.joints != target.joints || leading.grip != target.grip
    }
    public init(current: Pose) { self.current = current; target = current; leading = current }
    public mutating func reset(to pose: Pose) {
        self = ManualMotion(current: pose)
    }
    public mutating func retarget(to pose: Pose) {
        guard pose.joints.count == current.joints.count, pose.joints.allSatisfy(\.isFinite), pose.grip.isFinite else { return }
        target = pose
    }
    public mutating func advance(seconds: Double) {
        guard isMoving, seconds.isFinite, seconds > 0 else { return }
        // One second already decays below numerical significance; this also
        // keeps extreme finite timestamps out of the polynomial calculation.
        let time = Self.rate * min(seconds, 1), decay = exp(-time)
        func step(_ first: Double, _ second: Double, _ goal: Double) -> (Double, Double) {
            let a = first - goal, b = second - goal
            return (goal + a * decay, goal + (b + time * a) * decay)
        }
        for i in current.joints.indices {
            (leading.joints[i], current.joints[i]) = step(leading.joints[i], current.joints[i], target.joints[i])
        }
        (leading.grip, current.grip) = step(leading.grip, current.grip, target.grip)
        if zip(leading.joints, target.joints).allSatisfy({ abs($0 - $1) < Self.tolerance }),
           zip(current.joints, target.joints).allSatisfy({ abs($0 - $1) < Self.tolerance }),
           abs(leading.grip - target.grip) < Self.tolerance,
           abs(current.grip - target.grip) < Self.tolerance {
            current = target; leading = target
        }
    }
}
