import Foundation
import Testing
import simd
@testable import RobotCore

struct GraspTests {
    private func setup() throws -> Kinematics { Kinematics(try RobotDefinition.load()) }

    @Test func closeInAABBAttachesAndLiftMovesCube() throws {
        let robot = try setup()
        var q = homePose
        let target = SIMD3(0.28, 0, 0.12)
        let solved = robot.solve(target: target, initial: q)
        #expect(solved.success, "IK error \(solved.error)")
        q = solved.joints
        let end = robot.endLink(q, grip: 60)
        var cube = CubeState.spawn
        cube.center = translation(end)
        cube.restOnFloor()
        cube.center = translation(end)
        #expect(Grasp.aabbContains(cubeCenter: cube.center, cubeSize: cube.size, endLink: end))
        let open = Pose(name: "open", joints: q, grip: 60)
        Grasp.update(previousGrip: 60, pose: open, cube: &cube, endLink: robot.endLink(q, grip: 60))
        #expect(!cube.attached)
        let close = Pose(name: "close", joints: q, grip: 20)
        Grasp.update(previousGrip: 60, pose: close, cube: &cube, endLink: robot.endLink(q, grip: 20))
        #expect(cube.attached)
        let before = cube.center
        var lifted = q
        let lift = robot.solve(target: target + SIMD3(0, 0, 0.1), initial: q)
        #expect(lift.success)
        lifted = lift.joints
        Grasp.update(previousGrip: 20, pose: Pose(name: "lift", joints: lifted, grip: 20), cube: &cube, endLink: robot.endLink(lifted, grip: 20))
        #expect(cube.attached)
        #expect(abs(cube.center.z - before.z - 0.1) < 0.015)
    }

    @Test func openReleasesOntoThePlane() throws {
        let robot = try setup()
        let solved = robot.solve(target: SIMD3(0.28, 0, 0.12), initial: homePose)
        #expect(solved.success)
        let q = solved.joints
        var cube = CubeState.spawn
        cube.center = translation(robot.endLink(q, grip: 20))
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: q, grip: 20), cube: &cube, endLink: robot.endLink(q, grip: 20))
        #expect(cube.attached)
        Grasp.update(previousGrip: 20, pose: Pose(name: "o", joints: q, grip: 50), cube: &cube, endLink: robot.endLink(q, grip: 50))
        #expect(!cube.attached)
        #expect(cube.minimumHeight >= FloorConstraint.height - 1e-9)
    }

    @Test func cubeOutsideAABBDoesNotAttach() throws {
        let robot = try setup()
        var cube = CubeState.spawn
        cube.center = SIMD3(0.5, 0.2, 0.02)
        let q = homePose
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: q, grip: 20), cube: &cube, endLink: robot.endLink(q, grip: 20))
        #expect(!cube.attached)
    }

    @Test func heldCubeStopsAtTheFloor() throws {
        let robot = try setup()
        let floor = try FloorConstraint(robot)
        let solved = robot.solve(target: SIMD3(0.28, 0, 0.08), initial: homePose)
        #expect(solved.success)
        var cube = CubeState.spawn
        cube.center = translation(robot.endLink(solved.joints, grip: 20))
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: solved.joints, grip: 20), cube: &cube, endLink: robot.endLink(solved.joints, grip: 20))
        #expect(cube.attached)
        let from = Pose(name: "held", joints: solved.joints, grip: 20)
        let down = robot.solve(target: SIMD3(0.28, 0, -0.05), initial: solved.joints)
        var to = from; to.joints = down.joints
        let stopped = floor.limited(from: from, to: to, cube: cube)
        #expect(floor.minimumHeight(stopped, cube: cube) >= FloorConstraint.height - 1e-8)
        #expect(stopped.joints != to.joints || floor.isAllowed(to, cube: cube))
    }
}
