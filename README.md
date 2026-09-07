# ReBot B601-DM Motion Lab

A browser-based kinematic simulator using the Seeed B601-DM robot model.

## Run locally

Requires Node.js 22.13 or later.

```sh
npm install
npm run dev
```

Open the URL printed by the development server. Build for deployment with `npm run build`.

## Controls

- Drag to orbit, right-drag to pan, scroll to zoom. Use Orbit, Front or Top to reset the camera.
- Move the six joint sliders or enter joint angles in degrees. Angles are constrained to the published URDF limits.
- Set the nominal gripper opening from 0 to 90 mm. The two finger joints move symmetrically.
- Enter a target X/Y/Z in millimeters relative to the base. The position-only damped least-squares solver accepts errors below 2 mm; failed solutions leave the pose unchanged. Wrist orientation is unconstrained.
- Record the current pose, remove waypoints, or play the sample sequence. Playback uses quintic interpolation with a nominal maximum joint speed of 60 degrees/s at 100% playback speed. Pause/resume preserves progress; Stop or Escape stops at the current pose. Reset immediately restores the ready pose.
- Export a sequence as JSON. Poses remain in memory until the page reloads. The file is a simulator interchange format, not a hardware control program.

The simulator models forward and inverse kinematics. It does not calculate contact, self-collisions, dynamics, gravity, torque, payload behavior, or physical grasping. It has no hardware connection.

## Model provenance

URDF and colored STL geometry are from [Seeed-Projects/reBot-DevArm](https://github.com/Seeed-Projects/reBot-DevArm), commit `c9b893aa26c7d89019dd3d0a28ff8f6a7d47ccf9`. Their CERN-OHL-W-2.0 license and notices are retained under `public/model/`. `model.json` is a mechanical browser-friendly conversion of the included URDF, with the same license. Tool-center position uses the source `end_link` frame, at the gripper tips.

[Seeed's simulator guide](https://wiki.seeedstudio.com/rebot_arm_b601_dm_web_simulator_developer_guide/) describes the full ROS2/MuJoCo stack for dynamics and hardware integration.

## Verification

```sh
npx tsc --noEmit
npx oxlint app lib/robot.ts lib/motion.ts
mkdir -p work
npx esbuild tests/kinematics.ts --bundle --platform=node --format=esm --outfile=work/kinematics.mjs
node work/kinematics.mjs
```

The kinematics checks cover base rotation, finger mimic behavior, pose heights, reachable and unreachable IK targets, joint bounds, solver state preservation, interpolation endpoints, velocity limits, and STL file integrity.

## Actuator reference

The separate `/actuators` page documents all 53 Damiao registers in the pinned MotorBridge register table, every field in the published Seeed B601-DM hardware YAML, motion-command fields, per-joint gains, firmware caveats, and maintenance operations. It is read-only and does not apply settings. A standalone Markdown copy is served at `/B601-DM-actuator-settings.md`.

The reference distinguishes software defaults from actual hardware readback, covers 26 writable and 27 read-only registers, and flags the published `kd = 8` versus encoded `kd <= 5` discrepancy. Firmware support and unknown raw units remain explicitly qualified. Source links are pinned in `lib/actuators.json`.
