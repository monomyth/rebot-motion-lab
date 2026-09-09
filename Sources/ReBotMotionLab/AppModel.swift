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

enum ControlMode: String {
    case scripted, servo
}

@MainActor final class MotionReadout: ObservableObject {
    @Published private(set) var pose = Pose.startup
    private(set) var tcp = SIMD3<Double>(repeating: 0)
    private(set) var rpy = SIMD3<Double>(repeating: 0)
    private(set) var tcpLevel = false
    private(set) var cube = CubeState.spawn
    private(set) var progress = 0.0
    func update(pose: Pose, tcp: SIMD3<Double>, rpy: SIMD3<Double>, tcpLevel: Bool, cube: CubeState, progress: Double) {
        self.tcp = tcp; self.rpy = rpy; self.tcpLevel = tcpLevel; self.cube = cube; self.progress = progress; self.pose = pose
    }
}

@MainActor final class AppModel: ObservableObject {
    let floor: FloorConstraint
    let robot: Kinematics
    let reference: ActuatorReference
    @Published var page: WorkspacePage = .simulator {
        didSet {
            if page != .simulator {
                if playback == .playing { pause(); status = "Playback paused" }
                if manualMoving { setManualTracking(false) }
                if controlMode == .servo { exitServo() }
            }
        }
    }
    private(set) var current = Pose.startup
    @Published var waypoints = Pose.example
    @Published var speed = 50.0
    @Published private(set) var playback: PlaybackState = .stopped
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
    @Published var keepLevel = true
    @Published private(set) var controlMode: ControlMode = .scripted
    private(set) var cube = CubeState.spawn
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
    // Retain the native scene so reference navigation doesn't reload 34 STL meshes.
    var viewport: RobotViewport?
    private var player = MotionPlayer(current: .startup)
    private var readoutElapsed = 0.0
    private var lastReadoutTime = 0.0
    private var isSequence = true
    private var completionStatus = "Sequence complete"
    var tcp: SIMD3<Double> { robot.position(current.joints) * 1000 }
    var tcpRPY: SIMD3<Double> { robot.rpy(current.joints) * (180 / .pi) }
    var tcpLevel: Bool { robot.isLevel(current.joints, cubeTop: cube.attached ? cube.topNormal : nil) }
    var controlsLocked: Bool { playback != .stopped }
    var scriptedLocked: Bool { controlsLocked || controlMode == .servo }
    var hasMotion: Bool { controlsLocked || manualMoving }

    init() throws {
        robot = Kinematics(try RobotDefinition.load())
        floor = try FloorConstraint(robot)
        reference = try ActuatorReference.load()
        publishReadout(); useCurrentTarget()
        mcpControl.attach(self)
    }
    private func commit(_ pose: Pose, previousGrip: Double, immediately: Bool) {
        current = pose
        let end = robot.endLink(current.joints, grip: current.grip)
        Grasp.update(previousGrip: previousGrip, pose: current, cube: &cube, endLink: end)
        viewport?.applyPose(current)
        viewport?.syncCube(cube)
        if immediately { publishReadout() }
    }
    private func apply(_ pose: Pose, immediately: Bool) {
        let previousGrip = current.grip
        let allowed = floor.limited(from: current, to: pose, cube: cube)
        commit(allowed, previousGrip: previousGrip, immediately: immediately)
    }
    private func publishReadout() {
        telemetry.update(pose: current, tcp: tcp, rpy: tcpRPY, tcpLevel: tcpLevel, cube: cube, progress: progress)
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
        let previousGrip = current.grip
        commit(pose, previousGrip: previousGrip, immediately: false)
        poseControls.update(current)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastReadoutTime >= 1.0 / 15 {
            telemetry.update(pose: current, tcp: tcp, rpy: tcpRPY, tcpLevel: tcpLevel, cube: cube, progress: progress)
            lastReadoutTime = now
        }
    }
    @discardableResult func setJoint(_ index: Int, _ value: Double) -> Double {
        guard current.joints.indices.contains(index) else { return 0 }
        guard !controlsLocked, value.isFinite else { return current.joints[index] }
        var pose = current
        pose.joints[index] = value
        pose.joints = robot.clampPose(pose.joints)
        applyInteractive(floor.limited(from: current, to: pose, cube: cube))
        return current.joints[index]
    }
    @discardableResult func setGrip(_ value: Double) -> Double {
        guard !controlsLocked, value.isFinite else { return current.grip }
        var pose = current
        pose.grip = clamp(value, 0, 90)
        applyInteractive(floor.limited(from: current, to: pose, cube: cube))
        return current.grip
    }
    func setPose(_ pose: Pose) {
        guard !controlsLocked else { return }
        setManualTracking(false)
        let target = Pose(name: pose.name, joints: robot.clampPose(pose.joints), grip: clamp(pose.grip, 0, 90))
        let allowed = floor.limited(from: current, to: target, cube: cube)
        apply(allowed, immediately: true)
        status = allowed.joints == target.joints && allowed.grip == target.grip ? "\(pose.name) pose" : "Stopped at base plane"
    }
    func moveToPose(_ pose: Pose, completion: String? = nil) {
        guard !scriptedLocked else { return }
        setManualTracking(false)
        let requested = Pose(name: pose.name, joints: robot.clampPose(pose.joints), grip: clamp(pose.grip, 0, 90))
        let bounded = floor.limited(from: current, to: requested, cube: cube)
        let hitFloor = bounded.joints != requested.joints || bounded.grip != requested.grip
        completionStatus = hitFloor ? "Stopped at base plane · Move away to continue" : (completion ?? "\(pose.name) pose reached")
        if bounded.joints == current.joints && bounded.grip == current.grip { status = completionStatus; publishReadout(); return }
        isSequence = false; page = .simulator
        player.start([bounded], from: current); playback = .playing; activeWaypoint = nil; progress = 0
        status = "Moving to \(pose.name)"; publishReadout()
    }
    func reset() {
        stop(); controlMode = .scripted
        cube.restoreSpawn()
        apply(.startup, immediately: true)
        viewport?.syncCube(cube)
        resetCamera("Orbit"); traceRevision += 1; useCurrentTarget(); status = "Reset to folded startup position"
    }
    func resetCamera(_ name: String) { camera = name; cameraRevision += 1 }
    func useCurrentTarget() { let p = tcp; targetX = p.x; targetY = p.y; targetZ = p.z }
    func solve() {
        guard !scriptedLocked else { return }
        let result = robot.solve(
            target: SIMD3(targetX, targetY, targetZ) / 1000, initial: current.joints,
            keepLevel: keepLevel, cubeTopInTool: Grasp.cubeTopInTool(cube)
        )
        if result.success {
            let note = keepLevel ? " · level" : ""
            moveToPose(Pose(name: "target", joints: result.joints, grip: current.grip), completion: String(format: "Target reached · %.2f mm error%@", result.error * 1000, note))
        } else { status = keepLevel ? "No level solution within 2 mm / 5°. The pose was preserved." : "No solution within 2 mm from this pose. Try a closer target or another starting pose." }
    }
    func addWaypoint() {
        guard !controlsLocked else { return }
        waypoints.append(Pose(name: "Pose \(waypoints.count + 1)", joints: current.joints, grip: current.grip))
        status = "Pose added to sequence"
    }
    private func pause() { player.pause(); playback = .paused; publishReadout() }
    func playPause() {
        page = .simulator
        if playback == .playing { pause(); status = "Playback paused"; return }
        if playback == .paused { player.resume(); playback = .playing; status = "Playback resumed"; return }
        guard !waypoints.isEmpty, controlMode == .scripted else { return }
        setManualTracking(false)
        isSequence = true; completionStatus = "Sequence complete"
        var route = [Pose](), from = current
        for target in waypoints {
            let allowed = floor.limited(from: from, to: target, cube: cube)
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
        guard seconds.isFinite, seconds > 0 else { return }
        if playback == .playing {
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
        tickCubeGravity(seconds)
    }
    private func tickCubeGravity(_ dt: Double) {
        if cube.attached {
            cube.verticalVelocity = 0
            return
        }
        guard cube.integrateGravity(dt: dt) else { return }
        viewport?.syncCube(cube)
        readoutElapsed += max(0, dt)
        if readoutElapsed >= 1.0 / 15 { publishReadout() }
    }
    func stop() {
        setManualTracking(false)
        player.stop(); playback = .stopped; activeWaypoint = nil; progress = 0
        status = controlMode == .servo ? "Servo mode" : "Motion stopped"; publishReadout()
    }
    func enterServo() {
        stop(); setManualTracking(false); controlMode = .servo; page = .simulator; status = "Servo mode"; publishReadout()
    }
    func exitServo() {
        controlMode = .scripted
        if playback != .stopped { stop() }
        status = "Scripted mode"; publishReadout()
    }
    @discardableResult func servoTo(_ pose: Pose) -> Pose {
        guard controlMode == .servo, !manualMoving else { return current }
        setManualTracking(false)
        apply(pose, immediately: true)
        return current
    }
    func applyCube(_ next: CubeState) {
        cube = next
        if cube.attached {
            cube = Grasp.aligned(cube, endLink: robot.endLink(current.joints, grip: current.grip))
        } else {
            cube.restOnFloor()
        }
        viewport?.syncCube(cube)
        publishReadout()
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
