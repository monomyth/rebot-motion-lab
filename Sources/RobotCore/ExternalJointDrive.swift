import Foundation

/// Bounded first-order position tracking for external controllers only.
/// Small neural corrections should not become full-speed mechanical impulses.
public enum ExternalJointDrive {
    public static func advance(current: [Double], target: [Double], seconds: Double) -> [Double] {
        let delta=zip(current,target).map { $1-$0 }
        let maximum=delta.map(abs).max() ?? 0
        guard maximum > 0, seconds > 0 else { return current }
        let fraction=min(1-exp(-1.5*seconds),30*seconds/maximum)
        return zip(current,delta).map { $0+$1*fraction }
    }
}
