import Foundation
import Testing
import RobotCore
import simd

struct CubePlacementTests {
    @Test func sideBoundsMatchFullyOpenGripper() throws {
        let robot=Kinematics(try RobotDefinition.load()), floor=try FloorConstraint(robot)
        #expect(CubePlacement.minimumSideMM == 10)
        #expect(CubePlacement.maximumSideMM == maximumGripperOpeningMM)
        for side in [10.0, 10.01, 50, 89.99, 90] {
            var task=ExperimentTask(); task.cubeSizeMM=side
            _ = try task.validated(robot:robot,floor:floor)
            #expect(abs(task.initialCubePose.positionMM[2] - (-1+side/2)) < 1e-9)
        }
        for side in [0.0, 9.99, 90.01, 100, Double.nan, Double.infinity] {
            var task=ExperimentTask(); task.cubeSizeMM=side
            #expect(throws:ExperimentError.self) { try task.validated(robot:robot,floor:floor) }
        }
    }
    @Test func floorPlacementDoesNotRequireReachableIK() throws {
        let robot=Kinematics(try RobotDefinition.load()), floor=try FloorConstraint(robot)
        for xy in [[1500.0,-1000],[-1800,1800],[150,0],[0,0]] {
            var task=ExperimentTask(); task.cubeXYMM=xy
            _ = try task.validated(robot:robot,floor:floor)
        }
        // Occupancy is checked against the live robot separately; reach is never a placement gate.
        var far=ExperimentTask(); far.cubeXYMM=[1500,1500]
        let solution=try robot.solvePose(target:far.graspPose(clearanceMM:0),initial:homePose,frame:"grasp")
        #expect(!solution.success)
    }
    @Test func rotatedFootprintAndJitterMustFitFloor() throws {
        try CubePlacement.validate(xyMM:[1955,1955],sideMM:90,yawDeg:0)
        #expect(throws:ExperimentError.self) { try CubePlacement.validate(xyMM:[1955,0],sideMM:90,yawDeg:45) }
        try CubePlacement.validate(xyMM:[1930,1930],sideMM:90,yawDeg:45)
        #expect(throws:ExperimentError.self) { try CubePlacement.validate(xyMM:[1930,0],sideMM:90,yawDeg:45,jitterMM:10) }
        #expect(throws:ExperimentError.self) { try CubePlacement.validate(xyMM:[Double.nan,0],sideMM:50,yawDeg:0) }
        #expect(throws:ExperimentError.self) { try CubePlacement.validate(xyMM:[0],sideMM:50,yawDeg:0) }
    }
    @Test func floorRayIntersectionHandlesPerspectiveAndHorizon() {
        let point=CubePlacement.floorPoint(origin:[0,0,1],direction:[0.3,-0.2,-1])!
        #expect(simd_distance(point,[0.3003,-0.2002,-0.001]) < 1e-10)
        #expect(CubePlacement.floorPoint(origin:[0,0,1],direction:[1,0,0]) == nil)
        #expect(CubePlacement.floorPoint(origin:[0,0,1],direction:[0,0,1]) == nil)
        #expect(CubePlacement.floorPoint(origin:[0,0,Double.nan],direction:[0,0,-1]) == nil)
    }
}
