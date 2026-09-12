import SwiftUI
import SceneKit
import Foundation
import RobotControl

@MainActor final class BrainActivityStore: ObservableObject {
    @Published var status = "Idle"
    @Published var live = false
    @Published var mapped = 0
    @Published var total = 0
    @Published var changed = 0
    @Published var mean: Float = 0
    @Published var peak: Float = 0
    @Published var stamp: UInt64 = 0
    @Published var pulse: UInt64 = 0
    fileprivate var positions = Data()
    fileprivate var graphIndex: [UInt32] = []
    fileprivate var magnitudes: [Float] = []
    fileprivate var changes: [Float] = []
    fileprivate var highlights: [UInt32] = []
    private var previous: [Float] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        loadGeometry()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func home() -> URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["MALECNS_HOME"] ?? FlyBrainLaunch.malecnsHome)
    }

    private func loadGeometry() {
        let url = home().appendingPathComponent("prepared/malecns-v1.0-somas.bin")
        guard let data = try? Data(contentsOf: url), data.count >= 12 else { return }
        let magic = data.prefix(4)
        guard magic == Data("MLC2".utf8) || magic == Data("MLCS".utf8) else { return }
        let count = Int(data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        total = Int(data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        let xyzBytes = count * 12
        let idxStart = 12 + xyzBytes
        guard data.count >= idxStart + count * 4 else { return }
        positions = data.subdata(in: 12..<idxStart)
        graphIndex = data.subdata(in: idxStart..<(idxStart + count * 4)).withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        mapped = count
        objectWillChange.send()
    }

    private func poll() {
        if positions.isEmpty { loadGeometry() }
        let count = graphIndex.count
        if magnitudes.count != count {
            magnitudes = [Float](repeating: 0, count: count)
            changes = [Float](repeating: 0, count: count)
            previous = [Float](repeating: 0, count: count)
        }
        for i in 0..<count { magnitudes[i] *= 0.76 }

        let ipc = LocalSocket.directory.appendingPathComponent("activity.bin")
        let fallback = URL(fileURLWithPath: FlyBrainLaunch.projectData).appendingPathComponent("live/activity.bin")
        let url = FileManager.default.fileExists(atPath: ipc.path) ? ipc : fallback
        if let data = try? Data(contentsOf: url), data.count >= 16, data.prefix(4) == Data("MLCN".utf8) {
            let n = Int(data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            let gen = data.subdata(in: 8..<16).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            if gen != stamp, n > 0 {
                stamp = gen
                live = true
                status = "Live"
                let rates = data.subdata(in: 16..<min(data.count, 16 + n * 4)).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                for i in 0..<count {
                    let gi = Int(graphIndex[i])
                    let v = gi < rates.count ? max(0, min(rates[gi], 1)) : 0
                    let prev = previous[i]
                    changes[i] = abs(v - prev)
                    magnitudes[i] = max(magnitudes[i], v)
                    previous[i] = v
                }
            }
        }

        var gold: [(Float, Int)] = []
        var sum: Float = 0
        var high: Float = 0
        var changing = 0
        for i in 0..<count {
            let v = magnitudes[i]
            sum += v
            high = max(high, v)
            if changes[i] > 0.02 { changing += 1 }
            if v > 0.05 { gold.append((v, i)) }
        }
        gold.sort { $0.0 > $1.0 }
        highlights = gold.prefix(10_000).map { UInt32($0.1) }
        changed = changing
        mean = count == 0 ? 0 : sum / Float(count)
        peak = high
        pulse += 1
    }

    static func contrast(_ value: Float) -> Float {
        log1p(999 * max(0, min(1, value))) / log(1000)
    }
}

struct BrainOverlayView: View {
    @StateObject private var store = BrainActivityStore()
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("MALE CNS").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                Spacer()
                Circle().fill(store.live ? Color.labAccent : Color.gray).frame(width: 5, height: 5)
                Text(store.status).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            BrainPointCloud(store: store, revision: store.pulse, live: store.live)
                .frame(height: 205)
            HStack(spacing: 5) {
                Circle().fill(.cyan).frame(width: 5, height: 5)
                Text("Activity").foregroundStyle(.secondary)
                Circle().fill(Color(red: 1, green: 0.72, blue: 0.18)).frame(width: 5, height: 5).padding(.leading, 7)
                Text("Change").foregroundStyle(.secondary)
                Spacer()
            }.font(.system(size: 10))
            if store.live {
                HStack {
                    Text("\(store.changed.formatted()) changing")
                    Spacer()
                    Text(String(format: "peak %.2f", store.peak)).monospacedDigit()
                }.font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.34))
                Text(String(format: "Mean %.3f  ·  Peak %.3f", store.mean, store.peak))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                Text("Waiting for fly-brain activity").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text("Simulated activity · enhanced contrast")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            if store.mapped > 0 {
                Text("\(store.mapped.formatted()) / \(store.total.formatted()) somata mapped")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(12).frame(width: 230)
        .background(Color(red: 0.035, green: 0.055, blue: 0.07).opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
        .allowsHitTesting(false)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }
}

private final class PassiveBrainView: SCNView {
    let points = SCNNode()
    let highlights = SCNNode()
    var stamp: UInt64 = 0
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct BrainPointCloud: NSViewRepresentable {
    @ObservedObject var store: BrainActivityStore
    var revision: UInt64
    var live: Bool
    func makeNSView(context: Context) -> PassiveBrainView {
        let view = PassiveBrainView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 37
        camera.position = SCNVector3(0.45, 0.12, 3.6)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera
        scene.rootNode.addChildNode(view.points)
        scene.rootNode.addChildNode(view.highlights)
        view.highlights.renderingOrder = 10
        return view
    }

    func updateNSView(_ view: PassiveBrainView, context: Context) {
        let n = store.graphIndex.count
        guard n > 0, store.positions.count == n * 12 else { return }
        let vertices = SCNGeometrySource(
            data: store.positions, semantic: .vertex, vectorCount: n,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        if view.points.geometry == nil {
            var idle = [Float](repeating: 0, count: n * 4)
            for i in 0..<n {
                idle[i * 4] = 0.05
                idle[i * 4 + 1] = 0.16
                idle[i * 4 + 2] = 0.24
                idle[i * 4 + 3] = 0.32
            }
            let colorData = idle.withUnsafeBytes { Data($0) }
            let source = SCNGeometrySource(
                data: colorData, semantic: .color, vectorCount: n,
                usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16
            )
            let elements = SCNGeometryElement(data: nil, primitiveType: .point, primitiveCount: n, bytesPerIndex: 4)
            elements.pointSize = 1.1
            elements.minimumPointScreenSpaceRadius = 0.45
            elements.maximumPointScreenSpaceRadius = 1.3
            let cloud = SCNGeometry(sources: [vertices, source], elements: [elements])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor.white
            material.blendMode = .alpha
            material.isDoubleSided = true
            cloud.materials = [material]
            view.points.geometry = cloud
        }
        guard live, !store.highlights.isEmpty else {
            view.highlights.geometry = nil
            return
        }
        var gold = [Float](repeating: 0, count: n * 4)
        for index in 0..<n {
            let v = BrainActivityStore.contrast(index < store.magnitudes.count ? store.magnitudes[index] : 0)
            gold[index * 4] = 0.2 + 0.8 * v
            gold[index * 4 + 1] = 0.55 + 0.4 * v
            gold[index * 4 + 2] = 0.12 + 0.2 * v
            gold[index * 4 + 3] = 0.15 + 0.85 * v
        }
        let goldData = gold.withUnsafeBytes { Data($0) }
        let goldSource = SCNGeometrySource(
            data: goldData, semantic: .color, vectorCount: n,
            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16
        )
        let indices = store.highlights.withUnsafeBytes { Data($0) }
        let dots = SCNGeometryElement(
            data: indices, primitiveType: .point,
            primitiveCount: store.highlights.count, bytesPerIndex: 4
        )
        dots.pointSize = 5
        dots.minimumPointScreenSpaceRadius = 1.8
        dots.maximumPointScreenSpaceRadius = 5
        let highlights = SCNGeometry(sources: [vertices, goldSource], elements: [dots])
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = NSColor.white
        glow.blendMode = .add
        glow.isDoubleSided = true
        glow.readsFromDepthBuffer = false
        glow.writesToDepthBuffer = false
        highlights.materials = [glow]
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        view.highlights.geometry = highlights
        SCNTransaction.commit()
    }
}
