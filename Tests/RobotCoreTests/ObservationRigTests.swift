import Testing
import Foundation
import simd
@testable import RobotCore

struct ObservationRigTests {
    @Test func frontFacesTheWorkFromBeyondTheCubeAt45Degrees() throws {
        let m=ObservationRig.worldFromCamera("Front")
        let direction = -SIMD3(m[2].x,m[2].y,m[2].z)
        #expect(direction.x < 0 && abs(direction.y)<1e-12)
        #expect(abs(direction.z + sqrt(0.5))<1e-12)
        #expect(m[3].x > 0.35 && m[3].z < 1.0)
        let cube=m.inverse*SIMD4<Double>(0.35,0,0.01,1)
        let base=m.inverse*SIMD4<Double>(0,0,0,1)
        #expect(cube.z > base.z) // Cube is nearer than the base, both in front of camera.
        #expect(cube.z<0 && base.z<0)
        let robot=Kinematics(try RobotDefinition.load())
        #expect(m[3].z > robot.position(foldedPose).z)
    }
    @Test func gripperMountFollowsAllSixJointsAndKeepsItsLocalTilt() throws {
        let robot=Kinematics(try RobotDefinition.load())
        let a=robot.toolTransform(foldedPose), b=robot.toolTransform([25,-45,-60,20,15,35])
        let first=ObservationRig.worldFromCamera("Gripper",worldFromTool:a)
        let second=ObservationRig.worldFromCamera("Gripper",worldFromTool:b)
        #expect(simd_distance(first[3],second[3])>0.05)
        let local=b.inverse*second
        for i in 0..<4 { #expect(simd_distance(local[i],ObservationRig.gripperMount[i])<1e-10) }
        #expect(abs(local[3].z-0.06004716196264202)<1e-10)
        let ray = -SIMD3(local[2].x,local[2].y,local[2].z)
        #expect(abs(atan2(-ray.z,ray.x)*180 / .pi-15)<1e-10)
        #expect(abs(ObservationRig.gripperRearMidpoint.z-0.066)<1e-10)
    }
    @Test func cameraFramesAreRightHandedAndObservationPairIsExplicit() {
        for name in ObservationRig.viewNames.filter({$0 != "Orbit"}) {
            let m=ObservationRig.worldFromCamera(name)
            #expect(abs(simd_determinant(m)-1)<1e-10)
        }
        #expect(ObservationRig.observationNames == ["Front","Gripper"])
    }
    @Test func referenceHousingMeshIsRegisteredToTheToolFrame() throws {
        let mesh=try STLMesh(data:Data(contentsOf:Assets.url("model/camera/gemini305-housing.stl")))
        let lowX=mesh.positions.map(\.x).min()!, highZ=mesh.positions.map(\.z).max()!
        #expect(abs(lowX + 0.093064412)<1e-6)
        #expect(abs(highZ - 0.085676223)<1e-6)
        let cradle=try STLMesh(data:Data(contentsOf:Assets.url("model/camera/gemini305-cradle.stl")))
        #expect(abs(cradle.positions.map(\.z).min()! - 0.022737635)<1e-6)
    }

    @Test func orbbecRGBOpticsMatchNominalSensorFieldOfView() {
        for name in ObservationRig.observationNames {
            #expect(ObservationRig.imageWidth == 320 && ObservationRig.imageHeight(name) == 200)
            #expect(abs(ObservationRig.fieldOfView(name)-68)<1e-10)
            #expect(abs(ObservationRig.horizontalFieldOfView(name)-94)<0.5)
            let focal=ObservationRig.focalLengthPixels(name)
            #expect(abs(2*atan(100/focal)*180 / .pi-68)<1e-10)
            #expect(abs(2*atan(160/focal)*180 / .pi-ObservationRig.horizontalFieldOfView(name))<1e-10)
        }
        #expect(ObservationRig.cameraModel("Front").contains("336L"))
        #expect(ObservationRig.cameraModel("Gripper").contains("305"))
    }
    @Test func sensorViewportsPreserveOpticsAcrossWindowAspectRatios() {
        for name in ObservationRig.observationNames {
            for available in [SIMD2<Double>(1000,400),SIMD2<Double>(450,700),SIMD2<Double>(800,500)] {
                let size=ObservationRig.viewportSize(name,width:available.x,height:available.y)
                #expect(size.x<=available.x && size.y<=available.y)
                #expect(abs(size.x/size.y-1.6)<1e-10)
                #expect(abs(size.x-available.x)<1e-10 || abs(size.y-available.y)<1e-10)
            }
        }
        #expect(ObservationRig.viewportSize("Orbit",width:1000,height:400) == SIMD2<Double>(1000,400))
        #expect(ObservationRig.viewportSize("Front",width:0,height:0) == .zero)
    }

}
