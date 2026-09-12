import Testing
import Foundation
import simd
@testable import RobotCore

struct CollisionSectionsTests {
    @Test func clippedSectionsStayInsideTheOriginalTetrahedron() {
        let a=SIMD3<Float>(0,0,0), b=SIMD3<Float>(1,0,0), c=SIMD3<Float>(0,1,0), d=SIMD3<Float>(0,0,1)
        let triangles=[a,b,c,a,b,d,a,c,d,b,c,d]
        let cuts:[Float]=[-0.1,0.25,0.5,1.1]
        let sections=CollisionSections.alongX(triangles:triangles,cuts:cuts)
        #expect(sections.count == 3)
        for (index,points) in sections.enumerated() {
            #expect(points.allSatisfy { $0.x >= cuts[index] && $0.x <= cuts[index+1] })
            #expect(points.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.z >= 0 && $0.x+$0.y+$0.z <= 1.000001 })
        }
        #expect(sections[0].contains(a) && sections[0].contains(c) && sections[0].contains(d))
        #expect(sections[2].contains(b))
        let seam=Set(sections[0].filter { $0.x == 0.25 })
        #expect(!seam.isEmpty && seam == Set(sections[1].filter { $0.x == 0.25 }))
    }
    @Test func fingertipSectionsPreserveMeshBoundsAndVertices() throws {
        let robot=try RobotDefinition.load()
        for link in robot.links where link.name == "finger_left_link" || link.name == "finger_right_link" {
            let visual=try #require(link.visuals.first { $0.mesh.contains("finger_black") })
            let mesh=try STLMesh(data:Data(contentsOf:Assets.url("model/"+visual.mesh)))
            let sections=CollisionSections.alongX(triangles:mesh.positions,cuts:[-0.07,-0.05,-0.03,-0.02,-0.015,-0.01,-0.005,0.001])
            #expect(sections.count == 7)
            let points=Set(sections.flatMap { $0 })
            #expect(Set(mesh.positions).isSubset(of:points))
            #expect(points.map(\.x).min() == mesh.positions.map(\.x).min())
            #expect(points.map(\.x).max() == mesh.positions.map(\.x).max())
            #expect(sections.suffix(3).allSatisfy { $0.count >= 4 })
        }
    }
}
