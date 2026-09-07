import Foundation
import CoreFoundation

/// The stdio MCP subset this server advertises: tools and readable resources.
public final class MCPProtocol {
    public typealias Backend = (String, [String: Any]) throws -> [String: Any]
    private let backend: Backend
    private var initialized = false, ready = false
    private var version = "2025-11-25"
    public init(backend: @escaping Backend) { self.backend = backend }
    public func handle(_ data: Data) -> [String: Any]? {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { return self.error(NSNull(), -32700, "Parse error") }
        guard let message = raw as? [String: Any], message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else { return error(NSNull(), -32600, "Invalid request") }
        let id = message["id"]
        if id == nil {
            if method == "notifications/initialized", initialized { ready = true }
            return nil // Notifications never receive a response.
        }
        guard validID(id!) else { return error(NSNull(), -32600, "Invalid request ID") }
        guard message["params"] == nil || message["params"] is [String: Any] else { return error(id!, -32602, "Parameters must be an object") }
        let params = message["params"] as? [String: Any] ?? [:]
        if method == "ping" { return result(id!, [:]) }
        if method == "initialize" {
            guard !initialized, let requested = params["protocolVersion"] as? String, params["capabilities"] is [String: Any], let info = params["clientInfo"] as? [String: Any], info["name"] is String, info["version"] is String else { return error(id!, -32602, "Invalid or duplicate initialization") }
            if ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"].contains(requested) { version = requested }
            initialized = true
            return result(id!, ["protocolVersion": version, "serverInfo": ["name": "rebot-motion-lab", "version": ControlCatalog.version], "capabilities": ["tools": ["listChanged": false], "resources": ["subscribe": false, "listChanged": false]], "instructions": "Controls the native B601-DM kinematic simulator only. Read state and limits first. Motion tools return acceptance, not physical completion; poll rebot_get_state until playback is stopped and manual_motion is false. Stop existing motion before commanding another pose. Navigating away from Simulator pauses playback and stops manual adjustment. No robot hardware or motor writes."])
        }
        guard ready else { return error(id!, -32002, "Initialize and send notifications/initialized first") }
        switch method {
        case "tools/list": return result(id!, ["tools": ControlCatalog.tools])
        case "resources/list": return result(id!, ["resources": ControlCatalog.resources])
        case "tools/call":
            guard let name = params["name"] as? String, ControlCatalog.tools.contains(where: { $0["name"] as? String == name }), params["arguments"] == nil || params["arguments"] is [String: Any] else { return error(id!, -32602, "Unknown tool or invalid arguments object") }
            do {
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                try ControlCatalog.validate(arguments, for: name)
                let value = try backend(name, arguments)
                var content: [String: Any] = ["content": [["type": "text", "text": try Self.json(value)]], "isError": false]
                if version >= "2025-06-18" { content["structuredContent"] = value }
                return result(id!, content)
            } catch { return result(id!, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]) }
        case "resources/read":
            guard let uri = params["uri"] as? String, let resource = ControlCatalog.resources.first(where: { $0["uri"] as? String == uri }) else { return error(id!, -32602, "Unknown resource") }
            do {
                let value = try backend(uri == "rebot://state" ? "rebot_get_state" : "read_actuators", [:])
                let text = uri == "rebot://state" ? try Self.json(value) : value["text"] as? String ?? ""
                return result(id!, ["contents": [["uri": uri, "mimeType": resource["mimeType"]!, "text": text]]])
            } catch { return self.error(id!, -32000, error.localizedDescription) }
        default: return error(id!, -32601, "Method not found: \(method)")
        }
    }
    public static func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
    }
    private func validID(_ id: Any) -> Bool {
        if id is String { return true }
        guard let n = id as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
        return n.doubleValue.isFinite && n.doubleValue.rounded() == n.doubleValue
    }
    private func result(_ id: Any, _ value: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }
    private func error(_ id: Any, _ code: Int, _ message: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]] }
}
