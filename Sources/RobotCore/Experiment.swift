import Foundation
import simd

public enum ExperimentError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public struct ExperimentTask: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case version, friction, seed
        case cubeSizeMM="cube_size_mm", cubeXYMM="cube_xy_mm", cubeYawDeg="cube_yaw_deg", massGrams="mass_grams"
        case liftClearanceMM="lift_clearance_mm", tiltToleranceDeg="tilt_tolerance_deg", holdSeconds="hold_seconds", timeoutSeconds="timeout_seconds"
        case stableLinearMMPerSecond="stable_linear_mm_s", stableAngularDegPerSecond="stable_angular_deg_s"
        case initialJoints="initial_joints_deg", initialGripperMM="initial_gripper_mm", inputMode="input_mode", placementJitterMM="placement_jitter_mm"
    }
    public var version = 1
    public var cubeSizeMM = 50.0
    public var cubeXYMM = [350.0, 0.0]
    public var cubeYawDeg = 0.0
    public var massGrams = 50.0
    public var friction = 0.9
    public var liftClearanceMM = 100.0
    public var tiltToleranceDeg = 5.0
    public var holdSeconds = 5.0
    public var timeoutSeconds = 120.0
    public var stableLinearMMPerSecond = 15.0
    public var stableAngularDegPerSecond = 10.0
    public var initialJoints = homePose
    public var initialGripperMM = 90.0
    public var inputMode = "vision"
    public var seed: UInt64 = 1
    public var placementJitterMM = 0.0
    public init() {}
    public func validated(robot: Kinematics, floor: FloorConstraint) throws -> Self {
        try CubePlacement.validate(xyMM:cubeXYMM, sideMM:cubeSizeMM, yawDeg:cubeYawDeg, jitterMM:placementJitterMM)
        let values = [cubeSizeMM, cubeYawDeg, massGrams, friction, liftClearanceMM, tiltToleranceDeg, holdSeconds, timeoutSeconds, stableLinearMMPerSecond, stableAngularDegPerSecond, initialGripperMM, placementJitterMM] + cubeXYMM + initialJoints
        guard version == 1, values.allSatisfy(\.isFinite), cubeXYMM.count == 2, initialJoints.count == 6,
              initialJoints == robot.clampPose(initialJoints), (0...maximumGripperOpeningMM).contains(initialGripperMM),
              seed <= 9007199254740991,
              (10...250).contains(massGrams), (0.1...2).contains(friction),
              (20...250).contains(liftClearanceMM), (1...30).contains(tiltToleranceDeg), (1...60).contains(holdSeconds),
              timeoutSeconds >= holdSeconds + 5, timeoutSeconds <= 600,
              (1...100).contains(stableLinearMMPerSecond), (1...90).contains(stableAngularDegPerSecond), (0...20).contains(placementJitterMM),
              ["vision", "state"].contains(inputMode), floor.isAllowed(Pose(name: "initial", joints: initialJoints, grip: initialGripperMM))
        else { throw ExperimentError.invalid("Invalid task parameters; the initial robot pose must clear the floor. See task schema.") }
        // Placement is independent of arm reach. Individual motion requests still validate IK.
        return self
    }
    public func episode(seed: UInt64? = nil) -> Self {
        var sampled=self; sampled.seed=seed ?? self.seed
        var rng=SeededGenerator(seed:sampled.seed)
        sampled.cubeXYMM=cubeXYMM.map { $0 + (Double(rng.next() >> 11)/9007199254740992.0*2-1)*placementJitterMM }
        sampled.placementJitterMM=0
        return sampled
    }
    public var initialCubePose: CartesianPose {
        let q = simd_quatd(angle: cubeYawDeg * degreesToRadians, axis: [0,0,1]).vector
        return CartesianPose(positionMM: [cubeXYMM[0],cubeXYMM[1],FloorConstraint.height * 1000 + cubeSizeMM/2], quaternionXYZW: [q.x,q.y,q.z,q.w])
    }
    public func graspPose(clearanceMM: Double) -> CartesianPose {
        let q = (simd_quatd(angle: cubeYawDeg * degreesToRadians, axis: [0,0,1]) * simd_quatd(angle: .pi/2, axis: [0,1,0])).vector
        return CartesianPose(positionMM: [cubeXYMM[0],cubeXYMM[1],FloorConstraint.height * 1000 + cubeSizeMM/2 + clearanceMM], quaternionXYZW: [q.x,q.y,q.z,q.w])
    }
}

public struct HoldSample: Sendable {
    public var clearanceMM: Double
    public var tiltDeg: Double
    public var linearSpeedMM: Double
    public var angularSpeedDeg: Double
    public var leftContact: Bool
    public var rightContact: Bool
    public var otherSupport: Bool
    public var valid: Bool
    public init(clearanceMM: Double, tiltDeg: Double, linearSpeedMM: Double, angularSpeedDeg: Double, leftContact: Bool, rightContact: Bool, otherSupport: Bool, valid: Bool = true) {
        self.clearanceMM=clearanceMM; self.tiltDeg=tiltDeg; self.linearSpeedMM=linearSpeedMM; self.angularSpeedDeg=angularSpeedDeg
        self.leftContact=leftContact; self.rightContact=rightContact; self.otherSupport=otherSupport; self.valid=valid
    }
}
public struct HoldEvaluator: Sendable {
    public private(set) var holdSeconds = 0.0
    public private(set) var success = false
    public private(set) var everLifted = false
    public private(set) var dropped = false
    public init() {}
    public mutating func update(_ sample: HoldSample, dt: Double, running: Bool, task: ExperimentTask) {
        guard running else { return }
        guard dt.isFinite, dt > 0, dt <= 0.25 else { holdSeconds=0; return }
        guard sample.valid, [sample.clearanceMM,sample.tiltDeg,sample.linearSpeedMM,sample.angularSpeedDeg].allSatisfy(\.isFinite) else { holdSeconds=0; return }
        if sample.clearanceMM > 10 && sample.leftContact && sample.rightContact { everLifted=true }
        if everLifted && sample.clearanceMM < 2 && !(sample.leftContact && sample.rightContact) { dropped=true }
        let stable = sample.clearanceMM >= task.liftClearanceMM && sample.tiltDeg <= task.tiltToleranceDeg &&
            sample.linearSpeedMM <= task.stableLinearMMPerSecond && sample.angularSpeedDeg <= task.stableAngularDegPerSecond &&
            sample.leftContact && sample.rightContact && !sample.otherSupport
        holdSeconds = stable ? holdSeconds + dt : 0
        if holdSeconds >= task.holdSeconds { success=true }
    }
}

/// Only one external controller can write. Tokens are episode-scoped and expire on silence.
public struct ControllerLease: Sendable {
    public private(set) var token: String?
    public private(set) var episodeID = ""
    public private(set) var provenance = "manual"
    public private(set) var modelID = ""
    public private(set) var lastActionID: Int = -1
    public private(set) var heartbeat = 0.0
    public init() {}
    public mutating func acquire(episode: String, provenance: String, modelID: String, now: Double) throws -> String {
        guard token == nil, ["conventional","teacher_assisted","malecns"].contains(provenance), !modelID.isEmpty, modelID.count <= 200 else { throw ExperimentError.invalid("Controller already connected or invalid provenance/model identifier.") }
        let t = UUID().uuidString; token=t; episodeID=episode; self.provenance=provenance; self.modelID=modelID; heartbeat=now; lastActionID = -1; return t
    }
    public mutating func validate(token: String, episode: String, actionID: Int, observedFrame: Int, currentFrame: Int, now: Double) throws {
        guard self.token == token, episodeID == episode, actionID > lastActionID, observedFrame >= 0, observedFrame <= currentFrame, currentFrame-observedFrame <= 120, now-heartbeat <= 2 else { throw ExperimentError.invalid("Stale, duplicate, expired, or unauthorized controller action. Observe state and reacquire after a reset.") }
        lastActionID=actionID; heartbeat=now
    }
    public func expired(now: Double) -> Bool { token != nil && now-heartbeat > 2 }
    public mutating func release() { self = ControllerLease() }
}

public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state=seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z=state; z=(z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9; z=(z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
