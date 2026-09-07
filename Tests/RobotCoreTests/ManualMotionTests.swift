import Foundation
import Testing
@testable import RobotCore

struct ManualMotionTests {
    private let start = Pose.startup
    private func pose(_ angle: Double, grip: Double = 0) -> Pose {
        Pose(name: "Manual", joints: [angle, 0, 0, 0, 0, 0], grip: grip)
    }
    @Test func inputDoesNotJumpAndSettlesQuickly() {
        var motion = ManualMotion(current: start)
        let target = pose(120, grip: 90)
        motion.retarget(to: target)
        #expect(motion.current == start)
        motion.advance(seconds: 1.0 / 60)
        #expect(motion.current.joints[0] > 0 && motion.current.joints[0] < 30)
        #expect(motion.current.grip > 0 && motion.current.grip < 90)
        for _ in 0..<5 { motion.advance(seconds: 1.0 / 60) }
        #expect(motion.current.joints[0] > 108) // More than 90% there at 100 ms.
        for _ in 0..<24 { motion.advance(seconds: 1.0 / 60) }
        #expect(motion.current == target)
        #expect(!motion.isMoving)
    }
    @Test func retargetPreservesPositionAndVelocity() {
        var motion = ManualMotion(current: start)
        motion.retarget(to: pose(100)); motion.advance(seconds: 0.035)
        let before = motion.current.joints[0]
        var continuation = motion
        motion.retarget(to: pose(-100))
        #expect(motion.current.joints[0] == before)
        let dt = 0.000001
        continuation.advance(seconds: dt); motion.advance(seconds: dt)
        let oldVelocity = (continuation.current.joints[0] - before) / dt
        let newVelocity = (motion.current.joints[0] - before) / dt
        #expect(abs(newVelocity - oldVelocity) < 0.2)
        motion.advance(seconds: 0.5)
        #expect(motion.current.joints[0] == -100)
    }
    @Test func irregularFramesHaveEquivalentResponse() {
        var fast = ManualMotion(current: start), irregular = fast
        for target in [pose(130, grip: 90), pose(-80, grip: 20), pose(20, grip: 50)] {
            fast.retarget(to: target); irregular.retarget(to: target)
            for _ in 0..<12 { fast.advance(seconds: 1.0 / 120) }
            for dt in [0.008, 0.023, 0.017, 0.052] { irregular.advance(seconds: dt) }
            #expect(abs(fast.current.joints[0] - irregular.current.joints[0]) < 1e-9)
            #expect(abs(fast.current.grip - irregular.current.grip) < 1e-9)
        }
    }
    @Test func repeatedReversalsStayWithinMechanicalLimits() throws {
        let robot = Kinematics(try RobotDefinition.load())
        var motion = ManualMotion(current: start)
        for n in 0..<200 {
            let angles = robot.definition.armJoints.map { (n.isMultiple(of: 2) ? $0.upper : $0.lower) / degreesToRadians }
            let target = Pose(name: "Limits", joints: angles, grip: n.isMultiple(of: 2) ? 90 : 0)
            motion.retarget(to: target)
            for dt in [0.003, 0.011, 0.027] {
                motion.advance(seconds: dt)
                #expect(motion.current.joints == robot.clampPose(motion.current.joints))
                #expect((0...90).contains(motion.current.grip))
            }
        }
    }
    @Test func resetDiscardsPendingTargetAndMomentum() {
        var motion = ManualMotion(current: start)
        motion.retarget(to: pose(90, grip: 80)); motion.advance(seconds: 0.02)
        let stopped = motion.current
        motion.reset(to: stopped); motion.advance(seconds: 1)
        #expect(motion.current == stopped && !motion.isMoving)
        motion.retarget(to: pose(-90)); motion.reset(to: start)
        motion.advance(seconds: 1)
        #expect(motion.current == start && !motion.isMoving)
    }
    @Test func invalidInputAndTimeAreIgnored() {
        var motion = ManualMotion(current: start)
        motion.retarget(to: pose(.nan))
        motion.retarget(to: pose(1, grip: .infinity))
        motion.retarget(to: Pose(name: "Bad", joints: [], grip: 0))
        #expect(!motion.isMoving)
        motion.retarget(to: pose(30))
        for dt in [Double.nan, .infinity, 0, -1] { motion.advance(seconds: dt) }
        #expect(motion.current == start)
        motion.advance(seconds: .greatestFiniteMagnitude)
        #expect(motion.current.joints[0] == 30 && !motion.isMoving)
    }
}
