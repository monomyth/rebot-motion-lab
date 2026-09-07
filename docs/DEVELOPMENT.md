# Development

ReBot Motion Lab uses a Swift package with two executables and two shared modules. It requires macOS and Apple's frameworks; it does not build as a Linux or Windows application.

## Architecture

| Module | Responsibility |
| --- | --- |
| `RobotCore` | Model/resource loading, lossless STL indexing, forward/inverse kinematics, manual smoothing, playback, trajectory validation, and reference metadata |
| `ReBotMotionLab` | SwiftUI state and controls, AppKit window/keyboard integration, RealityKit transforms and cameras, import/export, native checks |
| `RobotControl` | MCP lifecycle, tool schemas and validation, same-user Unix socket transport |
| `ReBotMCP` | Newline-delimited stdio server, IPC client, optional app launch |

`AppModel.current` is the actual rendered pose. Manual input updates a separate target; a critically damped filter follows that target from RealityKit frame events. Presets, IK moves, and sequences use the quintic playback engine. Numeric readouts are sampled at 15 Hz. See [motion performance](../PERFORMANCE.md) for the math, scene optimizations, and measured samples.

## Build and test

```sh
bash scripts/swift-local.sh test
bash scripts/build-app.sh ./dist
```

`swift-local.sh` forwards to the selected Apple Swift toolchain. If an upgraded Command Line Tools installation contains mismatched public/private package-manifest interfaces, the wrapper prepares a matching copy in `.build/manifest-runtime`. It also supplies Swift Testing framework paths when needed. System toolchain files are never edited.

The build script compiles x86_64 and arm64 independently with a macOS 14 deployment target, combines each executable with `lipo`, bundles offline resources, creates an icon, and ad-hoc signs/verifies the app. Do not move existing compiler module caches between directories; recreate them when changing build paths.

## Native app checks

The explicit smoke harness opens its own app window, exercises controls, captures only its own views, and exits. Use a temporary control directory to keep it separate from any running copy:

```sh
CONTROL_DIR="$(mktemp -d /tmp/rebot-smoke.XXXXXX)"
REBOT_CONTROL_DIRECTORY="$CONTROL_DIR" \
  "dist/ReBot Motion Lab.app/Contents/MacOS/ReBotMotionLab" \
  --smoke-test "$PWD/work/smoke"
```

Inspect `work/smoke/smoke-result.txt` for success or `smoke-error.txt` for a failure. The harness writes native view screenshots and `manual-motion.json`, which records actual scene updates during 100 native slider action/binding changes. It checks target retention, smooth settling, cancellation, TCP agreement, folded startup, IK, playback, font shortcuts, reference navigation, and MCP control state.

The MCP integration script launches its own isolated app and stdio helper and terminates only those processes:

```sh
python3 scripts/test-mcp.py "dist/ReBot Motion Lab.app" "$PWD/work/mcp"
```

Python 3 is needed for this development script only. The shipped app and MCP executable do not require Python.

## Benchmarks

```sh
"dist/ReBot Motion Lab.app/Contents/MacOS/ReBotMotionLab" \
  --performance-check "$PWD/work/performance"
```

This reports scene-update cadence, CPU time, and notification/entity counts for visible playback. It does not measure GPU presentation FPS. Hardware, display configuration, warm-up, and other apps influence results. See [PERFORMANCE.md](../PERFORMANCE.md) and [Verification](../Verification/README.md).

## Continuous integration

The GitHub Actions workflow tests the core and transport on macOS runners for Intel and Apple silicon. The Apple silicon job also builds a universal app and uploads a ZIP artifact. GUI/MCP end-to-end checks are separate local checks because they require a working native window and renderer.

## Release packaging

Build from the release commit, then package the signed bundle with `ditto` so executable permissions and bundle metadata are preserved:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  "dist/ReBot Motion Lab.app" "dist/ReBot-Motion-Lab-macOS.zip"
shasum -a 256 "dist/ReBot-Motion-Lab-macOS.zip"
```

Attach the ZIP and checksum to the corresponding GitHub release. The app is ad-hoc signed; Developer ID signing and notarization are separate distribution steps and are not configured by this repository.
