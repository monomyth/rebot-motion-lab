import AppKit
import SwiftUI
import RealityKit
import RobotCore
import simd

/// A render-only copy. Policy images never borrow the spectator camera or dynamic scene clock.
@MainActor final class ObservationCamera {
    let view: ARView
    let name: String
    let anchor=AnchorEntity(world:.zero)
    let camera=PerspectiveCamera()
    private let robotRoot: Entity
    private var cubeCopy: ModelEntity?
    let width=ObservationRig.imageWidth
    let height:Int
    private(set) var latestImage: NSImage?
    init(name: String, source: RobotViewport) throws {
        self.name=name
        height = ObservationRig.imageHeight(name)
        view=ARView(frame:NSRect(x:0,y:0,width:width,height:height))
        view.environment.background = .color(NSColor(red:0.12,green:0.15,blue:0.13,alpha:1))
        guard let root=source.world.findEntity(named:"base_link") else { throw ExperimentError.invalid("Robot rendering is not ready.") }
        robotRoot=root.clone(recursive:true)
        robotRoot.findEntity(named:"tool_axes")?.removeFromParent()
        if name == "Gripper" { robotRoot.findEntity(named:"gripper_camera_housing")?.removeFromParent() }
        else { robotRoot.findEntity(named:"gripper_camera_housing")?.isEnabled = true }
        anchor.addChild(robotRoot)
        let floor=ModelEntity(mesh:.generateBox(size:[4,4,0.002]),materials:[SimpleMaterial(color:NSColor(white:0.18,alpha:1),roughness:1,isMetallic:false)])
        floor.position.z = -0.002; anchor.addChild(floor)
        let light=DirectionalLight(); light.light.intensity=4500
        light.look(at:[0.25,0,0.1],from:[1,-1,2],upVector:[0,0,1],relativeTo:nil); anchor.addChild(light)
        let fill=PointLight(); fill.light.intensity=1800; fill.light.attenuationRadius=6; fill.position=[-1,-0.4,1.2]; anchor.addChild(fill)
        camera.camera.fieldOfViewInDegrees=Float(ObservationRig.fieldOfView(name)); camera.camera.near=0.005; camera.camera.far=30
        camera.transform=Transform(matrix:floatMatrix(ObservationRig.worldFromCamera(name)))
        anchor.addChild(camera); view.scene.addAnchor(anchor)
    }
    func update(pose: Pose, definition: RobotDefinition, cube: ModelEntity) {
        for (i,joint) in definition.armJoints.enumerated() {
            robotRoot.findEntity(named:"motion_"+joint.name)?.orientation=simd_quatf(angle:Float(pose.joints[i]*degreesToRadians),axis:SIMD3<Float>(vector(joint.axis)))
        }
        robotRoot.findEntity(named:"motion_finger_left")?.position.y=Float(pose.grip/2000)
        robotRoot.findEntity(named:"motion_finger_right")?.position.y = -Float(pose.grip/2000)
        // Compute extrinsics from this frozen render copy, including all wrist rotations.
        let tool=robotRoot.findEntity(named:"end_link")!.transformMatrix(relativeTo:anchor)
        camera.transform=Transform(matrix:floatMatrix(ObservationRig.worldFromCamera(name,worldFromTool:doubleMatrix(tool))))
        cubeCopy?.removeFromParent()
        let copy=cube.clone(recursive:true)
        copy.components.remove(PhysicsBodyComponent.self); copy.components.remove(PhysicsMotionComponent.self); copy.components.remove(CollisionComponent.self)
        anchor.addChild(copy); cubeCopy=copy
    }
    var calibration: [String:Any] {
        let fy=ObservationRig.focalLengthPixels(name)
        let m=camera.transform.matrix
        return ["name":name,"rig_revision":ObservationRig.revision,
                "mount_frame":name == "Gripper" ? "end_link" : "robot_base",
                "attachment":name == "Gripper" ? "reference CAD cradle on gripper plate" : "fixed world camera",
                "camera_model":ObservationRig.cameraModel(name),
                "specification_url":ObservationRig.specificationURL(name),
                "nominal_rgb_fov_deg":["horizontal":94.0,"vertical":68.0,"tolerance":3.0],
                "stream":name == "Gripper" ? "left_color" : "color",
                "downward_pitch_deg":name == "Gripper" ? ObservationRig.gripperPitchDegrees : 45.0,
                "projection_model":"ideal pinhole; nominal FOV; no lens distortion or stereo depth",
                "horizontal_fov_deg":ObservationRig.horizontalFieldOfView(name),
                "vertical_fov_deg":ObservationRig.fieldOfView(name),
                "mount_from_camera":matrixRows(name == "Gripper" ? ObservationRig.gripperMount : ObservationRig.worldFromCamera(name)),
                "width":width,"height":height,"projection":"perspective",
                "intrinsics":[[fy,0,Double(width)/2],[0,fy,Double(height)/2],[0,0,1]],
                "world_from_camera":(0..<4).map { r in (0..<4).map { c in Double(m[c][r]) } },
                "world_units":"meters","camera_axes":"right +X, up +Y, view -Z","pixel_origin":"top_left"]
    }
    func capture() async throws -> [String:Any] {
        guard view.window != nil else { throw ExperimentError.invalid("Observation views must be attached. Open the experiment panel before image capture.") }
        let image:NSImage? = await withCheckedContinuation { continuation in
            let waiter=CameraSnapshotWaiter(continuation)
            view.snapshot(saveToHDR:false) { image in Task { @MainActor in waiter.finish(image) } }
            Task { @MainActor in try? await Task.sleep(for:.seconds(1.5)); waiter.finish(nil) }
        }
        guard let image else { throw ExperimentError.invalid("Camera snapshot unavailable.") }
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context=NSGraphicsContext(bitmapImageRep:bitmap) else { throw ExperimentError.invalid("Cannot allocate camera image.") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
        image.draw(in:NSRect(x:0,y:0,width:width,height:height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data=bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.8]) else { throw ExperimentError.invalid("Cannot encode camera image.") }
        latestImage=NSImage(data:data)
        var result=calibration; result["mime_type"]="image/jpeg"; result["jpeg_base64"]=data.base64EncodedString()
        return result
    }
}

struct ObservationPreview: NSViewRepresentable {
    let camera: ObservationCamera
    func makeNSView(context: Context) -> ARView { camera.view }
    func updateNSView(_ view: ARView, context: Context) {}
}

@MainActor private final class CameraSnapshotWaiter {
    private var continuation: CheckedContinuation<NSImage?,Never>?
    init(_ continuation: CheckedContinuation<NSImage?,Never>) { self.continuation=continuation }
    func finish(_ image:NSImage?) { continuation?.resume(returning:image); continuation=nil }
}

private func matrixRows(_ m:simd_double4x4) -> [[Double]] {
    (0..<4).map { r in (0..<4).map { c in m[c][r] } }
}
