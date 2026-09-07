import Foundation
import simd

public struct STLMesh: Sendable {
    public struct Indexed: Sendable {
        public let positions: [SIMD3<Float>]
        public let normals: [SIMD3<Float>]
        public let indices: [UInt32]
    }
    /// Weld identical position/normal pairs; triangle order and hard edges stay exact.
    public func indexed() -> Indexed {
        struct Vertex: Hashable { let position: SIMD3<Float>; let normal: SIMD3<Float> }
        var lookup = [Vertex: UInt32](), points = [SIMD3<Float>](), norms = [SIMD3<Float>](), indices = [UInt32]()
        lookup.reserveCapacity(positions.count / 2); indices.reserveCapacity(positions.count)
        for i in positions.indices {
            let vertex = Vertex(position: positions[i], normal: normals[i])
            if let index = lookup[vertex] { indices.append(index) }
            else {
                let index = UInt32(points.count); lookup[vertex] = index
                points.append(vertex.position); norms.append(vertex.normal); indices.append(index)
            }
        }
        return Indexed(positions: points, normals: norms, indices: indices)
    }
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public var triangleCount: Int { positions.count / 3 }
    public enum Invalid: Error { case malformed }
    public init(data: Data) throws {
        guard data.count >= 84 else { throw Invalid.malformed }
        let count = data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self))) }
        guard count > 0, count <= (data.count - 84) / 50, data.count == 84 + count * 50 else { throw Invalid.malformed }
        var points = [SIMD3<Float>](), norms = [SIMD3<Float>]()
        points.reserveCapacity(count * 3); norms.reserveCapacity(count * 3)
        try data.withUnsafeBytes { bytes in
            func number(_ offset: Int) -> Float { Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
            func point(_ offset: Int) -> SIMD3<Float> { SIMD3(number(offset), number(offset + 4), number(offset + 8)) }
            for i in 0..<count {
                let offset = 84 + i * 50
                let a = point(offset + 12), b = point(offset + 24), c = point(offset + 36)
                guard [a, b, c].allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { throw Invalid.malformed }
                var n = point(offset)
                if !n.x.isFinite || !n.y.isFinite || !n.z.isFinite || simd_length_squared(n) < 1e-12 { n = simd_cross(b - a, c - a) }
                n = simd_length_squared(n) > 1e-12 ? simd_normalize(n) : SIMD3(0, 0, 1)
                points.append(contentsOf: [a, b, c]); norms.append(contentsOf: [n, n, n])
            }
        }
        positions = points; normals = norms
    }
}
