import SwiftUI
import SceneKit
import RobotControl

private struct BrainGeometry {
    let directory: String
    let layout: BrainSomaLayout
    let positions: Data
}

/// File I/O and geometry validation stay off the main thread and the control socket.
private final class BrainActivityReader: @unchecked Sendable {
    private var cached: BrainGeometry?
    func read(defaultDirectory: URL?, episode: String, owner: String) -> (BrainGeometry?, BrainActivityFrame?, String) {
        var frame: BrainActivityFrame?
        var problem: String?
        let url = LocalSocket.directory.appendingPathComponent("brain-activity.json")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 400_000 {
            do {
                let candidate = try JSONDecoder().decode(BrainActivityFrame.self, from: Data(contentsOf: url))
                try candidate.validate()
                if candidate.isLive(episode: episode, owner: owner, now: Date().timeIntervalSince1970) { frame = candidate }
            } catch { problem = "Activity unavailable" }
        }
        let directory = frame.map { URL(fileURLWithPath: $0.layout_directory) } ?? defaultDirectory
        if let directory, cached?.directory != directory.path {
            do {
                let metadata = directory.appendingPathComponent("layout.json")
                let vertexURL = directory.appendingPathComponent("positions.f32")
                guard (try metadata.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 32_768,
                      (try vertexURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2_400_000 else {
                    throw ControlError("Brain geometry is too large")
                }
                let layout = try JSONDecoder().decode(BrainSomaLayout.self, from: Data(contentsOf: metadata))
                let positions = try Data(contentsOf: vertexURL)
                try layout.validate(positions: positions)
                cached = BrainGeometry(directory: directory.path, layout: layout, positions: positions)
            } catch { cached = nil; problem = "Geometry unavailable" }
        }
        if let current = frame, current.graph_id != cached?.layout.graph_id || current.count != cached?.layout.count {
            frame = nil; problem = "Activity unavailable"
        }
        let status = frame != nil ? "Live" : owner == "malecns" ? (problem ?? "Waiting for activity") : "Idle"
        return (cached, frame, status)
    }
}

@MainActor final class BrainActivityStore: ObservableObject {
    private(set) var status = "Idle"
    fileprivate var geometry: BrainGeometry?
    fileprivate var frame: BrainActivityFrame?
    fileprivate var display: BrainActivityDisplay?
    private unowned let coordinator: ExperimentCoordinator
    private let reader = BrainActivityReader()
    private let queue = DispatchQueue(label: "local.rebot.brain-display", qos: .utility)
    private var timer: Timer?
    private var reading = false
    private var receivedFrames = 0
    init(coordinator: ExperimentCoordinator) { self.coordinator = coordinator }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func poll() {
        guard !reading else { return }
        reading = true
        let episode = coordinator.episodeID, owner = coordinator.owner
        let checkpoint = coordinator.flyBrain.checkpointURL
        let root = coordinator.flyBrain.dataDirectory
        queue.async { [weak self, reader] in
            var directory: URL?
            if let data = try? Data(contentsOf: checkpoint.appendingPathComponent("manifest.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let graphID = json["graph_id"] as? String, BrainActivityFrame.validGraphID(graphID) {
                directory = root.appendingPathComponent("visualizations/\(graphID)/soma-v1")
            }
            let (geometry, frame, status) = reader.read(defaultDirectory: directory, episode: episode, owner: owner)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reading = false
                // A delayed disk read must not restore an old episode or a released controller.
                guard self.coordinator.episodeID == episode, self.coordinator.owner == owner else { return }
                if self.frame?.generated_at != frame?.generated_at, frame != nil { self.receivedFrames += 1 }
                if self.geometry?.directory != geometry?.directory || self.frame?.generated_at != frame?.generated_at || self.status != status {
                    self.objectWillChange.send()
                    self.display = frame.map { BrainActivityDisplay(frame: $0, previous: self.frame) }
                    self.geometry = geometry; self.frame = frame; self.status = status
                }
            }
        }
    }
    var diagnosticState: [String: Any] {
        ["status": status, "positioned_neurons": geometry?.layout.count ?? 0,
         "total_neurons": geometry?.layout.total_neurons ?? 0, "received_frames": receivedFrames,
         "frame_id": frame?.frame_id as Any? ?? NSNull(), "episode_id": frame?.episode_id as Any? ?? NSNull(),
         "minimum_activity": frame?.values.min().map { Double($0) / 255 } as Any? ?? NSNull(),
         "maximum_activity": frame?.values.max().map { Double($0) / 255 } as Any? ?? NSNull(),
         "changing_neurons": display?.changedCount ?? 0, "highlighted_neurons": display?.highlightIndices.count ?? 0,
         "mean_activity": display?.mean as Any? ?? NSNull(),
         "dopamine_signal": frame?.dopamine?.signal as Any? ?? NSNull(),
         "dopamine_cells": frame?.dopamine?.cells ?? 0,
         "reward": frame?.dopamine?.reward as Any? ?? NSNull(),
         "motor_scores": frame?.motor?.scores as Any? ?? NSNull(),
         "motor_choices": frame?.motor?.choices as Any? ?? NSNull(),
         "display_style": "logarithmic_blue_activity_gold_change", "interactive": false]
    }
}

struct BrainActivityOverlay: View {
    @ObservedObject var store: BrainActivityStore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MALE CNS").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                Spacer()
                Circle().fill(store.frame == nil ? Color.gray : Color.labAccent).frame(width: 5, height: 5)
                Text(store.status).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            BrainPointView(geometry: store.geometry, frame: store.frame, display: store.display)
                .frame(height: 205)
                .overlay {
                    if store.geometry == nil {
                        Text("Run fly brain to load the 3D map").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                    }
                }
            HStack(spacing: 5) {
                Circle().fill(.cyan).frame(width: 5, height: 5)
                Text("Activity").foregroundStyle(.secondary)
                Circle().fill(Color(red: 1, green: 0.72, blue: 0.18)).frame(width: 5, height: 5).padding(.leading, 7)
                Text("Change").foregroundStyle(.secondary)
                Spacer()
            }.font(.system(size: 10))
            if let frame = store.frame, let display = store.display {
                HStack {
                    Text("\(display.changedCount.formatted()) changing")
                    Spacer()
                    Text(String(format: "t %.1f s", frame.simulation_time)).monospacedDigit()
                }.font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.34))
                Text(String(format: "Mean %.3f  ·  Peak %.3f", display.mean, display.peak))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                Text("Waiting for fly-brain activity").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let dopamine = store.frame?.dopamine {
                Text(String(format:"PAM01 (%d)  %+.3f · Reward %.2f",dopamine.cells,dopamine.signal,dopamine.reward))
                    .font(.system(size:9,design:.monospaced)).foregroundStyle(Color.labAccent)
            }
            if let motor=store.frame?.motor {
                VStack(alignment:.leading,spacing:3) {
                    Text("Motor drive · 6 joints + gripper").foregroundStyle(.secondary)
                    Text(String(format:"J1 %+.2f  J2 %+.2f  J3 %+.2f",motor.scores[0],motor.scores[1],motor.scores[2]))
                    Text(String(format:"J4 %+.2f  J5 %+.2f  J6 %+.2f",motor.scores[3],motor.scores[4],motor.scores[5]))
                    Text(String(format:"Grip %+.2f",motor.scores[6]))
                }.font(.system(size:9,design:.monospaced)).foregroundStyle(Color.labAccent)
            }
            Text("Simulated activity · enhanced contrast")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            if let layout = store.geometry?.layout {
                Text("\(layout.count.formatted()) / \(layout.total_neurons.formatted()) somata mapped")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(12).frame(width: 230)
        .background(Color(red: 0.035, green: 0.055, blue: 0.07).opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Male CNS 3D brain activity, \(store.status). Non-interactive simulated activation.")
        .onAppear { store.start() }.onDisappear { store.stop() }
    }
}

private final class PassiveBrainView: SCNView {
    let points = SCNNode()
    let highlights = SCNNode()
    var layoutDirectory: String?
    var timestamp: Double?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct BrainPointView: NSViewRepresentable {
    let geometry: BrainGeometry?
    let frame: BrainActivityFrame?
    let display: BrainActivityDisplay?
    func makeNSView(context: Context) -> PassiveBrainView {
        let view = PassiveBrainView()
        let scene = SCNScene()
        view.scene = scene; view.backgroundColor = .clear
        view.allowsCameraControl = false; view.isPlaying = false; view.rendersContinuously = false
        view.antialiasingMode = .multisampling4X
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 37
        camera.position = SCNVector3(0.45, 0.12, 3.6)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera); view.pointOfView = camera
        scene.rootNode.addChildNode(view.points)
        scene.rootNode.addChildNode(view.highlights)
        view.highlights.renderingOrder = 10
        return view
    }
    func updateNSView(_ view: PassiveBrainView, context: Context) {
        guard view.layoutDirectory != geometry?.directory || view.timestamp != frame?.generated_at else { return }
        view.layoutDirectory = geometry?.directory; view.timestamp = frame?.generated_at
        guard let geometry else { view.points.geometry = nil; view.highlights.geometry = nil; return }
        let n = geometry.layout.count
        let vertices = SCNGeometrySource(data: geometry.positions, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                                        componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        var colors = [Float](); colors.reserveCapacity(n * 4)
        var gold = [Float](); gold.reserveCapacity(n * 4)
        for index in 0..<n {
            let value = display?.magnitudes[index] ?? 0
            let brightness = BrainActivityDisplay.contrast(value)
            colors.append(contentsOf: [0.045 + brightness * 0.15, 0.17 + brightness * 0.68,
                                       0.25 + brightness * 0.72, frame == nil ? 0.3 : 0.3 + brightness * 0.55])
            let change = display?.changes[index] ?? 0
            let strength = BrainActivityDisplay.contrast(change)
            gold.append(contentsOf: [1, 0.56 + strength * 0.35, 0.12 + strength * 0.25, 0.35 + strength * 0.6])
        }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let source = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: n, usesFloatComponents: true,
                                      componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let elements = SCNGeometryElement(data: nil, primitiveType: .point, primitiveCount: n, bytesPerIndex: 4)
        elements.pointSize = 1.1; elements.minimumPointScreenSpaceRadius = 0.45; elements.maximumPointScreenSpaceRadius = 1.3
        let cloud = SCNGeometry(sources: [vertices, source], elements: [elements])
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = NSColor.white; material.blendMode = .alpha
        material.isDoubleSided = true
        cloud.materials = [material]
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        view.points.geometry = cloud
        if let display, !display.highlightIndices.isEmpty {
            let goldData = gold.withUnsafeBytes { Data($0) }
            let colors = SCNGeometrySource(data: goldData, semantic: .color, vectorCount: n, usesFloatComponents: true,
                                           componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let indices = display.highlightIndices.withUnsafeBytes { Data($0) }
            let dots = SCNGeometryElement(data: indices, primitiveType: .point,
                                         primitiveCount: display.highlightIndices.count, bytesPerIndex: 4)
            dots.pointSize = 3.2; dots.minimumPointScreenSpaceRadius = 1.2; dots.maximumPointScreenSpaceRadius = 2.8
            let highlights = SCNGeometry(sources: [vertices, colors], elements: [dots])
            let glow = SCNMaterial(); glow.lightingModel = .constant; glow.diffuse.contents = NSColor.white
            glow.blendMode = .alpha; glow.isDoubleSided = true
            // Show activity inside the volume instead of letting quiet foreground somata hide it.
            glow.readsFromDepthBuffer = false; glow.writesToDepthBuffer = false
            highlights.materials = [glow]
            view.highlights.geometry = highlights
        } else { view.highlights.geometry = nil }
        SCNTransaction.commit()
        view.needsDisplay = true
    }
}
