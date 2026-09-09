# Cube pickup environment for external neural controllers

This branch implements the native simulator side of the MaleCNS experiment proposal. The arm remains kinematic. The cube is a dynamic RealityKit rigid body with gravity and frictional contacts. No cube attachment, parenting-to-gripper, or hidden grasp animation is used.

The app is packaged as **ReBot Motion Lab Codex.app**, bundle identifier `local.rebot.motionlab.flycodex`. Its default socket directory is `rebot-motionlab-codex-<uid>` under the per-user Darwin temporary directory, allowing the original app to coexist. `REBOT_CONTROL_DIRECTORY` still overrides it for isolated runs.

The app-generated Codex registration is `[mcp_servers.rebot-motion-lab-codex]`; other MCP clients use the same server key. The stdio handshake reports `rebot-motion-lab-codex`.

Standard kinematic mode supports macOS 14+. Manipulation experiments require macOS 15+ for public RealityKit physics clocks and physics-step callbacks. Unsupported systems return an experiment setup error while retaining the original simulator.

## Quick start

1. Build with `bash scripts/build-app.sh ./dist` and open the resulting Codex app.
2. In Simulator, expand **Cube pickup experiment**, select observations, and choose **Set up cube**. Wait for Ready. Use **Apply cube** to change X/Y, yaw, or size later, or **Place with mouse** to click a clear floor point in Top view. Cube sides are bounded to 10–90 mm (1–9 cm). Setup builds compound convex colliders asynchronously.
3. Choose Front or Top in the existing viewing controls. The two smaller observation views stay fixed independently of that spectator camera.
4. Start an episode, record a demonstration, or connect an external controller. Use **Stop arm / Take over** to return control to the sliders. **Pause** freezes the whole experiment. **Reset** restores the configured starting state.
5. Save/load task JSON separately from ordinary trajectory JSON. Use Record / Stop recording to obtain a private recording directory.

Robot geometry, joint limits, instantaneous manual slider updates, floor protection for every moving mesh, and legacy trajectory interpolation are retained. Physics colliders use a compound of convex shapes generated from each visual part. This approximates concave geometry and is not a robot actuator or torque model. Robot self-collision remains outside this implementation.

## Coordinate and observation contract

- World and robot base coincide: right-handed, Z up, meters internally.
- API positions and apertures: millimeters. Joint angles and angular readouts: degrees.
- Quaternions: unit `[x, y, z, w]`; `q` and `-q` represent the same orientation.
- `tool`: source URDF `end_link`, at the fingertip center at closed aperture.
- `grasp`: 20 mm behind the tool along its local X axis, between the fingers.
- The existing floor top is at Z = −1 mm. An upright 50 mm cube starts with center Z = 24 mm.
- Initial cube yaw rotates about world Z. Its marked local +Z face defines levelness.

`rebot_get_observation` returns one episode/frame ID, physics time, task time, actual rendered joints, derived joint velocities, aperture, tool/grasp poses, finger contacts, and camera calibration. `input_mode: state` also includes exact cube pose. `input_mode: vision` omits it.

`rebot_get_task`, `rebot_get_state`, and `rebot_get_evaluation` are privileged setup/evaluator interfaces. Their cube state must not enter a policy run described as vision-only. The sample policy runner supplies only `get_observation` output to the policy. This is an experimental information boundary, not an access-control boundary against another program owned by the same user.

For `images: true`, the policy observation contains two JPEGs and calibration. Images are exactly **320 × 240 pixels**, independent of Retina backing scale. Intrinsics are pixel units with origin at top left; the camera frame is right +X, up +Y, viewing along −Z. `world_from_camera` is a row-major 4 × 4 matrix with translations in meters.

At capture start, both render-only scene copies receive the same frozen robot and cube poses as the telemetry. Independent snapshot completion times do not change their content. `image_state_skew_seconds` is zero for these copies; `capture_latency_seconds` reports the later delivery time. Cube visibility can be occluded by the arm in a particular view. Spectator overlays are excluded. Capture requires the observation views to remain attached in Simulator and has a bounded timeout.

Depth, segmentation, accelerated stepping, and a browser controller endpoint are not advertised. `get_task.capabilities` reports these as unsupported. They were optional later milestones in the proposal.

## Physics, grasp, and timing

The cube's mass, friction, and size are configurable. The floor is static and the robot collision bodies are kinematic. Collider velocities are applied in `PhysicsSimulationEvents.WillSimulate` using the physics timestep, and state is measured after `DidSimulate`. Display refresh does not supply the physics timestep.

The geometric jaw stop prevents a close command from passing through an enclosed cube. A 0.1 mm total preload supplies contact to the solver. It never widens the requested aperture or attaches the cube. Opening releases the cube, and gravity remains enabled after arm stop or controller timeout.

Task stability uses finite differences of post-physics cube poses. RealityKit's raw solver velocities can contain contact-correction motion even while the resolved pose is stationary; they are separately exported under `solver_velocities`. Contact impulses are reported in N·s, not mislabelled as force. These measurements do not validate real gripper force, load limits, or actuator dynamics.

Physics is real time and is not claimed to be bitwise deterministic. `seed` controls optional uniform XY placement jitter (`placement_jitter_mm`, 0–20 mm per axis), not RealityKit's solver. Reset with the same seed reproduces the initial placement; a different seed changes it when jitter is enabled. Every sampled setup is validated to keep its full footprint on the floor and its initial robot pose clear of the floor. Cube placement is independent of arm reach; reachability and approach clearance are checked when requesting motion. Reset invalidates the controller token and clears velocities, contacts, queued targets, neural-session ownership, and evaluation counters, then reports `settling` until the scene is ready. The external process must reset its own neural state.

`get_task.configuration` is the saved task recipe; `get_task.task` is the current sampled episode. Setup validation is distinct from control failure. A cube displaced during initial settling produces `phase: invalid`.

Pause freezes physics time and stops arm commands; resume requires reacquiring external control. Stop/takeover stops commands while cube physics continues. Navigating away from Simulator pauses the experiment. A finished success remains in the episode result; subsequent intentional release does not erase it. Reset starts a new result.

## Added MCP tools

The original 12 tools and two resources remain. The 12 additional tools are:

| Tool | Inputs / result |
| --- | --- |
| `rebot_configure_task` | `task` overrides defaults; returns setup acceptance. Poll phase until ready/invalid. |
| `rebot_get_task` | Recipe, sampled task, size/floor limits, capabilities, and evaluator state. |
| `rebot_place_cube` | `x_mm`, `y_mm`, optional `size_mm` and `yaw_deg`; place/resize on the floor while preserving the arm pose. |
| `rebot_reset_episode` | Optional `seed`; invalidates the old controller session. |
| `rebot_get_observation` | Optional `images` boolean; policy observations. |
| `rebot_get_evaluation` | Privileged cube pose, motion, contact, score, and status. |
| `rebot_experiment_control` | `action`: start, pause, resume, stop, takeover, or disable. |
| `rebot_controller_connect` | `provenance` and `model_id`; returns episode-scoped token. |
| `rebot_controller_action` | Token, episode ID, increasing action ID, observed frame ID, six joint targets, and gripper target. |
| `rebot_solve_pose` | `pose: {position_mm, quaternion_xyzw}`, optional frame/tool aperture; solve without moving. |
| `rebot_move_to_pose` | Same pose schema; ordinary eased movement, requiring stopped motion and no external owner. |
| `rebot_recording` | `action: start` or `stop`; private recording directory and completion status. |

The pose frame defaults to `grasp`. Full-pose IK must converge within 2 mm and 1 degree. Both position and orientation error are returned. Joint targets are validated against limits and floor-clear endpoints; execution checks the swept floor path and geometric jaw stop. An obstructed move may stop before its target, so inspect actual observations. Cube interaction is handled by the running contact simulation.

Controller sessions accept new targets while running. All joint deltas use a common rate-limiting fraction, preserving coordinated motion, with a maximum of 30°/s per joint and 25 mm/s aperture change. This mode does not replace legacy quintic interpolation or add lag to manual sliders. Only one external controller owns motion. Manual controls are locked during ownership; explicit takeover restores them.

Each action must refer to the current episode and a non-future observation no more than 120 frames old. Action IDs increase strictly; duplicates and expired tokens are rejected without consuming another action. Submit an action within two seconds to retain the lease. Repeating the current target acts as a heartbeat. Acceptance does not mean the target was reached. No automatic retry of uncertain motion commands is performed.

All IPC remains local and same-user, bounded to 1 MiB with I/O timeouts. Use the direct Unix socket client for frequent actions and MCP for orchestration. JPEG observations fit the bound; no public HTTP endpoint is introduced.

## External-controller examples

`examples/controller_client.py` implements the private socket protocol using Python's standard library, including peer UID verification. It contains an explicitly privileged conventional pickup baseline for environment verification.

`examples/run_policy.py` loads a user-provided `module:factory`. The object must implement:

```python
class Policy:
    def reset(self, observation):
        # Reset neuron state for this episode.
        ...

    def act(self, observation):
        # Encode observation, update your neural model, decode its activity.
        return {"joints_deg": six_joint_angles, "gripper_mm": opening}
```

Run against an already configured simulator:

```sh
python3 examples/run_policy.py \
  --control-directory /path/to/private/control-directory \
  --policy my_fly_controller:create_policy \
  --model-id malecns-v1-preprocessing-hash-checkpoint-id \
  --provenance malecns
```

The policy must finish inference and submit actions within the lease timeout. `--state-only` is accepted only for a state-assisted task. Dataset loading, neural dynamics, encoder/decoder training, and neural ablation experiments belong in the external project. No MaleCNS checkpoint or trained neural controller is bundled, and the conventional baseline is not labelled as fly control.

## Scoring and recordings

Default success: the cube's lowest point is at least 100 mm above the floor, tilt is at most 5°, measured linear speed is at most 15 mm/s, angular speed is at most 10°/s, and both fingers support it with no other support for five consecutive simulated seconds. Paused time does not count; interrupted or unobserved intervals reset the hold timer. Transient upward motion and a closed empty gripper cannot pass. Timeout, workspace violation, and a drop during an active episode are recorded separately.

Recordings contain `manifest.json` and bounded asynchronous `events.jsonl`: setup, actions, executed observations, evaluator telemetry, controller provenance/model ID, camera calibration, and timestamps. Telemetry is recorded at up to 10 Hz. Manual/sequence runs request RGB at up to 2 Hz; external runs record every explicitly requested image observation. The conventional baseline requests images during motion for demonstration training. Queue overflow or disk errors mark a run incomplete.

```sh
python3 examples/replay_recording.py /path/to/recording --frames /tmp/recorded-frames
```

This exports recorded frames and summarizes events. It does not claim to reproduce the physics by resimulation. Model IDs should identify the external checkpoint and connectome preprocessing, and provenance must distinguish `conventional`, `teacher_assisted`, and `malecns`.

## Verification

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh ./dist
python3 scripts/test-mcp.py "dist/ReBot Motion Lab Codex.app" /tmp/rebot-mcp-check
python3 scripts/verify-experiment.py \
  "dist/ReBot Motion Lab Codex.app/Contents/MacOS/ReBotMotionLab" /tmp/rebot-fly-check
```

The native experiment verifier launches only its own app and private socket, drives the conventional controller through the public IPC, captures front/top images, verifies contact pickup and five-second holding, releases the cube, checks controller timeout and reset, and checks vision-mode input isolation. `--cube-x`, `--cube-y`, and `--cube-yaw` select additional placements. It cleans up only its own process. Native checks require a working macOS window/renderer.

Run the existing `--smoke-test` and `--performance-check` harnesses for the original UI and immediate slider behaviour. Examine native images and measurement reports in addition to unit tests. A successful conventional trial proves environment readiness for that configuration; it does not prove MaleCNS learning, robustness to every grasp, or transfer to hardware.

## Repositioning and resizing

The existing floor is 4 m × 4 m, centered at the robot base. Cube centers can use any X/Y for which the complete rotated cube footprint fits on that surface, including positions outside the arm's reach. Cube side length is 10–90 mm inclusive; 90 mm is the fully open gripper limit, independent of its current aperture. A conservative check against per-part robot collision bounds rejects occupied locations before changing the scene.

After setup, edit **Cube X mm**, **Cube Y mm**, **Cube side mm**, and yaw, then press **Apply cube**. **Place with mouse** switches to Top view and arms the next floor click using the entered side and yaw. Shift-drag/right-drag pans, scrolling zooms, and Escape cancels placement. Coordinate fields synchronize after mouse/MCP placement and reset.

Through MCP:

```json
{
  "name": "rebot_place_cube",
  "arguments": {"x_mm": 450, "y_mm": -100, "size_mm": 30, "yaw_deg": 0}
}
```

Changing the cube rebuilds only its rendered/physical body, preserves the current arm joints/aperture and other task settings, clears placement jitter, and starts a fresh episode with the cube resting on the floor. Reset remembers the new cube settings and restores the configured initial robot pose. Stop motion, external control, and recording before editing. Rejected dimensions, occupied positions, and off-floor footprints leave the previous episode and cube unchanged.

Run `python3 scripts/verify-cube-edit.py "dist/ReBot Motion Lab Codex.app" /tmp/rebot-cube-check` to verify both size limits, far-floor placement, dimensions in the actual collider, arm-state preservation, rejection, reset, and a pickup regression through MCP.
