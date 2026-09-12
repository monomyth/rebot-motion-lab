import Foundation
import Testing
@testable import RobotCore

struct SimulatorDocumentTests {
    private var taskData: Data { Data(#"{"version":1,"cube_size_mm":20,"cube_xy_mm":[350,0],"cube_yaw_deg":0,"mass_grams":50,"friction":0.9,"lift_clearance_mm":100,"tilt_tolerance_deg":5,"hold_seconds":5,"timeout_seconds":120,"stable_linear_mm_s":15,"stable_angular_deg_s":10,"initial_joints_deg":[0,0,0,0,0,0],"initial_gripper_mm":0,"input_mode":"state","seed":2000,"placement_jitter_mm":0}"#.utf8) }
    @Test func routesFoldedCubeTaskFromEitherImporter() throws {
        guard case .task(let task) = try SimulatorDocument.decode(taskData) else { Issue.record("Task was routed as trajectory"); return }
        #expect(task.cubeSizeMM == 20 && task.initialJoints == foldedPose && task.initialGripperMM == 0)
        #expect(try SimulatorDocument.decodeTask(taskData) == task)
        let robot=Kinematics(try RobotDefinition.load())
        #expect(try task.validated(robot:robot,floor:FloorConstraint(robot)) == task)
    }
    @Test func keepsTrajectoryImportsWorking() throws {
        let original=TrajectoryFile(poses:[.startup],speed:50)
        let data=try JSONEncoder().encode(original)
        guard case .trajectory(let file) = try SimulatorDocument.decode(data) else { Issue.record("Trajectory was routed as task"); return }
        let poses = try file.validated(using:Kinematics(RobotDefinition.load()))
        #expect(poses.count == 1 && poses[0].joints == foldedPose && poses[0].grip == 0 && poses[0].name == "Folded")
        #expect(throws:ExperimentError.self) { try SimulatorDocument.decodeTask(data) }
    }
    @Test func invalidTaskFieldHasAnActionableMessage() throws {
        let bad=String(decoding:taskData,as:UTF8.self).replacingOccurrences(of:"\"cube_size_mm\":20",with:"\"cube_size_mm\":\"tiny\"")
        do { _ = try SimulatorDocument.decode(Data(bad.utf8)); Issue.record("Accepted a string cube size") }
        catch { #expect(error.localizedDescription.contains("cube_size_mm")) }
        #expect(throws:ExperimentError.self) { try SimulatorDocument.decode(Data("[]".utf8)) }
    }
}
