import Foundation
import Testing
import RobotCore

struct FlyBrainLaunchConfigurationTests {
    @Test func normalLaunchReadsDeploymentAndUsesMetalRunner() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("code/codex/fly-brain")
        try FileManager.default.createDirectory(at: project.appendingPathComponent("configs"), withIntermediateDirectories: true)
        let checkpoint = project.appendingPathComponent("data/checkpoints/rebot/current").path
        try JSONSerialization.data(withJSONObject: ["checkpoint":checkpoint]).write(to: project.appendingPathComponent("configs/trained-runtime.json"))
        let settings = FlyBrainLaunchConfiguration(homeDirectory: home, environment: [:], savedCheckpoint: nil)
        #expect(settings.checkpointURL.path == checkpoint)
        #expect(settings.executable(motorController: true).path == project.appendingPathComponent("scripts/fly-brain-mlx").path)
        #expect(settings.executable(motorController: false).path == project.appendingPathComponent(".venv/bin/fly-brain").path)
    }
    @Test func explicitOverridesAndSavedSelectionArePreserved() {
        let home = URL(fileURLWithPath: "/tmp/fly-brain-test")
        let settings = FlyBrainLaunchConfiguration(homeDirectory: home, environment: ["FLY_BRAIN_EXECUTABLE":"/tmp/custom-runner", "FLY_BRAIN_CHECKPOINT":"/tmp/explicit-checkpoint", "FLY_BRAIN_DEPLOYMENT":"/tmp/explicit-deployment.json"], savedCheckpoint: "/tmp/saved-checkpoint")
        #expect(settings.executable(motorController: true).path == "/tmp/custom-runner")
        #expect(settings.checkpointURL.path == "/tmp/explicit-checkpoint")
        #expect(settings.deploymentURL.path == "/tmp/explicit-deployment.json")
        let saved = FlyBrainLaunchConfiguration(homeDirectory: home, environment: [:], savedCheckpoint: "/tmp/saved-checkpoint")
        #expect(saved.checkpointURL.path == "/tmp/saved-checkpoint")
    }
    @Test func uiSetupStartsFoldedWithoutChangingProtocolDefaults() throws {
        let task = ExperimentTask.flyBrainStartup
        #expect(task.cubeSizeMM == 20)
        #expect(task.initialJoints == [0,0,0,0,0,0])
        #expect(task.initialGripperMM == 0)
        #expect(task.holdSeconds == 5)
        #expect(task.timeoutSeconds == 180)
        #expect(ExperimentTask().cubeSizeMM == 50)
        let robot = Kinematics(try RobotDefinition.load())
        _ = try task.validated(robot: robot, floor: FloorConstraint(robot))
    }
}
