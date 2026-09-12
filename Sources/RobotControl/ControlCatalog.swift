import Foundation
import CoreFoundation

public enum ControlCatalog {
    public static let version = "1.9"
    private static func number(_ description: String, min: Double? = nil, max: Double? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "number", "description": description]
        if let min { s["minimum"] = min }; if let max { s["maximum"] = max }; return s
    }
    private static func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = [], readOnly: Bool = false, destructive: Bool = false) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive, "openWorldHint": false]]
    }
    public static let tools: [[String: Any]] = [
        tool("rebot_get_state", "Read the live simulator pose, TCP in mm, tool RPY, cube, grasp, control mode, joint limits, playback, sequence, presets, camera, and app instance. No hardware connection.", readOnly: true),
        tool("rebot_move_joints", "Smoothly move all six simulated joints. Angles must be within get_state limits. Returns accepted motion; poll get_state for completion. Stop existing motion first.", ["joints_deg": ["type": "array", "items": ["type": "number"], "minItems": 6, "maxItems": 6], "gripper_mm": number("Optional gripper opening; otherwise preserved.", min: 0, max: 90)], required: ["joints_deg"]),
        tool("rebot_set_joint", "Smoothly move one simulated joint, preserving other angles and gripper. Stop existing motion first.", ["joint": ["type": "integer", "minimum": 1, "maximum": 6], "angle_deg": number("Target angle in degrees; see get_state joint limits.")], required: ["joint", "angle_deg"]),
        tool("rebot_set_gripper", "Smoothly change the simulated gripper opening, preserving the arm pose. Stop existing motion first.", ["opening_mm": number("0 is closed; 90 is open.", min: 0, max: 90)], required: ["opening_mm"]),
        tool("rebot_move_to_position", "Position-only IK in robot base coordinates (mm). Orientation is unconstrained. Unreachable targets leave the pose unchanged. Returns accepted motion; poll get_state until stopped. Disabled in servo mode.", ["x_mm": number("Base X in mm."), "y_mm": number("Base Y in mm."), "z_mm": number("Base Z in mm.")], required: ["x_mm", "y_mm", "z_mm"]),
        tool("rebot_move_to_pose", "Cartesian IK with optional keep_level (tool +Z / cube top within 5° of world +Z, jaws along ±Y) or fingers_down (fingertips down: tool +X along world −Z). TCP is the fingertip. Position in mm. Unreachable targets leave the pose unchanged. Disabled in servo mode.", [
            "x_mm": number("Base X in mm."), "y_mm": number("Base Y in mm."), "z_mm": number("Base Z in mm."),
            "roll_deg": number("Optional tool roll in degrees."), "pitch_deg": number("Optional tool pitch in degrees."),
            "yaw_deg": number("Optional tool yaw in degrees."),
            "keep_level": ["type": "boolean", "description": "Keep the tool or attached cube level: tool +Z or cube top along world +Z."],
            "fingers_down": ["type": "boolean", "description": "Point the fingertips down (tool +X along world −Z). TCP stays the fingertip; the wrist stays above. Overrides keep_level."]
        ], required: ["x_mm", "y_mm", "z_mm"]),
        tool("rebot_set_cube", "Place or resize the scene cube on the solid base plane. X/Y are mm in the robot base frame; Z is ignored and the cube sits on the plane. Size is 10–90 mm (open gripper). Omitted fields stay unchanged.", [
            "x_mm": number("Cube center X in mm on the base plane."), "y_mm": number("Cube center Y in mm on the base plane."),
            "z_mm": number("Ignored. The cube always rests on the base plane."),
            "size_mm": number("Cube edge length in mm. 10 mm minimum; 90 mm is the fully open gripper.", min: 10, max: 90),
            "yaw_deg": number("Yaw about world Z in degrees."),
            "present": ["type": "boolean", "description": "False hides the cube."],
            "attached": ["type": "boolean", "description": "False forces a drop onto the plane."]
        ]),
        tool("rebot_capture_view", "JPEG of a scene camera. apply=false renders offscreen and does not change the live view.", [
            "camera": ["type": "string", "enum": ["Orbit", "Front", "Top", "Gripper"]],
            "width": number("Image width in pixels.", min: 64, max: 640),
            "height": number("Image height in pixels.", min: 64, max: 480),
            "apply": ["type": "boolean", "description": "If true, switch the live camera to the captured preset."]
        ]),
        tool("rebot_set_control_mode", "scripted uses quintic MCP pose tools. servo applies immediate slider-style updates via rebot_servo_joints / rebot_servo_tcp.", [
            "mode": ["type": "string", "enum": ["scripted", "servo"]]
        ], required: ["mode"]),
        tool("rebot_servo_joints", "Immediate floor-limited joint/gripper update. Requires servo mode. Last command wins; no MotionPlayer.", [
            "joints_deg": ["type": "array", "items": ["type": "number"], "minItems": 6, "maxItems": 6],
            "gripper_mm": number("Optional gripper opening.", min: 0, max: 90)
        ]),
        tool("rebot_servo_tcp", "Immediate IK from the current pose. Requires servo mode. keep_level and fingers_down match rebot_move_to_pose.", [
            "x_mm": number("Base X in mm."), "y_mm": number("Base Y in mm."), "z_mm": number("Base Z in mm."),
            "keep_level": ["type": "boolean", "description": "Keep the tool or attached cube level."],
            "fingers_down": ["type": "boolean", "description": "Point the fingertips down (tool +X along world −Z). TCP stays the fingertip; the wrist stays above. Overrides keep_level."]
        ], required: ["x_mm", "y_mm", "z_mm"]),
        tool("rebot_apply_preset", "Smoothly move to a preset. Folded also closes the gripper; other presets preserve opening.", ["name": ["type": "string", "enum": ["Folded", "Ready", "Reach", "Upright"]]], required: ["name"]),
        tool("rebot_playback", "Control simulator playback. play starts the sequence; resume continues paused motion. stop holds the current pose. reset immediately returns to folded startup and clears the trace, preserving the sequence.", ["action": ["type": "string", "enum": ["play", "pause", "resume", "stop", "reset"]]], required: ["action"]),
        tool("rebot_set_speed", "Set sequence playback speed. Single-pose moves use the simulator's nominal 60 degrees/second peak limit.", ["percent": number("Sequence speed percentage.", min: 10, max: 100)], required: ["percent"]),
        tool("rebot_add_waypoint", "Append the current stopped pose to the sequence.", ["name": ["type": "string", "minLength": 1, "maxLength": 120]]),
        tool("rebot_set_sequence", "Replace the simulator sequence after validating every pose. Does not start playback. Export from the app to save permanently.", ["poses": ["type": "array", "minItems": 1, "maxItems": 1000, "items": ["type": "object", "properties": ["name": ["type": "string", "minLength": 1, "maxLength": 120], "joints_deg": ["type": "array", "items": ["type": "number"], "minItems": 6, "maxItems": 6], "gripper_mm": number("Opening in mm.", min: 0, max: 90)], "required": ["name", "joints_deg", "gripper_mm"], "additionalProperties": false]]], required: ["poses"], destructive: true),
        tool("rebot_clear_sequence", "Clear all simulator waypoints. Does not change the pose. Stop playback first.", destructive: true),
        tool("rebot_set_view", "Show the simulator and set its camera or overlays. Omitted settings stay unchanged.", ["camera": ["type": "string", "enum": ["Orbit", "Front", "Top", "Gripper"]], "grid": ["type": "boolean"], "tool_axes": ["type": "boolean"], "trace": ["type": "boolean"], "clear_trace": ["type": "boolean"]])
    ]
    public static let resources: [[String: Any]] = [
        ["uri": "rebot://state", "name": "Live simulator state", "mimeType": "application/json"],
        ["uri": "rebot://actuators", "name": "B601-DM actuator settings reference", "mimeType": "text/markdown"]
    ]
    public static func validate(_ arguments: [String: Any], for name: String) throws {
        guard let tool = tools.first(where: { $0["name"] as? String == name }), let schema = tool["inputSchema"] as? [String: Any] else { throw ControlError("Unknown tool: \(name)") }
        try validate(arguments, schema: schema, path: "arguments")
    }
    private static func validate(_ value: Any, schema: [String: Any], path: String) throws {
        switch schema["type"] as? String {
        case "object":
            guard let object = value as? [String: Any] else { throw ControlError("\(path) must be an object") }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            for key in schema["required"] as? [String] ?? [] where object[key] == nil { throw ControlError("Missing \(path).\(key)") }
            for (key, item) in object {
                guard let property = properties[key] else { throw ControlError("Unknown field \(path).\(key)") }
                try validate(item, schema: property, path: "\(path).\(key)")
            }
        case "array":
            guard let items = value as? [Any], items.count >= (schema["minItems"] as? Int ?? 0), items.count <= (schema["maxItems"] as? Int ?? Int.max) else { throw ControlError("\(path) has an invalid array length") }
            for (i, item) in items.enumerated() { try validate(item, schema: schema["items"] as? [String: Any] ?? [:], path: "\(path)[\(i)]") }
        case "number", "integer":
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw ControlError("\(path) must be a finite number") }
            let d = n.doubleValue
            guard d >= ((schema["minimum"] as? NSNumber)?.doubleValue ?? -.infinity), d <= ((schema["maximum"] as? NSNumber)?.doubleValue ?? .infinity), schema["type"] as? String != "integer" || d.rounded() == d else { throw ControlError("\(path) is outside its allowed range") }
        case "boolean":
            guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw ControlError("\(path) must be a boolean") }
        case "string":
            guard let s = value as? String, s.count >= (schema["minLength"] as? Int ?? 0), s.count <= (schema["maxLength"] as? Int ?? Int.max), !(schema["minLength"] != nil && s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { throw ControlError("\(path) must be a nonempty string within its length limit") }
            if let choices = schema["enum"] as? [String], !choices.contains(s) { throw ControlError("\(path) must be one of: \(choices.joined(separator: ", "))") }
        default: break
        }
    }
}
public struct ControlError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
