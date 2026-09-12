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

    private func padPick(_ robot: Kinematics) throws -> Kinematics.Solution {
        let above = levelPick(robot, z: 0.048)
        #expect(above.success)
        let target = Grasp.padGraspTCP(CubeState.spawn, toolX: robot.toolX(above.joints), toolZ: robot.toolZ(above.joints))
        let grasp = robot.solve(target: target, initial: above.joints, keepLevel: true, cubeTopInTool: nil)
        #expect(grasp.success, "pad grasp IK \(grasp.error) ori \(grasp.orientationError)")
        return grasp
    }

    @Test func keepLevelPickReachesTheCube() throws {
        let (robot, floor) = try setup()
        let high = levelPick(robot, z: 0.080)
        #expect(high.success, "IK error \(high.error) ori \(high.orientationError)")
        #expect(robot.toolZ(high.joints).z > 0.92)
        #expect(!Grasp.inJaws(cube: .spawn, endLink: robot.endLink(high.joints, grip: 60), gripMM: 60))
        let solved = levelPick(robot, z: 0.048)
        #expect(solved.success, "IK error \(solved.error) ori \(solved.orientationError)")
        #expect(robot.toolZ(solved.joints).z > 0.92)
        let pose = Pose(name: "pick", joints: solved.joints, grip: 60)
        #expect(floor.minimumHeight(pose) > 0)
        // 40 mm cube top already overlaps the jaw cavity at TCP z=48, cube XY. That is a
        // solid pinch volume (center is still below the box).
        #expect(Grasp.inJaws(cube: .spawn, endLink: robot.endLink(solved.joints, grip: 60), gripMM: 60))
        let pad = try padPick(robot)
        #expect(Grasp.inJaws(cube: .spawn, endLink: robot.endLink(pad.joints, grip: 60), gripMM: 60))
    }

    @Test func pinchDoesNotPutPadsInsideTheCube() throws {
        let (robot, floor) = try setup()
        let solved = try padPick(robot)
        var cube = CubeState.spawn
        let from = Pose(name: "open", joints: solved.joints, grip: 90)
        var requested = from; requested.grip = 20
        let stopped = floor.limited(from: from, to: requested, cube: cube)
        let links = robot.transforms(stopped.joints, grip: stopped.grip)
        Grasp.update(
            previousGrip: 90, pose: stopped, cube: &cube, endLink: robot.endLink(stopped.joints, grip: stopped.grip),
            leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!
        )
        // Yawed keep_level can graze one pad at ~65 mm. That is glue, not a pinch of the solid.
        #expect(!Grasp.pinching(cube: CubeState.spawn, leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!))
        #expect(!cube.attached)
        let pen = Grasp.padPenetration(cube: CubeState.spawn, leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!)
        #expect(pen < 0.0015)
        #expect(stopped.grip > 20 && stopped.grip < 90)
        var crush = stopped
        crush.grip = 20
        #expect(!floor.isAllowed(crush, cube: CubeState.spawn))
    }

    @Test func angledJawsStopOnTheSolidCube() throws {
        let (robot, floor) = try setup()
        let solved = robot.solve(target: SIMD3(0.303, 0.026, 0.048), initial: homePose, keepLevel: true, cubeTopInTool: nil)
        #expect(solved.success)
        let cube = CubeState.spawn
        let from = Pose(name: "open", joints: solved.joints, grip: 90)
        var requested = from; requested.grip = 20
        let stopped = floor.limited(from: from, to: requested, cube: cube)
        let links = robot.transforms(stopped.joints, grip: stopped.grip)
        let pen = Grasp.padPenetration(cube: cube, leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!)
        #expect(pen < 0.0015)
        #expect(stopped.grip > 20)
        var crush = stopped
        crush.grip = 20
        #expect(!floor.isAllowed(crush, cube: cube))
    }

    @Test func pinchAtCubeWidthAttachesAndLiftMovesCube() throws {
        let (robot, _) = try setup()
        let solved = try padPick(robot)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube, endLink: robot.endLink(solved.joints, grip: 60))
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
        let solved = try padPick(robot)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube, endLink: robot.endLink(solved.joints, grip: 60))
        Grasp.update(previousGrip: 60, pose: Pose(name: "c", joints: solved.joints, grip: pinch), cube: &cube, endLink: robot.endLink(solved.joints, grip: pinch))
        let lift = robot.solve(target: SIMD3(0.28, 0, 0.16), initial: solved.joints, keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube))
        #expect(lift.success)
        Grasp.update(previousGrip: pinch, pose: Pose(name: "lift", joints: lift.joints, grip: pinch), cube: &cube, endLink: robot.endLink(lift.joints, grip: pinch))
        let heldZ = cube.center.z
        Grasp.update(previousGrip: pinch, pose: Pose(name: "o", joints: lift.joints, grip: 90), cube: &cube, endLink: robot.endLink(lift.joints, grip: 90))
        #expect(!cube.attached)
        #expect(abs(cube.center.z - heldZ) < 1e-9)
        #expect(cube.minimumHeight > FloorConstraint.height + 0.05)
    }

    @Test func cubeBesideOrInFrontOfTipsIsNotInJaws() throws {
        let robot = Kinematics(try RobotDefinition.load())
        let solved = robot.solve(target: SIMD3(0.28, 0, 0.048), initial: homePose, keepLevel: true, cubeTopInTool: nil)
        #expect(solved.success)
        let end = robot.endLink(solved.joints, grip: 22)
        let tcp = robot.position(solved.joints)
        var beside = CubeState.spawn
        beside.center = tcp + SIMD3(0, 0.04, 0)
        #expect(!Grasp.inJaws(cube: beside, endLink: end, gripMM: 22))
        var inFront = CubeState.spawn
        inFront.center = tcp + SIMD3(0.04, 0, 0)
        #expect(!Grasp.inJaws(cube: inFront, endLink: end, gripMM: 22))
    }

    @Test func solidAtTheTipsCountsAsInJaws() throws {
        let robot = Kinematics(try RobotDefinition.load())
        let solved = robot.solve(target: SIMD3(0.28, 0, 0.020), initial: homePose, keepLevel: true, cubeTopInTool: nil)
        #expect(solved.success, "IK error \(solved.error) ori \(solved.orientationError)")
        #expect(robot.toolZ(solved.joints).z > 0.92)
        let cube = try CubeState.spawn.placing(center: SIMD3(0.28, 0, 0), size: SIMD3(repeating: 0.02))
        let end = robot.endLink(solved.joints, grip: 22)
        #expect(Grasp.inJaws(cube: cube, endLink: end, gripMM: 22))
        let tcp = robot.position(solved.joints)
        let centerInBoxX = (end.inverse * SIMD4(cube.center.x, cube.center.y, cube.center.z, 1)).x
        #expect(centerInBoxX > Grasp.jawXMax, "center is still in front of the cavity; only the solid overlaps")
        #expect(abs(tcp.z - 0.020) < 0.003)
    }

    @Test func keepLevelTwentyMillimeterSolidPinchAttachesAndLifts() throws {
        let (robot, floor) = try setup()
        let cubeRest = try CubeState.spawn.placing(center: SIMD3(0.28, 0, 0), size: SIMD3(repeating: 0.02))
        // Level fingers at this reach put link5 through the plane below ~42 mm. Fingertips
        // down keeps the wrist up; TCP is still the tip. A top-edge of the solid is enough.
        let grasp = robot.solve(
            target: SIMD3(0.28, 0, 0.008), initial: homePose,
            keepLevel: false, cubeTopInTool: nil, fingersDown: true
        )
        #expect(grasp.success, "tips-down IK \(grasp.error) ori \(grasp.orientationError)")
        #expect(robot.toolX(grasp.joints).z < -0.92, "tool +X should point down, got \(robot.toolX(grasp.joints))")
        #expect(abs(robot.toolY(grasp.joints).x) < 0.15, "jaws should open along ±Y, toolY=\(robot.toolY(grasp.joints))")
        let ikPose = Pose(name: "grasp", joints: grasp.joints, grip: 90)
        let low = floor.lowestSupport(ikPose)
        #expect(low.height >= FloorConstraint.height, "tips-down min=\(low.height) @ \(low.name)")
        let pose = floor.limited(from: Pose(name: "ready", joints: homePose, grip: 90), to: ikPose, cube: cubeRest)
        let tcp = robot.position(pose.joints)
        #expect(tcp.z < 0.025, "floor/cube stopped tips-down at z=\(tcp.z) min=\(floor.lowestSupport(pose).height) @ \(floor.lowestSupport(pose).name)")
        let end = robot.endLink(pose.joints, grip: 22)
        let local = end.inverse * SIMD4(cubeRest.center.x, cubeRest.center.y, cubeRest.center.z, 1)
        #expect(
            Grasp.inJaws(cube: cubeRest, endLink: end, gripMM: 22),
            "cube in tool \(SIMD3(local.x, local.y, local.z)) tcp \(tcp) toolX \(robot.toolX(pose.joints))"
        )
        var cube = cubeRest
        var close = pose
        close.grip = 20
        let stopped = floor.limited(from: pose, to: close, cube: cube)
        let links = robot.transforms(stopped.joints, grip: stopped.grip)
        Grasp.update(
            previousGrip: 90, pose: stopped, cube: &cube, endLink: links["end_link"]!,
            leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!
        )
        #expect(
            cube.attached,
            "grip \(stopped.grip) tcp \(robot.position(stopped.joints)) pinch \(Grasp.pinching(cube: cubeRest, leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!)) pen \(Grasp.padPenetration(cube: cubeRest, leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!))"
        )
        let before = cube.center
        let lift = robot.solve(
            target: SIMD3(0.28, 0, 0.16), initial: stopped.joints,
            keepLevel: true, cubeTopInTool: Grasp.cubeTopInTool(cube)
        )
        #expect(lift.success)
        var up = stopped
        up.joints = lift.joints
        let lifted = floor.limited(from: stopped, to: up, cube: cube)
        Grasp.update(
            previousGrip: stopped.grip, pose: lifted, cube: &cube,
            endLink: robot.endLink(lifted.joints, grip: lifted.grip)
        )
        #expect(cube.attached)
        #expect(cube.center.z - before.z > 0.08)
        #expect(Grasp.isLevel(toolZ: robot.toolZ(lifted.joints), cubeTop: cube.topNormal))
    }

    @Test func onePadGlueDoesNotAttach() throws {
        let (robot, floor) = try setup()
        let cubeRest = try CubeState.spawn.placing(center: SIMD3(0.28, 0.030, 0), size: SIMD3(repeating: 0.02))
        let solved = robot.solve(target: SIMD3(0.28, 0, 0.020), initial: homePose, keepLevel: true, cubeTopInTool: nil)
        #expect(solved.success)
        var from = Pose(name: "open", joints: solved.joints, grip: 90)
        from = floor.limited(from: Pose(name: "ready", joints: homePose, grip: 90), to: from, cube: cubeRest)
        var close = from
        close.grip = 20
        let stopped = floor.limited(from: from, to: close, cube: cubeRest)
        var cube = cubeRest
        let links = robot.transforms(stopped.joints, grip: stopped.grip)
        Grasp.update(
            previousGrip: 90, pose: stopped, cube: &cube, endLink: links["end_link"]!,
            leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!
        )
        #expect(!cube.attached)
        #expect(!Grasp.pinching(cube: cubeRest, leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!))
    }

    @Test func openGripperDoesNotAttachEvenWhenSolidIsInTheCavity() throws {
        let robot = Kinematics(try RobotDefinition.load())
        let solved = robot.solve(target: SIMD3(0.28, 0, 0.020), initial: homePose, keepLevel: true, cubeTopInTool: nil)
        #expect(solved.success)
        var cube = try CubeState.spawn.placing(center: SIMD3(0.28, 0, 0), size: SIMD3(repeating: 0.02))
        let links = robot.transforms(solved.joints, grip: 90)
        Grasp.update(
            previousGrip: 90,
            pose: Pose(name: "open", joints: solved.joints, grip: 90),
            cube: &cube,
            endLink: links["end_link"]!,
            leftFinger: links["finger_left_link"]!,
            rightFinger: links["finger_right_link"]!
        )
        #expect(!cube.attached)
        let pitched = robot.solve(target: SIMD3(0.28, 0, 0.020), initial: homePose)
        #expect(pitched.success)
        var glued = try CubeState.spawn.placing(center: SIMD3(0.28, 0, 0), size: SIMD3(repeating: 0.02))
        let pLinks = robot.transforms(pitched.joints, grip: 90)
        Grasp.update(
            previousGrip: 90.0,
            pose: Pose(name: "pitch", joints: pitched.joints, grip: 90),
            cube: &glued,
            endLink: pLinks["end_link"]!,
            leftFinger: pLinks["finger_left_link"]!,
            rightFinger: pLinks["finger_right_link"]!
        )
        #expect(!glued.attached)
        Grasp.update(
            previousGrip: 90.0,
            pose: Pose(name: "pitch-close", joints: pitched.joints, grip: 89.999),
            cube: &glued,
            endLink: pLinks["end_link"]!,
            leftFinger: pLinks["finger_left_link"]!,
            rightFinger: pLinks["finger_right_link"]!
        )
        #expect(!glued.attached)
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
        let solved = try padPick(robot)
        var cube = CubeState.spawn
        let pinch = Grasp.attachOpeningMM(cube, endLink: robot.endLink(solved.joints, grip: 60))
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
