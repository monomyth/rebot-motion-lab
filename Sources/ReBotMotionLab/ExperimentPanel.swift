import SwiftUI
import AppKit
import RobotCore

struct ExperimentPanel: View {
    @ObservedObject var coordinator: ExperimentCoordinator
    @State private var x=350.0
    @State private var y=0.0
    @State private var size=ExperimentTask.flyBrainStartup.cubeSizeMM
    @State private var mass=50.0
    @State private var yaw=0.0
    @State private var mode="vision"
    @State private var message: String?
    @State private var expanded=true
    private var editingAllowed: Bool { coordinator.enabled ? coordinator.canEditCube : coordinator.phase != "configuring" }

    var body: some View {
        DisclosureGroup("Cube pickup experiment",isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:12) {
                VStack(alignment:.leading,spacing:8) {
                    HStack { field("Cube X mm",$x); field("Cube Y mm",$y) }
                    HStack {
                        field("Cube side mm",$size)
                        Stepper("Cube side",value:$size,in:CubePlacement.sideRangeMM,step:1).labelsHidden().accessibilityLabel("Cube side in millimeters")
                        field("Yaw °",$yaw)
                    }
                    Text("Side: 10–90 mm (1–9 cm). Maximum is the fully open gripper.").foregroundStyle(.secondary)
                }.disabled(!editingAllowed)
                Button("Load task…") { loadTask() }.labLinkStyle().disabled(!editingAllowed)
                if !coordinator.enabled {
                    field("Mass g",$mass).disabled(!editingAllowed)
                    Picker("Observations",selection:$mode) { Text("Vision").tag("vision"); Text("State assisted").tag("state") }.disabled(!editingAllowed)
                    Button("Set up cube") { perform {
                        var task=ExperimentTask.flyBrainStartup; task.cubeXYMM=[x,y]; task.cubeSizeMM=size; task.massGrams=mass; task.cubeYawDeg=yaw; task.inputMode=mode
                        try coordinator.configure(task)
                    } }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!editingAllowed)
                    if coordinator.phase == "configuring" {
                        ProgressView("Preparing contact geometry…")
                        Button("Cancel setup") { coordinator.stopArm(reason:"stop") }
                    }
                } else {
                    HStack {
                        Button("Apply cube") { perform { try coordinator.placeCube(xMM:x,yMM:y,sizeMM:size,yawDeg:yaw) } }.disabled(!editingAllowed)
                        Button(coordinator.placingCube ? "Cancel placement" : "Place with mouse") {
                            if coordinator.placingCube { coordinator.cancelFloorPlacement() }
                            else { perform { try coordinator.armFloorPlacement(sizeMM:size,yawDeg:yaw) } }
                        }.disabled(!editingAllowed && !coordinator.placingCube)
                    }
                    FlyBrainControls(coordinator:coordinator,runner:coordinator.flyBrain)
                    Text("Place on any clear part of the floor. Applying changes starts a new episode and keeps the arm in place.").foregroundStyle(.secondary)
                    if !editingAllowed { Text("Stop motion/control and recording before editing; wait for setup or capture to finish.").foregroundStyle(.secondary) }
                    if let placementMessage=coordinator.placementMessage { Text(placementMessage).foregroundStyle(.orange) }
                    let e=coordinator.evaluation()
                    HStack { Text(coordinator.phase.capitalized).foregroundStyle(Color.labAccent); Spacer(); Text(coordinator.owner).foregroundStyle(.secondary) }
                    Text(String(format:"Clearance %.1f mm · Tilt %.1f°",e["clearance_mm"] as? Double ?? 0,e["tilt_deg"] as? Double ?? 0)).monospacedDigit()
                    Text(String(format:"Level hold %.1f / %.1f s",coordinator.evaluator.holdSeconds,coordinator.task.holdSeconds)).monospacedDigit()
                    Text("Contacts: \((e["contacts"] as? [String] ?? []).map { $0 == "finger_left_link" ? "Left finger" : $0 == "finger_right_link" ? "Right finger" : $0 == "floor" ? "Floor" : "Arm" }.joined(separator:", "))").foregroundStyle(.secondary)
                    HStack {
                        Button(coordinator.phase == "paused" ? "Resume physics" : "Start physics") { command(coordinator.phase == "paused" ? "resume" : "start") }.disabled(coordinator.flyBrain.isRunning || !["ready","paused"].contains(coordinator.phase))
                        Button("Pause") { command("pause") }.disabled(coordinator.phase != "running")
                        Button("Reset") { perform { try coordinator.reset() } }
                    }
                    HStack {
                        Button("Stop arm / Take over") { coordinator.stopFlyBrainAndArm() }
                        Button("Disable") { command("disable") }
                    }
                    HStack {
                        Button(coordinator.recording ? "Stop recording" : "Record") { perform { let r=try coordinator.handle("rebot_recording",["action":coordinator.recording ? "stop" : "start"]); message=r["directory"] as? String } }
                        Button("Save task…") { saveTask() }
                    }
                    ForEach(coordinator.cameras,id:\.name) { camera in
                        Text("\(camera.name) observation").foregroundStyle(.secondary)
                        ObservationPreview(camera:camera).id(ObjectIdentifier(camera)).frame(width:256,height:256*CGFloat(camera.height)/CGFloat(camera.width)).clipShape(RoundedRectangle(cornerRadius:6))
                    }
                    Text("Dynamic cube · Contact and friction grasp\nPolicy input: \(coordinator.task.inputMode)").foregroundStyle(.secondary)
                    if let error=coordinator.lastError { Text(error).foregroundStyle(.orange) }
                }
                if let message { Text(message).textSelection(.enabled).foregroundStyle(.orange) }
            }.controlSize(.small).labFont(.caption).padding(.top,10)
        }.labFont(.headline)
        .onAppear { syncFields() }
        .onChange(of:coordinator.episodeID) { _,_ in syncFields() }
    }
    private func syncFields() {
        guard coordinator.enabled else { return }
        let task=coordinator.task
        x=task.cubeXYMM[0]; y=task.cubeXYMM[1]; size=task.cubeSizeMM; yaw=task.cubeYawDeg; mass=task.massGrams; mode=task.inputMode
    }
    private func field(_ label:String,_ value:Binding<Double>) -> some View {
        VStack(alignment:.leading) { Text(label).labFont(.caption2); TextField(label,value:value,format:.number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder) }
    }
    private func command(_ action:String) { perform { _ = try coordinator.handle("rebot_experiment_control",["action":action]) } }
    private func perform(_ body:() throws -> Void) { do { message=nil; try body() } catch { message=error.localizedDescription } }
    private func saveTask() {
        let panel=NSSavePanel(); panel.nameFieldStringValue="cube-task.json"; panel.allowedContentTypes=[.json]
        guard panel.runModal() == .OK, let url=panel.url else { return }
        perform { let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; try encoder.encode(coordinator.configuration).write(to:url,options:.atomic) }
    }
    private func loadTask() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.json]; panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK, let url=panel.url else { return }
        perform { try coordinator.configure(SimulatorDocument.decodeTask(Data(contentsOf:url))) }
    }
}

struct CubePlacementHint: View {
    @ObservedObject var coordinator: ExperimentCoordinator
    var body: some View {
        Text(coordinator.placingCube ? "Click a clear floor point · Escape cancels" : "Orbit: drag / pan / zoom · Front, Top and Gripper: calibrated views")
            .labFont(.system(size:10)).foregroundStyle(coordinator.placingCube ? Color.labAccent : Color.secondary)
    }
}

struct SimulationModeLabel: View {
    @ObservedObject var coordinator: ExperimentCoordinator
    var body: some View {
        Text(coordinator.enabled ? "B601-DM · Kinematic arm + dynamic cube" : "B601-DM · 6-axis kinematic simulator")
    }
}
