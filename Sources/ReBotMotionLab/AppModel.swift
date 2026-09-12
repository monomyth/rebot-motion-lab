import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RobotCore
import RobotControl
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
    static let cameras = SceneCamera.names
    @Published var camera = "Orbit"
    @Published var cameraRevision = 0
    @Published var traceRevision = 0
    @Published var targetX = 542.9
    @Published var targetY = 0.0
    @Published var targetZ = 409.3
    @Published var cubeX = 280.0
    @Published var cubeY = 0.0
    @Published var cubeSize = 40.0
    @Published var keepLevel = true
    @Published private(set) var controlMode: ControlMode = .scripted
    private(set) var cube = CubeState.spawn
    @Published var status = "Folded startup position · Select Ready to unfold"
    @Published var error: String?
    @Published var sceneReady = false
    @Published var sceneError: String?
    @Published private(set) var flyBrainRunning = false
    @Published private(set) var flyBrainStatus = "Place the cube, then run the fly brain."
    private var flyBrainProcess: Process?
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
    private var servoGoal: Pose?
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
        let links = robot.transforms(current.joints, grip: current.grip)
        Grasp.update(
            previousGrip: previousGrip, pose: current, cube: &cube, endLink: links["end_link"]!,
            leftFinger: links["finger_left_link"]!, rightFinger: links["finger_right_link"]!
        )
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
        stopFlyBrain()
        stop(); controlMode = .scripted
        cube.restoreSpawn()
        cubeX = cube.center.x * 1000
        cubeY = cube.center.y * 1000
        cubeSize = cube.size.x * 1000
        apply(.startup, immediately: true)
        viewport?.syncCube(cube)
        resetCamera("Orbit"); traceRevision += 1; useCurrentTarget(); status = "Reset to folded startup position"
    }
    func resetCamera(_ name: String) {
        camera = Self.cameras.contains(name) ? name : "Orbit"
        cameraRevision += 1
    }
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
            apply(player.current, immediately: false)
            let index = isSequence ? player.index : nil
            if activeWaypoint != index { activeWaypoint = index }
            readoutElapsed += max(0, seconds)
            if readoutElapsed >= 1.0 / 15 || player.state == .stopped { publishReadout() }
            if player.state == .stopped { playback = .stopped; status = completionStatus }
        } else if controlMode == .servo, player.state == .playing {
            // Same quintic interpolator as Play on the example sequence.
            player.advance(seconds: seconds, speed: 100)
            apply(player.current, immediately: false)
            readoutElapsed += max(0, seconds)
            if readoutElapsed >= 1.0 / 15 || player.state == .stopped { publishReadout() }
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
        servoGoal = nil
        player.stop(); playback = .stopped; activeWaypoint = nil; progress = 0
        status = controlMode == .servo ? "Servo mode" : "Motion stopped"; publishReadout()
    }
    func enterServo() {
        stop(); setManualTracking(false); controlMode = .servo; page = .simulator; status = "Servo mode"; publishReadout()
    }
    func exitServo() {
        servoGoal = nil
        player.stop()
        controlMode = .scripted
        if playback != .stopped { stop() }
        status = "Scripted mode"; publishReadout()
    }
    @discardableResult func servoTo(_ pose: Pose) -> Pose {
        guard controlMode == .servo, !manualMoving else { return current }
        setManualTracking(false)
        let allowed = floor.limited(from: current, to: pose, cube: cube)
        servoGoal = allowed
        if allowed.joints == current.joints, allowed.grip == current.grip {
            player.stop()
            return current
        }
        player.start([allowed], from: current)
        return allowed
    }
    func applyCube(_ next: CubeState) {
        cube = next
        if cube.attached {
            cube = Grasp.aligned(cube, endLink: robot.endLink(current.joints, grip: current.grip))
        } else {
            cube.sitOnFloor()
        }
        cubeX = cube.center.x * 1000
        cubeY = cube.center.y * 1000
        cubeSize = cube.size.x * 1000
        viewport?.syncCube(cube)
        publishReadout()
    }
    func placeCube() {
        guard !controlsLocked || flyBrainRunning else { return }
        do {
            let next = try cube.placing(
                center: SIMD3(cubeX, cubeY, 0) / 1000,
                size: SIMD3(repeating: cubeSize / 1000)
            )
            applyCube(next)
            status = String(format: "Cube placed · %.0f mm at %.0f, %.0f mm", cubeSize, cubeX, cubeY)
        } catch { self.error = error.localizedDescription }
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
    func startFlyBrain() { launchFlyBrainScript("scripts/run_policy.py") }

    func startFlyBrainLearn() { launchFlyBrainScript("scripts/run_learn.py") }

    private func launchFlyBrainScript(_ relative: String) {
        flyBrainStatus = "Starting \(relative)…"
        status = "Fly brain starting"
        try? "\(Date()) \(relative)\n".write(toFile: "/tmp/rebot-flybrain-ui.log", atomically: true, encoding: .utf8)
        guard !flyBrainRunning else { return }
        if !mcpControl.enabled { mcpControl.setEnabled(true) }
        guard let launch = FlyBrainLaunch.paths() else {
            error = "Fly brain controller not found. Expected /Users/monomyth/code/grok/fly-brain/controller/.venv."
            flyBrainStatus = "Controller not found."
            return
        }
        let script = launch.home.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: script.path) else {
            error = "Missing \(relative)"
            flyBrainStatus = error ?? ""
            return
        }
        let process = Process()
        // Keep the venv stub. Resolving the symlink jumps to Homebrew Python and drops site-packages.
        process.executableURL = launch.python
        process.arguments = [script.path, "--mcp", launch.mcp.path]
        process.currentDirectoryURL = launch.home
        var environment = ProcessInfo.processInfo.environment
        let venv = launch.home.appendingPathComponent(".venv").path
        environment["VIRTUAL_ENV"] = venv
        environment["PATH"] = "\(venv)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["REBOT_MCP_NO_LAUNCH"] = "1"
        environment["MALECNS_HOME"] = FlyBrainLaunch.malecnsHome
        environment["FLYBRAIN_DATA"] = FlyBrainLaunch.projectData
        environment["REBOT_CONTROL_DIRECTORY"] = LocalSocket.directory.path
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONPATH"] = launch.home.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let logURL = URL(fileURLWithPath: "/tmp/rebot-flybrain-ui.log")
        FileManager.default.createFile(atPath: logURL.path, contents: Data())
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let log = try? FileHandle(forWritingTo: logURL) {
                log.seekToEndOfFile()
                log.write(data)
                try? log.close()
            }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            let line = chunk.split(whereSeparator: \.isNewline).last.map(String.init) ?? chunk
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { @MainActor in
                self?.flyBrainStatus = String(line.prefix(240))
            }
        }
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                output.fileHandleForReading.readabilityHandler = nil
                if let leftover = try? output.fileHandleForReading.readToEnd(), let log = try? FileHandle(forWritingTo: logURL) {
                    log.seekToEndOfFile()
                    log.write(leftover)
                    try? log.close()
                }
                self.flyBrainProcess = nil
                self.flyBrainRunning = false
                if self.controlMode == .servo { self.exitServo() }
                let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                let tail = text.split(whereSeparator: \.isNewline).suffix(8).joined(separator: "\n")
                if finished.terminationStatus == 0 {
                    self.flyBrainStatus = "Fly brain finished."
                    self.status = "Fly brain finished"
                } else {
                    self.flyBrainStatus = tail.isEmpty ? "Fly brain exited \(finished.terminationStatus). See /tmp/rebot-flybrain-ui.log" : String(tail.prefix(500))
                    self.status = "Fly brain stopped"
                    self.error = self.flyBrainStatus
                }
            }
        }
        do {
            try process.run()
            flyBrainProcess = process
            flyBrainRunning = true
            flyBrainStatus = "Starting \(launch.python.lastPathComponent)…"
            status = "Fly brain starting"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stopFlyBrain() {
        guard let process = flyBrainProcess else {
            flyBrainRunning = false
            return
        }
        process.terminate()
        flyBrainProcess = nil
        flyBrainRunning = false
        if controlMode == .servo { exitServo() }
        flyBrainStatus = "Fly brain stopped."
        status = "Fly brain stopped"
    }

    func saveReference() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "B601-DM-actuator-settings.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(contentsOf: Assets.url("B601-DM-actuator-settings.md")).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}
