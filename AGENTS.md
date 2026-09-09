# Agent notes (Codex, Cursor, and other coding agents)

This repository contains the native macOS ReBot Motion Lab Swift package (`SwiftUI` + `AppKit` + `RealityKit`), its MCP server, and the browser simulator in `web/`. The repository root is the Swift package root; run web commands from `web/`.

**Read [HANDOFF.md](HANDOFF.md) before changing sliders, pose updates, or smoke checks.** Codex’s v1.4 manual-motion filter is the bug that made dragging feel like dropped FPS; it is not a feature to restore.

The user has authorized consolidation into this repository. Preserve the motion architecture below when updating either app. Floor contact must include every moving link and both gripper fingers, including their tips.

## Motion architecture

- **Interactive sliders and numeric fields apply the pose immediately.** `AppModel.setJoint` / `setGrip` write `current` and call `RobotViewport.applyPose` on the same event. The 3D arm must track the thumb with no filter and no SwiftUI round-trip.
- **Do not reintroduce `ManualMotion` or any critically damped / 100 ms chase on slider input.** That lag is what made dragging feel like lost FPS. Presets, IK, MCP pose commands, and sequence playback stay on `MotionPlayer` (quintic interpolation).
- **Do not bind SwiftUI `Slider` to an `ObservableObject` that publishes on every tick.** Joint/gripper controls use `LiveSlider` (`NSSlider` representable). `updateNSView` must not push `doubleValue` while the mouse is down.
- **`manualMoving` is “a slider is currently tracking,” not “a filter is catching up.”** It is intentionally not `@Published`. Publishing `AppModel` (status, `manualMoving`, etc.) mid-drag rebuilds `SimulatorView` and `RobotScene.updateNSView` and hitchs the renderer.
- **`RobotScene` does not observe `AppModel`.** Pose updates go through `applyPose`. `updateNSView` only syncs grid, axes, trace, camera flags, and the cube entity.
- Numeric TCP/joint readouts may update at 15 Hz. The viewport must not wait on those publishes.
- **Do not `@Publish` cube pose or servo ticks.** Cube transforms go through `RobotViewport.syncCube`. Servo uses the interactive apply path (`commit` / `applyPose`), not `MotionPlayer` and not `ManualMotion`.
- Floor limiting must include a **held** cube AABB. Unattached cubes do not collide with the arm. They fall under `CubeState.integrateGravity` from the RealityKit frame callback even when playback is stopped. Do not `@Publish` those ticks.

## Files

| Path | Role |
| --- | --- |
| `Sources/ReBotMotionLab/AppModel.swift` | Pose, playback, interactive apply, cube, servo, MCP-facing `manualMoving` |
| `Sources/ReBotMotionLab/SimulatorView.swift` | Controls, `LiveSlider` / `TrackingSlider` |
| `Sources/ReBotMotionLab/RobotViewport.swift` | RealityKit hierarchy, `applyPose`, cube, capture |
| `Sources/RobotCore/SceneObject.swift` | Cube state and floor placement |
| `Sources/RobotCore/Grasp.swift` | Kinematic attach/release |
| `Sources/RobotCore/MotionPlayer.swift` | Playback / preset interpolation |
| `Sources/ReBotMotionLab/SmokeCheck.swift` | Native slider harness; expects immediate tracking, not lag |

## Checks

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh ./dist
```

Slider-drag smoke (`--smoke-test`) must keep `current` on the requested value, keep `main_model_notifications` low, and must **not** require lagging scene frames. If a test “fails” because the arm no longer trails the slider, fix the test, not the app.

## Floor stops

Manual setters return the accepted value after geometric floor limiting. The native slider action may set `doubleValue` directly when the floor clamps an input; `updateNSView` must still avoid setting it during tracking. Keep this physical stop separate from motion smoothing. See `docs/DEVELOPMENT.md` for geometry generation and swept-path checks.

Idle slider rows subscribe to `PoseControls.$pose` with `onReceive` and update local state only when their own value changes. This keeps Reset, presets, playback, and MCP synchronized without observing the entire panel. Do not remove that subscription: a plain `displayed` property can remain unchanged across a Reset even when the row has stale local state.
