import Foundation
import simd

/// Clip the existing triangles into adjacent slabs before convex collision cooking.
/// Every emitted point stays on an original triangle; no gripping pads are added.
public enum CollisionSections {
    public static func alongX(triangles: [SIMD3<Float>], cuts: [Float]) -> [[SIMD3<Float>]] {
        precondition(triangles.count % 3 == 0 && cuts.count >= 2)
        func clip(_ polygon: [SIMD3<Float>], at x: Float, keepGreater: Bool) -> [SIMD3<Float>] {
            guard var previous = polygon.last else { return [] }
            var result = [SIMD3<Float>]()
            for current in polygon {
                let a = keepGreater ? previous.x >= x : previous.x <= x
                let b = keepGreater ? current.x >= x : current.x <= x
                if a != b {
                    let t = (x - previous.x) / (current.x - previous.x)
                    var point = previous + (current - previous) * t
                    point.x = x; result.append(point)
                }
                if b { result.append(current) }
                previous = current
            }
            return result
        }
        return zip(cuts, cuts.dropFirst()).compactMap { low, high in
            var points = Set<SIMD3<Float>>()
            for i in stride(from: 0, to: triangles.count, by: 3) {
                let triangle = Array(triangles[i..<i+3])
                let polygon = clip(clip(triangle, at: low, keepGreater: true), at: high, keepGreater: false)
                points.formUnion(polygon)
            }
            guard points.count >= 4 else { return nil }
            return points.sorted { a,b in a.x != b.x ? a.x < b.x : a.y != b.y ? a.y < b.y : a.z < b.z }
        }
    }
}
