import AppKit
import SwiftUI
import Foundation
import RobotControl
import RobotCore
import Darwin

/// Owns only the Python policy process. The simulator window remains user-owned.
@MainActor final class FlyBrainRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready to run"
    @Published private(set) var checkpointURL: URL
    @Published private(set) var resultDirectory: URL?
    @Published var learnFromReward = false
    private unowned let coordinator: ExperimentCoordinator
    private var process: Process?
    private var outputHandle: FileHandle?
    private var stopRequested = false
    private let launchConfiguration: FlyBrainLaunchConfiguration
    private var lastRunnerURL: URL?
    private let assetsHome: URL

    init(coordinator: ExperimentCoordinator) {
        self.coordinator = coordinator
        let configuration = FlyBrainLaunchConfiguration(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            environment: ProcessInfo.processInfo.environment,
            savedCheckpoint: UserDefaults.standard.string(forKey: "flyBrainCheckpointPath"))
        launchConfiguration = configuration
        assetsHome = configuration.dataDirectory
        checkpointURL = configuration.checkpointURL
    }
    var dataDirectory: URL { assetsHome }
    var checkpointName: String { checkpointURL.lastPathComponent }
    var isRetinalController: Bool { ((try? manifest())?["architecture"] as? [String:Any])?["kind"] as? String == "malecns_visual_dopamine" }
    var isMotorController: Bool { ((try? manifest())?["architecture"] as? [String:Any])?["kind"] as? String == "malecns_motor_dopamine" }
    var isImageController: Bool { isRetinalController || isMotorController }
    var scopeDescription: String { isMotorController ? "Seven mapped motor channels. Experimental reaching and grasping; start folded and Reset before each trial." : isRetinalController ? "Visual-response curriculum: turns the base toward the cube. Place the cube at Y = ±8–15 mm and Reset before each attempt." : "Experimental checkpoint — pickup is not yet reliable." }
    var inputDescription: String {
        if isImageController { return "Camera pixels → visual neurons → leg motor neurons" }
        let schema = (try? manifest())?["observation_schema"] as? [String:Any]
        return schema?["mode"] as? String == "vision" ? "Camera input" : "Simulator state input"
    }
    private func manifest() throws -> [String:Any] {
        let url = checkpointURL.appendingPathComponent("manifest.json")
        guard let value = try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any],
              let architecture = value["architecture"] as? [String:Any], ["malecns", "malecns_visual_dopamine", "malecns_motor_dopamine"].contains(architecture["kind"] as? String ?? "") else {
            throw ExperimentError.invalid("Choose a MaleCNS checkpoint folder containing manifest.json and its model weights.")
        }
        return value
    }
    func chooseCheckpoint() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a MaleCNS checkpoint"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = checkpointURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let previous = checkpointURL
        checkpointURL = url
        do { _ = try manifest(); UserDefaults.standard.set(checkpointURL.path,forKey:"flyBrainCheckpointPath"); status = "Ready to run" }
        catch { checkpointURL = previous; status = error.localizedDescription }
    }
    func start() {
        guard !isRunning else { return }
        do {
            let info = try manifest()
            let motorController = (info["architecture"] as? [String:Any])?["kind"] as? String == "malecns_motor_dopamine"
            let runnerURL = launchConfiguration.executable(motorController: motorController)
            let mode = (info["observation_schema"] as? [String:Any])?["mode"] as? String ?? "state"
            guard FileManager.default.isExecutableFile(atPath:runnerURL.path) else {
                throw ExperimentError.invalid("Fly-brain runner is missing at \(runnerURL.path). Install the fly-brain project first.")
            }
            if mode == "vision" {
                let schema=info["observation_schema"] as? [String:Any]
                guard schema?["camera_rig_revision"] as? String == ObservationRig.revision,
                      schema?["camera_names"] as? [String] == ObservationRig.observationNames else {
                    throw ExperimentError.invalid("This model uses previous camera optics. Collect Front/Gripper data and train a matching model.")
                }
            }
            try coordinator.prepareFlyBrainRun(inputMode:mode)
            let directory = assetsHome.appendingPathComponent("runs/rebot-ui/\(UUID().uuidString)", isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let log = directory.appendingPathComponent("runner.log")
            FileManager.default.createFile(atPath:log.path,contents:nil)
            let handle = try FileHandle(forWritingTo:log)
            let child = Process()
            child.executableURL = runnerURL
            child.currentDirectoryURL = launchConfiguration.projectDirectory
            let command = isMotorController ? "motor-run" : isRetinalController ? "visual-run" : "run"
            child.arguments = ["--home", assetsHome.path, command, "--current-episode", "--episode-id", coordinator.episodeID,
                               "--control-directory", LocalSocket.directory.path, "--checkpoint", checkpointURL.path,
                               "--record-images", "--floor-projection", "--output", directory.path]
            if isImageController {
                if let steps=info["deployment_max_steps"] as? Int { child.arguments! += ["--max-steps",String(steps)] }
                if learnFromReward { child.arguments!.append("--learn") }
            }
            child.environment = ProcessInfo.processInfo.environment.merging(["PYTHONUNBUFFERED":"1", "FLY_BRAIN_DEPLOYMENT":launchConfiguration.deploymentURL.path]) { _, new in new }
            lastRunnerURL = runnerURL
            child.standardOutput = handle; child.standardError = handle
            child.terminationHandler = { [weak self] completed in
                Task { @MainActor in self?.finished(completed, directory:directory) }
            }
            outputHandle = handle; process = child; resultDirectory = directory; stopRequested = false
            isRunning = true; status = "Loading fly-brain model…"
            coordinator.flyBrainStateChanged()
            do { try child.run() }
            catch {
                process = nil; isRunning = false; try? handle.close(); outputHandle = nil
                coordinator.flyBrainStateChanged(); throw error
            }
        } catch { status = error.localizedDescription }
    }
    func stop() {
        guard let process, isRunning, !stopRequested else { return }
        stopRequested = true; status = "Stopping fly brain…"
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGINT) }
        Task { @MainActor [weak self, weak process] in
            try? await Task.sleep(for:.seconds(2))
            guard let self, let process, self.process === process, process.isRunning else { return }
            process.terminate()
        }
    }
    private func finished(_ child:Process, directory:URL) {
        guard process === child else { return }
        try? outputHandle?.close(); outputHandle = nil; process = nil; isRunning = false
        if stopRequested { status = "Fly brain stopped" }
        else if let data = try? Data(contentsOf:directory.appendingPathComponent("evaluation.json")),
                let report = try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
            if report["task_kind"] as? String == "seven_motor_control" {
                if (report["successes"] as? Int ?? 0)>0 {
                    status = (report["release_required"] as? Bool ?? false) ? "Pickup, hold and drop completed" : "Pickup and hold completed"
                }
                else if let episodes=report["episodes"] as? [[String:Any]], let error=episodes.last?["error"] as? String { status=error }
                else if let episodes=report["episodes"] as? [[String:Any]], let metrics=episodes.last?["final_metrics"] as? [String:Any], let distance=metrics["position_error_mm"] as? Double {
                    status=String(format:"Grasp distance %.1f mm · pickup incomplete",distance)
                } else { status="Motor run finished; pickup incomplete" }
                if let path=report["learned_checkpoint"] as? String {
                    checkpointURL=URL(fileURLWithPath:path,isDirectory:true)
                    UserDefaults.standard.set(path,forKey:"flyBrainCheckpointPath")
                    status += " · learned checkpoint saved"
                }
                coordinator.finishVisualResponse()
            }
            else if (report["task_kind"] as? String)?.hasPrefix("visual_base") == true {
                if (report["successes"] as? Int ?? 0) > 0 { status = "Visual base-turn response succeeded" }
                else if let episodes=report["episodes"] as? [[String:Any]], let error=episodes.last?["error"] as? String { status = error }
                else { status = "Visual base-turn response did not succeed" }
                if let path=report["learned_checkpoint"] as? String {
                    checkpointURL=URL(fileURLWithPath:path,isDirectory:true)
                    UserDefaults.standard.set(path,forKey:"flyBrainCheckpointPath")
                    status += " · learned checkpoint saved"
                }
                coordinator.finishVisualResponse()
            }
            else if (report["successes"] as? Int ?? 0) > 0 { status = "Pickup, hold and release completed" }
            else if let episodes=report["episodes"] as? [[String:Any]], let error=episodes.last?["error"] as? String { status = "Run ended: \(error)" }
            else { status = "Run finished; task was not completed" }
        } else { status = "Runner exited (\(child.terminationStatus)). Open Results for the log." }
        coordinator.flyBrainStateChanged()
    }
    func showResults() { if let resultDirectory { NSWorkspace.shared.open(resultDirectory) } }
    var diagnosticState:[String:Any] {
        ["running":isRunning,"checkpoint":checkpointName,"status":status,
         "runner_executable":lastRunnerURL?.path as Any? ?? NSNull(),"deployment_configuration":launchConfiguration.deploymentURL.path,
         "process_id":process?.processIdentifier as Any? ?? NSNull(),"result_directory":resultDirectory?.path as Any? ?? NSNull()]
    }
}

struct FlyBrainControls: View {
    @ObservedObject var coordinator: ExperimentCoordinator
    @ObservedObject var runner: FlyBrainRunner
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Fly-brain controller").font(.headline)
            HStack {
                Text(runner.checkpointName).lineLimit(2).help(runner.checkpointURL.path)
                Spacer()
                Button("Choose model…") { runner.chooseCheckpoint() }.disabled(runner.isRunning)
            }
            Text(runner.inputDescription).foregroundStyle(.secondary)
            Text(runner.scopeDescription).foregroundStyle(.secondary)
            if runner.isImageController {
                Toggle("Learn from reward",isOn:$runner.learnFromReward).disabled(runner.isRunning)
                Text(runner.learnFromReward ? "Uses exploration and saves a new checkpoint in Results." : "Evaluation: synaptic weights stay fixed.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Run fly brain") { runner.start() }.disabled(!coordinator.canRunFlyBrain)
                Button("Stop fly brain") { coordinator.stopFlyBrainAndArm() }.disabled(!runner.isRunning)
            }
            Text(runner.isRunning && coordinator.hasOwner ? "Fly brain is controlling this cube" : runner.status).foregroundStyle(.secondary)
            if !runner.isRunning && coordinator.phase != "ready" {
                Text("Apply the cube or Reset to start another attempt.").foregroundStyle(.secondary)
            }
            if runner.resultDirectory != nil { Button("Results…") { runner.showResults() }.labLinkStyle() }
        }
    }
}
