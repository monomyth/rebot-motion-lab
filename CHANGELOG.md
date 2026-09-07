# Changelog

## Unreleased

- Joint and gripper sliders apply the rendered pose immediately. Interactive dragging no longer uses a 100 ms damped chase or a SwiftUI `Slider` bound to a republishing observable object.

## 1.4.0 — 2026-09-07

First public source release of ReBot Motion Lab. The macOS application reports version 1.4.

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
