import Foundation
import Testing
import simd
@testable import RobotCore

struct RobotCoreTests {
    func robot() throws -> Kinematics { Kinematics(try RobotDefinition.load()) }
    @Test func testKnownReadyPosition() throws {
        let p = try robot().position(homePose) * 1000
        expectEqual(p.x, 542.91, accuracy: 0.1)
        expectEqual(p.y, 0, accuracy: 0.1)
        expectEqual(p.z, 409.29, accuracy: 0.1)
    }
    @Test func testRotationAroundActualBasePivot() throws {
        let k = try robot(), p = k.position(homePose)
        var pose = homePose; pose[0] = 90
        let rotated = k.position(pose)
        let pivotX = k.definition.armJoints[0].xyz[0]
        expectEqual(rotated.x, pivotX - p.y, accuracy: 1e-9)
        expectEqual(rotated.y, p.x - pivotX, accuracy: 1e-9)
        expectEqual(rotated.z, p.z, accuracy: 1e-9)
    }
    @Test func testSymmetricGripperAndFixedTCP() throws {
        let k = try robot()
        let closed = k.transforms(homePose, grip: 0), opened = k.transforms(homePose, grip: 90)
        let inverse = opened["end_link"]!.inverse
        let left = (inverse * opened["finger_left_link"]!).columns.3
        let right = (inverse * opened["finger_right_link"]!).columns.3
        expectEqual(left.y, 0.045, accuracy: 1e-9)
        expectEqual(right.y, -0.045, accuracy: 1e-9)
        expectEqual(closed["end_link"], opened["end_link"])
    }
    @Test func testIKForReachableTargetsWithoutMutatingInitialPose() throws {
        let k = try robot(), initial = homePose
        for sample in 0..<12 {
            let q = k.clampPose(homePose.enumerated().map { i, v in v + sin(Double(sample + i)) * 8 })
            let target = k.position(q)
            let result = k.solve(target: target, initial: initial)
            expectTrue(result.success, "Sample \(sample): \(result.error)")
            expectLess(simd_distance(k.position(result.joints), target), 0.002)
            expectEqual(result.joints, k.clampPose(result.joints))
        }
        expectEqual(initial, homePose)
    }
    @Test func testIKRejectsUnreachableAndNonFiniteTargets() throws {
        let k = try robot()
        expectFalse(k.solve(target: [5, 5, 5], initial: homePose).success)
        expectFalse(k.solve(target: [.nan, 0, 0], initial: homePose).success)
        expectFalse(k.solve(target: [0, .infinity, 0], initial: homePose).success)
    }
    @Test func testLevelIKReachesCubeWorkspace() throws {
        let k = try robot()
        let result = k.solve(target: SIMD3(0.28, 0, 0.20), initial: homePose, keepLevel: true, cubeTopInTool: nil)
        expectLess(result.error, 0.005)
        expectLess(result.orientationError, 15 * degreesToRadians)
        expectGreater(k.toolZ(result.joints).z, 0.95)
        let initial = homePose
        let missed = k.solve(target: SIMD3(5, 5, 5), initial: initial, keepLevel: true, cubeTopInTool: nil)
        expectFalse(missed.success)
        expectEqual(initial, homePose)
    }
    @Test func testBoundsAndInvalidInputs() throws {
        let k = try robot()
        let q = k.clampPose([999, -999, .nan, .infinity])
        expectEqual(q[0], 2.8 / degreesToRadians)
        expectEqual(q[1], -3.14 / degreesToRadians)
        expectEqual(Array(q[2...]), Array(homePose[2...]))
        for preset in robotPresets { expectGreater(k.position(preset.joints).z, 0) }
    }
    @Test func testQuinticEndpointsAndMaximumSpeed() {
        let from = Pose(name: "a", joints: homePose, grip: 0)
        let to = Pose(name: "b", joints: [80, -150, -45, 60, 20, -60], grip: 90)
        expectEqual(Motion.interpolate(from: from, to: to, fraction: -1).joints, from.joints)
        expectEqual(Motion.interpolate(from: from, to: to, fraction: 2).joints, to.joints)
        let duration = Motion.duration(from: from, to: to), steps = 1000
        var previous = from
        for i in 1...steps {
            let pose = Motion.interpolate(from: from, to: to, fraction: Double(i) / Double(steps))
            for j in 0..<6 { expectAtMost(abs(pose.joints[j] - previous.joints[j]) / (duration / Double(steps)), 60.001) }
            expectAtMost(abs(pose.grip - previous.grip) / (duration / Double(steps)), 60.001)
            previous = pose
        }
    }
    @Test func testTrajectoryRoundTripAndValidation() throws {
        let k = try robot(), file = TrajectoryFile(poses: Pose.example, speed: 50)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(TrajectoryFile.self, from: data)
        let poses = try decoded.validated(using: k)
        expectEqual(poses.map(\.joints), Pose.example.map(\.joints))
        expectEqual(poses.map(\.grip), Pose.example.map(\.grip))
        var invalid = file; invalid.angle_unit = "radians"
        expectThrows(try invalid.validated(using: k))
        invalid = file; invalid.poses[0].joints[0] = 999
        expectThrows(try invalid.validated(using: k))
        invalid = file; invalid.poses[0].joints = [0, 0]
        expectThrows(try invalid.validated(using: k))
        invalid = file; invalid.poses[0].gripper_opening = -1
        expectThrows(try invalid.validated(using: k))
    }
    @Test func testAllBundledMeshes() throws {
        let definition = try RobotDefinition.load()
        var count = 0, triangles = 0
        for visual in definition.links.flatMap(\.visuals) {
            let mesh = try STLMesh(data: Data(contentsOf: Assets.url("model/" + visual.mesh)))
            expectEqual(mesh.positions.count, mesh.normals.count)
            triangles += mesh.triangleCount; count += 1
        }
        expectEqual(count, 34)
        expectEqual(triangles, 430_912)
    }
    @Test func testMalformedSTLRejected() {
        expectThrows(try STLMesh(data: Data()))
        var invalid = Data(repeating: 0, count: 84); invalid[80] = 1
        expectThrows(try STLMesh(data: invalid))
    }
    @Test func testReferenceCompletenessAndSources() throws {
        let ref = try ActuatorReference.load()
        expectEqual(ref.actuators.count, 7)
        expectEqual(ref.registers.count, 53)
        expectEqual(Set(ref.registers.map(\.rid)).count, 53)
        expectEqual(ref.registers.filter { $0.access == "RW" }.count, 26)
        expectEqual(ref.registers.filter { $0.access == "RO" }.count, 27)
        expectEqual(ref.modes.count, 4)
        expectEqual(ref.software.count, 30)
        let sources = Set(ref.sources.map(\.id))
        for s in ref.software { expectTrue(sources.contains(s.source)) }
        for op in ref.operations { expectTrue(sources.contains(op.source)) }
        for n in ref.notes { for id in n.sources ?? [] { expectTrue(sources.contains(id)) } }
        for r in ref.registers { expectFalse(r.description.isEmpty); expectTrue(ref.categories.contains(r.category)) }
        expectTrue(FileManager.default.fileExists(atPath: Assets.url("model/LICENSE.txt").path))
        expectTrue(FileManager.default.fileExists(atPath: Assets.url("MOTORBRIDGE-LICENSE.txt").path))
    }
}

private func expectEqual<T: Equatable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a == b, sourceLocation: sourceLocation) }
private func expectEqual(_ a: Double, _ b: Double, accuracy: Double, sourceLocation: SourceLocation = #_sourceLocation) { #expect(abs(a - b) <= accuracy, sourceLocation: sourceLocation) }
private func expectTrue(_ value: Bool, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) { #expect(value, Comment(rawValue: message), sourceLocation: sourceLocation) }
private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value, sourceLocation: sourceLocation) }
private func expectLess<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a < b, sourceLocation: sourceLocation) }
private func expectGreater<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a > b, sourceLocation: sourceLocation) }
private func expectAtMost<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a <= b, sourceLocation: sourceLocation) }
private func expectThrows<T>(_ value: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(throws: (any Error).self, sourceLocation: sourceLocation) { _ = try value() } }
