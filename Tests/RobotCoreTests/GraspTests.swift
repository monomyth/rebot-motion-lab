import Foundation
import Testing
import simd
@testable import RobotCore

struct GraspTests {
    private func setup() throws -> (Kinematics, FloorConstraint) {
        let robot = Kinematics(try RobotDefinition.load())
        return (robot, try FloorConstraint(robot))
    }

    private func levelPick(_ robot: Kinematics, z: Double, initial: [Double] = homePose) -> Kinematics.Solution {
        robot.solve(target: SIMD3(0.28, 0, z), initial: initial, keepLevel: true, cubeTopInTool: nil)
    }

    @Test func keepLevelPointsToolZUpAndClearsTheFloorAtPickHeight() throws {
        let (robot, floor) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success, "IK error \(solved.error) ori \(solved.orientationError)")
        #expect(robot.toolZ(solved.joints).z > 0.98)
        let pose = Pose(name: "pick", joints: solved.joints, grip: 60)
        #expect(floor.isAllowed(pose, cube: .spawn))
        #expect(floor.minimumHeight(pose) > 0)
        let end = robot.endLink(solved.joints, grip: 60)
        #expect(Grasp.inJaws(cube: .spawn, endLink: end))
    }

    @Test func pinchAtCubeWidthAttachesAndLiftMovesCube() throws {
        let (robot, floor) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let open = Pose(name: "open", joints: solved.joints, grip: 60)
        #expect(floor.isAllowed(open, cube: cube))
        Grasp.update(previousGrip: 60, pose: open, cube: &cube, endLink: robot.endLink(solved.joints, grip: 60))
        #expect(!cube.attached)
        let pinch = Grasp.attachOpeningMM(cube)
        let close = Pose(name: "close", joints: solved.joints, grip: pinch)
        Grasp.update(previousGrip: 60, pose: close, cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        #expect(cube.attached)
        #expect(abs(close.grip - 42) < 1e-9)
        let before = cube.center
        let lift = robot.solve(
            target: SIMD3(0.28, 0, 0.16), initial: solved.joints,
            keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube)
        )
        #expect(lift.success)
        Grasp.update(
            previousGrip: pinch,
            pose: Pose(name: "lift", joints: lift.joints, grip: pinch),
            cube: &cube,
            endLink: robot.endLink(lift.joints, grip: pinch)
        )
        #expect(cube.attached)
        #expect(cube.center.z - before.z > 0.08)
    }

    @Test func closingThroughTheCubeStopsAtWidthAndStillAttaches() throws {
        let (robot, floor) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let from = Pose(name: "open", joints: solved.joints, grip: 60)
        var requested = from
        requested.grip = 20
        let stopped = floor.limited(from: from, to: requested, cube: cube)
        #expect(abs(stopped.grip - Grasp.minimumOpeningMM(cube)) < 1e-9)
        #expect(stopped.grip > 35)
        #expect(floor.cubePenetration(stopped, cube: cube) <= 0.0005)
        Grasp.update(previousGrip: from.grip, pose: stopped, cube: &cube, endLink: robot.endLink(stopped.joints, grip: stopped.grip))
        #expect(cube.attached)
        #expect(!floor.isAllowed(requested, cube: CubeState.spawn))
    }

    @Test func openReleasesWithoutSnappingToThePlane() throws {
        let (robot, _) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube)
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: solved.joints, grip: pinch), cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        #expect(cube.attached)
        let lift = robot.solve(
            target: SIMD3(0.28, 0, 0.16), initial: solved.joints,
            keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube)
        )
        #expect(lift.success)
        Grasp.update(previousGrip: pinch, pose: Pose(name: "lift", joints: lift.joints, grip: pinch), cube: &cube, endLink: robot.endLink(lift.joints, grip: pinch))
        #expect(cube.attached)
        let heldZ = cube.center.z
        #expect(heldZ > 0.08)
        Grasp.update(previousGrip: pinch, pose: Pose(name: "o", joints: lift.joints, grip: 60), cube: &cube, endLink: robot.endLink(lift.joints, grip: 60))
        #expect(!cube.attached)
        #expect(abs(cube.center.z - heldZ) < 1e-9)
        #expect(cube.minimumHeight > FloorConstraint.height + 0.05)
    }

    @Test func cubeOutsideJawsDoesNotAttach() throws {
        let (robot, _) = try setup()
        var cube = CubeState.spawn
        cube.center = SIMD3(0.5, 0.2, 0.02)
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: homePose, grip: 20), cube: &cube, endLink: robot.endLink(homePose, grip: 20))
        #expect(!cube.attached)
        #expect(!Grasp.inJaws(cube: cube, endLink: robot.endLink(homePose, grip: 60)))
    }

    @Test func liftingHeldCubeOffTheFloorIsAllowed() throws {
        let (robot, floor) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube)
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: solved.joints, grip: pinch), cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        #expect(cube.attached)
        let from = Pose(name: "pick", joints: solved.joints, grip: pinch)
        let lift = robot.solve(
            target: SIMD3(0.28, 0, 0.16), initial: solved.joints,
            keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube)
        )
        #expect(lift.success)
        var to = from; to.joints = lift.joints
        #expect(floor.isAllowed(to, cube: cube))
        let allowed = floor.limited(from: from, to: to, cube: cube)
        #expect(abs(robot.position(allowed.joints).z - 0.16) < 0.01)
        Grasp.update(previousGrip: pinch, pose: allowed, cube: &cube, endLink: robot.endLink(allowed.joints, grip: pinch))
        #expect(cube.attached)
        #expect(cube.center.z > 0.08)
    }

    @Test func heldCubeStopsAtTheFloor() throws {
        let (robot, floor) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube)
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: solved.joints, grip: pinch), cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        #expect(cube.attached)
        let from = Pose(name: "held", joints: solved.joints, grip: pinch)
        let down = robot.solve(target: SIMD3(0.28, 0, -0.05), initial: solved.joints, keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube))
        var to = from; to.joints = down.joints
        let stopped = floor.limited(from: from, to: to, cube: cube)
        #expect(floor.minimumHeight(stopped, cube: cube) >= FloorConstraint.height - 1e-8)
        #expect(stopped.joints != to.joints || floor.isAllowed(to, cube: cube))
    }
}
