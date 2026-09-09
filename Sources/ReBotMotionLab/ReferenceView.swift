import SwiftUI
import RobotCore

enum ReferenceSection: String, CaseIterable, Identifiable {
    case overview = "Overview", actuators = "Actuators", registers = "Registers", software = "SDK settings", commands = "Commands", modes = "Modes", operations = "Operations", sources = "Sources"
    var id: String { rawValue }
}

struct ReferenceView: View {
    @ObservedObject var model: AppModel
    @Environment(\.fontScale) private var fontScale
    private var section: ReferenceSection { model.referenceSection }
    private var search: String { model.referenceSearch }
    @State private var category = "All categories"
    private var ref: ActuatorReference { model.reference }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Inside the actuators.").labFont(.system(size: 27, weight: .medium))
                    Text("Damiao 4340P & 4310 · Published settings and what they do").foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.saveReference() } label: { Label("Save reference", systemImage: "square.and.arrow.down") }
            }.padding(24)
            HStack(spacing: 14) {
                Picker("Reference section", selection: $model.referenceSection) {
                    ForEach(ReferenceSection.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 210 * fontScale)
                TextField("Search this section", text: $model.referenceSearch).textFieldStyle(.roundedBorder)
                if !search.isEmpty { Button { model.referenceSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
                if section == .registers {
                    Picker("Category", selection: $category) {
                        Text("All categories").tag("All categories")
                        ForEach(ref.categories, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 180 * min(fontScale, 1.3))
                }
            }.padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .overview: overview
                    case .actuators: actuators
                    case .registers: registers
                    case .software: settings
                    case .commands: commands
                    case .modes: modes
                    case .operations: operations
                    case .sources: sources
                    }
                }.padding(24).frame(maxWidth: 1050, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            }.textSelection(.enabled)
            Divider()
            Text("Reference only · These settings do not configure the simulator or connect to hardware. · Reviewed \(ref.checked)")
                .labFont(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
        }
        .onChange(of: section) { _, _ in model.referenceSearch = "" }
    }
    private func matches(_ strings: String...) -> Bool { search.isEmpty || strings.joined(separator: " ").localizedCaseInsensitiveContains(search) }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                statistic("7", "actuators"); statistic("53", "documented registers"); statistic("4", "control modes")
            }
            Text("A separate reference for the settings exposed by the pinned Seeed SDK, MotorBridge, the robot URDF, and Damiao V1.4. Includes software defaults, command fields, read/write registers, read-only diagnostics, and state operations.")
                .labFont(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(ref.notes.filter { matches($0.title, $0.text) }, id: \.title) { note in
                referenceCard(title: note.title, value: nil, caption: nil, description: note.text) {
                    if let ids = note.sources { sourceLinks(ids) }
                }
            }
            HStack {
                Button("Browse registers") { model.referenceSection = .registers }
                Button("See per-joint defaults") { model.referenceSection = .actuators }
            }
        }
    }
    private func statistic(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).labFont(.system(size: 33, weight: .medium, design: .rounded)).foregroundStyle(Color.labAccent)
            Text(label).labFont(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private var actuators: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Published per-actuator defaults").labFont(.title2)
            Text("Mapping ranges define protocol encoding. They are separate from joint travel limits. The SDK settings section explains each gain and field.").foregroundStyle(.secondary)
            sourceLinks(["sdk-config", "models", "model"])
            ForEach(ref.actuators.filter { matches($0.joint, $0.model, $0.motor_id, $0.feedback_id) }) { a in
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(a.joint == "gripper" ? "Gripper" : a.joint.replacingOccurrences(of: "joint", with: "Joint ")).labFont(.headline)
                        Spacer(); Text("DM-\(a.model)").labFont(.system(.headline, design: .monospaced)).foregroundStyle(Color.labAccent)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), alignment: .leading)], alignment: .leading, spacing: 14) {
                        field("Motor / feedback ID", "\(a.motor_id) / \(a.feedback_id)")
                        field("MIT kp / kd", "\(number(a.kp)) / \(number(a.kd))")
                        field("Velocity kp / ki", "\(number(a.vel_kp)) / \(number(a.vel_ki))")
                        field("Position kp / ki", "\(number(a.pos_kp)) / \(number(a.pos_ki))")
                        field("VLIM", "\(number(a.vlim)) rad/s")
                        field("PMAX", "±\(number(a.pmax)) rad")
                        field("VMAX", "±\(number(a.vmax)) rad/s")
                        field("TMAX", "±\(number(a.tmax)) N·m")
                        if let lower = a.lower, let upper = a.upper {
                            field("URDF travel", "\(number(lower)) … \(number(upper)) rad")
                            field("Travel in degrees", String(format: "%.1f … %.1f°", lower / degreesToRadians, upper / degreesToRadians))
                        }
                        if let effort = a.urdf_effort { field("URDF effort", "\(number(effort)) N·m") }
                        if let velocity = a.urdf_velocity { field("URDF velocity", "\(number(velocity)) rad/s") }
                    }
                    if a.kd > 5 { Text("kd = 8 exceeds the inspected encoder’s 0–5 range; it clips to 5. See the overview note.").labFont(.caption).foregroundStyle(.orange) }
                }.padding(18).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private var filteredRegisters: [ActuatorReference.Register] {
        ref.registers.filter { (category == "All categories" || $0.category == category) && matches($0.name, $0.description, $0.category, $0.access, String($0.rid), $0.unit) }
    }
    private var registers: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Register dictionary").labFont(.title2); Spacer()
                Text("\(filteredRegisters.count) of \(ref.registers.count)").foregroundStyle(.secondary)
            }
            Text("RW = writable on a compatible drive; RO = read-only. No register values here are live readings. Ranges reflect the inspected library and firmware documentation, not recommended tuning values.").foregroundStyle(.secondary)
            sourceLinks(["registers", "manual"])
            if filteredRegisters.isEmpty { ContentUnavailableView.search(text: search) }
            LazyVStack(spacing: 12) {
                ForEach(filteredRegisters) { r in
                    referenceCard(title: r.name, value: "RID \(r.rid) · \(r.access)", caption: "\(r.category) · \(r.type) · \(r.unit)", description: r.description) {
                        Text("Range: \(r.range)").labFont(.system(.caption, design: .monospaced)).foregroundStyle(Color.labAccent)
                        if r.extended { Text("Library extension; check firmware support.").labFont(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SDK settings").labFont(.title2)
            Text("Host configuration and software defaults, with their effect on commands and actuator setup.").foregroundStyle(.secondary)
            ForEach(ref.software.filter { matches($0.key, $0.value, $0.unit, $0.description) }) { s in
                referenceCard(title: s.key, value: s.value, caption: s.unit, description: s.description) { sourceLinks([s.source]) }
            }
        }
    }
    private var commands: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Motion command fields").labFont(.title2)
            Text("MIT torque combines stiffness, damping, and feedforward: τ = kp × (p_des − p) + kd × (v_des − v) + τ_ff. Firmware limits and protections still apply.").foregroundStyle(.secondary)
            sourceLinks(["protocol", "sdk-code", "manual"])
            ForEach(ref.commands.filter { matches($0.key, $0.range, $0.unit, $0.description) }) { c in
                referenceCard(title: c.key, value: nil, caption: c.unit, description: c.description) {
                    Text("Range: \(c.range)").labFont(.system(.caption, design: .monospaced)).foregroundStyle(Color.labAccent)
                }
            }
        }
    }
    private var modes: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Control modes").labFont(.title2)
            Text("The control mode changes how the drive interprets incoming command fields and which CAN identifier is used.").foregroundStyle(.secondary)
            sourceLinks(["protocol", "registers", "manual"])
            ForEach(ref.modes.filter { matches($0.name, $0.offset, $0.description, String($0.code)) }) { m in
                referenceCard(title: m.name, value: "Mode \(m.code)", caption: "Command CAN ID: \(m.offset)", description: m.description) { EmptyView() }
            }
        }
    }
    private var operations: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("State & maintenance operations").labFont(.title2)
            ForEach(ref.operations.filter { matches($0.name, $0.description, $0.persistence) }) { op in
                referenceCard(title: op.name, value: nil, caption: op.persistence, description: op.description) { sourceLinks([op.source]) }
            }
            Text("Reported status codes").labFont(.title2).padding(.top, 12)
            ForEach(ref.statuses.filter { matches($0.joined(separator: " ")) }, id: \.self) { status in
                HStack { Text(status[0]).labFont(.system(.body, design: .monospaced)).foregroundStyle(Color.labAccent).frame(width: 70, alignment: .leading); Text(status[1]); Spacer() }
                    .padding(10).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
            }
            sourceLinks(["manual"])
        }
    }
    private var sources: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sources & provenance").labFont(.title2)
            Text("Reviewed \(ref.checked). Pinned source revisions make the reference reproducible; firmware and installed SDK versions may differ.").foregroundStyle(.secondary)
            ForEach(ref.sources.filter { matches($0.title, $0.detail, $0.url) }) { source in
                referenceCard(title: source.title, value: nil, caption: nil, description: source.detail) {
                    if let url = URL(string: source.url) { Link(destination: url) { Label("Open source", systemImage: "arrow.up.right") }.labLinkStyle().labFont(.caption) }
                }
            }
        }
    }
    @ViewBuilder private func sourceLinks(_ ids: [String]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { links(ids) }
            VStack(alignment: .leading, spacing: 6) { links(ids) }
        }.labFont(.caption)
    }
    @ViewBuilder private func links(_ ids: [String]) -> some View {
        ForEach(ref.sources.filter { ids.contains($0.id) }) { s in
            if let url = URL(string: s.url) { Link(s.title, destination: url).labLinkStyle() }
        }
    }
    private func field(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).labFont(.caption).foregroundStyle(.secondary)
            Text(value).labFont(.system(.callout, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func number(_ value: Double) -> String { String(format: "%.6g", value) }
}

func referenceCard<Content: View>(title: String, value: String?, caption: String?, description: String, @ViewBuilder footer: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top) {
            Text(title).labFont(.headline).textSelection(.enabled)
            Spacer(minLength: 15)
            if let value { Text(value).labFont(.system(.callout, design: .monospaced)).foregroundStyle(Color.labAccent).multilineTextAlignment(.trailing) }
        }
        if let caption { Text(caption).labFont(.caption).foregroundStyle(.secondary) }
        Text(description).labFont(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        footer()
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
}

struct AboutView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("ReBot Motion Lab").labFont(.largeTitle.weight(.medium))
                Text("A native SwiftUI + RealityKit workspace for the Seeed ReBot B601-DM.").labFont(.title3).foregroundStyle(.secondary)
                referenceCard(title: "What this simulator models", value: nil, caption: nil,
                    description: "Six revolute joints, the coupled gripper fingers, URDF joint limits, forward kinematics, and position-only inverse kinematics. Motion uses quintic interpolation with nominal maximum speeds of 60°/s for joints and 60 mm/s for the gripper at 100% playback speed.") { EmptyView() }
                referenceCard(title: "Scope", value: "Kinematic", caption: nil,
                    description: "The solid base plane stops every moving link, both gripper fingertips, and a held scene cube. Closing the gripper around the cube attaches it kinematically; there is no payload mass or contact friction. The arm can pass through an unattached cube. This app does not model self-collisions, forces, torque, drive response, or thermal behavior. It does not connect to hardware. Gripper opening is nominal 0–90 mm; the tool center is the source end_link origin at the closed fingertip center.") { EmptyView() }
                referenceCard(title: "Robot geometry", value: "34 meshes", caption: "430,912 triangles · Seeed-Projects/reBot-DevArm",
                    description: "Original URDF and colored STL files are bundled verbatim under CERN-OHL-W-2.0. The derived model.json preserves their joint graph. Source revision: \(model.robot.definition.commit).") {
                    HStack {
                        Link("Original model source", destination: URL(string: "https://github.com/Seeed-Projects/reBot-DevArm/tree/\(model.robot.definition.commit)")!).labLinkStyle()
                        Button("Read model license") { NSWorkspace.shared.open(Assets.url("model/LICENSE.txt")) }.labLinkStyle()
                        Button("Read notice") { NSWorkspace.shared.open(Assets.url("model/NOTICE.txt")) }.labLinkStyle()
                    }.labFont(.caption)
                }
                referenceCard(title: "Actuator documentation", value: "53 registers", caption: "Reviewed \(model.reference.checked)",
                    description: "The full reference and pinned sources are bundled locally. Links to source repositories and manufacturer documents open in your browser. Register metadata is derived in part from MotorBridge; its MIT license is included.") {
                    HStack {
                        Button("Browse reference") { model.page = .actuators }.labLinkStyle()
                        Button("Read MotorBridge license") { NSWorkspace.shared.open(Assets.url("MOTORBRIDGE-LICENSE.txt")) }.labLinkStyle()
                    }.labFont(.caption)
                }
                Text("Shortcuts: ⌘O import · ⌘S export · ⌘K add pose · ⌘Return play/pause · Esc stop · ⌘R reset · ⌘+/⌘− text size · ⌘0 actual text size").labFont(.callout).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.textSelection(.enabled)
    }
}
