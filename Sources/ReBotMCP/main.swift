import Foundation
import Darwin
import RobotControl

// stdout is exclusively newline-delimited MCP JSON-RPC.
signal(SIGPIPE, SIG_IGN)
let arguments = CommandLine.arguments
if arguments.contains("--help") {
    FileHandle.standardError.write(Data("ReBotMCP \(ControlCatalog.version) — stdio MCP for ReBot Motion Lab.\nLaunch from an MCP client; do not pass JSON as command-line arguments.\nREBOT_MCP_NO_LAUNCH=1 disables automatic app launch.\n".utf8))
    exit(0)
}
var attemptedLaunch = false
func callSimulator(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
    let request: [String: Any] = ["tool": name, "arguments": args]
    let response: [String: Any]
    do { response = try LocalSocket.request(request) }
    catch is SimulatorUnavailable {
        guard !attemptedLaunch, ProcessInfo.processInfo.environment["REBOT_MCP_NO_LAUNCH"] != "1" else { throw SimulatorUnavailable() }
        attemptedLaunch = true
        let binary = URL(fileURLWithPath: arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        let app = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app", FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/ReBotMotionLab").path) else { throw ControlError("Open ReBot Motion Lab first, or use ReBotMCP from inside the packaged .app") }
        let launch = Process(); launch.executableURL = URL(fileURLWithPath: "/usr/bin/open"); launch.arguments = ["-g", app.path]
        launch.standardOutput = FileHandle.standardError; launch.standardError = FileHandle.standardError
        try launch.run(); launch.waitUntilExit()
        guard launch.terminationStatus == 0 else { throw SimulatorUnavailable() }
        var connected: [String: Any]?
        for _ in 0..<60 {
            Thread.sleep(forTimeInterval: 0.25)
            do { connected = try LocalSocket.request(request); break }
            catch is SimulatorUnavailable { continue } // Only retry connection failures before any command was sent.
        }
        guard let connected else { throw SimulatorUnavailable() }
        response = connected
    }
    guard response["ok"] as? Bool == true, let result = response["data"] as? [String: Any] else { throw ControlError(response["error"] as? String ?? "Invalid simulator response") }
    return result
}
let server = MCPProtocol(backend: callSimulator)
var pending = Data(), discarding = false
var input = [UInt8](repeating: 0, count: 8192)
while true {
    // POSIX read returns currently available pipe bytes. Foundation's read(upToCount:)
    // can wait for the requested byte count and deadlock an interactive MCP client.
    let count = Darwin.read(STDIN_FILENO, &input, input.count)
    if count < 0 && errno == EINTR { continue }
    if count <= 0 { break }
    for byte in input.prefix(count) {
        if byte == 10 {
            let response = discarding ? ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Message exceeds 1 MiB"]] as [String: Any] : server.handle(pending)
            if let response { FileHandle.standardOutput.write(Data(((try MCPProtocol.json(response)) + "\n").utf8)) }
            pending.removeAll(keepingCapacity: true); discarding = false
        } else if !discarding {
            if pending.count == 1_048_576 { pending.removeAll(keepingCapacity: true); discarding = true }
            else { pending.append(byte) }
        }
    }
}
