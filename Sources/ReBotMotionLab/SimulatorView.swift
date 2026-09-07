import SwiftUI
import RobotCore

struct SimulatorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.fontScale) private var fontScale
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Explore every move.").labFont(.system(size: 27, weight: .medium))
                    Text("B601-DM · 6-axis kinematic simulator").labFont(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Label("SIMULATION", systemImage: "circle.dotted").labFont(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Color.labAccent)
                Button { model.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }.help("Reset to the folded startup position").padding(.leading, 12)
            }.padding(22)
            HSplitView {
                viewport.frame(minWidth: 410, maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        JointControlsView(model: model, controls: model.poseControls)
                        Divider()
                        targetControls
                    }.padding(20)
                }.frame(minWidth: 285, idealWidth: 310 * min(fontScale, 1.25), maxWidth: 345 * min(fontScale, 1.25))
            }
            Divider()
            sequence.padding(.horizontal, 22).padding(.vertical, 16)
            HStack(spacing: 8) {
                Circle().fill(model.playback == .playing || model.manualMoving ? Color.labAccent : Color.secondary).frame(width: 5, height: 5)
                Text(model.status).lineLimit(2)
                Spacer(minLength: 12)
                Text("No collision or dynamics model").foregroundStyle(.tertiary)
            }.labFont(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 12)
        }
    }
    private var viewport: some View {
        ZStack(alignment: .topLeading) {
            RobotScene(model: model)
                .accessibilityLabel("Interactive 3D B601-DM robot")
                .accessibilityHint("Drag to orbit, shift-drag to pan, and scroll or pinch to zoom.")
            if let image = model.captureImage { Image(nsImage: image).resizable().allowsHitTesting(false) }
            VStack {
                HStack {
                    Picker("Camera", selection: Binding(get: { model.camera }, set: { model.resetCamera($0) })) {
                        Text("Orbit").tag("Orbit"); Text("Front").tag("Front"); Text("Top").tag("Top")
                    }.pickerStyle(.segmented).frame(width: 210 * fontScale)
                    Spacer()
                    Button { model.resetCamera(model.camera) } label: { Image(systemName: "viewfinder") }.help("Reset camera")
                }
                Spacer()
                HStack(alignment: .bottom) {
                    ToolReadout(telemetry: model.telemetry)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Toggle("Grid", isOn: $model.showGrid)
                    Toggle("Tool axes", isOn: $model.showAxes)
                    Toggle("Trace", isOn: $model.showTrace)
                    if model.showTrace { Button("Clear") { model.traceRevision += 1 }.buttonStyle(.link) }
                    Spacer()
                }.toggleStyle(.checkbox).labFont(.caption).padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }.padding(16)
            if !model.sceneReady && model.sceneError == nil { ProgressView("Loading robot geometry…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let error = model.sceneError {
                ContentUnavailableView("3D model unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .overlay(alignment: .top) {
            Text("Drag to orbit · Shift-drag to pan · Scroll to zoom").labFont(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 55).allowsHitTesting(false)
        }
    }
    private var targetControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Move to position", subtitle: "Base coordinates · millimeters")
            HStack(spacing: 8) {
                targetField("X", $model.targetX); targetField("Y", $model.targetY); targetField("Z", $model.targetZ)
            }
            HStack {
                Button("Use current") { model.useCurrentTarget() }
                Spacer()
                Button("Solve & move") { model.solve() }.buttonStyle(.borderedProminent).foregroundStyle(.black)
            }.controlSize(.small)
            Text("Position-only IK. Wrist orientation is free. Solutions must be within 2 mm; unreachable targets keep the current pose.")
                .labFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.disabled(model.controlsLocked)
    }
    private func targetField(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).labFont(.caption2).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).labFont(.system(.caption, design: .monospaced))
        }
    }
    private var sequence: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Motion sequence").labFont(.headline)
                Text("\(model.waypoints.count) poses").labFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Example") { model.waypoints = Pose.example }.disabled(model.controlsLocked)
                Button("Clear") { model.waypoints = [] }.disabled(model.controlsLocked || model.waypoints.isEmpty)
                Button { model.addWaypoint() } label: { Label("Add pose", systemImage: "plus") }.disabled(model.controlsLocked)
            }.controlSize(.small)
            if model.waypoints.isEmpty {
                Text("Move the robot, then add a pose to start a sequence.").labFont(.callout).foregroundStyle(.secondary).frame(height: 78)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.waypoints.enumerated()), id: \.element.id) { i, pose in waypointCard(i, pose) }
                    }.padding(.bottom, 4)
                }.frame(height: 94 * fontScale)
            }
            PlaybackControlsView(model: model, telemetry: model.telemetry)
        }
    }
    private func waypointCard(_ i: Int, _ pose: Pose) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: "%02d", i + 1)).foregroundStyle(Color.labAccent).labFont(.system(.caption, design: .monospaced))
                TextField("Pose name", text: Binding(get: { model.waypoints.first(where: { $0.id == pose.id })?.name ?? pose.name }, set: { name in
                    if let index = model.waypoints.firstIndex(where: { $0.id == pose.id }) { model.waypoints[index].name = name.isEmpty ? "Pose \(index + 1)" : name }
                })).textFieldStyle(.plain).labFont(.caption.weight(.medium))
                Button { model.waypoints.removeAll { $0.id == pose.id } } label: { Image(systemName: "xmark").labFont(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove pose")
            }
            Text("Gripper \(Int(pose.grip)) mm").labFont(.caption2).foregroundStyle(.secondary)
            Button("Apply pose") { model.moveToPose(pose) }.buttonStyle(.link).labFont(.caption2)
        }.padding(10).frame(width: 160 * min(fontScale, 1.5))
            .background(model.activeWaypoint == i ? Color.labAccent.opacity(0.13) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.activeWaypoint == i ? Color.labAccent.opacity(0.7) : Color.white.opacity(0.08)))
            .disabled(model.controlsLocked)
    }
}

func sectionTitle(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) { Text(title).labFont(.headline); Text(subtitle).labFont(.caption).foregroundStyle(.secondary) }
}


private struct JointControlsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controls: PoseControls
    @Environment(\.fontScale) private var fontScale
    var body: some View { VStack(alignment: .leading, spacing: 22) { jointControls; Divider(); gripperControls } }
    private var jointControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Joint control", subtitle: "Target angles in degrees · Smooth response")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(robotPresets, id: \.name) { preset in
                    Button(preset.name) { model.moveToPose(Pose(name: preset.name, joints: preset.joints, grip: preset.grip ?? controls.pose.grip)) }
                        .frame(maxWidth: .infinity)
                        .help(preset.name == "Folded" ? "Fold to startup position and close the gripper" : "Move smoothly to \(preset.name)")
                }
            }.controlSize(.small)
            ForEach(Array(model.robot.definition.armJoints.enumerated()), id: \.offset) { i, joint in
                VStack(spacing: 4) {
                    HStack {
                        Text("J\(i + 1)").labFont(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Color.labAccent)
                        Text(["Base", "Shoulder", "Elbow", "Wrist pitch", "Wrist yaw", "Tool roll"][i]).labFont(.caption).foregroundStyle(.secondary)
                        Spacer()
                        TextField("J\(i + 1) angle", value: Binding(get: { controls.pose.joints[i] }, set: { model.setJoint(i, $0) }), format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 70 * fontScale).labFont(.system(.caption, design: .monospaced))
                        Text("°").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { controls.pose.joints[i] }, set: { model.setJoint(i, $0) }), in: (joint.lower / degreesToRadians)...(joint.upper / degreesToRadians))
                        .accessibilityLabel("Joint \(i + 1) angle in degrees")
                    HStack {
                        Text(joint.lower / degreesToRadians, format: .number.precision(.fractionLength(1)))
                        Spacer()
                        Text(joint.upper / degreesToRadians, format: .number.precision(.fractionLength(1)))
                    }.labFont(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }.disabled(model.controlsLocked)
    }
    private var gripperControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gripper").labFont(.headline); Spacer()
                TextField("Gripper opening", value: Binding(get: { controls.pose.grip }, set: { model.setGrip($0) }), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 70 * fontScale)
                Text("mm").labFont(.caption).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { controls.pose.grip }, set: { model.setGrip($0) }), in: 0...90).accessibilityLabel("Gripper opening in millimeters")
            HStack { Text("Closed · 0"); Spacer(); Text("Open · 90") }.labFont(.caption2).foregroundStyle(.secondary)
        }.disabled(model.controlsLocked)
    }

}

private struct ToolReadout: View {
    @ObservedObject var telemetry: MotionReadout
    var body: some View {
VStack(alignment: .leading, spacing: 6) {
                        Text("TOOL CENTER / mm").labFont(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
                        HStack(spacing: 15) {
                            coordinate("X", telemetry.tcp.x, .red)
                            coordinate("Y", telemetry.tcp.y, .green)
                            coordinate("Z", telemetry.tcp.z, .blue)
                        }
                    }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    private func coordinate(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).labFont(.caption.weight(.bold)).foregroundStyle(color)
            Text(value, format: .number.precision(.fractionLength(1))).labFont(.system(size: 15, weight: .medium, design: .monospaced))
        }
    }

}

private struct PlaybackControlsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var telemetry: MotionReadout
    @Environment(\.fontScale) private var fontScale
    var body: some View {
HStack(spacing: 12) {
                Button { model.playPause() } label: {
                    Label(model.playback == .playing ? "Pause" : model.playback == .paused ? "Resume" : "Play", systemImage: model.playback == .playing ? "pause.fill" : "play.fill")
                        .frame(width: 66 * fontScale)
                }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(model.waypoints.isEmpty)
                Button { model.stop() } label: { Image(systemName: "stop.fill") }.help("Stop motion · Escape").disabled(!model.hasMotion)
                ProgressView(value: telemetry.progress).frame(maxWidth: .infinity)
                Text("Speed").labFont(.caption).foregroundStyle(.secondary)
                Slider(value: $model.speed, in: 10...100, step: 5).frame(width: 100).accessibilityLabel("Playback speed percent")
                Text("\(Int(model.speed))%").labFont(.system(.caption, design: .monospaced)).frame(width: 36 * fontScale)
            }
    }
}
