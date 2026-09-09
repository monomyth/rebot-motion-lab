# Native cube experiment implementation

Implemented on `feature/fly-brain-codex` in the separate `rebot-motion-lab-codex` clone. The original checkout was not edited.

## Delivered scope

| Proposal | Implementation |
| --- | --- |
| Configurable cube and task | Validated size, mass, friction, XY/yaw, initial pose, goal, input mode, and seeded placement jitter; task JSON save/load |
| Grasp physics | Native dynamic cube, static floor, compound convex robot/finger colliders, geometric jaw contact stop, gravity, friction, and physical release |
| Orientation control | Full position/quaternion IK with tool/grasp frames, error reporting, and coordinated rate-limited external movement |
| Observation cameras | Independent front/top render copies, synchronized RGB/telemetry, exact 320×240 encoding, intrinsics/extrinsics, and capture latency |
| Manipulation observations | Joints, aperture, poses, contacts, measured motion; exact cube state restricted to declared state observations and evaluator interfaces |
| External control | Same-user private IPC, exclusive ownership, stale/duplicate action rejection, two-second lease, manual takeover, and Python client/policy runner |
| Episodes and time | Cancellable asynchronous setup, atomic reset and settling, pause/resume, separate arm stop, seeded placement, and native physics-step timing |
| Evaluation | Clearance, marked-face tilt, observed stability, five-second continuous bilateral hold, active-trial drop, timeout, and workspace/physics failure states |
| Demonstrations | Bounded asynchronous JSONL recording, RGB observations, actions/executed state, evaluator data, provenance/model IDs, and recorded-frame export |
| MCP/UI | 11 added tools, task controls and previews, results, recording, task files, stop/reset, and `rebot-motion-lab-codex` configuration/handshake identity |
| Regression checks | Core/protocol tests, original MCP and native smoke harnesses, real native manipulation trials, calibration checks, and visual inspection |

The app is built as `dist/ReBot Motion Lab Codex.app`, with Intel and Apple silicon executables, its own bundle ID, and its own default socket directory. Standard mode remains macOS 14+; manipulation physics requires macOS 15+.

## Validation evidence

Verified on Apple silicon running macOS 26.7:

- **36 Swift tests passed**: 28 core tests and 8 protocol/catalog tests.
- **9 original MCP integration groups passed** with all 23 tools available.
- **Original native smoke harness passed**, including floor contact, playback, trajectory interchange, shortcuts, cached scene navigation, and the renamed copied MCP configuration.
- **100 native slider inputs** produced **zero lagging scene updates** and **zero main-model notifications**.
- Packaged application signature verification passed; both executables are universal.
- Camera encoding dimensions match calibration, and the projected initial cube center is within **0.27 pixels** of a visible cube pixel in the front image.

Physical pickup, level holding, and release passed at these placements, using an explicitly conventional external controller:

| Cube XY (mm) | Yaw | Measured clearance | Measured tilt | Continuous hold |
| --- | --- | --- | --- | --- |
| 350, 0 | 0° | 115.27 mm | 0.020° | 5.0 s |
| 330, 25 | 10° | 115.34 mm | 0.008° | 5.0 s |
| 380, −25 | −10° | 115.02 mm | 0.024° | 5.0 s |

The central trial was repeated after the requested MCP rename and also checked setup cancellation, paused physics time, duplicate/future/stale action rejection, controller timeout, reset isolation, recording contents, and vision-input isolation.

Compact evidence, images, and binary hashes are in [Verification/fly-codex](../Verification/fly-codex/results.json). Full recordings, native logs, and intermediate diagnostics remain under the ignored `work/` directory. The whole-window pickup image was captured during a successful packaged-app run; minor label/name refinements followed it, while the final camera images and central report were regenerated afterward.

## Explicit boundaries

The simulator environment is ready for an external MaleCNS controller. No trained MaleCNS model is bundled, and the conventional validation controller is not a neural-learning result. Loading the connectome, defining neuron dynamics, training adapters, and measuring the connectome's contribution remain external project work, as specified in the proposal.

The optional later milestones—depth/segmentation, accelerated or batch stepping, multiple objects, and browser parity—are not part of the native first version. Capability discovery reports unsupported channels and stepping honestly. Grasp contacts approximate the supplied visual meshes; no actuator-force or hardware-transfer claim is made. See [FLY_EXPERIMENT.md](FLY_EXPERIMENT.md) for timing, contact, observation, and raw solver-velocity details.
