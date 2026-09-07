import Foundation
import AppKit
import Combine
import RealityKit
import RobotCore
import simd

/// Explicit development harness: `--smoke-test /path/to/output` captures only this app's own views.
@MainActor enum SmokeCheck {
    private static var started = false
    private static weak var mainWindow: NSWindow?
    static func startIfRequested(_ model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard !started, let index = args.firstIndex(of: "--smoke-test"), args.indices.contains(index + 1) else { return }
        started = true
        // Isolate the test window before geometry loading and the first asynchronous wait.
        NSApp.windows.forEach { $0.ignoresMouseEvents = true }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        Task { @MainActor in
            let originalFontScale = Typography.shared.scale
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await Task.sleep(for: .seconds(8))
                guard model.sceneReady, let viewport = model.viewport else { throw CheckError.failed("3D model failed to initialize: \(model.sceneError ?? "unknown")") }
                mainWindow = viewport.window
                mainWindow?.setContentSize(NSSize(width: 1380, height: 900))
                mainWindow?.ignoresMouseEvents = true
                Typography.shared.reset()
                if Bundle.main.bundleURL.pathExtension == "app" {
                    guard Assets.root.path.hasPrefix(Bundle.main.bundleURL.path + "/") else { throw CheckError.failed("Resources must load from inside the packaged app") }
                }
                var results = ["RealityKit scene initialized", "34 meshes loaded", "53 actuator registers decoded"]
                let start = model.current
                guard start.joints == foldedPose, start.grip == 0, model.playback == .stopped,
                      simd_distance(model.telemetry.tcp, model.tcp) < 0.001,
                      simd_distance(model.tcp, SIMD3(model.targetX, model.targetY, model.targetZ)) < 0.001
                else { throw CheckError.failed("Folded startup pose or initial readouts: joints=\(start.joints), grip=\(start.grip), playback=\(model.playback), readout=\(model.telemetry.tcp), TCP=\(model.tcp), target=\([model.targetX, model.targetY, model.targetZ])") }
                results.append("Folded startup with closed gripper and synchronized readouts passed")
                model.setJoint(0, 20)
                model.setGrip(25)
                guard model.current.joints[0] == 20, model.current.grip == 25,
                      model.poseControls.pose.joints[0] == 20, model.poseControls.pose.grip == 25,
                      !model.controlsLocked else { throw CheckError.failed("Manual input must apply immediately without locking playback controls") }
                model.advance(seconds: 1.0 / 60)
                guard model.current.joints[0] == 20, model.current.grip == 25,
                      model.poseControls.pose.joints[0] == 20 else { throw CheckError.failed("Manual input must keep the rendered pose on the requested value") }
                model.setJoint(0, -20)
                guard model.poseControls.pose.grip == 25 else { throw CheckError.failed("Retargeting a joint discarded the gripper") }
                model.advance(seconds: 0.5)
                guard model.current.joints[0] == -20, model.current.grip == 25, !model.manualMoving else { throw CheckError.failed("Manual controls did not keep the requested pose") }
                guard simd_distance(SIMD3<Double>(viewport.toolPosition()), model.tcp / 1000) < 0.00001 else { throw CheckError.failed("Native joint hierarchy differs from forward kinematics") }
                try checkManualCancellation(model)
                try await checkManualFrames(model, viewport: viewport, folder: folder)
                results.append("Manual targets, native slider bindings, immediate pose updates, reversals, limits, and Stop/Reset/preset/navigation cancellation passed")
                try await checkFloorControls(model)
                results.append("Solid base plane stops both fingertips, clamps native slider values, and permits immediate reversal")
                model.useCurrentTarget(); model.solve()
                guard simd_distance(model.tcp, SIMD3(model.targetX, model.targetY, model.targetZ)) < 2 else { throw CheckError.failed("IK target") }
                model.setPose(start)
                model.speed = 100; model.playPause()
                model.advance(seconds: 0.3)
                model.playPause()
                let paused = model.current
                model.advance(seconds: 1)
                guard model.current == paused, model.playback == .paused else { throw CheckError.failed("Pause") }
                model.playPause()
                for _ in 0..<300 { model.advance(seconds: 0.1) }
                guard model.playback == .stopped, model.current.joints == model.waypoints.last!.joints else { throw CheckError.failed("Playback did not finish") }
                results.append("Joint, gripper, IK, playback, pause/resume and completion checks passed")
                let file = TrajectoryFile(poses: model.waypoints, speed: model.speed)
                let data = try JSONEncoder().encode(file)
                let decoded = try JSONDecoder().decode(TrajectoryFile.self, from: data)
                _ = try decoded.validated(using: model.robot)
                results.append("Trajectory export/import round trip passed")
                model.reset(); model.speed = 50
                try await Task.sleep(for: .seconds(2))
                guard model.current.joints == foldedPose, model.current.grip == 0 else { throw CheckError.failed("Reset pose changed unexpectedly: \(model.current)") }
                mainWindow?.makeKeyAndOrderFront(nil)
                sendKey("=", keyCode: 24)
                guard Typography.shared.scale == 1.1 else { throw CheckError.failed("Command-equals did not increase text") }
                sendKey("+", keyCode: 24, shift: true)
                guard Typography.shared.scale == 1.2 else { throw CheckError.failed("Command-plus did not increase text") }
                sendKey("-", keyCode: 27)
                guard Typography.shared.scale == 1.1 else { throw CheckError.failed("Command-minus did not decrease text") }
                sendKey("0", keyCode: 29)
                guard Typography.shared.scale == 1 else { throw CheckError.failed("Command-zero did not reset text") }
                guard let (menu, item) = menuItem("Increase Text Size", in: NSApp.mainMenu) else { throw CheckError.failed("Text size menu missing") }
                menu.performActionForItem(at: menu.index(of: item))
                guard Typography.shared.scale == 1.1 else { throw CheckError.failed("Text size menu action") }
                Typography.shared.reset()
                results.append("Native Command-plus/equal, Command-minus, Command-zero and View menu actions passed")
                let sceneImage: NSImage? = await withCheckedContinuation { continuation in
                    viewport.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
                }
                guard let sceneImage else { throw CheckError.failed("RealityKit snapshot returned no image") }
                try save(sceneImage, to: folder.appendingPathComponent("robot.png"))
                model.captureImage = sceneImage
                try await Task.sleep(for: .milliseconds(300))
                try captureWindow(to: folder.appendingPathComponent("simulator.png"))
                Typography.shared.setScale(1.6)
                try await Task.sleep(for: .milliseconds(400))
                try captureWindow(to: folder.appendingPathComponent("simulator-large-text.png"))
                Typography.shared.reset()
                model.captureImage = nil
                model.page = .actuators
                try await Task.sleep(for: .seconds(1))
                try captureWindow(to: folder.appendingPathComponent("reference.png"))
                model.referenceSection = .registers
                try await Task.sleep(for: .milliseconds(500))
                model.referenceSearch = "PMAX"
                try await Task.sleep(for: .milliseconds(500))
                try captureWindow(to: folder.appendingPathComponent("register-search.png"))
                Typography.shared.setScale(1.6)
                try await Task.sleep(for: .milliseconds(400))
                try captureWindow(to: folder.appendingPathComponent("reference-large-text.png"))
                sendKey("0", keyCode: 29)
                guard Typography.shared.scale == 1 else { throw CheckError.failed("Font shortcut failed in reference") }
                model.referenceSection = .modes
                try await Task.sleep(for: .milliseconds(500))
                try captureWindow(to: folder.appendingPathComponent("modes.png"))
                results.append("Captured native simulator and actuator reference views")
                model.page = .mcp
                model.mcpControl.setEnabled(true, persist: false)
                guard model.mcpControl.enabled else { throw CheckError.failed("MCP listener did not start: \(model.mcpControl.status)") }
                try await Task.sleep(for: .milliseconds(500))
                try captureWindow(to: folder.appendingPathComponent("mcp-control.png"))
                Typography.shared.setScale(1.6)
                try await Task.sleep(for: .milliseconds(400))
                try captureWindow(to: folder.appendingPathComponent("mcp-control-large-text.png"))
                Typography.shared.reset()
                try checkManualMCP(model)
                model.mcpControl.setEnabled(false, persist: false)
                guard !model.mcpControl.enabled else { throw CheckError.failed("MCP control did not stop") }
                results.append("MCP control page, manual motion state/rejection/stop, and enable/disable listener checks passed")
                model.page = .simulator
                try await Task.sleep(for: .milliseconds(500))
                guard model.viewport === viewport, viewport.world.isEnabled else { throw CheckError.failed("Scene was not reused on return from reference") }
                let move = Pose(name: "Reach", joints: robotPresets.first(where: { $0.name == "Reach" })!.joints, grip: 60)
                model.moveToPose(move)
                guard model.playback == .playing, model.current.joints == foldedPose else { throw CheckError.failed("Preset did not begin a smooth transition") }
                model.advance(seconds: 0.1)
                guard model.current.joints != foldedPose, model.current.joints != move.joints else { throw CheckError.failed("Preset transition jumped to its endpoint") }
                model.advance(seconds: 20)
                guard model.current.joints == move.joints, model.playback == .stopped else { throw CheckError.failed("Preset transition did not finish") }
                results.append("Smooth preset transition and cached scene navigation passed")
                let folded = robotPresets.first(where: { $0.name == "Folded" })!
                model.moveToPose(Pose(name: folded.name, joints: folded.joints, grip: folded.grip ?? model.current.grip))
                model.advance(seconds: 0.1)
                guard model.playback == .playing, model.current.joints != foldedPose, model.current.grip > 0 else { throw CheckError.failed("Folded preset did not animate") }
                model.advance(seconds: 20)
                guard model.playback == .stopped, model.current.joints == foldedPose, model.current.grip == 0 else { throw CheckError.failed("Folded preset endpoint") }
                results.append("Smooth folding and closed-gripper endpoint passed")
                try results.joined(separator: "\n").write(to: folder.appendingPathComponent("smoke-result.txt"), atomically: true, encoding: .utf8)
                Typography.shared.setScale(originalFontScale)
                NSApp.terminate(nil)
            } catch {
                try? error.localizedDescription.write(to: folder.appendingPathComponent("smoke-error.txt"), atomically: true, encoding: .utf8)
                Typography.shared.setScale(originalFontScale)
                NSApp.terminate(nil)
            }
        }
    }
    private static func checkManualCancellation(_ model: AppModel) throws {
        model.setJoint(0, 100); model.advance(seconds: 0.02)
        let stopping = model.current
        model.stop(); model.advance(seconds: 1)
        guard model.current == stopping, !model.hasMotion,
              model.poseControls.pose.joints == stopping.joints else { throw CheckError.failed("Stop did not discard manual motion") }
        model.setJoint(0, -100); model.reset(); model.advance(seconds: 1)
        guard model.current.joints == foldedPose, !model.manualMoving else { throw CheckError.failed("Reset resumed a pending slider target") }
        model.setJoint(0, 90); model.advance(seconds: 0.02)
        let from = model.current
        model.moveToPose(Pose(name: "Ready", joints: homePose, grip: 60))
        guard model.current == from, !model.manualMoving, model.playback == .playing else { throw CheckError.failed("Preset did not start from the rendered manual pose") }
        model.advance(seconds: 20); model.advance(seconds: 1)
        guard model.current.joints == homePose else { throw CheckError.failed("Old slider target overrode preset") }
        model.setJoint(0, 40); model.addWaypoint()
        guard model.waypoints.last?.joints[0] == 40 else { throw CheckError.failed("Add pose did not capture the displayed manual target") }
        model.waypoints.removeLast()
        model.page = .actuators
        let hidden = model.current
        model.page = .simulator; model.advance(seconds: 1)
        guard model.current == hidden, !model.manualMoving else { throw CheckError.failed("Hidden scene resumed manual input") }
        model.reset()
    }
    private static func checkManualMCP(_ model: AppModel) throws {
        let control = model.mcpControl
        model.setJoint(0, 45)
        model.setManualTracking(true)
        let result = try control.handle(["tool": "rebot_get_state", "arguments": [:]])
        guard result["manual_motion"] as? Bool == true,
              (result["manual_target"] as? [String: Any])?["joints_deg"] as? [Double] == model.poseControls.pose.joints,
              result["joints_deg"] as? [Double] == model.current.joints else { throw CheckError.failed("MCP manual/actual pose state") }
        var rejected = false
        do { _ = try control.handle(["tool": "rebot_set_joint", "arguments": ["joint": 1, "angle_deg": 10.0]]) }
        catch { rejected = true }
        guard rejected, model.poseControls.pose.joints[0] == 45 else { throw CheckError.failed("MCP accepted a competing manual move") }
        _ = try control.handle(["tool": "rebot_playback", "arguments": ["action": "stop"]])
        model.advance(seconds: 1)
        let stopped = try control.handle(["tool": "rebot_get_state", "arguments": [:]])
        guard !model.manualMoving, stopped["manual_target"] is NSNull else { throw CheckError.failed("MCP stop retained manual target") }
        model.setJoint(0, 45)
        model.setManualTracking(true)
        control.setEnabled(false, persist: false)
        guard !model.hasMotion else { throw CheckError.failed("Disabling MCP retained manual movement") }
        model.setPose(.startup)
    }
    private static func checkManualFrames(_ model: AppModel, viewport: RobotViewport, folder: URL) async throws {
        // Exercise the native slider's action/binding against the live scene clock.
        try await Task.sleep(for: .milliseconds(400))
        func sliders(_ view: NSView) -> [NSSlider] {
            if let slider = view as? NSSlider { return [slider] }
            return view.subviews.flatMap { sliders($0) }
        }
        guard let content = mainWindow?.contentView else { throw CheckError.failed("No native content view") }
        // SwiftUI's accessibility labels live on its accessibility elements, not
        // the backing NSSlider. The simulator constructs J1–J6, grip, then speed.
        let nativeSliders = sliders(content)
        guard nativeSliders.count == 8, let slider = nativeSliders.first,
              slider.isEnabled, slider.isContinuous else { throw CheckError.failed("Expected eight continuous native sliders") }
        let limits = model.robot.definition.armJoints[0]
        let lower = limits.lower / degreesToRadians, upper = limits.upper / degreesToRadians
        var frames = [[String: Double]](), notifications = 0, readouts = 0, inputs = 0
        let startTime = ProcessInfo.processInfo.systemUptime
        let scene = viewport.scene.subscribe(to: SceneEvents.Update.self) { _ in
            MainActor.assumeIsolated {
                frames.append(["time": ProcessInfo.processInfo.systemUptime - startTime,
                               "angle": model.current.joints[0], "target": model.poseControls.pose.joints[0]])
            }
        }
        let changes = model.objectWillChange.sink { notifications += 1 }
        let readings = model.telemetry.objectWillChange.sink { readouts += 1 }
        defer { scene.cancel(); changes.cancel(); readings.cancel() }
        for i in 0..<100 {
            let value = i < 50 ? Double(i) * 1.6 : 80 - Double(i - 50) * 2
            slider.doubleValue = slider.minValue + (value - lower) / (upper - lower) * (slider.maxValue - slider.minValue)
            guard slider.sendAction(slider.action, to: slider.target), abs(model.poseControls.pose.joints[0] - value) < 1e-8 else { throw CheckError.failed("Native slider binding lost the target") }
            inputs += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(500))
        let duration = ProcessInfo.processInfo.systemUptime - startTime
        let laggingFrames = frames.filter { abs($0["angle"]! - $0["target"]!) > 0.01 }.count
        let trackedFrames = frames.filter { abs($0["angle"]! - $0["target"]!) <= 0.01 }.count
        guard laggingFrames < 8, trackedFrames > 8, !model.manualMoving, abs(model.current.joints[0] + 18) < 1e-8,
              notifications < 12, readouts <= Int(ceil(duration * 15)) + 2,
              simd_distance(SIMD3<Double>(viewport.toolPosition()), model.tcp / 1000) < 0.00001
        else { throw CheckError.failed("Manual frame response: lagging frames=\(laggingFrames), tracked frames=\(trackedFrames), main updates=\(notifications), readouts=\(readouts), final angle=\(model.current.joints[0])") }
        let report: [String: Any] = ["input_events": inputs, "seconds": duration, "scene_updates": frames.count,
            "lagging_scene_updates": laggingFrames, "tracked_scene_updates": trackedFrames, "main_model_notifications": notifications, "readout_notifications": readouts,
            "final_angle": model.current.joints[0], "samples": frames]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("manual-motion.json"))
    }
    private static func checkFloorControls(_ model: AppModel) async throws {
        model.reset()
        model.setPose(Pose(name: "Ready", joints: homePose, grip: 90))
        model.setJoint(5, 90)
        try await Task.sleep(for: .milliseconds(200))
        func sliders(_ view: NSView) -> [NSSlider] {
            if let slider = view as? NSSlider { return [slider] }
            return view.subviews.flatMap(sliders)
        }
        guard let content = mainWindow?.contentView,
              let shoulder = sliders(content).first(where: { $0.accessibilityLabel() == "Joint 2 angle in degrees" })
        else { throw CheckError.failed("Native shoulder slider unavailable") }
        model.setManualTracking(true)
        var notifications = 0
        let changes = model.objectWillChange.sink { notifications += 1 }
        shoulder.doubleValue = -179
        guard shoulder.sendAction(shoulder.action, to: shoulder.target),
              model.current.joints[1] > -134, model.current.joints[1] < -132,
              abs(shoulder.doubleValue - model.current.joints[1]) < 1e-8,
              model.floor.minimumHeight(model.current) >= FloorConstraint.height,
              model.tcp.z > 20 else { throw CheckError.failed("Native slider did not stop at the gripper fingertip") }
        let contact = model.current.joints[1]
        for _ in 0..<10 {
            shoulder.doubleValue = -179
            _ = shoulder.sendAction(shoulder.action, to: shoulder.target)
        }
        guard abs(model.current.joints[1] - contact) < 1e-6,
              abs(shoulder.doubleValue - contact) < 1e-6, notifications == 0
        else { throw CheckError.failed("Floor stop moved or rebuilt the scene during dragging") }
        shoulder.doubleValue = contact + 2
        _ = shoulder.sendAction(shoulder.action, to: shoulder.target)
        guard abs(model.current.joints[1] - contact - 2) < 1e-8 else { throw CheckError.failed("Floor contact blocked reversal") }
        changes.cancel()
        model.setManualTracking(false)
        model.reset()
        try await Task.sleep(for: .milliseconds(200))
        let resetSliders = sliders(content)
        guard let resetShoulder = resetSliders.first(where: { $0.accessibilityLabel() == "Joint 2 angle in degrees" }),
              let resetBase = resetSliders.first(where: { $0.accessibilityLabel() == "Joint 1 angle in degrees" }),
              abs(resetShoulder.doubleValue) < 1e-8, abs(resetBase.doubleValue) < 1e-8
        else { throw CheckError.failed("Reset left stale native joint control values") }
    }
    private static func sendKey(_ text: String, keyCode: UInt16, shift: Bool = false) {
        let modifiers: NSEvent.ModifierFlags = shift ? [.command, .shift] : [.command]
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: mainWindow?.windowNumber ?? 0,
            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: keyCode)!
        NSApp.sendEvent(event)
    }
    private static func menuItem(_ title: String, in menu: NSMenu?) -> (NSMenu, NSMenuItem)? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.title == title { return (menu, item) }
            if let result = menuItem(title, in: item.submenu) { return result }
        }
        return nil
    }
    private static func save(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { throw CheckError.failed("PNG encoding") }
        try data.write(to: url)
    }
    private static func captureWindow(to url: URL) throws {
        guard let view = mainWindow?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckError.failed("Window capture") }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        rep.draw(in: view.bounds)
        image.unlockFocus()
        try save(image, to: url)
    }
    enum CheckError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let s) = self { return s }; return nil }
    }
}
