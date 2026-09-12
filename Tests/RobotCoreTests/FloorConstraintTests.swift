import Foundation
import Testing
import simd
@testable import RobotCore

struct FloorConstraintTests {
    private func setup() throws -> (Kinematics, FloorConstraint) {
        let robot = Kinematics(try RobotDefinition.load())
        return (robot, try FloorConstraint(robot))
    }
    private func pose(_ q: [Double] = homePose, _ grip: Double = 60) -> Pose { Pose(name: "test", joints: q, grip: grip) }
    @Test func startupAndReadyRemainClear() throws {
        let (_, floor) = try setup()
        #expect(floor.minimumHeight(.startup) > 0)
        #expect(floor.minimumHeight(pose()) > 0)
        let ready = pose()
        #expect(floor.limited(from: .startup, to: ready) == ready)
    }
    @Test(arguments: [-90.0, 90.0]) func fingertipStopsBeforeTCPReachesFloor(roll: Double) throws {
        let (robot, floor) = try setup()
        var from = pose(homePose, 90); from.joints[5] = roll
        var target = from; target.joints[1] = -179
        let stopped = floor.limited(from: from, to: target)
        #expect(stopped.joints[1] > -134 && stopped.joints[1] < -132)
        #expect(robot.position(stopped.joints).z > 0.02)
        let measured = try originalMeshMinimum(robot, stopped)
        #expect(measured.link == (roll < 0 ? "finger_left_link" : "finger_right_link"))
        #expect(measured.height >= FloorConstraint.height)
        #expect(measured.height - FloorConstraint.height < 0.000002)
        #expect(abs(measured.height - floor.minimumHeight(stopped)) < 1e-10)
        let pushed = floor.limited(from: stopped, to: target)
        #expect(abs(pushed.joints[1] - stopped.joints[1]) < 1e-6)
        var reversed = stopped; reversed.joints[1] += 2
        #expect(floor.limited(from: stopped, to: reversed) == reversed)
        var rotating = stopped; rotating.joints[0] = 100
        #expect(floor.limited(from: stopped, to: rotating) == rotating)
    }
    @Test func openingGripperStopsAtFingerContact() throws {
        let (_, floor) = try setup()
        let closed = pose([0,-135,-95,10,0,90], 0)
        var requested = closed; requested.grip = 90
        let stopped = floor.limited(from: closed, to: requested)
        #expect(stopped.grip > 0 && stopped.grip < 90)
        #expect(floor.minimumHeight(stopped) >= FloorConstraint.height)
        #expect(floor.limited(from: stopped, to: closed) == closed)
    }
    @Test func clearEndpointCannotTunnelThroughFloor() throws {
        let (_, floor) = try setup()
        let from = pose([134.15847243481227,-116.72407774837623,-169.71850875742604,60.65879017574375,12.048834920242973,-116.09563604143887],90)
        var to = from; to.joints[2] = 0
        #expect(floor.minimumHeight(from) > 0.01 && floor.minimumHeight(to) > 0.01)
        let stopped = floor.limited(from: from, to: to)
        #expect(stopped.joints[2] < -70)
        for i in 0...100 {
            let sample = Motion.interpolate(from: from, to: stopped, fraction: Double(i)/100)
            #expect(floor.minimumHeight(sample) >= FloorConstraint.height)
        }
    }
    @Test func coordinatedMovesStopBeforePenetration() throws {
        let (_, floor) = try setup()
        let from = pose(), target = pose([100,-179,-60,20,20,90],90)
        let stopped = floor.limited(from: from, to: target)
        #expect(stopped.joints != target.joints)
        for i in 0...100 {
            #expect(floor.minimumHeight(Motion.interpolate(from: from, to: stopped, fraction: Double(i)/100)) >= FloorConstraint.height)
        }
    }
    @Test func coordinatedMotionCanRaiseFromExactFloorContact() throws {
        let (_, floor) = try setup()
        var contact = pose(homePose, 90); contact.joints[5] = 90
        var safe = contact.joints[1], unsafe = -179.0
        for _ in 0..<60 {
            let middle = (safe + unsafe) / 2
            contact.joints[1] = middle
            if floor.isAllowed(contact) { safe = middle } else { unsafe = middle }
        }
        contact.joints[1] = safe
        #expect(floor.minimumHeight(contact) >= FloorConstraint.height)
        #expect(floor.minimumHeight(contact) - FloorConstraint.height < 1e-10)
        var up = contact; up.joints[0] += 2; up.joints[1] += 2; up.grip -= 1
        let escaped = floor.limited(from: contact, to: up)
        #expect(escaped == up)
        for i in 0...100 {
            #expect(floor.minimumHeight(Motion.interpolate(from: contact, to: escaped, fraction: Double(i)/100)) >= FloorConstraint.height)
        }
        var down = contact; down.joints[0] += 2; down.joints[1] -= 2
        let blocked = floor.limited(from: contact, to: down)
        #expect(abs(blocked.joints[1] - contact.joints[1]) < 1e-6)
        #expect(floor.minimumHeight(blocked) >= FloorConstraint.height)
    }
    @Test func jointFloorContactDoesNotFreezeSafeJawClosure() throws {
        let (_, floor) = try setup()
        var ready = pose(homePose, 90); ready.joints[5] = 90
        var below = ready; below.joints[1] = -179
        let contact = floor.limited(from: ready, to: below)
        var request = contact; request.joints[1] = -179; request.grip = 0
        let coupled = floor.limited(from: contact, to: request)
        let accepted = floor.limitedWithIndependentGrip(from: contact, to: request)
        #expect(accepted.joints == coupled.joints)
        #expect(accepted.joints[1] > request.joints[1])
        #expect(coupled.grip > accepted.grip)
        #expect(accepted.grip == 0)
        for i in 0...100 {
            #expect(floor.isAllowed(Motion.interpolate(from: contact, to: accepted, fraction: Double(i)/100)))
        }
    }
    private func originalMeshMinimum(_ robot: Kinematics, _ pose: Pose) throws -> (height: Double, link: String) {
        let transforms = robot.transforms(pose.joints, grip: pose.grip)
        var lowest = Double.infinity, name = ""
        for link in robot.definition.links where link.name != "base_link" {
            for visual in link.visuals {
                let transform = transforms[link.name]! * originTransform(xyz: visual.xyz, rpy: visual.rpy)
                let mesh = try STLMesh(data: Data(contentsOf: Assets.url("model/" + visual.mesh)))
                for p in mesh.positions {
                    let z = (transform * SIMD4<Double>(Double(p.x), Double(p.y), Double(p.z), 1)).z
                    if z < lowest { lowest = z; name = link.name }
                }
            }
        }
        return (lowest, name)
    }
}
