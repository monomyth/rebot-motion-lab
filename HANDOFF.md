# Handoff: slider FPS (what Codex got wrong)

Interactive joint/gripper dragging is **fixed**. Do not restore the v1.4 “smooth manual motion” design. Resume from this file plus [AGENTS.md](AGENTS.md).

## The mistake

Codex treated jerky slider dragging as a motion-planning problem and added a critically damped filter (`ManualMotion`, ~100 ms to 90% of a step, ~50 ms trail while dragging). Slider events only updated a **target**. RealityKit frames chased that target. The 3D arm lagged the thumb, which the user correctly read as lost FPS.

That was the wrong diagnosis. Applying six joint quaternions in RealityKit is cheap. The hitch was **main-thread SwiftUI work on every pointer tick**, plus intentional lag:

1. **Lag by design.** `setJoint` / `setGrip` called `ManualMotion.retarget` instead of `applyPose`. The arm could not keep up with the control.
2. **SwiftUI rebuilt the sliders being dragged.** `JointControlsView` observed `PoseControls`. Every tick published the whole pose, so all six `Slider`s plus the gripper were reconstructed mid-drag.
3. **Full simulator invalidation.** Drag start published `AppModel` (`manualMoving`, `status = "Adjusting pose"`), which rebuilt `SimulatorView` and `RobotScene.updateNSView`.
4. **The tests encoded the bug.** Smoke required `movingFrames > 8` (arm behind the slider) and copy in README/PERFORMANCE advertised the 100 ms trail. A later agent that made dragging immediate would “fail” those checks.

Playback FPS was measured (~38 scene updates/s in v1.1). **Slider-drag FPS was not.** The filter made the metric look sophisticated while the actual interaction stayed jerky.

Presets, IK, MCP pose commands, and sequence playback were never the problem. Those should stay on `MotionPlayer` (quintic interpolation).

## What is true now

- Slider/text input writes `AppModel.current` and calls `RobotViewport.applyPose` on the same event.
- Joint/gripper controls use `LiveSlider` (`NSSlider` representable). Do not push `doubleValue` back while the mouse is down.
- `manualMoving` means “a slider is tracking,” is **not** `@Published`, and must not rebuild the scene.
- `RobotScene` does not observe `AppModel`. Overlays (grid/axes/camera) go through `updateNSView`; pose does not.
- Smoke expects `current` to match the requested value, low `main_model_notifications`, and **must not** require lagging frames.
- Packaged-app slider sample: 100 native slider events, ~60 scene updates/s, 0 lagging frames, 0 main-model notifications.

## Do not

- Reintroduce `ManualMotion` or any chase/damp/lerp on interactive sliders.
- Bind SwiftUI `Slider` to an `ObservableObject` that publishes every tick.
- Publish `AppModel` (status, `manualMoving`, etc.) on pointer-move.
- “Fix” immediate tracking by changing the app to satisfy an old lagging-frame assertion. Change the test.

Accent color is lime `labAccent` (0.76, 0.91, 0.35). System-blue `Link` / `.buttonStyle(.link)` falls out of the scheme; use `labLinkStyle()` and `NSSlider.trackFillColor = .labAccent`.
