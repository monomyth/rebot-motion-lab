# Motion performance

## Version 1.4: manual controls

Manual joint and gripper controls now update a target instead of applying a pose directly for every input event. RealityKit frame events advance a critically damped filter; its two internal stages retain their state across input changes, so repeated events and reversals do not reset the arm's velocity. The analytic update gives the same response at different frame cadences and stays within the supplied joint/gripper bounds. A fixed target covers 90% of its distance in about 100 ms; the controls show the requested value immediately. This response is separate from the slower, speed-limited preset/MCP/sequence playback.

The control target has its own observable object. Actual pose/TCP readouts refresh at most 15 times per second during manual movement, and the full app model publishes only motion start/finish transitions. Stop, Reset, presets, playback, and leaving the simulator discard pending manual movement as appropriate.

Six additional core tests cover response time and settling, continuous retargeting, irregular frame timing, repeated limit-to-limit reversals, cancellation, and invalid input. The native smoke harness also drives the actual NSSlider action/binding while the real scene clock animates the arm, records intermediate poses and notification counts in `manual-motion.json`, and verifies cancellation and displayed targets.

The v1.4 release sample processed 100 native slider action/binding updates and recorded 129 scene updates over 2.63 seconds, including 110 intermediate moving poses. The main model published four notifications; actual-position readouts published 31. These are event/update counts from this Mac, not GPU presentation FPS or a guarantee for other hardware. The raw sample is `Verification/manual-motion.json`.

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

The 16 core tests include time carryover, equivalent poses at different frame cadences, pause/resume, invalid time handling, and a check that every source mesh vertex and normal is preserved by indexing. The native smoke check also exercises smooth presets, scene reuse, and text-size keyboard shortcuts.
