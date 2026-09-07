# ReBot Motion Lab

**A native macOS workspace for exploring the ReBot B601-DM robot arm.**

[![CI](https://github.com/monomyth/rebot-motion-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/monomyth/rebot-motion-lab/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-171c19)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![Application code: MIT](https://img.shields.io/badge/application_code-MIT-c3e878)](LICENSE)

Move six joints and a coupled gripper, plan repeatable trajectories, inspect actuator settings, and control the simulator through MCP. Built with **SwiftUI, AppKit, and RealityKit**, with the robot geometry and reference material bundled for offline use.

[**Download for macOS**](https://github.com/monomyth/rebot-motion-lab/releases/latest) · [Build from source](#build-from-source) · [MCP setup](MCP.md) · [Actuator reference](Sources/RobotCore/Resources/B601-DM-actuator-settings.md)

![ReBot Motion Lab showing the folded B601-DM, joint controls, tool coordinates, and a waypoint sequence](docs/images/simulator.png)

## Explore the arm

- **Smooth manual motion.** Sliders and numeric fields set a target immediately; the arm follows on each scene frame, including through quick direction changes.
- **Fold, unfold, and position.** Start in the folded pose with a closed gripper. Choose Folded, Ready, Reach, or Upright, or solve for a tool position with inverse kinematics.
- **Build a motion sequence.** Capture named poses, play/pause/resume, adjust speed, and import or export portable trajectory JSON.
- **Inspect the scene.** Orbit, pan, and zoom; switch camera presets; show the grid, tool axes, and TCP trace.
- **Keep the reference beside the simulator.** Browse 53 documented actuator registers, seven actuator assignments, SDK defaults, command fields, operating modes, and source links.
- **Control it through MCP.** A bundled native server exposes 12 tools and two resources to compatible clients. No Python or Node runtime is needed to use it.

This is a **kinematic simulator**. It does not connect to robot hardware or simulate collisions, payloads, forces, torque, thermal behavior, or actuator dynamics. Published motor settings are reference data; they do not configure the simulator.

## Get started

1. Download **ReBot-Motion-Lab-macOS.zip** from [Releases](https://github.com/monomyth/rebot-motion-lab/releases/latest), unzip it, and move **ReBot Motion Lab.app** to Applications.
2. Open the app and select **Ready** to unfold the arm.
3. Adjust a joint or the gripper, then choose **Add pose** to save the displayed control values.
4. Add more poses and press **Play**. Export the sequence to keep it between sessions.

Requires **macOS 14 or later** and Metal-capable graphics. The app contains Intel and Apple silicon executables. Release builds are locally ad-hoc signed, not Developer ID signed or notarized; macOS may require explicit approval to open them. Building from source is also supported.

### Controls

| Action | Control |
| --- | --- |
| Orbit / pan / zoom | Drag / Shift-drag or right-drag / scroll or pinch |
| Play or pause | ⌘Return |
| Stop motion | Escape |
| Reset to folded startup | ⌘R |
| Add the displayed pose | ⌘K |
| Import / export trajectory | ⌘O / ⌘S |
| Increase / decrease text | ⌘+ or ⌘= / ⌘− |
| Reset text size | ⌘0 |

Text size persists from 80% to 160%. The joint controls show **requested targets**; the TCP readout shows the **actual rendered position**. Stop freezes motion. Reset and presets discard a pending manual target. Leaving the simulator pauses playback and stops manual adjustment.

The [example trajectory](examples/trajectory.json) uses the same `rebot-motion-lab-v1` format as the original browser prototype: six joint angles in degrees, gripper opening in millimeters, and playback speed from 10–100%. Waypoints stay in memory until exported.

## Actuator reference

A separate view explains the documented settings and what they do. It includes 53 registers, 30 SDK settings, 11 command fields, four control modes, ten operations, status codes, and pinned primary sources. Search within sections and filter registers by category, or export the complete Markdown reference from the app.

![Native actuator reference with motor assignments and documented defaults](docs/images/actuator-reference.png)

The reference preserves differences between source versions. For example, Seeed's J1–J3 MIT-mode `kd = 8` is clipped to 5 by the inspected encoder. Defaults are not live device readings, and protocol mapping ranges are not mechanical joint limits. See the [full reference](Sources/RobotCore/Resources/B601-DM-actuator-settings.md) for details.

## Connect an MCP client

Open **MCP control** in the sidebar to enable access and copy a configuration for the app's current location. With the app in Applications, a standard stdio configuration is:

```json
{
  "mcpServers": {
    "rebot": {
      "command": "/Applications/ReBot Motion Lab.app/Contents/MacOS/ReBotMCP",
      "args": []
    }
  }
}
```

Try: *“Unfold the robot to Ready, rotate joint 1 to 30 degrees, then close the gripper.”*

The helper can launch the app. Tools return when a move is accepted; clients read state until it finishes. All control stays on the same Mac through a private Unix socket. MCP is enabled by default and can be disabled in the app. It controls this simulator only.

See [MCP.md](MCP.md) for the complete tool list, Codex registration, motion workflow, units, error handling, and transport details. A reusable [configuration example](examples/mcp.json) is included.

## Build from source

Use Xcode 16 or later, or Apple Command Line Tools with Swift 6. There are **no third-party Swift package dependencies**.

```sh
git clone https://github.com/monomyth/rebot-motion-lab.git
cd rebot-motion-lab

# Run the native app.
bash scripts/swift-local.sh run ReBotMotionLab

# Run the core and protocol tests.
bash scripts/swift-local.sh test

# Build a universal macOS application.
bash scripts/build-app.sh ./dist
open "dist/ReBot Motion Lab.app"
```

In Xcode, open `Package.swift`, choose **ReBotMotionLab**, and run on **My Mac**. This project targets macOS; an iOS app is not included.

The wrapper handles a known Command Line Tools manifest-interface mismatch within the build directory; it never changes the installed Apple toolchain. On a matching Xcode installation, `swift run` and `swift test` also work directly.

See [Development](docs/DEVELOPMENT.md) for app-level checks, packaging, architecture, and reproducible validation. [PERFORMANCE.md](PERFORMANCE.md) documents the motion implementation and measured local samples.

## Project layout

```text
Sources/
  RobotCore/       Kinematics, motion, model assets, and actuator data
  ReBotMotionLab/  SwiftUI interface and RealityKit scene
  RobotControl/    MCP protocol, tool validation, and private IPC
  ReBotMCP/        Native stdio server and app launch helper
Tests/            Core, motion, mesh, and protocol tests
examples/         Importable trajectory and MCP configuration
docs/             Development guide and native screenshots
scripts/          Build, packaging, and integration checks
```

## Contributing

Bug reports, documentation corrections, and focused pull requests are welcome. Include the app/macOS version and a short reproduction for motion issues. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and validation guidance, and [CHANGELOG.md](CHANGELOG.md) for the current release.

## License and credits

The application code, scripts, and original documentation use the **[MIT License](LICENSE)**. MIT keeps reuse straightforward while requiring preservation of the copyright and license notice.

The bundled robot model has a separate license: Seeed's URDF/STL assets and their `model.json` conversion remain under **CERN-OHL-W-2.0**. MotorBridge-derived metadata retains its **MIT** notice. These materials are not relicensed by the application's MIT license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for exact paths, pinned sources, and license texts.

Robot model: [Seeed-Projects/reBot-DevArm](https://github.com/Seeed-Projects/reBot-DevArm). Actuator metadata: [MotorBridge](https://github.com/motorbridge/motorbridge) and the pinned sources in the reference. This is an independent project, not an official Seeed or Damiao product.
