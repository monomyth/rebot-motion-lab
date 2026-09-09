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

    @Test func keepLevelPickReachesTheCube() throws {
        let (robot, floor) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success, "IK error \(solved.error) ori \(solved.orientationError)")
        #expect(robot.toolZ(solved.joints).z > 0.92)
        let pose = Pose(name: "pick", joints: solved.joints, grip: 60)
        #expect(floor.minimumHeight(pose) > 0)
        #expect(Grasp.inJaws(cube: .spawn, endLink: robot.endLink(solved.joints, grip: 60)))
    }

    @Test func pinchDoesNotPutPadsInsideTheCube() throws {
        let (robot, floor) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube)
        let close = Pose(name: "close", joints: solved.joints, grip: pinch)
        Grasp.update(previousGrip: 60, pose: close, cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        #expect(cube.attached)
        let links = robot.transforms(solved.joints, grip: pinch)
        #expect(Grasp.padPenetration(cube: cube, leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!) < 0.002)
        var crush = close
        crush.grip = 20
        #expect(!floor.isAllowed(crush, cube: CubeState.spawn) || Grasp.padPenetration(cube: CubeState.spawn, leftFinger: robot.transforms(solved.joints, grip: 20)["finger_left_link"]!, rightFinger: robot.transforms(solved.joints, grip: 20)["finger_right_link"]!) > 0.001)
    }

    @Test func pinchAtCubeWidthAttachesAndLiftMovesCube() throws {
        let (robot, _) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube)
        Grasp.update(previousGrip: 60, pose: Pose(name: "close", joints: solved.joints, grip: pinch), cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        #expect(cube.attached)
        let before = cube.center
        let lift = robot.solve(target: SIMD3(0.28, 0, 0.16), initial: solved.joints, keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube))
        #expect(lift.success)
        Grasp.update(previousGrip: pinch, pose: Pose(name: "lift", joints: lift.joints, grip: pinch), cube: &cube, endLink: robot.endLink(lift.joints, grip: pinch))
        #expect(cube.attached)
        #expect(cube.center.z - before.z > 0.08)
    }

    @Test func openAfterLiftReleasesWithoutSnapping() throws {
        let (robot, _) = try setup()
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube)
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: solved.joints, grip: pinch), cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        let lift = robot.solve(target: SIMD3(0.28, 0, 0.16), initial: solved.joints, keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube))
        #expect(lift.success)
        Grasp.update(previousGrip: pinch, pose: Pose(name: "lift", joints: lift.joints, grip: pinch), cube: &cube, endLink: robot.endLink(lift.joints, grip: pinch))
        let heldZ = cube.center.z
        Grasp.update(previousGrip: pinch, pose: Pose(name: "o", joints: lift.joints, grip: 60), cube: &cube, endLink: robot.endLink(lift.joints, grip: 60))
        #expect(!cube.attached)
        #expect(abs(cube.center.z - heldZ) < 1e-9)
        #expect(cube.minimumHeight > FloorConstraint.height + 0.05)
    }

    @Test func cubeOutsideJawsDoesNotAttach() throws {
        let (robot, _) = try setup()
        var cube = CubeState.spawn
        cube.center = SIMD3(0.5, 0.2, 0.02)
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: homePose, grip: 42), cube: &cube, endLink: robot.endLink(homePose, grip: 42))
        #expect(!cube.attached)
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
        let lift = robot.solve(target: SIMD3(0.28, 0, 0.16), initial: solved.joints, keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube))
        #expect(lift.success)
        var to = from; to.joints = lift.joints
        let allowed = floor.limited(from: from, to: to, cube: cube)
        #expect(abs(robot.position(allowed.joints).z - 0.16) < 0.01)
    }
}
