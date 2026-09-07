import Foundation

/// A frame-rate-independent clock. Excess time is carried across segment boundaries.
public struct MotionPlayer: Sendable {
    public enum State: Sendable { case stopped, playing, paused }
    public private(set) var state: State = .stopped
    public private(set) var current: Pose
    public private(set) var index: Int?
    public private(set) var progress = 0.0
    private var sequence: [Pose] = []
    private var from: Pose
    private var elapsed = 0.0
    private var segmentDuration = 0.6
    public init(current: Pose) { self.current = current; from = current }
    public mutating func start(_ poses: [Pose], from pose: Pose) {
        current = pose; from = pose; sequence = poses; elapsed = 0; progress = 0
        guard let first = poses.first else { stop(); return }
        index = 0; segmentDuration = Motion.duration(from: pose, to: first); state = .playing
    }
    public mutating func pause() { if state == .playing { state = .paused } }
    public mutating func resume() { if state == .paused { state = .playing } }
    public mutating func stop() { state = .stopped; index = nil; sequence = []; elapsed = 0 }
    public mutating func advance(seconds: Double, speed: Double) {
        guard state == .playing, seconds.isFinite, seconds > 0, speed.isFinite else { return }
        var remaining = seconds * clamp(speed, 10, 100) / 100
        while remaining > 0, let i = index {
            let step = min(remaining, max(0, segmentDuration - elapsed))
            elapsed += step; remaining -= step
            let fraction = min(1, elapsed / segmentDuration)
            current = Motion.interpolate(from: from, to: sequence[i], fraction: fraction)
            progress = (Double(i) + fraction) / Double(sequence.count)
            if fraction >= 1 {
                if i + 1 == sequence.count { stop(); progress = 1 }
                else {
                    from = current; elapsed = 0; index = i + 1
                    segmentDuration = Motion.duration(from: from, to: sequence[i + 1])
                }
            }
        }
    }
}
