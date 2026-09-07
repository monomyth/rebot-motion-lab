# Motion performance

## Version 1.5: immediate slider pose

Dragging a joint or gripper slider applies the pose to the RealityKit hierarchy on the same input event. The previous critically damped manual filter made the arm trail the thumb by about 50–100 ms and, together with SwiftUI `Slider` rebuilds, dropped interactive frame cadence.

Interactive controls now use a persistent `NSSlider` representable that does not write `doubleValue` back while tracking. `AppModel` does not publish on each tick; numeric readouts still refresh at most 15 times per second. Preset, MCP, and sequence motion stay on the quintic playback engine.

Do not restore `ManualMotion` for slider input. See `AGENTS.md`.

A packaged-app smoke sample on this Mac processed 100 native slider action/binding updates over 2.14 seconds with 128 scene updates (about 60/s), 0 lagging frames, 0 main-model notifications, and 22 readout notifications. Playback `--performance-check` on the same machine reported 59.1 scene updates/second with and without trace.

## Version 1.4: manual controls (superseded for dragging)

Manual joint and gripper controls previously updated a target instead of applying a pose directly for every input event. RealityKit frame events advanced a critically damped filter so a fixed target covered 90% of its distance in about 100 ms. That path is removed for interactive dragging because it felt like lost FPS. Playback interpolation is unchanged.

The control panel still keeps displayed numeric values off the full app-model publish path. Stop, Reset, presets, playback, and leaving the simulator still discard in-progress slider tracking as appropriate.

## Version 1.1: renderer and playback

Playback advances directly on RealityKit frame updates. The renderer updates six joint rotations and two finger offsets through a native transform hierarchy. Numeric readouts refresh at most 15 times per second during playback. Animation no longer triggers a full SwiftUI interface refresh every tick.

The clock carries elapsed time across waypoint boundaries, so irregular frame timing does not stretch the motion or discard time. Presets, saved poses, and successful IK moves use the same eased interpolation as sequence playback.

The grid is one mesh. Trace segments are batched in chunks of 100, with at most 12 entities. Identical position/normal pairs are indexed in the original robot meshes, reducing vertices from 1,292,736 to 1,018,428 while preserving all 430,912 triangles and hard edges. Reference navigation reuses the loaded scene and suspends its animation updates while it is hidden.

## Measured on this Mac

One before/after run on Intel macOS 26.6.2, using the release app, a 1380 × 900 point window, the example trajectory at 50% speed, and two 10-second measurement phases. The trace phase prefills 800 poses. The same original app remained open in the background during both runs. This measures RealityKit scene-update cadence, not GPU presentation FPS; it is a local sample, not a guaranteed frame rate. The first phase includes more warm-up effects.

| Measurement | v1.0 | v1.1 |
| --- | ---: | ---: |
| Scene updates/second, trace off | 11.1 | 37.7 |
| Scene updates/second, trace on | 11.2 | 54.0 |
| CPU seconds per 10-second phase, trace off | 10.28 | 5.07 |
| CPU seconds per 10-second phase, trace on | 10.70 | 5.57 |
| Main model notifications, trace off / on | 477 / 459 | 7 / 7 |
| Trace entities after trace phase | 720 | 9 |

The median update interval improved from 46–52 ms to about 16.8 ms. Long intervals still occurred: the optimized 95th percentiles were 125 ms with trace off and 34 ms with trace on. Hardware, other apps, window size, and warm-up affect the results.

To reproduce the measurement, launch the packaged executable with `--performance-check /absolute/output/folder`. The explicit development harness opens its own window, writes `performance.json` or `error.txt`, and exits. The JSON field named `frames_per_second` refers to scene updates per second. Raw before/after samples are in `Verification/`.

The 22 core tests include time carryover, equivalent poses at different frame cadences, pause/resume, invalid time handling, and a check that every source mesh vertex and normal is preserved by indexing. The native smoke check also exercises immediate slider tracking, presets, scene reuse, and text-size keyboard shortcuts.

## Solid base plane

Plane checks use 2,123 precomputed support vertices instead of scanning the full STL triangles on pointer events. Single-joint edits solve first contact analytically; accepted angles return directly to the native slider, including during tracking. Playback paths are validated before motion starts. The render loop retains Cursor's direct pose updates and carries no per-frame floor search.
