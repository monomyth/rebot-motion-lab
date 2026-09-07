import RealityKit
import simd

@MainActor enum LineGeometry {
    /// Many line segments in one mesh, instead of an entity and draw call per segment.
    static func mesh(_ segments: [(SIMD3<Float>, SIMD3<Float>)], width: Float) throws -> MeshResource {
        var positions = [SIMD3<Float>](), indices = [UInt32]()
        positions.reserveCapacity(segments.count * 8); indices.reserveCapacity(segments.count * 36)
        let faces: [UInt32] = [0,2,1,1,2,3,4,5,6,5,7,6,0,1,4,1,5,4,2,6,3,3,6,7,0,4,2,2,4,6,1,3,5,3,7,5]
        for (a, b) in segments {
            let delta = b - a
            guard simd_length_squared(delta) > 1e-12 else { continue }
            let axis = simd_normalize(delta)
            let side = simd_normalize(simd_cross(axis, abs(axis.z) < 0.9 ? SIMD3(0,0,1) : SIMD3(0,1,0))) * (width / 2)
            let up = simd_normalize(simd_cross(axis, side)) * (width / 2)
            let offset = UInt32(positions.count)
            positions += [a-side-up, a+side-up, a-side+up, a+side+up, b-side-up, b+side-up, b-side+up, b+side+up]
            indices += faces.map { $0 + offset }
        }
        var descriptor = MeshDescriptor(name: "Batched lines")
        descriptor.positions = MeshBuffer(positions); descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
