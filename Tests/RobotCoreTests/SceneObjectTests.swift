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

    @Test func rejectPlacementThroughTheFloor() {
        let cube = CubeState.spawn
        #expect(throws: CubeError.self) {
            _ = try cube.placing(center: SIMD3(0.28, 0, FloorConstraint.height - 0.02))
        }
        #expect(cube.center == CubeState.spawn.center)
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
