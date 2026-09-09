import SwiftUI
import AppKit
import RobotCore

struct ExperimentPanel: View {
    @ObservedObject var coordinator: ExperimentCoordinator
    @State private var x=350.0
    @State private var y=0.0
    @State private var size=50.0
    @State private var mass=50.0
    @State private var yaw=0.0
    @State private var mode="vision"
    @State private var message: String?
    @State private var expanded=true
    var body: some View {
        DisclosureGroup("Cube pickup experiment",isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:12) {
                if !coordinator.enabled {
                    HStack { field("X mm",$x); field("Y mm",$y) }
                    HStack { field("Size mm",$size); field("Mass g",$mass); field("Yaw °",$yaw) }
                    Picker("Observations",selection:$mode) { Text("Vision").tag("vision"); Text("State assisted").tag("state") }
                    Button("Set up cube") { perform {
                        var task=ExperimentTask(); task.cubeXYMM=[x,y]; task.cubeSizeMM=size; task.massGrams=mass; task.cubeYawDeg=yaw; task.inputMode=mode
                        try coordinator.configure(task)
                    } }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(coordinator.phase == "configuring")
                    if coordinator.phase == "configuring" {
                        ProgressView("Preparing contact geometry…")
                        Button("Cancel setup") { coordinator.stopArm(reason:"stop") }
                    }
                    Button("Load task…") { loadTask() }.labLinkStyle()
                } else {
                    let e=coordinator.evaluation()
                    HStack { Text(coordinator.phase.capitalized).foregroundStyle(Color.labAccent); Spacer(); Text(coordinator.owner).foregroundStyle(.secondary) }
                    Text(String(format:"Clearance %.1f mm · Tilt %.1f°",e["clearance_mm"] as? Double ?? 0,e["tilt_deg"] as? Double ?? 0)).monospacedDigit()
                    Text(String(format:"Level hold %.1f / %.1f s",coordinator.evaluator.holdSeconds,coordinator.task.holdSeconds)).monospacedDigit()
                    Text("Contacts: \((e["contacts"] as? [String] ?? []).map { $0 == "finger_left_link" ? "Left finger" : $0 == "finger_right_link" ? "Right finger" : $0 == "floor" ? "Floor" : "Arm" }.joined(separator:", "))").foregroundStyle(.secondary)
                    HStack {
                        Button(coordinator.phase == "paused" ? "Resume" : "Start") { command(coordinator.phase == "paused" ? "resume" : "start") }.disabled(!["ready","paused"].contains(coordinator.phase))
                        Button("Pause") { command("pause") }.disabled(coordinator.phase != "running")
                        Button("Reset") { perform { try coordinator.reset() } }
                    }
                    HStack {
                        Button("Stop arm / Take over") { command("takeover") }
                        Button("Disable") { command("disable") }
                    }
                    HStack {
                        Button(coordinator.recording ? "Stop recording" : "Record") { perform { let r=try coordinator.handle("rebot_recording",["action":coordinator.recording ? "stop" : "start"]); message=r["directory"] as? String } }
                        Button("Save task…") { saveTask() }
                    }
                    ForEach(coordinator.cameras,id:\.name) { camera in
                        Text("\(camera.name) observation").foregroundStyle(.secondary)
                        ObservationPreview(camera:camera).frame(width:256,height:192).clipShape(RoundedRectangle(cornerRadius:6))
                    }
                    Text("Dynamic cube · Contact and friction grasp\nPolicy input: \(coordinator.task.inputMode)").foregroundStyle(.secondary)
                    if let error=coordinator.lastError { Text(error).foregroundStyle(.orange) }
                }
                if let message { Text(message).textSelection(.enabled).foregroundStyle(.secondary) }
            }.controlSize(.small).labFont(.caption).padding(.top,10)
        }.labFont(.headline)
    }
    private func field(_ label:String,_ value:Binding<Double>) -> some View {
        VStack(alignment:.leading) { Text(label).labFont(.caption2); TextField(label,value:value,format:.number).textFieldStyle(.roundedBorder) }
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
        perform { try coordinator.configure(JSONDecoder().decode(ExperimentTask.self,from:Data(contentsOf:url))) }
    }
}

struct SimulationModeLabel: View {
    @ObservedObject var coordinator: ExperimentCoordinator
    var body: some View {
        Text(coordinator.enabled ? "B601-DM · Kinematic arm + dynamic cube" : "B601-DM · 6-axis kinematic simulator")
    }
}
