import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RobotCore
import simd

enum WorkspacePage: String, CaseIterable, Identifiable {
    case simulator = "Simulator", actuators = "Actuator reference", mcp = "MCP control", about = "About & sources"
    var id: String { rawValue }
    var icon: String {
        switch self { case .simulator: return "cube.transparent"; case .actuators: return "slider.horizontal.3"; case .mcp: return "point.3.connected.trianglepath.dotted"; case .about: return "info.circle" }
    }
}
typealias PlaybackState = MotionPlayer.State

@MainActor final class PoseControls: ObservableObject {
    @Published private(set) var pose = Pose.startup
    func update(_ value: Pose) {
        if pose.joints != value.joints || pose.grip != value.grip { pose = value }
    }
}

@MainActor final class MotionReadout: ObservableObject {
    @Published private(set) var pose = Pose.startup
    private(set) var tcp = SIMD3<Double>(repeating: 0)
    private(set) var progress = 0.0
    func update(pose: Pose, tcp: SIMD3<Double>, progress: Double) {
        self.tcp = tcp; self.progress = progress; self.pose = pose
    }
}

@MainActor final class AppModel: ObservableObject {
    let floor: FloorConstraint
    let robot: Kinematics
    let reference: ActuatorReference
    @Published var page: WorkspacePage = .simulator {
        didSet {
            if page != .simulator {
                experiment.pause()
                if playback == .playing { pause(); status = "Playback paused" }
                if manualMoving { setManualTracking(false) }
            }
        }
    }
    private(set) var current = Pose.startup
    @Published var waypoints = Pose.example
    @Published var speed = 50.0
    @Published private(set) var playback: PlaybackState = .stopped
    @Published private(set) var externalControlLocked = false
    // Not @Published: slider tracking must not rebuild SimulatorView / RobotScene.
    private(set) var manualMoving = false
    @Published private(set) var activeWaypoint: Int?
    private(set) var progress = 0.0
    @Published var showGrid = true
    @Published var showAxes = true
    @Published var showTrace = false
    @Published var camera = "Orbit"
    @Published var cameraRevision = 0
    @Published var traceRevision = 0
    @Published var targetX = 542.9
    @Published var targetY = 0.0
    @Published var targetZ = 409.3
    @Published var status = "Folded startup position · Select Ready to unfold"
    @Published var error: String?
    @Published var sceneReady = false
    @Published var sceneError: String?
    @Published var referenceSection: ReferenceSection = .overview
    @Published var referenceSearch = ""
    // A frozen RealityKit frame lets the development harness capture the native overlays too.
    @Published var captureImage: NSImage?
    let telemetry = MotionReadout()
    let poseControls = PoseControls()
    let mcpControl = MCPControl()
    lazy var experiment = ExperimentCoordinator(model: self)
    // Retain the native scene so reference navigation doesn't reload 34 STL meshes.
    var viewport: RobotViewport?
    private var player = MotionPlayer(current: .startup)
    private var readoutElapsed = 0.0
    private var lastReadoutTime = 0.0
    private var isSequence = true
    private var completionStatus = "Sequence complete"
    var tcp: SIMD3<Double> { robot.position(current.joints) * 1000 }
    var controlsLocked: Bool { playback != .stopped || externalControlLocked }
    var hasMotion: Bool { controlsLocked || manualMoving }

    init() throws {
        robot = Kinematics(try RobotDefinition.load())
        floor = try FloorConstraint(robot)
        reference = try ActuatorReference.load()
        publishReadout(); useCurrentTarget()
        mcpControl.attach(self)
    }
    private func apply(_ pose: Pose, immediately: Bool) {
        current = experiment.limit(pose)
        viewport?.applyPose(current)
        if immediately { publishReadout() }
    }
    private func publishReadout() {
        telemetry.update(pose: current, tcp: tcp, progress: progress)
        poseControls.update(current)
        readoutElapsed = 0
        lastReadoutTime = ProcessInfo.processInfo.systemUptime
    }
    func setManualTracking(_ tracking: Bool) {
        guard manualMoving != tracking else { return }
        manualMoving = tracking
        if tracking { progress = 0 }
        else { publishReadout() }
    }
    private func applyInteractive(_ pose: Pose) {
        current = experiment.limit(pose)
        viewport?.applyPose(current)
        poseControls.update(current)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastReadoutTime >= 1.0 / 15 {
            telemetry.update(pose: current, tcp: tcp, progress: progress)
            lastReadoutTime = now
        }
    }
    @discardableResult func setJoint(_ index: Int, _ value: Double) -> Double {
        guard current.joints.indices.contains(index) else { return 0 }
        guard !controlsLocked, value.isFinite else { return current.joints[index] }
        var pose = current
        pose.joints[index] = value
        pose.joints = robot.clampPose(pose.joints)
        applyInteractive(floor.limited(from: current, to: pose))
        return current.joints[index]
    }
    @discardableResult func setGrip(_ value: Double) -> Double {
        guard !controlsLocked, value.isFinite else { return current.grip }
        var pose = current
        pose.grip = clamp(value, 0, 90)
        applyInteractive(floor.limited(from: current, to: pose))
        return current.grip
    }
    func setPose(_ pose: Pose) {
        guard !controlsLocked else { return }
        setManualTracking(false)
        let target = Pose(name: pose.name, joints: robot.clampPose(pose.joints), grip: clamp(pose.grip, 0, 90))
        let allowed = floor.limited(from: current, to: target)
        apply(allowed, immediately: true)
        status = allowed.joints == target.joints && allowed.grip == target.grip ? "\(pose.name) pose" : "Stopped at base plane"
    }
    func moveToPose(_ pose: Pose, completion: String? = nil) {
        guard !controlsLocked else { return }
        setManualTracking(false)
        let requested = Pose(name: pose.name, joints: robot.clampPose(pose.joints), grip: clamp(pose.grip, 0, 90))
        let bounded = floor.limited(from: current, to: requested)
        let hitFloor = bounded.joints != requested.joints || bounded.grip != requested.grip
        completionStatus = hitFloor ? "Stopped at base plane · Move away to continue" : (completion ?? "\(pose.name) pose reached")
        if bounded.joints == current.joints && bounded.grip == current.grip { status = completionStatus; publishReadout(); return }
        isSequence = false; page = .simulator
        player.start([bounded], from: current); playback = .playing; activeWaypoint = nil; progress = 0
        status = "Moving to \(pose.name)"; publishReadout()
    }
    func reset() {
        if experiment.enabled { do { try experiment.reset() } catch { self.error=error.localizedDescription }; return }
        stop(); apply(.startup, immediately: true)
        resetCamera("Orbit"); traceRevision += 1; useCurrentTarget(); status = "Reset to folded startup position"
    }
    func resetCamera(_ name: String) { camera = name; cameraRevision += 1 }
    func useCurrentTarget() { let p = tcp; targetX = p.x; targetY = p.y; targetZ = p.z }
    func solve() {
        guard !controlsLocked else { return }
        let result = robot.solve(target: SIMD3(targetX, targetY, targetZ) / 1000, initial: current.joints)
        if result.success {
            moveToPose(Pose(name: "target", joints: result.joints, grip: current.grip), completion: String(format: "Target reached · %.2f mm error", result.error * 1000))
        } else { status = "No solution within 2 mm from this pose. Try a closer target or another starting pose." }
    }
    func addWaypoint() {
        guard !controlsLocked else { return }
        waypoints.append(Pose(name: "Pose \(waypoints.count + 1)", joints: current.joints, grip: current.grip))
        status = "Pose added to sequence"
    }
    private func pause() { player.pause(); playback = .paused; publishReadout() }
    func playPause() {
        guard !externalControlLocked else { return }
        page = .simulator
        if playback == .playing { pause(); status = "Playback paused"; return }
        if playback == .paused { player.resume(); playback = .playing; status = "Playback resumed"; return }
        guard !waypoints.isEmpty else { return }
        setManualTracking(false)
        isSequence = true; completionStatus = "Sequence complete"
        var route = [Pose](), from = current
        for target in waypoints {
            let allowed = floor.limited(from: from, to: target)
            route.append(allowed)
            if allowed.joints != target.joints || allowed.grip != target.grip {
                completionStatus = "Stopped at base plane · Move away to continue"
                break
            }
            from = allowed
        }
        player.start(route, from: current); playback = .playing; activeWaypoint = 0; progress = 0
        status = "Playing sequence"; publishReadout()
    }
    // Invoked by RealityKit's frame event, without routing animation through SwiftUI.
    func advance(seconds: Double) {
        guard seconds.isFinite, seconds > 0, playback == .playing else { return }
        player.advance(seconds: seconds, speed: isSequence ? speed : 100)
        progress = player.progress
        // The complete route was checked before starting, including skipped waypoint
        // boundaries after a long frame. Rendering remains independent of collision work.
        apply(player.current, immediately: false)
        let index = isSequence ? player.index : nil
        if activeWaypoint != index { activeWaypoint = index }
        readoutElapsed += max(0, seconds)
        if readoutElapsed >= 1.0 / 15 || player.state == .stopped { publishReadout() }
        if player.state == .stopped { playback = .stopped; status = completionStatus }
    }
    func stop() {
        experiment.stopArm(reason: "stop")
        stopPlaybackOnly()
    }
    func applyExperimentPose(_ pose: Pose, immediately: Bool = false) {
        current=pose; viewport?.applyPose(pose)
        if immediately || ProcessInfo.processInfo.systemUptime-lastReadoutTime >= 1.0/15 { publishReadout() }
    }
    func setExternalControlLock(_ locked: Bool) {
        if externalControlLocked != locked { externalControlLocked=locked }
    }
    func stopPlaybackOnly() {
        setManualTracking(false)
        player.stop(); playback = .stopped; activeWaypoint = nil; progress = 0
        status = "Motion stopped"; publishReadout()
    }
    func exportTrajectory() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "B601-DM-trajectory.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(TrajectoryFile(poses: waypoints, speed: speed)).write(to: url, options: .atomic)
            status = "Trajectory saved"
        } catch { self.error = error.localizedDescription }
    }
    func importTrajectory() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 2_000_000 else { throw TrajectoryError.invalid }
            let file = try JSONDecoder().decode(TrajectoryFile.self, from: Data(contentsOf: url))
            let poses = try file.validated(using: robot)
            stop(); waypoints = poses; speed = file.speed_percent; status = "Imported \(poses.count) waypoints"
        } catch { self.error = error.localizedDescription }
    }
    func saveReference() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "B601-DM-actuator-settings.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(contentsOf: Assets.url("B601-DM-actuator-settings.md")).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}
