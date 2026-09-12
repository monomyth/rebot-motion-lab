import Foundation
import Testing
import simd
@testable import RobotCore

struct SceneObjectTests {
    @Test func defaultCubeRestsOnThePlane() {
        let cube = CubeState.spawn
        #expect(cube.present)
        #expect(!cube.attached)
        #expect(abs(cube.size.x - 0.04) < 1e-12)
        #expect(abs(cube.center.x - 0.28) < 1e-12)
        #expect(abs(cube.center.y) < 1e-12)
        #expect(abs(cube.minimumHeight - FloorConstraint.height) < 1e-9)
        #expect(abs(cube.center.z - (FloorConstraint.height + 0.02)) < 1e-9)
        #expect(abs(cube.topNormal.z - 1) < 1e-9)
    }

    @Test func placementSitsOnThePlane() throws {
        let raised = try CubeState.spawn.placing(center: SIMD3(0.32, 0.04, 0.4))
        #expect(abs(raised.center.x - 0.32) < 1e-12)
        #expect(abs(raised.center.y - 0.04) < 1e-12)
        #expect(abs(raised.minimumHeight - FloorConstraint.height) < 1e-9)
        let lowered = try CubeState.spawn.placing(center: SIMD3(0.28, 0, FloorConstraint.height - 0.02))
        #expect(abs(lowered.minimumHeight - FloorConstraint.height) < 1e-9)
    }

    @Test func placementIgnoresRequestedHeight() throws {
        let cube = try CubeState.spawn.placing(center: SIMD3(0.25, -0.08, 1.5), size: SIMD3(repeating: 0.025))
        #expect(abs(cube.center.x - 0.25) < 1e-12)
        #expect(abs(cube.center.y + 0.08) < 1e-12)
        #expect(abs(cube.size.x - 0.025) < 1e-12)
        #expect(abs(cube.minimumHeight - FloorConstraint.height) < 1e-9)
        #expect(abs(cube.center.z - (FloorConstraint.height + 0.0125)) < 1e-9)
    }

    @Test func sizeMustFitTheOpenGripper() {
        let cube = CubeState.spawn
        #expect(throws: CubeError.self) { _ = try cube.placing(size: SIMD3(repeating: 0.009)) }
        #expect(throws: CubeError.self) { _ = try cube.placing(size: SIMD3(repeating: 0.091)) }
        #expect(throws: CubeError.self) { _ = try cube.placing(size: SIMD3(repeating: .nan)) }
    }

    @Test func resizeKeepsTheCubeOnThePlane() throws {
        let small = try CubeState.spawn.placing(size: SIMD3(repeating: 0.01))
        #expect(abs(small.size.x - 0.01) < 1e-12)
        #expect(abs(small.size.y - 0.01) < 1e-12)
        #expect(abs(small.size.z - 0.01) < 1e-12)
        #expect(abs(small.minimumHeight - FloorConstraint.height) < 1e-9)
        let large = try CubeState.spawn.placing(center: SIMD3(0.2, -0.05, 0), size: SIMD3(repeating: 0.09))
        #expect(abs(large.size.x - 0.09) < 1e-12)
        #expect(abs(large.size.y - 0.09) < 1e-12)
        #expect(abs(large.size.z - 0.09) < 1e-12)
        #expect(abs(large.center.x - 0.2) < 1e-12)
        #expect(abs(large.center.y + 0.05) < 1e-12)
        #expect(abs(large.minimumHeight - FloorConstraint.height) < 1e-9)
    }

    @Test func visualPoseScalesEveryAxis() throws {
        let cube = try CubeState.spawn.placing(size: SIMD3(repeating: 0.08))
        #expect(abs(cube.visualScale.x - 2) < 1e-12)
        #expect(abs(cube.visualScale.y - 2) < 1e-12)
        #expect(abs(cube.visualScale.z - 2) < 1e-12)
        let visual = cube.visualPoseMatrix(cube.worldMatrix)
        let pose = cube.worldMatrix
        func length(_ column: SIMD4<Double>) -> Double { simd_length(SIMD3(column.x, column.y, column.z)) }
        #expect(abs(length(pose.columns.0) - 1) < 1e-12)
        #expect(abs(length(visual.columns.0) - 2) < 1e-12)
        #expect(abs(length(visual.columns.1) - 2) < 1e-12)
        #expect(abs(length(visual.columns.2) - 2) < 1e-12)
        #expect(abs(visual.columns.3.x - pose.columns.3.x) < 1e-12)
        #expect(abs(visual.columns.3.y - pose.columns.3.y) < 1e-12)
        #expect(abs(visual.columns.3.z - pose.columns.3.z) < 1e-12)
    }

    @Test func restoreSpawnClearsAttachment() throws {
        var cube = try CubeState.spawn.placing(center: SIMD3(0.3, 0.05, 0.04), yaw: 0.4)
        cube.attached = true
        cube.restoreSpawn()
        #expect(!cube.attached)
        #expect(abs(cube.center.x - 0.3) < 1e-12)
        #expect(abs(cube.center.y - 0.05) < 1e-12)
        #expect(cube.minimumHeight >= FloorConstraint.height - 1e-9)
    }

    @Test func unattachedCubeFallsOntoThePlane() {
        var cube = CubeState.spawn
        cube.center.z = 0.15
        #expect(cube.isFalling)
        var t = 0.0
        while t < 1.5, cube.isFalling {
            _ = cube.integrateGravity(dt: 1.0 / 120)
            t += 1.0 / 120
        }
        #expect(!cube.isFalling)
        #expect(abs(cube.verticalVelocity) < 1e-12)
        #expect(abs(cube.minimumHeight - FloorConstraint.height) < 1e-6)
        #expect(abs(cube.center.x - 0.28) < 1e-12)
    }

    @Test func attachedCubeDoesNotFall() {
        var cube = CubeState.spawn
        cube.center.z = 0.15
        cube.attached = true
        let z = cube.center.z
        let moved = cube.integrateGravity(dt: 0.1)
        #expect(!moved)
        #expect(abs(cube.center.z - z) < 1e-12)
    }
}
