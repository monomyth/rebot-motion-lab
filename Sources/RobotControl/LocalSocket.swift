import Foundation
import Darwin

public struct SimulatorUnavailable: LocalizedError {
    public init() {}
    public var errorDescription: String? { "The simulator is not running or MCP control is off. Open ReBot Motion Lab and enable MCP control." }
}

public enum LocalSocket {
    public static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["REBOT_CONTROL_DIRECTORY"] { return URL(fileURLWithPath: override, isDirectory: true) }
        var bytes = [CChar](repeating: 0, count: 4096)
        let size = confstr(_CS_DARWIN_USER_TEMP_DIR, &bytes, bytes.count)
        let base = size > 0 && size <= bytes.count ? String(cString: bytes) : "/tmp"
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("rebot-motionlab-\(getuid())", isDirectory: true)
    }
    public static var path: String { directory.appendingPathComponent("control.sock").path }
    public static func prepareDirectory() throws {
        let url = directory
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw ControlError("MCP control directory must be a private directory owned by this user: \(url.path)") }
    }
    static func withAddress<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ControlError("MCP socket path is too long") }
        address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            for i in bytes.indices { destination[i] = UInt8(bitPattern: bytes[i]) }
        }
        return try withUnsafePointer(to: &address) { try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    }
    static func configure(_ fd: Int32) {
        var noPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }
    static func validatePeer(_ fd: Int32) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw ControlError("MCP socket peer belongs to another user") }
    }
    public static func request(_ object: [String: Any]) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError("Could not create control socket") }
        defer { close(fd) }; configure(fd)
        let connected = try withAddress { Darwin.connect(fd, $0, $1) }
        guard connected == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED { throw SimulatorUnavailable() }
            throw ControlError("Could not connect to simulator: \(String(cString: strerror(errno)))")
        }
        try validatePeer(fd)
        try write(object, to: fd)
        return try read(from: fd)
    }
    static func read(from fd: Int32) throws -> [String: Any] {
        var data = Data(), chunk = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(5)
        while data.count <= 1_048_576, Date() < deadline {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw ControlError("Simulator connection closed or timed out; check state before retrying a motion") }
            data.append(contentsOf: chunk.prefix(n))
            if let end = data.firstIndex(of: 10) {
                guard end <= 1_048_576, let object = try JSONSerialization.jsonObject(with: data.prefix(upTo: end)) as? [String: Any] else { throw ControlError("Invalid control message") }
                return object
            }
        }
        throw ControlError("Control message is too large or timed out")
    }
    static func write(_ object: [String: Any], to fd: Int32) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 1_048_576 else { throw ControlError("Control response exceeds 1 MiB") }
        data.append(10)
        try data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let n = send(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw ControlError("Control write failed; check state before retrying a motion") }
                sent += n
            }
        }
    }
}

/// Private same-user IPC. This is not a network MCP endpoint; ReBotMCP provides stdio MCP.
public final class LocalControlServer: @unchecked Sendable {
    public typealias Reply = ([String: Any]) -> Void
    public typealias Handler = ([String: Any], @escaping Reply) -> Void
    private let lock = NSLock()
    private var listener: Int32 = -1, lockFile: Int32 = -1
    private var generation: UUID?
    public init() {}
    public func start(handler: @escaping Handler) throws {
        lock.lock(); defer { lock.unlock() }
        guard listener == -1 else { return }
        try LocalSocket.prepareDirectory()
        let lockFD = open(LocalSocket.directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw ControlError("Cannot open simulator instance lock") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); throw ControlError("Another ReBot Motion Lab instance already provides MCP control. Use that instance or turn off its MCP control.") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { close(lockFD); throw ControlError("Cannot create simulator listener") }
        do {
            LocalSocket.configure(fd)
            unlink(LocalSocket.path)
            guard try LocalSocket.withAddress({ Darwin.bind(fd, $0, $1) }) == 0, chmod(LocalSocket.path, 0o600) == 0, listen(fd, 8) == 0 else { throw ControlError("Cannot bind simulator control socket") }
        } catch { close(fd); close(lockFD); throw error }
        listener = fd; lockFile = lockFD
        let token = UUID(); generation = token
        let slots = DispatchSemaphore(value: 4)
        DispatchQueue(label: "rebot.control.accept", qos: .utility).async { [weak self] in
            while self?.isActive(token) == true {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EINTR { continue }; break }
                guard self?.isActive(token) == true, slots.wait(timeout: .now()) == .success else { close(client); continue }
                LocalSocket.configure(client)
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try LocalSocket.validatePeer(client)
                        let request = try LocalSocket.read(from: client)
                        handler(request) { response in
                            DispatchQueue.global(qos: .utility).async {
                                try? LocalSocket.write(response, to: client)
                                close(client); slots.signal()
                            }
                        }
                    } catch {
                        try? LocalSocket.write(["ok": false, "error": error.localizedDescription], to: client)
                        close(client); slots.signal()
                    }
                }
            }
        }
    }
    private func isActive(_ token: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == token }
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard listener >= 0 else { return }
        generation = nil
        shutdown(listener, SHUT_RDWR); close(listener); listener = -1
        unlink(LocalSocket.path)
        close(lockFile); lockFile = -1
    }
    deinit { stop() }
}
