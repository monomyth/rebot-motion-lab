import Foundation

/// Shared project defaults for a normal application launch and explicit overrides.
public struct FlyBrainLaunchConfiguration {
    public let projectDirectory: URL
    public let dataDirectory: URL
    public let deploymentURL: URL
    public let checkpointURL: URL
    private let executableOverride: URL?

    public init(homeDirectory: URL, environment: [String: String], savedCheckpoint: String?) {
        projectDirectory = homeDirectory.appendingPathComponent("code/codex/fly-brain", isDirectory: true)
        let projectData = projectDirectory.appendingPathComponent("data", isDirectory: true)
        let legacy = homeDirectory.appendingPathComponent("code/data/malecns", isDirectory: true).path
        func relocated(_ path: String) -> String {
            path == legacy || path.hasPrefix(legacy + "/") ? projectData.path + String(path.dropFirst(legacy.count)) : path
        }
        dataDirectory = URL(fileURLWithPath: relocated(environment["FLY_BRAIN_DATA_HOME"] ?? environment["MALECNS_HOME"] ?? projectData.path), isDirectory: true)
        deploymentURL = URL(fileURLWithPath: environment["FLY_BRAIN_DEPLOYMENT"] ?? projectDirectory.appendingPathComponent("configs/trained-runtime.json").path)
        let configuration = (try? Data(contentsOf: deploymentURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let configuredCheckpoint = configuration?["checkpoint"] as? String
        let fallback = projectData.appendingPathComponent("checkpoints/rebot/corrected-fast-slow-seed0").path
        checkpointURL = URL(fileURLWithPath: relocated(environment["FLY_BRAIN_CHECKPOINT"] ?? savedCheckpoint ?? configuredCheckpoint ?? fallback), isDirectory: true)
        executableOverride = environment["FLY_BRAIN_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
    }

    public func executable(motorController: Bool) -> URL {
        executableOverride ?? projectDirectory.appendingPathComponent(motorController ? "scripts/fly-brain-mlx" : ".venv/bin/fly-brain")
    }
}

public extension ExperimentTask {
    static var flyBrainStartup: Self {
        var task = Self()
        task.cubeSizeMM = 20
        task.initialJoints = Array(repeating: 0, count: 6)
        task.initialGripperMM = 0
        task.timeoutSeconds = 180
        task.seed = 2000
        return task
    }
}
