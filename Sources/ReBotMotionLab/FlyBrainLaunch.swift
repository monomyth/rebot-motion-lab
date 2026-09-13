import Foundation

enum FlyBrainLaunch {
    static func paths() -> (python: URL, script: URL, mcp: URL, home: URL)? {
        let env = ProcessInfo.processInfo.environment
        let mcp = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("ReBotMCP")
        guard FileManager.default.isExecutableFile(atPath: mcp.path) else { return nil }
        var dir = Bundle.main.executableURL!.deletingLastPathComponent()
        if let root = env["FLYBRAIN_CONTROLLER"], !root.isEmpty {
            dir = URL(fileURLWithPath: root)
            let python = dir.appendingPathComponent(".venv/bin/python")
            let script = dir.appendingPathComponent("scripts/run_policy.py")
            if FileManager.default.isExecutableFile(atPath: python.path), FileManager.default.fileExists(atPath: script.path) {
                return (python, script, mcp, dir)
            }
        }
        for _ in 0..<12 {
            let candidates = [
                dir.appendingPathComponent("controller"),
                dir.appendingPathComponent("../controller").standardizedFileURL,
            ]
            for controller in candidates {
                let python = controller.appendingPathComponent(".venv/bin/python")
                let python3 = controller.appendingPathComponent(".venv/bin/python3")
                let script = controller.appendingPathComponent("scripts/run_policy.py")
                let exe = [python, python3].first { FileManager.default.isExecutableFile(atPath: $0.path) }
                if let exe, FileManager.default.fileExists(atPath: script.path) {
                    return (exe, script, mcp, controller)
                }
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static var malecnsHome: String {
        if let env = ProcessInfo.processInfo.environment["MALECNS_HOME"], !env.isEmpty {
            return env
        }
        let gpu = "/data/malecns"
        if FileManager.default.fileExists(atPath: gpu) { return gpu }
        return NSHomeDirectory() + "/data/malecns"
    }

    /// Checkpoints, teacher logs, live activity — not the GCS connectome cache.
    static var projectData: String {
        if let env = ProcessInfo.processInfo.environment["FLYBRAIN_DATA"], !env.isEmpty {
            return env
        }
        return NSHomeDirectory() + "/fly-brain-data"
    }
}
