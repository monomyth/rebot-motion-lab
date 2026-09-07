# Agent notes (Codex, Cursor, and other coding agents)

This is the native macOS ReBot Motion Lab package (`SwiftUI` + `AppKit` + `RealityKit`). The browser prototype lives in a sibling folder and is not this app.

**Read [HANDOFF.md](HANDOFF.md) before changing sliders, pose updates, or smoke checks.** Codex’s v1.4 manual-motion filter is the bug that made dragging feel like dropped FPS; it is not a feature to restore.

The intended long-term home is one repository for the web simulator, native Swift app, and MCP tools. The user has deferred consolidation: keep the current layout and do not move the web project or restructure these components as part of the initial GitHub publication.

## Motion architecture

- **Interactive sliders and numeric fields apply the pose immediately.** `AppModel.setJoint` / `setGrip` write `current` and call `RobotViewport.applyPose` on the same event. The 3D arm must track the thumb with no filter and no SwiftUI round-trip.
- **Do not reintroduce `ManualMotion` or any critically damped / 100 ms chase on slider input.** That lag is what made dragging feel like lost FPS. Presets, IK, MCP pose commands, and sequence playback stay on `MotionPlayer` (quintic interpolation).
- **Do not bind SwiftUI `Slider` to an `ObservableObject` that publishes on every tick.** Joint/gripper controls use `LiveSlider` (`NSSlider` representable). `updateNSView` must not push `doubleValue` while the mouse is down.
- **`manualMoving` is “a slider is currently tracking,” not “a filter is catching up.”** It is intentionally not `@Published`. Publishing `AppModel` (status, `manualMoving`, etc.) mid-drag rebuilds `SimulatorView` and `RobotScene.updateNSView` and hitchs the renderer.
- **`RobotScene` does not observe `AppModel`.** Pose updates go through `applyPose`. `updateNSView` only syncs grid, axes, trace, and camera flags.
- Numeric TCP/joint readouts may update at 15 Hz. The viewport must not wait on those publishes.

## Files

| Path | Role |
| --- | --- |
| `Sources/ReBotMotionLab/AppModel.swift` | Pose, playback, interactive apply, MCP-facing `manualMoving` |
| `Sources/ReBotMotionLab/SimulatorView.swift` | Controls, `LiveSlider` / `TrackingSlider` |
| `Sources/ReBotMotionLab/RobotViewport.swift` | RealityKit hierarchy and `applyPose` |
| `Sources/RobotCore/MotionPlayer.swift` | Playback / preset interpolation |
| `Sources/ReBotMotionLab/SmokeCheck.swift` | Native slider harness; expects immediate tracking, not lag |

## Checks

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh ./dist
```

Slider-drag smoke (`--smoke-test`) must keep `current` on the requested value, keep `main_model_notifications` low, and must **not** require lagging scene frames. If a test “fails” because the arm no longer trails the slider, fix the test, not the app.
