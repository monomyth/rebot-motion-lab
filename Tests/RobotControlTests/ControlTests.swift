import Foundation
import Testing
import RobotControl
import Darwin

struct ControlTests {
    private func request(_ method: String, _ params: [String: Any] = [:], id: Any = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }
    private func ready(_ server: MCPProtocol, version: String = "2025-11-25") throws {
        let result = server.handle(try request("initialize", ["protocolVersion": version, "capabilities": [:], "clientInfo": ["name": "tests", "version": "1"]]))!
        #expect((result["result"] as? [String: Any])?["protocolVersion"] as? String == version)
        #expect(server.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)) == nil)
    }
    @Test func lifecycleErrorsAndNotifications() throws {
        var invoked = false
        let server = MCPProtocol { _, _ in invoked = true; return [:] }
        #expect((server.handle(Data("{".utf8))?["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect((server.handle(try request("tools/list"))?["error"] as? [String: Any])?["code"] as? Int == -32002)
        #expect(server.handle(Data(#"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"rebot_playback","arguments":{"action":"reset"}}}"#.utf8)) == nil)
        #expect(!invoked)
        try ready(server)
        #expect((server.handle(try request("not_a_method"))?["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect((server.handle(try request("ping", id: true))?["error"] as? [String: Any])?["code"] as? Int == -32600)
        #expect((server.handle(try request("ping", id: "keep-id"))?["id"] as? String) == "keep-id")
    }
    @Test func discoveryAndStructuredResults() throws {
        let server = MCPProtocol { name, _ in ["tool": name, "joints_deg": [0,0,0,0,0,0]] }
        try ready(server)
        let list = server.handle(try request("tools/list"))!["result"] as! [String: Any]
        #expect((list["tools"] as? [[String: Any]])?.count == 18)
        let result = server.handle(try request("tools/call", ["name": "rebot_get_state"]))!["result"] as! [String: Any]
        #expect(result["isError"] as? Bool == false)
        #expect((result["structuredContent"] as? [String: Any])?["tool"] as? String == "rebot_get_state")
        let content = result["content"] as! [[String: Any]]
        let json = try JSONSerialization.jsonObject(with: Data((content[0]["text"] as! String).utf8)) as! [String: Any]
        #expect(json["tool"] as? String == "rebot_get_state")
    }
    @Test func validationRejectsCoercionAndUnknownFields() throws {
        let bad: [(String, [String: Any])] = [
            ("rebot_set_joint", ["joint": true, "angle_deg": 30]),
            ("rebot_set_joint", ["joint": 1.5, "angle_deg": 30]),
            ("rebot_set_joint", ["joint": 7, "angle_deg": 30]),
            ("rebot_set_joint", ["joint": 1, "angle_deg": "30"]),
            ("rebot_set_gripper", ["opening_mm": 91]),
            ("rebot_set_gripper", ["opening_mm": Double.nan]),
            ("rebot_set_view", ["grid": 1]),
            ("rebot_apply_preset", ["name": "unknown"]),
            ("rebot_move_joints", ["joints_deg": [0,0,0,0,0]]),
            ("rebot_set_sequence", ["poses": [["name": " ", "joints_deg": [0,0,0,0,0,0], "gripper_mm": 0]]]),
            ("rebot_get_state", ["unexpected": true])
        ]
        for (name, args) in bad { #expect(throws: ControlError.self) { try ControlCatalog.validate(args, for: name) } }
        try ControlCatalog.validate(["joint": 1, "angle_deg": 30.0], for: "rebot_set_joint")
        try ControlCatalog.validate(["grid": true, "camera": "Front"], for: "rebot_set_view")
        try ControlCatalog.validate(["camera": "Gripper"], for: "rebot_set_view")
        try ControlCatalog.validate(["camera": "Gripper", "apply": false], for: "rebot_capture_view")
        for toolName in ["rebot_set_view", "rebot_capture_view"] {
            let tool = ControlCatalog.tools.first { $0["name"] as? String == toolName }!
            let camera = ((tool["inputSchema"] as! [String: Any])["properties"] as! [String: Any])["camera"] as! [String: Any]
            #expect(camera["enum"] as? [String] == ["Orbit", "Front", "Top", "Gripper"])
        }
        for name in ["Orbit", "Front", "Top", "Gripper"] {
            try ControlCatalog.validate(["camera": name], for: "rebot_set_view")
            try ControlCatalog.validate(["camera": name, "apply": false], for: "rebot_capture_view")
        }
        #expect(throws: ControlError.self) { try ControlCatalog.validate(["camera": "Side"], for: "rebot_set_view") }
        #expect(throws: ControlError.self) { try ControlCatalog.validate(["camera": "top"], for: "rebot_capture_view") }
        try ControlCatalog.validate(["x_mm": 280.0, "y_mm": 0.0, "z_mm": 20.0, "keep_level": true], for: "rebot_move_to_pose")
        try ControlCatalog.validate(["x_mm": 280.0, "y_mm": 0.0, "z_mm": 80.0, "fingers_down": true], for: "rebot_move_to_pose")
        try ControlCatalog.validate(["x_mm": 245.0, "y_mm": 0.0, "z_mm": 48.0, "fingers_down": true], for: "rebot_servo_tcp")
        try ControlCatalog.validate(["present": true, "size_mm": 40.0], for: "rebot_set_cube")
        try ControlCatalog.validate(["x_mm": 200.0, "y_mm": -50.0, "size_mm": 10.0], for: "rebot_set_cube")
        try ControlCatalog.validate(["size_mm": 90.0], for: "rebot_set_cube")
        #expect(throws: ControlError.self) { try ControlCatalog.validate(["size_mm": 9.0], for: "rebot_set_cube") }
        #expect(throws: ControlError.self) { try ControlCatalog.validate(["size_mm": 91.0], for: "rebot_set_cube") }
        try ControlCatalog.validate(["mode": "servo"], for: "rebot_set_control_mode")
        #expect(throws: ControlError.self) { try ControlCatalog.validate(["mode": "fly"], for: "rebot_set_control_mode") }
    }
    @Test func rejectedArgumentsNeverReachBackend() throws {
        var count = 0
        let server = MCPProtocol { _, _ in count += 1; return [:] }
        try ready(server)
        let response = server.handle(try request("tools/call", ["name": "rebot_set_gripper", "arguments": ["opening_mm": -1]]))!
        #expect((response["result"] as? [String: Any])?["isError"] as? Bool == true)
        #expect(count == 0)
    }
    @Test func oldProtocolAndResourceErrors() throws {
        let server = MCPProtocol { name, _ in
            if name == "read_actuators" { return ["text": "# Reference"] }
            throw ControlError("Simulator unavailable")
        }
        try ready(server, version: "2024-11-05")
        let failure = server.handle(try request("tools/call", ["name": "rebot_get_state"]))!["result"] as! [String: Any]
        #expect(failure["isError"] as? Bool == true)
        #expect(failure["structuredContent"] == nil)
        let reference = server.handle(try request("resources/read", ["uri": "rebot://actuators"]))!["result"] as! [String: Any]
        #expect((reference["contents"] as? [[String: Any]])?.first?["text"] as? String == "# Reference")
        #expect((server.handle(try request("resources/read", ["uri": "file:///etc/passwd"]))?["error"] as? [String: Any])?["code"] as? Int == -32602)
    }
    @Test func privateSocketRoundTripAndInstanceLock() throws {
        let folder = URL(fileURLWithPath: "/tmp/rebot-test-\(UUID().uuidString.prefix(8))")
        setenv("REBOT_CONTROL_DIRECTORY", folder.path, 1)
        defer { unsetenv("REBOT_CONTROL_DIRECTORY"); try? FileManager.default.removeItem(at: folder) }
        let server = LocalControlServer(); defer { server.stop() }
        try server.start { value, reply in reply(["ok": true, "echo": value]) }
        let other = LocalControlServer()
        #expect(throws: ControlError.self) { try other.start { _, reply in reply([:]) } }
        let response = try LocalSocket.request(["number": 42])
        #expect(response["ok"] as? Bool == true)
        #expect((response["echo"] as? [String: Any])?["number"] as? Int == 42)
        let attributes = try FileManager.default.attributesOfItem(atPath: LocalSocket.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        server.stop()
        #expect(throws: SimulatorUnavailable.self) { try LocalSocket.request([:]) }
    }
}
