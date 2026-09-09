import AppKit
import RealityKit
import Combine
import CoreMedia
import RobotCore
import simd

/// Native rigid-body backend. Robot links are kinematic; the cube is always dynamic.
@MainActor final class ManipulationScene {
    let root = Entity()
    private(set) var cube = ModelEntity()
    private var colliders: [String: ModelEntity] = [:]
    private var subscriptions: [any Cancellable] = []
    private(set) var contacts = Set<String>()
    private(set) var impulses: [String: Float] = [:]
    private var clock: CMTimebase?
    private let robot: Kinematics
    private var task: ExperimentTask
    private var previousPose: Pose?
    private var pendingPose: Pose?
    private var physicsSeconds=0.0
    private(set) var physicsSteps=0
    private var previousCubeTransform: simd_double4x4?
    private(set) var measuredLinearMMPerSecond=0.0
    private(set) var measuredAngularDegPerSecond=0.0
    private(set) var onFloor = true
    var time: Double { physicsSeconds }
    init(viewport: RobotViewport, robot: Kinematics, task: ExperimentTask) async throws {
        guard #available(macOS 15.0, *) else { throw ExperimentError.invalid("Manipulation experiments require macOS 15 or later. Standard kinematic controls remain available.") }
        self.robot=robot; self.task=task; root.name="manipulation"
        var simulation=PhysicsSimulationComponent(); simulation.gravity=[0,0,-9.81]
        simulation.solverIterations = .init(positionIterations: 24, velocityIterations: 12)
        var tb: CMTimebase?
        guard CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb) == noErr, let tb else { throw ExperimentError.invalid("Cannot initialize experiment clock.") }
        clock=tb; CMTimebaseSetTime(tb,time:.zero); CMTimebaseSetRate(tb,rate:0)
        simulation.clock = tb; root.components.set(simulation)
        let material=PhysicsMaterialResource.generate(staticFriction: Float(task.friction), dynamicFriction: Float(task.friction), restitution: 0)
        let floor=ModelEntity(); floor.name="floor"
        let floorShape=ShapeResource.generateBox(size:[4,4,0.02])
        floor.position=[0,0,Float(FloorConstraint.height)-0.01]
        floor.collision=CollisionComponent(shapes:[floorShape],filter:CollisionFilter(group:.init(rawValue:1),mask:.init(rawValue:2)))
        floor.physicsBody=PhysicsBodyComponent(shapes:[floorShape],mass:1,material:material,mode:.static)
        root.addChild(floor)
        for link in robot.definition.links {
            var shapes=[ShapeResource]()
            for visual in link.visuals {
                try Task.checkCancellation()
                let mesh=try STLMesh(data:Data(contentsOf:Assets.url("model/"+visual.mesh)))
                let transform=floatMatrix(originTransform(xyz:visual.xyz,rpy:visual.rpy))
                let points=mesh.indexed().positions.map { p -> SIMD3<Float> in
                    let v=transform * SIMD4(p,1); return SIMD3(v.x,v.y,v.z)
                }
                shapes.append(try await ShapeResource.generateConvex(from:points))
            }
            let body=ModelEntity(); body.name=link.name
            body.collision=CollisionComponent(shapes:shapes,filter:CollisionFilter(group:.init(rawValue:4),mask:.init(rawValue:2)))
            body.physicsBody=PhysicsBodyComponent(shapes:shapes,mass:1,material:material,mode:link.name == "base_link" ? .static : .kinematic)
            body.physicsMotion=PhysicsMotionComponent()
            colliders[link.name]=body; root.addChild(body)
        }
        try validatePlacement(task, robotPose:Pose(name:"Initial",joints:task.initialJoints,grip:task.initialGripperMM))
        viewport.world.addChild(root)
        subscriptions.append(viewport.scene.subscribe(to:PhysicsSimulationEvents.WillSimulate.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.simulationEntity === self.root else { return }
                self.preparePhysicsStep(dt:event.deltaTime)
            }
        })
        subscriptions.append(viewport.scene.subscribe(to:PhysicsSimulationEvents.DidSimulate.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.simulationEntity === self.root, event.deltaTime > 0 else { return }
                self.physicsSeconds += event.deltaTime; self.physicsSteps += 1
                self.measureCubeMotion(dt:event.deltaTime)
            }
        })
        subscriptions.append(viewport.scene.subscribe(to:CollisionEvents.Began.self) { [weak self] event in
            MainActor.assumeIsolated { self?.contact(event.entityA,event.entityB,impulse:event.impulse,ended:false) }
        })
        subscriptions.append(viewport.scene.subscribe(to:CollisionEvents.Updated.self) { [weak self] event in
            MainActor.assumeIsolated { self?.contact(event.entityA,event.entityB,impulse:event.impulse,ended:false) }
        })
        subscriptions.append(viewport.scene.subscribe(to:CollisionEvents.Ended.self) { [weak self] event in
            MainActor.assumeIsolated { self?.contact(event.entityA,event.entityB,impulse:0,ended:true) }
        })
        reset(task:task,pose:Pose(name:"Initial",joints:task.initialJoints,grip:task.initialGripperMM))
    }
    private func contact(_ a: Entity, _ b: Entity, impulse: Float, ended: Bool) {
        guard a === cube || b === cube else { return }
        let other = a === cube ? b : a
        if ended { contacts.remove(other.name); impulses.removeValue(forKey:other.name) }
        else { contacts.insert(other.name); impulses[other.name]=impulse }
        onFloor=contacts.contains("floor")
    }
    func reset(task: ExperimentTask, pose: Pose) {
        self.task=task; setPaused(true)
        cube.removeFromParent(); contacts=[]; impulses=[:]; onFloor=true
        let size=Float(task.cubeSizeMM/1000), shape=ShapeResource.generateBox(size:.init(repeating:size))
        cube=ModelEntity(mesh:.generateBox(size:size),materials:[SimpleMaterial(color:.systemOrange,roughness:0.8,isMetallic:false)])
        cube.name="task_cube"
        cube.transform=Transform(matrix:floatMatrix(task.initialCubePose.transform))
        cube.collision=CollisionComponent(shapes:[shape],filter:CollisionFilter(group:.init(rawValue:2),mask:.init(rawValue:1|4)))
        let material=PhysicsMaterialResource.generate(staticFriction:Float(task.friction),dynamicFriction:Float(task.friction),restitution:0)
        var body=PhysicsBodyComponent(shapes:[shape],mass:Float(task.massGrams/1000),material:material,mode:.dynamic)
        body.isContinuousCollisionDetectionEnabled=true
        if #available(macOS 15.0, *) { body.linearDamping=0.05; body.angularDamping=0.1 }
        cube.physicsBody=body; cube.physicsMotion=PhysicsMotionComponent()
        let mark=ModelEntity(mesh:.generateBox(size:[size*0.55,size*0.55,0.0002]),materials:[UnlitMaterial(color:.white)])
        mark.name="cube_top_marker"; mark.position.z=size/2+0.0001; cube.addChild(mark)
        root.addChild(cube)
        syncRobot(pose,dt:1.0/60,teleport:true)
        physicsSeconds=0; physicsSteps=0
        previousCubeTransform=doubleMatrix(cube.transform.matrix)
        measuredLinearMMPerSecond=0; measuredAngularDegPerSecond=0
        if let clock { CMTimebaseSetTime(clock,time:.zero) }
    }
    func setPaused(_ paused: Bool) { if let clock { CMTimebaseSetRate(clock,rate:paused ? 0 : 1) } }
    /// Conservative per-part collision bounds reject occupied floor locations before mutation.
    func validatePlacement(_ placement:ExperimentTask, robotPose:Pose) throws {
        guard #available(macOS 15.0, *) else { return }
        let cubeFromWorld=placement.initialCubePose.transform.inverse
        let transforms=robot.transforms(robotPose.joints,grip:robotPose.grip)
        let half=placement.cubeSizeMM/2000
        for (name,body) in colliders {
            guard let worldFromBody=transforms[name], let collision=body.collision else { continue }
            let transform=cubeFromWorld * worldFromBody
            for shape in collision.shapes {
                let bounds=shape.bounds
                var minimum=SIMD3<Double>(repeating:.infinity), maximum=SIMD3<Double>(repeating:-.infinity)
                for x in [bounds.min.x,bounds.max.x] {
                    for y in [bounds.min.y,bounds.max.y] {
                        for z in [bounds.min.z,bounds.max.z] {
                            let p=transform * SIMD4(Double(x),Double(y),Double(z),1)
                            minimum=simd_min(minimum,SIMD3(p.x,p.y,p.z)); maximum=simd_max(maximum,SIMD3(p.x,p.y,p.z))
                        }
                    }
                }
                if minimum.x < half && maximum.x > -half && minimum.y < half && maximum.y > -half && minimum.z < half && maximum.z > -half {
                    throw ExperimentError.invalid("The cube intersects the robot's collision bounds. Choose a clear point on the floor.")
                }
            }
        }
    }
    var cubeColliderSizeMM: [Double] {
        guard #available(macOS 15.0, *), let shape=cube.collision?.shapes.first else { return [] }
        let size=shape.bounds.extents*1000
        return [Double(size.x),Double(size.y),Double(size.z)]
    }
    func remove() { setPaused(true); subscriptions.forEach { $0.cancel() }; subscriptions.removeAll(); root.removeFromParent() }
    func syncRobot(_ pose: Pose, dt: Double, teleport: Bool = false) {
        pendingPose=pose
        if teleport {
            let transforms=robot.transforms(pose.joints,grip:pose.grip)
            for (name,entity) in colliders {
                if let m=transforms[name] { entity.transform=Transform(matrix:floatMatrix(m)); entity.physicsMotion=PhysicsMotionComponent() }
            }
        }
        previousPose=pose
    }
    private func preparePhysicsStep(dt:Double) {
        guard let pose=pendingPose, dt.isFinite, dt > 0 else { return }
        let transforms=robot.transforms(pose.joints,grip:pose.grip)
        for (name,entity) in colliders {
            guard let m=transforms[name] else { continue }
            let desired=Transform(matrix:floatMatrix(m))
            let distance=desired.translation-entity.position
            let angle=rotationError(simd_quatd(vector:SIMD4<Double>(desired.rotation.vector)),simd_quatd(vector:SIMD4<Double>(entity.orientation.vector)))
            entity.physicsMotion=PhysicsMotionComponent(linearVelocity:simd_length(distance)<0.0000001 ? .zero : distance/Float(dt),
                                                        angularVelocity:simd_length(angle)<0.000001 ? .zero : SIMD3<Float>(angle/dt))
        }
    }
    /// Geometric contact stop with a small solver preload; never attaches the cube.
    func limitGrip(_ requested: Pose) -> Pose {
        let tool=robot.toolTransform(requested.joints), inv=tool.inverse
        let center=inv * SIMD4<Double>(SIMD3<Double>(cube.position),1)
        guard center.x > -0.065, center.x < 0.01, abs(center.z) < task.cubeSizeMM/2000+0.008 else { return requested }
        let relative=inv * doubleMatrix(cube.transform.matrix)
        let half=task.cubeSizeMM/2000
        let extent=half*(abs(relative[0].y)+abs(relative[1].y)+abs(relative[2].y))
        guard abs(center.y) < extent+requested.grip/2000+0.005 else { return requested }
        var accepted=requested
        // A closing command can stop at contact, but never commands an unsolicited opening.
        accepted.grip=max(requested.grip,min(previousPose?.grip ?? 90,(extent+abs(center.y))*2000-0.1))
        return accepted
    }
    var cubePose: CartesianPose { CartesianPose(doubleMatrix(cube.transform.matrix)) }
    private func measureCubeMotion(dt:Double) {
        let current=doubleMatrix(cube.transform.matrix)
        if let previous=previousCubeTransform {
            measuredLinearMMPerSecond=simd_distance(SIMD3(current[3].x,current[3].y,current[3].z),SIMD3(previous[3].x,previous[3].y,previous[3].z))*1000/dt
            measuredAngularDegPerSecond=simd_length(rotationError(simd_quatd(current).normalized,simd_quatd(previous).normalized))/degreesToRadians/dt
        }
        previousCubeTransform=current
    }
    var solverVelocities: [String:Double] {
        let motion=cube.physicsMotion ?? PhysicsMotionComponent()
        return ["linear_speed_mm_s":Double(simd_length(motion.linearVelocity))*1000,
                "angular_speed_deg_s":Double(simd_length(motion.angularVelocity))/degreesToRadians]
    }
    func sample() -> HoldSample {
        let transform=simd_double4x4(simd_quatd(doubleMatrix(cube.transform.matrix)).normalized), half=task.cubeSizeMM/2000
        let bottom=Double(cube.position.z)-half*(abs(transform[0].z)+abs(transform[1].z)+abs(transform[2].z))
        let tilt=acos(clamp(transform[2].z,-1,1))/degreesToRadians
        return HoldSample(clearanceMM:(bottom-FloorConstraint.height)*1000,tiltDeg:tilt,
                          linearSpeedMM:measuredLinearMMPerSecond,
                          angularSpeedDeg:measuredAngularDegPerSecond,
                          leftContact:contacts.contains("finger_left_link"),rightContact:contacts.contains("finger_right_link"),
                          otherSupport:!contacts.subtracting(["finger_left_link","finger_right_link"]).isEmpty)
    }
}

func doubleMatrix(_ m: simd_float4x4) -> simd_double4x4 {
    simd_double4x4(columns:(SIMD4<Double>(m[0]),SIMD4<Double>(m[1]),SIMD4<Double>(m[2]),SIMD4<Double>(m[3])))
}
