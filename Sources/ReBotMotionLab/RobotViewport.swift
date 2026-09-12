import SwiftUI
import Combine
import RealityKit
import RobotCore
import simd

struct RobotScene: NSViewRepresentable {
    var model: AppModel
    var showGrid: Bool
    var showAxes: Bool
    var showTrace: Bool
    var camera: String
    var cameraRevision: Int
    var traceRevision: Int
    func makeNSView(context: Context) -> RobotViewport {
        if let view = model.viewport { view.setActive(true); view.applyPose(model.current); view.update(model); return view }
        let view = RobotViewport(frame: .zero)
        model.viewport = view; view.owner = model
        do {
            try view.configure(robot: model.robot)
            view.applyPose(model.current)
            view.syncCube(model.cube)
            view.setActive(true)
            DispatchQueue.main.async { model.sceneReady = true }
        } catch { DispatchQueue.main.async { model.sceneError = "The bundled 3D model could not load: \(error.localizedDescription)" } }
        return view
    }
    func updateNSView(_ view: RobotViewport, context: Context) { view.update(model) }
    static func dismantleNSView(_ view: RobotViewport, coordinator: ()) { view.setActive(false) }
}

@MainActor final class RobotViewport: ARView {
    weak var owner: AppModel?
    let world = AnchorEntity(world: .zero)
    let cameraEntity = PerspectiveCamera()
    let gridEntity = Entity(), axesEntity = Entity(), traceEntity = Entity()
    private var linkEntities: [String: Entity] = [:]
    private var robot: Kinematics?
    private var previousPose: Pose?
    private var armMotion: [(entity: Entity, axis: SIMD3<Float>)] = []
    private var fingerMotion: [String: Entity] = [:]
    private var frameSubscription: (any Cancellable)?
    private var tracePoints: [SIMD3<Float>] = []
    private var traceChunk: ModelEntity?
    private(set) var originalVertexCount = 0
    private(set) var indexedVertexCount = 0
    private var previousTrace = false
    private var lastTracePoint: SIMD3<Float>?
    private var cameraRevision = -1, traceRevision = -1
    private var azimuth: Float = -0.9887, elevation: Float = 0.38, distance: Float = 2.04
    private var target: SIMD3<Float> = [0.18, 0, 0.22]
    private var activePreset = "Orbit"
    private var cubeEntity: ModelEntity?
    private var gripperHousing: Entity?
    private var captureView: ARView?
    private let lineMesh = MeshResource.generateBox(size: 1)
    private let trailMaterial = UnlitMaterial(color: NSColor(red: 0.76, green: 0.91, blue: 0.35, alpha: 1))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        environment.background = .color(NSColor(red: 0.12, green: 0.15, blue: 0.13, alpha: 1))
    }
    required init?(coder: NSCoder) { nil }
    func configure(robot: Kinematics) throws {
        self.robot = robot
        scene.addAnchor(world)
        cameraEntity.camera.fieldOfViewInDegrees = 38
        cameraEntity.camera.near = 0.005; cameraEntity.camera.far = 30
        world.addChild(cameraEntity)
        for link in robot.definition.links {
            let entity = Entity(); entity.name = link.name
            for visual in link.visuals {
                let stl = try STLMesh(data: Data(contentsOf: Assets.url("model/" + visual.mesh)))
                var descriptor = MeshDescriptor(name: visual.mesh)
                let indexed = stl.indexed()
                originalVertexCount += stl.positions.count; indexedVertexCount += indexed.positions.count
                descriptor.positions = MeshBuffer(indexed.positions)
                descriptor.normals = MeshBuffer(indexed.normals)
                descriptor.primitives = .triangles(indexed.indices)
                let mesh = try MeshResource.generate(from: [descriptor])
                let c = robot.definition.materials[visual.material] ?? [0.7, 0.7, 0.7, 1]
                let color = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
                let material = SimpleMaterial(color: color, roughness: 0.62, isMetallic: visual.material.contains("metal"))
                let part = ModelEntity(mesh: mesh, materials: [material])
                part.transform = Transform(matrix: floatMatrix(originTransform(xyz: visual.xyz, rpy: visual.rpy)))
                entity.addChild(part)
            }
            linkEntities[link.name] = entity
        }
        world.addChild(linkEntities["base_link"]!)
        for joint in robot.definition.joints {
            let origin = Entity(), motion = Entity()
            origin.transform = Transform(matrix: floatMatrix(originTransform(xyz: joint.xyz, rpy: joint.rpy)))
            linkEntities[joint.parent]!.addChild(origin); origin.addChild(motion)
            motion.addChild(linkEntities[joint.child]!)
            if joint.type == "revolute" { armMotion.append((motion, SIMD3<Float>(vector(joint.axis)))) }
            if joint.type == "prismatic" { fingerMotion[joint.name] = motion }
        }
        let sun = DirectionalLight(); sun.light.intensity = 4500
        sun.look(at: [0, 0, 0.3], from: [1, -1, 2], upVector: [0, 0, 1], relativeTo: nil)
        world.addChild(sun)
        let fill = PointLight(); fill.light.intensity = 1600; fill.light.attenuationRadius = 6; fill.position = [-1, -0.4, 1.2]
        world.addChild(fill)
        let rim = PointLight(); rim.light.intensity = 2200; rim.light.attenuationRadius = 6; rim.position = [0, 1.3, 1.8]
        world.addChild(rim)
        let floor = ModelEntity(mesh: .generateBox(size: [4, 4, 0.002]), materials: [SimpleMaterial(color: NSColor(red: 0.14, green: 0.18, blue: 0.15, alpha: 1), roughness: 1, isMetallic: false)])
        floor.position.z = -0.002; world.addChild(floor)
        let cube = ModelEntity(
            mesh: .generateBox(size: Float(CubeState.meshEdge)),
            materials: [SimpleMaterial(color: NSColor(srgbRed: 0.77, green: 0.36, blue: 0.15, alpha: 1), roughness: 0.45, isMetallic: false)]
        )
        cube.name = "scene_cube"
        world.addChild(cube)
        cubeEntity = cube
        if let owner { syncCube(owner.cube) }
        let gridColor = UnlitMaterial(color: NSColor(red: 0.24, green: 0.31, blue: 0.25, alpha: 1))
        var gridLines: [(SIMD3<Float>, SIMD3<Float>)] = []
        for i in -12...12 {
            let p = Float(i) / 10
            gridLines.append(([p,-1.2,0.0005], [p,1.2,0.0005]))
            gridLines.append(([-1.2,p,0.0005], [1.2,p,0.0005]))
        }
        gridEntity.addChild(ModelEntity(mesh: try LineGeometry.mesh(gridLines, width: 0.0008), materials: [gridColor]))
        world.addChild(gridEntity); world.addChild(traceEntity)
        for (axis, color) in [(SIMD3<Float>(0.12, 0, 0), NSColor.systemRed), (SIMD3<Float>(0, 0.12, 0), .systemGreen), (SIMD3<Float>(0, 0, 0.12), .systemBlue)] {
            axesEntity.addChild(line(from: .zero, to: axis, width: 0.002, material: UnlitMaterial(color: color)))
        }
        linkEntities["end_link"]!.addChild(axesEntity)
        let housing = makeGripperCameraHousing()
        gripperHousing = housing
        linkEntities["end_link"]!.addChild(housing)
        updateCamera()
    }
    func line(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float, material: UnlitMaterial) -> ModelEntity {
        let entity = ModelEntity(mesh: lineMesh, materials: [material])
        let delta = b - a
        entity.position = (a + b) / 2
        entity.scale = [width, width, max(simd_length(delta), 0.00001)]
        if simd_length_squared(delta) > 0.00000001 { entity.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(delta)) }
        return entity
    }
    func setActive(_ active: Bool) {
        world.isEnabled = active
        if active, frameSubscription == nil {
            frameSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated { self?.owner?.advance(seconds: event.deltaTime) }
            }
        } else if !active { frameSubscription?.cancel(); frameSubscription = nil }
    }
    func toolPosition() -> SIMD3<Float> { linkEntities["end_link"]!.position(relativeTo: world) }
    func applyPose(_ pose: Pose) {
        guard robot != nil, previousPose?.joints != pose.joints || previousPose?.grip != pose.grip else { return }
        for (i, joint) in armMotion.enumerated() where previousPose?.joints[i] != pose.joints[i] {
            joint.entity.orientation = simd_quatf(angle: Float(pose.joints[i] * degreesToRadians), axis: joint.axis)
        }
        if previousPose?.grip != pose.grip {
            fingerMotion["finger_left"]?.position.y = Float(pose.grip / 2000)
            fingerMotion["finger_right"]?.position.y = -Float(pose.grip / 2000)
        }
        previousPose = pose
        if owner?.showTrace == true { appendTrace(SIMD3<Float>(robot!.position(pose.joints))) }
    }
    private func appendTrace(_ p: SIMD3<Float>) {
        guard let last = lastTracePoint else { lastTracePoint = p; tracePoints = [p]; return }
        guard simd_distance(last, p) > 0.003 else { return }
        tracePoints.append(p); lastTracePoint = p
        let segments = zip(tracePoints, tracePoints.dropFirst()).map { ($0, $1) }
        guard let mesh = try? LineGeometry.mesh(segments, width: 0.002) else { return }
        if let traceChunk { traceChunk.model?.mesh = mesh }
        else {
            let entity = ModelEntity(mesh: mesh, materials: [trailMaterial])
            traceChunk = entity; traceEntity.addChild(entity)
            if traceEntity.children.count > 12 { traceEntity.children.first?.removeFromParent() }
        }
        if tracePoints.count == 101 { tracePoints = [p]; traceChunk = nil }
    }
    func update(_ state: AppModel) {
        guard robot != nil else { return }
        gridEntity.isEnabled = state.showGrid; axesEntity.isEnabled = state.showAxes; traceEntity.isEnabled = state.showTrace
        if traceRevision != state.traceRevision || (!previousTrace && state.showTrace) {
            traceEntity.children.removeAll(); lastTracePoint = nil; tracePoints = []; traceChunk = nil
            traceRevision = state.traceRevision
        }
        previousTrace = state.showTrace
        if state.showTrace, lastTracePoint == nil { appendTrace(SIMD3<Float>(robot!.position(state.current.joints))) }
        if cameraRevision != state.cameraRevision {
            cameraRevision = state.cameraRevision
            applyCameraPreset(state.camera)
        }
        syncCube(state.cube)
    }
    func applyCameraPreset(_ name: String) {
        activePreset = name
        cameraEntity.removeFromParent()
        gripperHousing?.isEnabled = name != "Gripper"
        axesEntity.isEnabled = name != "Gripper"
        if name == "Gripper", let end = linkEntities["end_link"] {
            end.addChild(cameraEntity)
            placeGripperCamera(cameraEntity)
            applyGeminiOptics(GripperCameraPreset.optics)
            return
        }
        world.addChild(cameraEntity)
        switch name {
        case "Front":
            azimuth = FrontCameraPreset.azimuth
            elevation = FrontCameraPreset.elevation
            distance = FrontCameraPreset.distance
            target = FrontCameraPreset.target
            applyGeminiOptics(FrontCameraPreset.optics)
        case "Top":
            azimuth = -.pi / 2
            elevation = .pi / 2 - 0.001
            distance = 1.45
            target = [0.18, 0, 0.22]
            cameraEntity.camera.fieldOfViewInDegrees = 38
            cameraEntity.camera.near = 0.005
            cameraEntity.camera.far = 30
        default:
            azimuth = -0.9887
            elevation = 0.38
            distance = 2.04
            target = [0.18, 0, 0.22]
            cameraEntity.camera.fieldOfViewInDegrees = 38
            cameraEntity.camera.near = 0.005
            cameraEntity.camera.far = 30
        }
        updateCamera()
    }
    private func applyGeminiOptics(_ spec: GeminiOptics) {
        cameraEntity.camera.fieldOfViewInDegrees = spec.verticalFOVDegrees
        cameraEntity.camera.near = spec.nearMeters
        cameraEntity.camera.far = spec.farMeters
    }

    private func placeGripperCamera(_ entity: Entity) {
        entity.look(at: GripperCameraPreset.lookAt, from: GripperCameraPreset.fromTCP, upVector: [0, 0, 1], relativeTo: entity.parent)
    }
    private func makeGripperCameraHousing() -> Entity {
        let root = Entity()
        root.name = "gripper_camera"
        let yellow = UnlitMaterial(color: NSColor(srgbRed: 0.90, green: 0.62, blue: 0.12, alpha: 1))
        let bodyMat = UnlitMaterial(color: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.19, alpha: 1))
        let lensMat = UnlitMaterial(color: NSColor(white: 0.04, alpha: 1))
        let pitch = simd_quatf(angle: GripperCameraPreset.pitchRadians, axis: [0, 1, 0])
        let backPlate = ModelEntity(mesh: .generateBox(size: [0.010, 0.044, 0.055]), materials: [yellow])
        backPlate.position = [-0.096, 0, 0.052]
        let stem = ModelEntity(mesh: .generateBox(size: [0.014, 0.024, 0.028]), materials: [yellow])
        stem.position = [-0.090, 0, 0.028]
        let cradle = ModelEntity(mesh: .generateBox(size: [0.020, 0.044, 0.012]), materials: [yellow])
        cradle.position = [-0.086, 0, 0.068]
        cradle.orientation = pitch
        let rig = Entity()
        rig.position = GripperCameraPreset.fromTCP
        rig.orientation = pitch
        let body = ModelEntity(mesh: .generateBox(size: [0.023, 0.042, 0.042]), materials: [bodyMat])
        let face = ModelEntity(mesh: .generateBox(size: [0.002, 0.040, 0.040]), materials: [lensMat])
        face.position = [0.0125, 0, 0]
        for dy: Float in [-0.009, 0.009] {
            let lens = ModelEntity(mesh: .generateBox(size: [0.003, 0.012, 0.012]), materials: [lensMat])
            lens.position = [0.014, dy, 0]
            rig.addChild(lens)
        }
        rig.addChild(body)
        rig.addChild(face)
        root.addChild(stem)
        root.addChild(backPlate)
        root.addChild(cradle)
        root.addChild(rig)
        return root
    }
    func syncCube(_ cube: CubeState) {
        guard let cubeEntity else { return }
        cubeEntity.isEnabled = cube.present
        cubeEntity.removeFromParent()
        if cube.attached, let end = linkEntities["end_link"] {
            end.addChild(cubeEntity)
            cubeEntity.transform = Transform(matrix: floatMatrix(cube.attachLocal))
        } else {
            self.world.addChild(cubeEntity)
            cubeEntity.transform = Transform(matrix: floatMatrix(cube.worldMatrix))
        }
        // Pose matrices are rotation+translation only. Scale after transform
        // or a 40 mm mesh stays 40 mm in X/Y while center.z follows size.
        cubeEntity.scale = SIMD3<Float>(cube.visualScale)
    }
    func captureJPEG(camera: String?, apply: Bool, width: Int, height: Int) async -> (data: Data, cubeInView: Bool, tcpInView: Bool)? {
        let name = camera ?? activePreset
        if apply {
            applyCameraPreset(name)
            owner?.resetCamera(name)
            layoutSubtreeIfNeeded()
            displayIfNeeded()
            return await encodeSnapshot(from: self, camera: cameraEntity, width: width, height: height)
        }
        return await captureOffscreen(preset: name, width: width, height: height)
    }
    private func captureOffscreen(preset: String, width: Int, height: Int) async -> (data: Data, cubeInView: Bool, tcpInView: Bool)? {
        let clone: Entity = world.clone(recursive: true)
        disablePerspectiveCameras(clone)
        clone.findEntity(named: "gripper_camera")?.isEnabled = preset != "Gripper"
        let cam = PerspectiveCamera()
        poseCaptureCamera(cam, preset: preset, root: clone)
        let view = offscreenCaptureView(width: width, height: height)
        view.scene.anchors.forEach { view.scene.removeAnchor($0) }
        let anchor: AnchorEntity
        if let existing = clone as? AnchorEntity {
            anchor = existing
        } else {
            anchor = AnchorEntity(world: .zero)
            anchor.addChild(clone)
        }
        view.scene.addAnchor(anchor)
        view.layoutSubtreeIfNeeded()
        let shot = await encodeSnapshot(from: view, camera: cam, width: width, height: height)
        view.scene.removeAnchor(anchor)
        return shot
    }
    private func offscreenCaptureView(width: Int, height: Int) -> ARView {
        let frame = CGRect(x: -10_000, y: 0, width: max(width, 64), height: max(height, 64))
        if let view = captureView {
            view.frame = frame
            return view
        }
        let view = ARView(frame: frame)
        view.environment.background = environment.background
        addSubview(view)
        captureView = view
        return view
    }
    private func poseCaptureCamera(_ cam: PerspectiveCamera, preset: String, root: Entity) {
        if preset == "Gripper" {
            let end = root.findEntity(named: "end_link") ?? root
            end.addChild(cam)
            cam.look(at: GripperCameraPreset.lookAt, from: GripperCameraPreset.fromTCP, upVector: [0, 0, 1], relativeTo: end)
            cam.camera.fieldOfViewInDegrees = GripperCameraPreset.optics.verticalFOVDegrees
            cam.camera.near = GripperCameraPreset.optics.nearMeters
            cam.camera.far = GripperCameraPreset.optics.farMeters
            return
        }
        root.addChild(cam)
        let az: Float, el: Float, dist: Float, tgt: SIMD3<Float>
        switch preset {
        case "Front":
            az = FrontCameraPreset.azimuth
            el = FrontCameraPreset.elevation
            dist = FrontCameraPreset.distance
            tgt = FrontCameraPreset.target
            cam.camera.fieldOfViewInDegrees = FrontCameraPreset.optics.verticalFOVDegrees
            cam.camera.near = FrontCameraPreset.optics.nearMeters
            cam.camera.far = FrontCameraPreset.optics.farMeters
        case "Top":
            az = -.pi / 2
            el = .pi / 2 - 0.001
            dist = 1.45
            tgt = [0.18, 0, 0.22]
            cam.camera.fieldOfViewInDegrees = 38
            cam.camera.near = 0.005
            cam.camera.far = 30
        default:
            az = -0.9887
            el = 0.38
            dist = 2.04
            tgt = [0.18, 0, 0.22]
            cam.camera.fieldOfViewInDegrees = 38
            cam.camera.near = 0.005
            cam.camera.far = 30
        }
        let offset = SIMD3<Float>(cos(az) * cos(el), sin(az) * cos(el), sin(el)) * dist
        cam.look(at: tgt, from: tgt + offset, upVector: [0, 0, 1], relativeTo: nil)
    }
    private func disablePerspectiveCameras(_ entity: Entity) {
        if entity is PerspectiveCamera { entity.isEnabled = false }
        for child in entity.children { disablePerspectiveCameras(child) }
    }
    private func encodeSnapshot(from view: ARView, camera: Entity, width: Int, height: Int) async -> (data: Data, cubeInView: Bool, tcpInView: Bool)? {
        let scene: NSImage? = await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        guard let scene, let tiff = scene.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let jpeg = scaledJPEG(rep, width: width, height: height) ?? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        guard let jpeg else { return nil }
        let cube = owner?.cube.center ?? CubeState.defaultCenter
        let tcpMM = owner?.tcp ?? .zero
        return (jpeg, projectedInView(float3(cube), camera: camera), projectedInView(float3(tcpMM / 1000), camera: camera))
    }
    private func scaledJPEG(_ rep: NSBitmapImageRep, width: Int, height: Int) -> Data? {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        image.unlockFocus()
        guard let out = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return nil }
        return out.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
    private func projectedInView(_ worldPoint: SIMD3<Float>, camera: Entity? = nil) -> Bool {
        let node = camera ?? cameraEntity
        let cam = node.position(relativeTo: nil)
        let rot = node.orientation(relativeTo: nil)
        let forward = rot.act(SIMD3<Float>(0, 0, -1))
        let right = rot.act(SIMD3<Float>(1, 0, 0))
        let up = rot.act(SIMD3<Float>(0, 1, 0))
        let aspect = Float(max(bounds.width / max(bounds.height, 1), 0.1))
        return CameraFrustum.contains(
            worldPoint: worldPoint,
            cameraPos: cam,
            forward: forward,
            right: right,
            up: up,
            fovYDegrees: (node as? PerspectiveCamera)?.camera.fieldOfViewInDegrees ?? cameraEntity.camera.fieldOfViewInDegrees,
            aspect: aspect
        )
    }
    func updateCamera() {
        let offset = SIMD3<Float>(cos(azimuth) * cos(elevation), sin(azimuth) * cos(elevation), sin(elevation)) * distance
        cameraEntity.look(at: target, from: target + offset, upVector: [0, 0, 1], relativeTo: nil)
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func mouseDragged(with event: NSEvent) {
        if activePreset == "Gripper" { return }
        if event.modifierFlags.contains(.shift) { pan(event); return }
        azimuth -= Float(event.deltaX) * 0.008
        elevation = min(.pi / 2 - 0.001, max(0.025, elevation + Float(event.deltaY) * 0.008))
        updateCamera()
    }
    override func rightMouseDragged(with event: NSEvent) { if activePreset != "Gripper" { pan(event) } }
    override func otherMouseDragged(with event: NSEvent) { pan(event) }
    private func pan(_ event: NSEvent) {
        let right = cameraEntity.orientation.act(SIMD3<Float>(1, 0, 0))
        let up = cameraEntity.orientation.act(SIMD3<Float>(0, 1, 0))
        target += (-right * Float(event.deltaX) + up * Float(event.deltaY)) * distance * 0.001
        updateCamera()
    }
    override func scrollWheel(with event: NSEvent) {
        if activePreset == "Gripper" { return }
        distance = min(4, max(0.25, distance * exp(Float(event.scrollingDeltaY) * 0.008)))
        updateCamera()
    }
    override func magnify(with event: NSEvent) { distance = min(4, max(0.25, distance * Float(1 - event.magnification))); updateCamera() }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { owner?.stop() } else { super.keyDown(with: event) } }
}

func floatMatrix(_ m: simd_double4x4) -> simd_float4x4 {
    simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
}
func float3(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
