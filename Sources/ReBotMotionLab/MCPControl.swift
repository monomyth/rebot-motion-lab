import SwiftUI
import AppKit
import RobotCore
import RobotControl
import simd

@MainActor final class MCPControl: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "MCP control is off"
    @Published private(set) var recentCommands: [String] = []
    private weak var model: AppModel?
    private let server = LocalControlServer()
    private let instanceID = UUID().uuidString
    private var revision = 0
    func attach(_ model: AppModel) {
        self.model = model
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("--smoke-test"), !arguments.contains("--performance-check") else { return }
        if arguments.contains("--mcp-integration-test") || UserDefaults.standard.object(forKey: "mcpControlEnabled") == nil || UserDefaults.standard.bool(forKey: "mcpControlEnabled") { setEnabled(true, persist: false) }
    }
    func setEnabled(_ value: Bool, persist: Bool = true) {
        if persist { UserDefaults.standard.set(value, forKey: "mcpControlEnabled") }
        if !value {
            server.stop(); enabled = false; status = "MCP control is off"
            model?.exitServo()
            if model?.hasMotion == true { model?.stop() }
            return
        }
        do {
            try server.start { [weak self] request, reply in
                Task { @MainActor in
                    guard let self else { reply(["ok": false, "error": "Simulator closed"]); return }
                    do { reply(["ok": true, "data": try self.handle(request)]) }
                    catch {
                        self.record("Rejected: \(error.localizedDescription)")
                        reply(["ok": false, "error": error.localizedDescription])
                    }
                }
            }
            enabled = true; status = "Ready for local MCP clients"
        } catch { enabled = false; status = error.localizedDescription }
    }
    var executable: String {
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ReBotMCP").path }
        return URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().appendingPathComponent("ReBotMCP").path
    }
    func configuration(codex: Bool, redactingLocation: Bool = false) -> String {
        // Keep screen sharing free of user names and private install directories.
        // The Copy action still supplies the real executable path to the client.
        let command = redactingLocation
            ? (Bundle.main.bundleURL.pathExtension == "app" ? "…/ReBot Motion Lab.app/Contents/MacOS/ReBotMCP" : "…/ReBotMCP")
            : executable
        if codex {
            let path = String(decoding: (try? JSONSerialization.data(withJSONObject: command, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
            return "[mcp_servers.rebot-motion-lab-grok]\ncommand = \(path)\nargs = []"
        }
        let json: [String: Any] = ["mcpServers": ["rebot-motion-lab-grok": ["command": command, "args": [String]()]]]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
    }
    func copyConfiguration(codex: Bool) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration(codex: codex), forType: .string)
    }
    private func record(_ text: String) {
        recentCommands.insert("\(Date().formatted(date: .omitted, time: .standard)) · \(text)", at: 0)
        recentCommands = Array(recentCommands.prefix(12))
    }
    private func showSimulator(_ model: AppModel) {
        model.page = .simulator
        if !ProcessInfo.processInfo.arguments.contains("--mcp-integration-test") {
            model.viewport?.window?.deminiaturize(nil)
            model.viewport?.window?.orderFront(nil)
        }
    }
    private func boundedPose(_ joints: [Double], grip: Double, name: String, model: AppModel) throws -> Pose {
        guard joints.count == 6, joints.allSatisfy(\.isFinite), joints == model.robot.clampPose(joints), grip.isFinite, (0...90).contains(grip) else { throw ControlError("Pose is outside simulator joint/gripper limits. Read rebot_get_state for limits; no motion was started.") }
        let pose = Pose(name: name, joints: joints, grip: grip)
        guard model.floor.isAllowed(pose, cube: model.cube) else {
            if model.floor.minimumHeight(pose, cube: model.cube) < FloorConstraint.height {
                throw ControlError("Pose intersects the solid base plane, including the gripper fingers. No motion was started.")
            }
            if model.floor.cubePenetration(pose, cube: model.cube) > 0.0005 {
                throw ControlError("Pose intersects the scene cube. No motion was started.")
            }
            throw ControlError("The gripper would close through the cube. Pinch near the cube width instead. No motion was started.")
        }
        return pose
    }
    private func requireStopped(_ model: AppModel) throws {
        guard !model.hasMotion else { throw ControlError("Motion is \(model.manualMoving ? "being adjusted with a slider" : String(describing: model.playback)). Use rebot_playback(action: stop) before sending another pose or editing the sequence.") }
    }
    private func requireScripted(_ model: AppModel) throws {
        try requireStopped(model)
        guard model.controlMode == .scripted else { throw ControlError("The simulator is in servo mode. Use rebot_set_control_mode with scripted, or rebot_servo_joints / rebot_servo_tcp.") }
    }
    private func doubles(_ value: Any) -> [Double] {
        (value as! [Any]).map { ($0 as! NSNumber).doubleValue }
    }
    private func optionalDouble(_ value: Any?) -> Double? {
        if value == nil || value is NSNull { return nil }
        return (value as? NSNumber)?.doubleValue
    }
    func handle(_ request: [String: Any]) throws -> [String: Any] {
        guard enabled, let model else { throw ControlError("MCP control is off") }
        guard let name = request["tool"] as? String, let args = request["arguments"] as? [String: Any] else { throw ControlError("Invalid control request") }
        if name == "read_actuators" {
            guard args.isEmpty else { throw ControlError("Reference takes no arguments") }
            return ["text": try String(contentsOf: Assets.url("B601-DM-actuator-settings.md"), encoding: .utf8)]
        }
        try ControlCatalog.validate(args, for: name)
        if name == "rebot_get_state" { return state(model) }
        guard model.sceneReady, model.sceneError == nil else { throw ControlError("The 3D scene is still loading or unavailable. Read state and retry when scene_ready is true.") }
        var extra: [String: Any] = [:]
        switch name {
        case "rebot_move_joints", "rebot_set_joint", "rebot_set_gripper":
            try requireScripted(model)
            var joints = model.current.joints, grip = model.current.grip
            if name == "rebot_move_joints" { joints = doubles(args["joints_deg"]!); grip = args["gripper_mm"] as? Double ?? grip }
            if name == "rebot_set_joint" { joints[(args["joint"] as! Int) - 1] = args["angle_deg"] as! Double }
            if name == "rebot_set_gripper" { grip = args["opening_mm"] as! Double }
            let pose = try boundedPose(joints, grip: grip, name: "MCP target", model: model)
            showSimulator(model); model.moveToPose(pose)
        case "rebot_move_to_position":
            try requireScripted(model)
            let target = SIMD3(args["x_mm"] as! Double, args["y_mm"] as! Double, args["z_mm"] as! Double)
            let solution = model.robot.solve(target: target / 1000, initial: model.current.joints)
            guard solution.success else { throw ControlError("No IK solution within 2 mm from the current pose. The robot pose was preserved.") }
            let pose = try boundedPose(solution.joints, grip: model.current.grip, name: "MCP Cartesian target", model: model)
            model.targetX = target.x; model.targetY = target.y; model.targetZ = target.z
            showSimulator(model); model.moveToPose(pose)
            extra["ik_error_mm"] = solution.error * 1000
        case "rebot_move_to_pose":
            try requireScripted(model)
            try moveToPose(args, model: model, extra: &extra)
        case "rebot_set_cube":
            try setCube(args, model: model)
        case "rebot_capture_view":
            extra.merge(try capture(args, model: model)) { _, new in new }
        case "rebot_set_control_mode":
            showSimulator(model)
            if args["mode"] as! String == "servo" { model.enterServo() } else { model.exitServo() }
        case "rebot_servo_joints":
            extra.merge(try servoJoints(args, model: model)) { _, new in new }
        case "rebot_servo_tcp":
            extra.merge(try servoTCP(args, model: model)) { _, new in new }
        case "rebot_apply_preset":
            try requireScripted(model)
            let preset = robotPresets.first { $0.name == args["name"] as? String }!
            showSimulator(model); model.moveToPose(Pose(name: preset.name, joints: preset.joints, grip: preset.grip ?? model.current.grip))
        case "rebot_playback":
            switch args["action"] as! String {
            case "play":
                try requireScripted(model)
                guard model.playback == .stopped, !model.waypoints.isEmpty else { throw ControlError("play needs a stopped simulator and a nonempty sequence; use resume for paused motion") }
                showSimulator(model); model.playPause()
            case "pause":
                guard model.playback == .playing else { throw ControlError("No motion is playing") }
                model.playPause()
            case "resume":
                guard model.playback == .paused else { throw ControlError("No motion is paused") }
                showSimulator(model); model.playPause()
            case "stop": model.stop()
            case "reset": showSimulator(model); model.reset()
            default: break
            }
        case "rebot_set_speed": model.speed = args["percent"] as! Double
        case "rebot_add_waypoint":
            try requireScripted(model)
            guard model.waypoints.count < 1000 else { throw ControlError("Sequence already has 1000 poses") }
            let label = args["name"] as? String ?? "Pose \(model.waypoints.count + 1)"
            model.waypoints.append(Pose(name: label, joints: model.current.joints, grip: model.current.grip))
            model.status = "MCP added \(label)"
        case "rebot_set_sequence":
            try requireScripted(model)
            let entries = args["poses"] as! [[String: Any]]
            let poses = try entries.map { try boundedPose($0["joints_deg"] as! [Double], grip: $0["gripper_mm"] as! Double, name: $0["name"] as! String, model: model) }
            model.waypoints = poses; model.status = "MCP loaded \(poses.count) waypoints"
        case "rebot_clear_sequence":
            try requireScripted(model); model.waypoints = []; model.status = "MCP cleared the sequence"
        case "rebot_set_view":
            showSimulator(model)
            if let camera = args["camera"] as? String { model.resetCamera(camera) }
            if let value = args["grid"] as? Bool { model.showGrid = value }
            if let value = args["tool_axes"] as? Bool { model.showAxes = value }
            if let value = args["trace"] as? Bool { model.showTrace = value }
            if args["clear_trace"] as? Bool == true { model.traceRevision += 1 }
        default: throw ControlError("Unknown simulator operation")
        }
        revision += 1
        record(name + (args["action"].map { " · \($0)" } ?? args["name"].map { " · \($0)" } ?? ""))
        extra["accepted"] = true; extra["state"] = state(model)
        return extra
    }
    private func moveToPose(_ args: [String: Any], model: AppModel, extra: inout [String: Any]) throws {
        let target = SIMD3(args["x_mm"] as! Double, args["y_mm"] as! Double, args["z_mm"] as! Double)
        let keepLevel = args["keep_level"] as? Bool ?? false
        let fingersDown = args["fingers_down"] as? Bool ?? false
        let solution = model.robot.solve(
            target: target / 1000, initial: model.current.joints,
            keepLevel: keepLevel, cubeTopInTool: Grasp.cubeTopInTool(model.cube),
            fingersDown: fingersDown
        )
        guard solution.success else {
            if fingersDown {
                throw ControlError("No fingers-down IK solution within 2 mm and 5°. The robot pose was preserved.")
            }
            throw ControlError(keepLevel
                ? "No level IK solution within 2 mm and 5°. The robot pose was preserved."
                : "No IK solution within 2 mm from the current pose. The robot pose was preserved.")
        }
        let pose = try boundedPose(solution.joints, grip: model.current.grip, name: "MCP pose target", model: model)
        model.targetX = target.x; model.targetY = target.y; model.targetZ = target.z
        showSimulator(model); model.moveToPose(pose)
        extra["ik_error_mm"] = solution.error * 1000
        extra["orientation_error_deg"] = solution.orientationError * 180 / .pi
    }
    private func setCube(_ args: [String: Any], model: AppModel) throws {
        var cube = model.cube
        if let present = args["present"] as? Bool { cube.present = present }
        if args["attached"] as? Bool == false {
            cube.attached = false
            cube.attachLocal = matrix_identity_double4x4
            cube.restOnFloor()
        }
        if cube.present {
            let center: SIMD3<Double>? = {
                if args["x_mm"] == nil && args["y_mm"] == nil && args["z_mm"] == nil { return nil }
                return SIMD3(
                    optionalDouble(args["x_mm"]) ?? cube.center.x * 1000,
                    optionalDouble(args["y_mm"]) ?? cube.center.y * 1000,
                    optionalDouble(args["z_mm"]) ?? cube.center.z * 1000
                ) / 1000
            }()
            let size = optionalDouble(args["size_mm"]).map { SIMD3(repeating: $0 / 1000) }
            let yaw = optionalDouble(args["yaw_deg"]).map { $0 * .pi / 180 }
            if center != nil || size != nil || yaw != nil {
                cube = try cube.placing(center: center, size: size, yaw: yaw)
                cube.present = true
            }
        }
        model.applyCube(cube)
        model.status = cube.present ? (cube.attached ? "Cube attached" : "Cube placed") : "Cube hidden"
    }
    private func capture(_ args: [String: Any], model: AppModel) throws -> [String: Any] {
        showSimulator(model)
        guard let viewport = model.viewport else { throw ControlError("The 3D scene is not ready to capture.") }
        let width = Int(optionalDouble(args["width"]) ?? 320)
        let height = Int(optionalDouble(args["height"]) ?? 240)
        let apply = args["apply"] as? Bool ?? false
        let camera = args["camera"] as? String
        guard let result = viewport.captureJPEG(camera: camera, apply: apply, width: width, height: height) else {
            throw ControlError("The scene camera could not be captured.")
        }
        return [
            "camera": camera ?? model.camera,
            "width": width, "height": height,
            "jpeg_base64": result.data.base64EncodedString(),
            "cube_in_view": result.cubeInView,
            "tcp_in_view": result.tcpInView
        ]
    }
    private func servoJoints(_ args: [String: Any], model: AppModel) throws -> [String: Any] {
        guard model.controlMode == .servo else { throw ControlError("rebot_servo_joints requires servo mode.") }
        try requireStopped(model)
        var joints = model.current.joints, grip = model.current.grip
        if args["joints_deg"] != nil { joints = doubles(args["joints_deg"]!) }
        if let value = optionalDouble(args["gripper_mm"]) { grip = value }
        guard args["joints_deg"] != nil || args["gripper_mm"] != nil else { throw ControlError("Provide joints_deg and/or gripper_mm.") }
        let pose = try boundedPose(joints, grip: grip, name: "servo", model: model)
        showSimulator(model)
        let applied = model.servoTo(pose)
        return ["clamped": applied.joints != joints || applied.grip != grip]
    }
    private func servoTCP(_ args: [String: Any], model: AppModel) throws -> [String: Any] {
        guard model.controlMode == .servo else { throw ControlError("rebot_servo_tcp requires servo mode.") }
        try requireStopped(model)
        let target = SIMD3(args["x_mm"] as! Double, args["y_mm"] as! Double, args["z_mm"] as! Double)
        let keepLevel = args["keep_level"] as? Bool ?? false
        let solution = model.robot.solve(
            target: target / 1000, initial: model.current.joints,
            keepLevel: keepLevel, cubeTopInTool: Grasp.cubeTopInTool(model.cube)
        )
        guard solution.success else { throw ControlError("No IK solution within 2 mm from the current pose. The robot pose was preserved.") }
        let pose = try boundedPose(solution.joints, grip: model.current.grip, name: "servo tcp", model: model)
        showSimulator(model)
        _ = model.servoTo(pose)
        return ["ik_error_mm": solution.error * 1000, "orientation_error_deg": solution.orientationError * 180 / .pi]
    }
    private func state(_ model: AppModel) -> [String: Any] {
        let tcp = model.tcp
        let rpy = model.tcpRPY
        let cube = model.cube
        let top = cube.topNormal
        return [
            "app_version": ControlCatalog.version, "instance_id": instanceID, "process_id": ProcessInfo.processInfo.processIdentifier,
            "simulation": "kinematic", "hardware_connected": false, "scene_ready": model.sceneReady,
            "mcp_enabled": enabled, "command_revision": revision, "control_mode": model.controlMode.rawValue,
            "joints_deg": model.current.joints, "gripper_mm": model.current.grip,
            "tcp_mm": ["x": tcp.x, "y": tcp.y, "z": tcp.z],
            "tcp_rpy_deg": ["roll": rpy.x, "pitch": rpy.y, "yaw": rpy.z],
            "tcp_level": model.tcpLevel,
            "playback": String(describing: model.playback), "progress": model.progress,
            "manual_motion": model.manualMoving,
            "manual_target": model.manualMoving ? ["joints_deg": model.poseControls.pose.joints, "gripper_mm": model.poseControls.pose.grip] as [String: Any] : NSNull(),
            "active_waypoint": model.activeWaypoint.map { $0 + 1 } as Any? ?? NSNull(),
            "speed_percent": model.speed, "status": model.status, "page": model.page.rawValue,
            "joint_limits_deg": model.robot.definition.armJoints.enumerated().map { i, joint in ["joint": Double(i + 1), "min": joint.lower / degreesToRadians, "max": joint.upper / degreesToRadians] },
            "gripper_limits_mm": [0, 90],
            "floor": ["enabled": true, "height_mm": FloorConstraint.height * 1000, "minimum_robot_height_mm": model.floor.minimumHeight(model.current) * 1000],
            "presets": robotPresets.map { ["name": $0.name, "joints_deg": $0.joints, "gripper_mm": $0.grip as Any? ?? NSNull()] as [String: Any] },
            "waypoints": model.waypoints.map { ["id": $0.id.uuidString, "name": $0.name, "joints_deg": $0.joints, "gripper_mm": $0.grip] as [String: Any] },
            "view": ["camera": model.camera, "grid": model.showGrid, "tool_axes": model.showAxes, "trace": model.showTrace],
            "objects": ["cube": [
                "present": cube.present, "attached": cube.attached, "falling": cube.isFalling,
                "size_mm": cube.size.x * 1000,
                "center_mm": ["x": cube.center.x * 1000, "y": cube.center.y * 1000, "z": cube.center.z * 1000],
                "yaw_deg": cube.yaw * 180 / .pi,
                "vertical_velocity_mm_s": cube.verticalVelocity * 1000,
                "top_normal": ["x": top.x, "y": top.y, "z": top.z]
            ] as [String: Any]]
        ]
    }
}

struct MCPControlView: View {
    @ObservedObject var control: MCPControl
    @State private var codex = true
    @Environment(\.fontScale) private var fontScale
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Control through MCP.").labFont(.system(size: 27, weight: .medium))
                Text("Connect an AI client to the live B601-DM simulator.").labFont(.callout).foregroundStyle(.secondary)
                Toggle("Enable local MCP control", isOn: Binding(get: { control.enabled }, set: { control.setEnabled($0) }))
                    .toggleStyle(.switch).labFont(.headline)
                Label(control.status, systemImage: control.enabled ? "circle.fill" : "circle").labFont(.callout).foregroundStyle(control.enabled ? Color.labAccent : .secondary)
                Text("Turning control off stops current motion. The connection stays on this Mac and controls the simulator only.").labFont(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Connect your client").labFont(.headline)
                HStack {
                    Picker("Configuration", selection: $codex) { Text("Codex").tag(true); Text("Other clients").tag(false) }
                        .pickerStyle(.segmented).frame(width: 240 * fontScale)
                    Button("Copy MCP configuration") { control.copyConfiguration(codex: codex) }
                    Spacer()
                }
                Text("Add this stdio server to your MCP client, then reload its tools. Keep the app in its current location, or copy a fresh configuration after moving it.").labFont(.body)
                Text(control.configuration(codex: codex, redactingLocation: true)).labFont(.system(size: 12, design: .monospaced)).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                Label("The preview hides your install location. Copy MCP configuration includes the full local path so your client can launch the app.", systemImage: "eye.slash").labFont(.caption).foregroundStyle(.secondary)
                Text("Try: “Unfold the robot to Ready, move joint 1 to 30 degrees, then close the gripper.”").labFont(.body)
                Text("Moves return as soon as they start. The client can read live state until motion finishes. Stop a running move before commanding another pose.").labFont(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Available tools").labFont(.headline)
                ForEach(ControlCatalog.tools, id: \.selfName) { tool in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool["name"] as? String ?? "").labFont(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.labAccent)
                        Text(tool["description"] as? String ?? "").labFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Recent commands").labFont(.headline)
                if control.recentCommands.isEmpty { Text("Waiting for the first command.").labFont(.body).foregroundStyle(.secondary) }
                ForEach(Array(control.recentCommands.enumerated()), id: \.offset) { _, entry in Text(entry).labFont(.caption).textSelection(.enabled) }
            }.padding(28).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
private extension Dictionary where Key == String, Value == Any { var selfName: String { self["name"] as? String ?? "" } }
