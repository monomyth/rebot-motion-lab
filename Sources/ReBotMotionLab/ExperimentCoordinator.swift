import Foundation
import AppKit
import Combine
import RobotCore
import RobotControl
import simd

@MainActor final class ExperimentCoordinator: ObservableObject {
    private unowned let model: AppModel
    @Published private(set) var enabled=false
    @Published private(set) var phase="disabled"
    @Published private(set) var cameras: [ObservationCamera]=[]
    @Published private(set) var displayRevision=0
    private(set) var scene: ManipulationScene?
    private(set) var task=ExperimentTask()
    private(set) var configuration=ExperimentTask()
    private(set) var episodeID=UUID().uuidString
    private(set) var frameID=0
    private(set) var evaluator=HoldEvaluator()
    private(set) var lease=ControllerLease()
    private(set) var elapsed=0.0
    private(set) var lastError: String?
    private var target: Pose?
    private var lastPhysicsTime=0.0
    private var lastReadout=0.0
    private var lastRecord=0.0
    private var lastImageRecord=0.0
    private var lastPose: Pose?
    private var jointVelocity=[Double](repeating:0,count:6)
    private var gripVelocity=0.0
    private var captureBusy=false
    private var setupTask: Task<Void,Never>?
    private let recorder=ExperimentRecorder()
    private(set) var recording=false
    private var observationCount=0
    private var actionCount=0
    private var startedWall=ProcessInfo.processInfo.systemUptime
    var hasOwner: Bool { lease.token != nil }
    var owner: String { hasOwner ? lease.provenance : model.playback == .stopped ? "manual" : "sequence" }
    init(model: AppModel) { self.model=model }

    func configure(_ configuration: ExperimentTask) throws {
        guard !captureBusy, !hasOwner, !model.hasMotion, phase != "configuring" else { throw ExperimentError.invalid("Stop motion, release the controller, and finish configuration/capture before configuring.") }
        let configuration=try configuration.validated(robot:model.robot,floor:model.floor)
        guard let viewport=model.viewport, model.sceneReady else { throw ExperimentError.invalid("Open Simulator and wait for the robot to load.") }
        if recording { _ = try recorder.stop(); recording=false }
        // Convex decomposition can take seconds. Accept setup immediately and yield during
        // native shape creation so the IPC and render thread remain responsive.
        phase="configuring"; lastError=nil; model.setExternalControlLock(true); scene?.setPaused(true)
        setupTask = Task { @MainActor in
            do {
                let next=try await ManipulationScene(viewport:viewport,robot:model.robot,task:configuration)
                guard !Task.isCancelled else { next.remove(); return }
                let views = try ["Front","Top"].map { try ObservationCamera(name:$0,source:viewport) }
                scene?.remove(); scene=next; self.configuration=configuration; task=configuration; cameras=views; enabled=true; phase="configured"
                model.page = .simulator
                try reset()
            } catch {
                guard !Task.isCancelled else { return }
                phase="invalid"; lastError=error.localizedDescription; model.setExternalControlLock(false)
            }
        }
    }
    func reset(seed: UInt64? = nil) throws {
        guard !captureBusy, phase != "configuring", let scene else { throw ExperimentError.invalid("Configure an experiment and finish image capture before reset.") }
        let trial=try configuration.episode(seed:seed).validated(robot:model.robot,floor:model.floor)
        task=trial
        lease.release(); target=nil
        model.setExternalControlLock(false)
        model.stopPlaybackOnly()
        let pose=Pose(name:"Experiment initial",joints:task.initialJoints,grip:task.initialGripperMM)
        model.applyExperimentPose(pose)
        scene.reset(task:task,pose:pose)
        episodeID=UUID().uuidString; frameID=0; elapsed=0; evaluator=HoldEvaluator(); lastPhysicsTime=0; lastReadout=0; lastRecord=0; lastImageRecord=0
        lastPose=pose; jointVelocity=Array(repeating:0,count:6); gripVelocity=0; lastError=nil; phase="settling"
        scene.setPaused(false); startedWall=ProcessInfo.processInfo.systemUptime; actionCount=0; observationCount=0
        recorder.append(["type":"reset","episode_id":episodeID,"task":try jsonObject(task)])
        updateCameras(); displayRevision += 1
    }
    func disable() throws {
        guard !captureBusy, phase != "configuring" else { throw ExperimentError.invalid("Finish configuration/image capture before disabling.") }
        stopArm(reason:"disabled"); scene?.remove(); scene=nil; cameras=[]; enabled=false; phase="disabled"
        if recording { _ = try recorder.stop(); recording=false }
    }
    func stopArm(reason: String) {
        if phase == "configuring" {
            setupTask?.cancel(); setupTask=nil; model.setExternalControlLock(false)
            phase=enabled ? "paused" : "disabled"; lastError="Experiment setup cancelled."
            return
        }
        guard enabled else { return }
        target=nil; lease.release()
        model.setExternalControlLock(false)
        recorder.append(["type":"stop_arm","reason":reason,"episode_id":episodeID,"frame_id":frameID,"time":elapsed])
        displayRevision += 1
    }
    func pause() {
        guard enabled, phase != "paused", phase != "configuring" else { return }
        stopArm(reason:"paused"); model.stopPlaybackOnly(); scene?.setPaused(true); phase="paused"
    }
    func limit(_ pose: Pose) -> Pose { scene?.limitGrip(pose) ?? pose }

    func advance() {
        guard enabled, phase != "configuring", let scene else { return }
        let now=ProcessInfo.processInfo.systemUptime
        if lease.expired(now:now) { stopArm(reason:"controller_timeout"); lastError="Controller heartbeat expired; arm stopped." }
        let time=scene.time, dt=time-lastPhysicsTime; lastPhysicsTime=time
        guard dt > 0, dt.isFinite else { return }
        frameID += 1
        if let target, hasOwner, ["running","completed"].contains(phase) {
            let seconds=min(dt,1.0/30)
            let delta=zip(model.current.joints,target.joints).map { $1-$0 }
            let maximum=delta.map(abs).max() ?? 0
            let fraction=maximum > 0 ? min(1,30*seconds/maximum) : 1
            let joints=zip(model.current.joints,delta).map { $0+$1*fraction }
            let grip=model.current.grip+clamp(target.grip-model.current.grip,-25*seconds,25*seconds)
            let proposed=Pose(name:"Controller",joints:joints,grip:grip)
            let bounded=model.floor.limited(from:model.current,to:proposed)
            model.applyExperimentPose(scene.limitGrip(bounded))
        }
        scene.syncRobot(model.current,dt:min(dt,0.05))
        if let previous=lastPose {
            jointVelocity=zip(model.current.joints,previous.joints).map { ($0-$1)/dt }
            gripVelocity=(model.current.grip-previous.grip)/dt
        }
        lastPose=model.current
        let sample=scene.sample()
        if ![Double(scene.cube.position.x),Double(scene.cube.position.y),Double(scene.cube.position.z),sample.clearanceMM,sample.tiltDeg,sample.linearSpeedMM,sample.angularSpeedDeg].allSatisfy(\.isFinite) {
            phase="physics_error"; lastError="Non-finite physics state; episode paused. Reset before continuing."
            stopArm(reason:"physics_error"); scene.setPaused(true); return
        }
        if phase == "settling", time >= 0.5 {
            let p=scene.cubePose.positionMM, expected=task.initialCubePose.positionMM
            if simd_distance(vector(p),vector(expected)) > 5 {
                phase="invalid"; lastError="Cube displaced during settling. Choose a clear initial placement."; scene.setPaused(true)
            } else { phase="ready" }
        }
        if phase == "running" {
            elapsed += dt
            let priorHold=evaluator.holdSeconds
            evaluator.update(sample,dt:dt,running:true,task:task)
            if priorHold > 0, evaluator.holdSeconds == 0 {
                recorder.append(["type":"hold_interrupted","prior_hold_seconds":priorHold,"sample":evaluation()])
            }
            if evaluator.success { phase="completed"; target=nil; recorder.append(["type":"success","episode_id":episodeID,"time":elapsed]) }
            else if elapsed >= task.timeoutSeconds { phase="timeout"; stopArm(reason:"timeout") }
            else if abs(scene.cube.position.x) > 1 || abs(scene.cube.position.y) > 1 || scene.cube.position.z < -0.05 {
                phase="workspace_violation"; stopArm(reason:"workspace_violation")
            }
        }
        if !captureBusy, now-lastReadout >= 0.1 { updateCameras(); displayRevision += 1; lastReadout=now }
        if recording, time-lastRecord >= 0.1 {
            recorder.append(["type":"telemetry","policy":observation(),"evaluator":evaluation(),"provenance":owner])
            lastRecord=time
        }
        if recording, !hasOwner, !captureBusy, phase != "settling", time-lastImageRecord >= 0.5 {
            lastImageRecord=time
            Task { @MainActor in
                do { _ = try await captureObservation() }
                catch { lastError="Recording camera: \(error.localizedDescription)" }
            }
        }
    }
    private func updateCameras() {
        guard let scene else { return }
        for camera in cameras { camera.update(pose:model.current,definition:model.robot.definition,cube:scene.cube) }
    }
    func observation() -> [String:Any] {
        var result:[String:Any] = ["episode_id":episodeID,"frame_id":frameID,"simulation_time":scene?.time ?? 0,
            "task_time":elapsed,"phase":phase,"input_mode":task.inputMode,"world_frame":"robot_base_Z_up",
            "goal":["clearance_mm":task.liftClearanceMM,"tilt_tolerance_deg":task.tiltToleranceDeg,"hold_seconds":task.holdSeconds],
            "grasp_offset_tool_mm":[-20,0,0],
            "joints_deg":model.current.joints,"joint_velocity_deg_s":jointVelocity,"gripper_mm":model.current.grip,
            "gripper_velocity_mm_s":gripVelocity,"tool_pose":(try? jsonObject(CartesianPose(model.robot.toolTransform(model.current.joints)))) ?? [:],
            "grasp_pose":(try? jsonObject(CartesianPose(model.robot.toolTransform(model.current.joints,frame:"grasp")))) ?? [:],
            "finger_contacts":["left":scene?.contacts.contains("finger_left_link") ?? false,"right":scene?.contacts.contains("finger_right_link") ?? false],
            "owner":owner,"last_action_id":lease.lastActionID,"camera_calibration":cameras.map(\.calibration)]
        if task.inputMode == "state", let scene { result["cube_pose"]=try? jsonObject(scene.cubePose) }
        return result
    }
    func evaluation() -> [String:Any] {
        if phase == "physics_error" { return ["phase":phase,"episode_id":episodeID,"frame_id":frameID,"error":lastError ?? "Physics error","success":false] }
        guard let scene else { return ["phase":phase,"error":lastError as Any? ?? NSNull()] }
        let sample=scene.sample()
        return ["episode_id":episodeID,"frame_id":frameID,"phase":phase,"task_time":elapsed,
                "cube_pose":(try? jsonObject(scene.cubePose)) ?? [:],"clearance_mm":sample.clearanceMM,"tilt_deg":sample.tiltDeg,
                "linear_speed_mm_s":sample.linearSpeedMM,"angular_speed_deg_s":sample.angularSpeedDeg,
                "velocity_measurement":"finite differences of post-physics cube poses", "solver_velocities":scene.solverVelocities,
                "contacts":scene.contacts.sorted(),"contact_impulse_Ns":scene.impulses,"held":sample.leftContact && sample.rightContact && !sample.otherSupport,
                "hold_seconds":evaluator.holdSeconds,"success":evaluator.success,"dropped":evaluator.dropped,
                "error":lastError as Any? ?? NSNull(),"capture_in_progress":captureBusy,"backend":"RealityKit dynamic cube / kinematic robot",
                "grasp_mode":"contact_friction","recording":recording,"owner":owner,
                "physics_steps":scene.physicsSteps,"observations":observationCount,"actions":actionCount,"wall_seconds":ProcessInfo.processInfo.systemUptime-startedWall]
    }
    func captureObservation() async throws -> [String:Any] {
        guard enabled, !captureBusy, !["settling","configuring","invalid","physics_error"].contains(phase), let scene else { throw ExperimentError.invalid("Observation not ready or capture already in progress.") }
        captureBusy=true; defer { captureBusy=false }
        let capturedEpisode=episodeID, start=ProcessInfo.processInfo.systemUptime
        var result=observation()
        for camera in cameras { camera.update(pose:model.current,definition:model.robot.definition,cube:scene.cube) }
        // All render copies now contain the same frozen pose. Physics can continue independently.
        var frames=[[String:Any]]()
        for camera in cameras { frames.append(try await camera.capture()) }
        guard capturedEpisode == episodeID else { throw ExperimentError.invalid("Episode changed while capturing.") }
        result["images"]=frames; result["capture_latency_seconds"]=ProcessInfo.processInfo.systemUptime-start
        result["image_state_skew_seconds"]=0.0; observationCount += 1
        recorder.append(["type":"observation","policy":result,"provenance":owner])
        return result
    }
    func handle(_ name: String, _ args: [String:Any]) throws -> [String:Any] {
        switch name {
        case "rebot_configure_task":
            guard let patch=args["task"] as? [String:Any] else { throw ExperimentError.invalid("Task is required.") }
            var values=try jsonObject(ExperimentTask()); patch.forEach { values[$0]=$1 }
            let next=try JSONDecoder().decode(ExperimentTask.self,from:JSONSerialization.data(withJSONObject:values))
            try configure(next); return ["accepted":true,"task":try jsonObject(next),"state":evaluation()]
        case "rebot_get_task": return ["task":try jsonObject(task),"configuration":try jsonObject(configuration),"capabilities":["backend":"RealityKit","fixed_step":false,"rgb":true,"depth":false,"segmentation":false,"hardware":false,"external_control":true],"state":evaluation()]
        case "rebot_reset_episode": try reset(seed:(args["seed"] as? NSNumber)?.uint64Value); return evaluation()
        case "rebot_get_observation":
            guard enabled, !["settling","configuring","invalid","physics_error"].contains(phase) else { throw ExperimentError.invalid("Wait for episode configuration/reset/settling.") }
            observationCount += 1; return observation()
        case "rebot_get_evaluation": return evaluation()
        case "rebot_experiment_control":
            guard enabled else { throw ExperimentError.invalid("Configure the experiment first.") }
            switch args["action"] as? String {
            case "start":
                guard phase == "ready" else { throw ExperimentError.invalid("Start requires a ready episode. Reset a finished episode first.") }
                elapsed=0; phase="running"; scene?.setPaused(false)
            case "pause": pause()
            case "resume":
                guard phase == "paused" else { throw ExperimentError.invalid("Episode is not paused.") }
                phase="running"; lastPhysicsTime=scene?.time ?? 0; scene?.setPaused(false)
            case "stop": stopArm(reason:"explicit_stop"); model.stopPlaybackOnly(); phase="stopped"
            case "takeover": stopArm(reason:"manual_takeover"); model.stopPlaybackOnly()
            case "disable": try disable()
            default: throw ExperimentError.invalid("Unknown experiment action.")
            }
            return evaluation()
        case "rebot_controller_connect":
            guard enabled, phase == "running", !model.hasMotion else { throw ExperimentError.invalid("Start an episode and stop other motion before connecting.") }
            let token=try lease.acquire(episode:episodeID,provenance:args["provenance"] as! String,modelID:args["model_id"] as! String,now:ProcessInfo.processInfo.systemUptime)
            target=model.current
            model.setExternalControlLock(true)
            recorder.append(["type":"controller_connected","episode_id":episodeID,"provenance":lease.provenance,"model_id":lease.modelID])
            displayRevision += 1
            return ["token":token,"episode_id":episodeID,"heartbeat_timeout_seconds":2,"observation":observation()]
        case "rebot_controller_action":
            guard enabled, ["running","completed"].contains(phase) else { throw ExperimentError.invalid("Controller actions require a running or completed episode.") }
            let q=args["joints_deg"] as! [Double], grip=args["gripper_mm"] as! Double
            guard q == model.robot.clampPose(q) else { throw ExperimentError.invalid("Joint target is outside limits.") }
            // Validate everything before consuming the monotonically increasing action ID.
            let requested=Pose(name:"external",joints:q,grip:grip)
            guard model.floor.isAllowed(requested) else { throw ExperimentError.invalid("Requested endpoint intersects the floor.") }
            try lease.validate(token:args["token"] as! String,episode:args["episode_id"] as! String,actionID:args["action_id"] as! Int,
                               observedFrame:args["observed_frame_id"] as! Int,currentFrame:frameID,now:ProcessInfo.processInfo.systemUptime)
            target=requested; actionCount += 1
            recorder.append(["type":"action","episode_id":episodeID,"frame_id":frameID,"simulation_time":scene?.time ?? 0,
                             "action_id":lease.lastActionID,"requested_joints_deg":q,"requested_gripper_mm":grip,"executed":observation(),"provenance":owner,"model_id":lease.modelID])
            return ["accepted":true,"completed":false,"observation":observation()]
        case "rebot_solve_pose", "rebot_move_to_pose":
            let pose=try decodePose(args["pose"] as! [String:Any])
            let solution=try model.robot.solvePose(target:pose,initial:model.current.joints,frame:args["frame"] as? String ?? "grasp")
            guard solution.success else { throw ExperimentError.invalid("No pose IK solution within 2 mm / 1 degree. Position and angular errors: \(solution.positionErrorMM), \(solution.orientationErrorDeg)") }
            let candidate=Pose(name:"Pose target",joints:solution.joints,grip:args["gripper_mm"] as? Double ?? model.current.grip)
            guard model.floor.isAllowed(candidate) else { throw ExperimentError.invalid("Pose solution intersects the floor.") }
            if name == "rebot_move_to_pose" {
                guard !model.hasMotion else { throw ExperimentError.invalid("Release external control and stop motion first.") }
                model.moveToPose(candidate)
            }
            return ["joints_deg":solution.joints,"position_error_mm":solution.positionErrorMM,"orientation_error_deg":solution.orientationErrorDeg,"accepted":true]
        case "rebot_recording":
            if args["action"] as? String == "start" {
                guard enabled else { throw ExperimentError.invalid("Configure experiment before recording.") }
                let path=try recorder.start(manifest:["schema":"rebot-experiment-v1","task":try jsonObject(task),"episode_id":episodeID,
                    "simulator_version":ControlCatalog.version,"created_at":ISO8601DateFormatter().string(from:Date()),"cameras":cameras.map(\.calibration),
                    "backend":"RealityKit","determinism":"seeded setup, real-time physics; not bitwise deterministic","input_mode":task.inputMode,
                    "grasp_mode":"contact_friction","grasp_offset_tool_mm":[-20,0,0],"policy_reward_input":false,
                    "recording_channels":"10 Hz telemetry; manual/sequence RGB up to 2 Hz; external RGB whenever requested",
                    "velocity_measurement":"post-physics pose differences; raw solver velocities separately logged"])
                recording=true; return ["directory":path,"recording":true]
            }
            recording=false; return try recorder.stop()
        default: throw ExperimentError.invalid("Unknown experiment tool.")
        }
    }
}

func jsonObject<T: Encodable>(_ value: T) throws -> [String:Any] {
    try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]
}
func decodePose(_ object:[String:Any]) throws -> CartesianPose {
    try JSONDecoder().decode(CartesianPose.self,from:JSONSerialization.data(withJSONObject:object)).validated()
}
