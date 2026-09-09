# Changelog

## 1.6.0 — 2026-09-09

- Added a kinematic scene cube on the base plane (default 40 mm at 280 mm forward), MCP `rebot_set_cube`, and reset-to-spawn.
- Closing the gripper in the fingertip AABB attaches the cube; opening releases it onto the plane. A held cube participates in floor stops. No payload physics.
- Added level IK (`rebot_move_to_pose`, Keep tool level) so the tool or attached cube stays within 5° of world vertical. State reports `tcp_rpy_deg` and `tcp_level`.
- Added `rebot_capture_view` JPEG snapshots of the RealityKit camera (default 320×240) for Front/Top/Orbit without stealing the user view unless `apply` is true. Top/Front framing includes the default cube.
- Added servo mode (`rebot_set_control_mode`, `rebot_servo_joints`, `rebot_servo_tcp`) for immediate closed-loop pose updates. Scripted quintic tools remain the default.
- MCP catalog version 1.6 with 18 tools. Client registration id is `rebot-motion-lab-grok` so it does not collide with the original lab. Web simulator shows the same default cube (visual only).
- Unattached cubes fall under gravity onto the base plane (no bounce). Held cubes still follow the tool kinematically.

## 1.5.0 — 2026-09-07

- Hide private install directories in both MCP configuration previews while copying a working configuration with the full executable path.
- Unified the web simulator, native Swift app, and native MCP server in one repository, preserving both source histories.
- Added solid base-plane stops for all moving geometry, including both gripper fingertips, with immediate slider clamping and swept-path checks.
- Added matching Swift/web collision tests and web CI.
- Kept idle joint controls synchronized after Reset, presets, playback, and MCP moves without rebuilding the full control panel during dragging.
- Joint and gripper sliders apply the rendered pose immediately. Interactive dragging no longer uses a 100 ms damped chase or a SwiftUI `Slider` bound to a republishing observable object.

## 1.4.0 — 2026-09-07

Earlier native source milestone. The application reported version 1.4; the initial public repository includes the newer 1.5 changes above.

### Simulator

- Native SwiftUI/AppKit interface and RealityKit rendering of the B601-DM.
- Smooth manual joint/gripper controls with continuous retargeting and separate target/readout state.
- Folded startup, closed gripper, and smooth Folded, Ready, Reach, and Upright presets.
- Position-only inverse kinematics, tool coordinates, camera controls, axes, grid, and TCP trace.
- Named waypoint sequences with play/pause/resume/stop, speed control, and JSON import/export.
- Persistent text-size controls, including ⌘+, ⌘−, and ⌘0.

### Reference and MCP

- Offline actuator reference with 53 documented registers and pinned primary sources.
- Native MCP stdio server with 12 tools and two resources.
- Same-user private socket transport, bounds validation, manual-motion state, and overlapping-command rejection.

### Distribution

- Universal Intel/Apple silicon macOS application and complete Swift source.
- MIT application license with preserved CERN-OHL-W-2.0 model and MIT metadata notices.
- Public documentation, native screenshots, example trajectory, and macOS CI configuration.
