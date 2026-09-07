import Foundation
import Testing
@testable import RobotCore

struct PlaybackTests {
    private let start = Pose(name: "Start", joints: homePose, grip: 60)
    @Test func clockCarriesTimeAcrossWaypointBoundaries() {
        let poses = Pose.example
        var player = MotionPlayer(current: start)
        player.start(poses, from: start)
        let first = Motion.duration(from: start, to: poses[0])
        let second = Motion.duration(from: poses[0], to: poses[1])
        player.advance(seconds: first + second / 2, speed: 100)
        #expect(player.index == 1)
        let expected = Motion.interpolate(from: poses[0], to: poses[1], fraction: 0.5).joints
        #expect(zip(player.current.joints, expected).allSatisfy { abs($0 - $1) < 1e-10 })
        #expect(abs(player.progress - 0.3) < 1e-10)
    }
    @Test func clockIsIndependentOfFrameCadence() {
        var fast = MotionPlayer(current: start), slow = fast
        fast.start(Pose.example, from: start); slow.start(Pose.example, from: start)
        for _ in 0..<300 { fast.advance(seconds: 1.0 / 60, speed: 65) }
        for _ in 0..<20 { slow.advance(seconds: 0.25, speed: 65) }
        #expect(fast.index == slow.index)
        #expect(abs(fast.progress - slow.progress) < 1e-10)
        #expect(zip(fast.current.joints, slow.current.joints).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(abs(fast.current.grip - slow.current.grip) < 1e-9)
    }
    @Test func pauseResumeStopAndLongFrame() {
        var player = MotionPlayer(current: start)
        player.start(Pose.example, from: start); player.advance(seconds: 1, speed: 100)
        player.pause(); let paused = player.current
        player.advance(seconds: 50, speed: 100)
        #expect(player.current == paused)
        player.resume(); player.advance(seconds: 100, speed: 100)
        #expect(player.state == .stopped)
        #expect(player.progress == 1)
        #expect(player.current.joints == Pose.example.last!.joints)
        #expect(player.current.grip == Pose.example.last!.grip)
    }
    @Test func invalidTimeDoesNotChangePose() {
        var player = MotionPlayer(current: start)
        player.start(Pose.example, from: start)
        for delta in [Double.nan, .infinity, -1] { player.advance(seconds: delta, speed: 100) }
        player.advance(seconds: 1, speed: .nan)
        #expect(player.current == start)
        #expect(player.progress == 0)
    }
    @Test func indexedGeometryIsLossless() throws {
        let definition = try RobotDefinition.load()
        var originalCount = 0, indexedCount = 0
        for visual in definition.links.flatMap(\.visuals) {
            let mesh = try STLMesh(data: Data(contentsOf: Assets.url("model/" + visual.mesh)))
            let indexed = mesh.indexed()
            #expect(indexed.indices.count == mesh.positions.count)
            #expect(indexed.indices.enumerated().allSatisfy { i, index in
                mesh.positions[i] == indexed.positions[Int(index)] && mesh.normals[i] == indexed.normals[Int(index)]
            })
            originalCount += mesh.positions.count; indexedCount += indexed.positions.count
        }
        #expect(indexedCount < originalCount)
    }
}
