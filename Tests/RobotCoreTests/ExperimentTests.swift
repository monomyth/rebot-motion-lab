import Foundation
import Testing
import RobotCore
import simd

struct ExperimentTests {
    @Test func fullPoseIKAndQuaternionSign() throws {
        let robot=Kinematics(try RobotDefinition.load())
        let goal=[20.0,-110,-100,15,20,30]
        let pose=CartesianPose(robot.toolTransform(goal,frame:"grasp"))
        let solved=try robot.solvePose(target:pose,initial:homePose,frame:"grasp")
        #expect(solved.success)
        var negative=pose; negative.quaternionXYZW=negative.quaternionXYZW.map { -$0 }
        let equivalent=try robot.solvePose(target:negative,initial:solved.joints,frame:"grasp")
        #expect(equivalent.success)
        #expect(equivalent.orientationErrorDeg < 0.1)
    }
    @Test func taskRejectsInvalidAndProvidesReachablePickup() throws {
        let robot=Kinematics(try RobotDefinition.load()), floor=try FloorConstraint(robot)
        let task=try ExperimentTask().validated(robot:robot,floor:floor)
        let pick=try robot.solvePose(target:task.graspPose(clearanceMM:0),initial:homePose,frame:"grasp")
        print("PICK",pick.joints,pick.positionErrorMM,pick.orientationErrorDeg)
        #expect(pick.success)
        #expect(abs(task.initialCubePose.positionMM[2] - 24) < 1e-9)
        var invalid=task; invalid.cubeSizeMM=100
        #expect(throws:ExperimentError.self) { try invalid.validated(robot:robot,floor:floor) }
        invalid=task; invalid.cubeXYMM=[0,0]
        #expect(throws:ExperimentError.self) { try invalid.validated(robot:robot,floor:floor) }
        invalid=task; invalid.initialJoints=[0,0]
        #expect(throws:ExperimentError.self) { try invalid.validated(robot:robot,floor:floor) }
    }
    @Test func malformedOrientationRejected() throws {
        #expect(throws:ExperimentError.self) { try CartesianPose(positionMM:[0,0,0],quaternionXYZW:[0,0,0,0]).validated() }
        #expect(throws:ExperimentError.self) { try CartesianPose(positionMM:[0,Double.nan,0],quaternionXYZW:[0,0,0,1]).validated() }
        #expect(throws:ExperimentError.self) { try CartesianPose(positionMM:[0,0,0],quaternionXYZW:[1]).validated() }
    }
    @Test func successNeedsStableBilateralSupportAndContinuousTime() {
        var score=HoldEvaluator(); var task=ExperimentTask(); task.holdSeconds=1
        var sample=HoldSample(clearanceMM:110,tiltDeg:0,linearSpeedMM:0,angularSpeedDeg:0,leftContact:true,rightContact:true,otherSupport:false)
        for _ in 0..<5 { score.update(sample,dt:0.1,running:true,task:task) }
        #expect(!score.success); #expect(score.holdSeconds > 0.4)
        sample.rightContact=false; score.update(sample,dt:0.1,running:true,task:task)
        #expect(score.holdSeconds == 0)
        sample.rightContact=true; sample.otherSupport=true
        for _ in 0..<20 { score.update(sample,dt:0.1,running:true,task:task) }
        #expect(!score.success)
        sample.otherSupport=false; sample.linearSpeedMM=100
        for _ in 0..<20 { score.update(sample,dt:0.1,running:true,task:task) }
        #expect(!score.success)
        sample.linearSpeedMM=0
        for _ in 0..<20 { score.update(sample,dt:0.1,running:false,task:task) }
        #expect(score.holdSeconds == 0)
        for _ in 0..<11 { score.update(sample,dt:0.1,running:true,task:task) }
        #expect(score.success)
    }
    @Test func transientLiftBadOrientationAndInvalidTimeDoNotPass() {
        var score=HoldEvaluator(); let task=ExperimentTask()
        var sample=HoldSample(clearanceMM:120,tiltDeg:20,linearSpeedMM:0,angularSpeedDeg:0,leftContact:true,rightContact:true,otherSupport:false)
        for _ in 0..<100 { score.update(sample,dt:0.1,running:true,task:task) }
        #expect(!score.success)
        sample.tiltDeg=0; score.update(sample,dt:10,running:true,task:task)
        #expect(!score.success)
        sample.leftContact=false; sample.rightContact=false; sample.clearanceMM=0
        score.update(sample,dt:0.1,running:true,task:task)
        #expect(score.dropped)
    }
    @Test func controllerOwnershipFreshnessAndReset() throws {
        var lease=ControllerLease()
        let token=try lease.acquire(episode:"one",provenance:"conventional",modelID:"test",now:10)
        #expect(throws:ExperimentError.self) { try lease.acquire(episode:"one",provenance:"malecns",modelID:"other",now:10) }
        try lease.validate(token:token,episode:"one",actionID:0,observedFrame:5,currentFrame:6,now:10.1)
        #expect(throws:ExperimentError.self) { try lease.validate(token:token,episode:"one",actionID:0,observedFrame:5,currentFrame:6,now:10.2) }
        #expect(throws:ExperimentError.self) { try lease.validate(token:token,episode:"two",actionID:1,observedFrame:5,currentFrame:6,now:10.2) }
        #expect(throws:ExperimentError.self) { try lease.validate(token:token,episode:"one",actionID:1,observedFrame:100,currentFrame:6,now:10.2) }
        #expect(lease.expired(now:13))
        lease.release(); #expect(lease.token == nil); #expect(lease.lastActionID == -1)
        #expect(throws:ExperimentError.self) { try lease.validate(token:token,episode:"one",actionID:1,observedFrame:5,currentFrame:6,now:10.2) }
    }
    @Test func taskRoundTripAndSeededSetup() throws {
        let task=ExperimentTask()
        #expect(try JSONDecoder().decode(ExperimentTask.self,from:JSONEncoder().encode(task)) == task)
        var a=SeededGenerator(seed:42), b=SeededGenerator(seed:42)
        #expect((0..<10).map { _ in a.next() } == (0..<10).map { _ in b.next() })
        var jitter=task; jitter.placementJitterMM=10
        #expect(jitter.episode(seed:42)==jitter.episode(seed:42))
        #expect(jitter.episode(seed:42).cubeXYMM != jitter.episode(seed:43).cubeXYMM)
        #expect(zip(jitter.episode(seed:42).cubeXYMM,task.cubeXYMM).allSatisfy { abs($0-$1)<=10 })
    }
}
