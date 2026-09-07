import AppKit
import Combine
import RealityKit
import RobotCore
import Darwin

/// Measures this app's frame cadence during real, visible playback.
@MainActor enum PerformanceCheck {
    private static var started = false
    static func startIfRequested(_ model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard !started, let i = args.firstIndex(of: "--performance-check"), args.indices.contains(i + 1) else { return }
        started = true
        let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await Task.sleep(for: .seconds(6))
                guard let view = model.viewport, model.sceneReady else { throw SmokeCheck.CheckError.failed("No viewport") }
                view.window?.setContentSize(NSSize(width: 1380, height: 900))
                view.window?.ignoresMouseEvents = true
                var reports = [[String: Any]]()
                for trace in [false, true] {
                    model.reset()
                    // Keep the benchmark's initial pose consistent with the v1.0/v1.1 samples.
                    model.setPose(Pose(name: "Ready", joints: homePose, grip: 60))
                    model.showTrace = trace
                    if trace {
                        for n in 0..<800 {
                            var pose = model.current
                            pose.joints[0] = -100 + Double(n) / 4
                            pose.joints[1] = -95 + 15 * sin(Double(n) / 50)
                            model.setPose(pose)
                            view.update(model)
                        }
                        var pose = model.current; pose.joints[0] = 0; pose.joints[1] = -95
                        model.setPose(pose)
                    }
                    model.speed = 50
                    try await Task.sleep(for: .seconds(2))
                    var frames = [Double](), notifications = 0
                    var last = ProcessInfo.processInfo.systemUptime
                    let sub = view.scene.subscribe(to: SceneEvents.Update.self) { _ in
                        let now = ProcessInfo.processInfo.systemUptime
                        frames.append(now - last); last = now
                    }
                    let changes = model.objectWillChange.sink { notifications += 1 }
                    let cpuStart = cpuTime(), start = ProcessInfo.processInfo.systemUptime
                    model.playPause()
                    try await Task.sleep(for: .seconds(10))
                    let elapsed = ProcessInfo.processInfo.systemUptime - start, cpu = cpuTime() - cpuStart
                    sub.cancel(); changes.cancel(); model.stop()
                    frames.sort()
                    guard !frames.isEmpty else { throw SmokeCheck.CheckError.failed("No render frames") }
                    reports.append([
                        "trace": trace, "seconds": elapsed, "frames": frames.count,
                        "frames_per_second": Double(frames.count) / elapsed,
                        "median_frame_ms": frames[frames.count / 2] * 1000,
                        "p95_frame_ms": frames[min(frames.count - 1, Int(Double(frames.count) * 0.95))] * 1000,
                        "frames_over_33ms": frames.filter { $0 > 0.0334 }.count,
                        "main_model_notifications": notifications,
                        "cpu_seconds": cpu, "trace_entities": view.traceEntity.children.count,
                        "original_vertices": view.originalVertexCount, "indexed_vertices": view.indexedVertexCount
                    ])
                }
                let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: folder.appendingPathComponent("performance.json"))
            } catch { try? error.localizedDescription.write(to: folder.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8) }
            NSApp.terminate(nil)
        }
    }
    private static func cpuTime() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
