import Foundation
import RobotControl

/// Bounded asynchronous JSONL recording; disk writes never run on the render thread.
final class ExperimentRecorder: @unchecked Sendable {
    private let queue=DispatchQueue(label:"rebot.experiment.recorder",qos:.utility)
    private let lock=NSLock()
    private var pending=0
    private var failure: String?
    private var handle: FileHandle?
    private(set) var directory: URL?
    func start(manifest: [String:Any]) throws -> String {
        _ = try stop()
        let dir=LocalSocket.directory.appendingPathComponent("experiments/"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("manifest.json"),options:.atomic)
        let path=dir.appendingPathComponent("events.jsonl")
        guard FileManager.default.createFile(atPath:path.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw ControlError("Cannot create recording file.") }
        handle=try FileHandle(forWritingTo:path); directory=dir; failure=nil
        return dir.path
    }
    func append(_ event: [String:Any]) {
        guard let handle else { return }
        do {
            var data=try JSONSerialization.data(withJSONObject:event,options:[.sortedKeys]); data.append(10)
            lock.lock()
            if pending >= 120 { failure="Recording queue exceeded 120 events; run is incomplete."; lock.unlock(); return }
            pending += 1; lock.unlock()
            queue.async { [self,data] in
                do { try handle.write(contentsOf:data) } catch { lock.lock(); failure=error.localizedDescription; lock.unlock() }
                lock.lock(); pending -= 1; lock.unlock()
            }
        } catch { lock.lock(); failure=error.localizedDescription; lock.unlock() }
    }
    @discardableResult func stop() throws -> [String:Any] {
        let current=handle; handle=nil
        queue.sync {
            do { try current?.synchronize(); try current?.close() }
            catch { lock.lock(); failure=error.localizedDescription; lock.unlock() }
        }
        lock.lock(); let message=failure; lock.unlock()
        return ["directory":directory?.path as Any? ?? NSNull(),"complete":message == nil,"error":message as Any? ?? NSNull()]
    }
}
